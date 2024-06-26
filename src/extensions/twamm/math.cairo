mod exp;
#[cfg(test)]
mod exp_test;

pub mod time;

#[cfg(test)]
mod time_test;

use core::integer::{u128_wide_mul, u256_sqrt};
use core::num::traits::{Zero};
use core::traits::{Into, TryInto};
use ekubo::math::fee::{compute_fee};
use ekubo::math::muldiv::{div, muldiv};
use ekubo::math::ticks::{max_sqrt_ratio, min_sqrt_ratio};

pub mod constants {
    pub const X32_u128: u128 = 0x100000000_u128;
    pub const X32_u256: u256 = 0x100000000_u256;

    // 2**64
    pub const X64_u128: u128 = 0x10000000000000000_u128;
    pub const X64_u256: u256 = 0x10000000000000000_u256;

    // 2**128
    pub const X128: u256 = 0x100000000000000000000000000000000_u256;

    // ~ ln(2**128) * 2**64
    pub const EXPONENT_LIMIT: u128 = 1623313478486440542208;

    // min and max usable prices
    pub const MAX_USABLE_TICK_MAGNITUDE: u128 = 88368108;
    pub const MAX_BOUNDS_MIN_SQRT_RATIO: u256 = 22027144413679976675;
    pub const MAX_BOUNDS_MAX_SQRT_RATIO: u256 =
        5256790760649093508123362461711849782692726119655358142129;
}

// Computes the sale rate as a fixed point 96.32 number for a given amount, which is the just the amount divided by the duration in seconds
// The maximum sale rate for a given 18 decimal token that can be expressed in a 96.32 is approximately ~79,228,162,514 tokens
// https://www.wolframalpha.com/input?i=%282**128+-+1%29+%2F+2**32+%2F+10**18

pub fn calculate_sale_rate(amount: u128, duration: u32) -> u128 {
    ((amount.into() * constants::X32_u256) / duration.into())
        .try_into()
        .expect('SALE_RATE_OVERFLOW')
}

// Computes the amount for the given sale rate over the given start and end time, which is just the amount times the duration
// Will never revert because we limit the duration of any order to 2**32
pub fn calculate_amount_from_sale_rate(sale_rate: u128, duration: u32, round_up: bool) -> u128 {
    div(sale_rate.into() * duration.into(), constants::X32_u256.try_into().unwrap(), round_up)
        .try_into()
        .unwrap()
}

pub fn calculate_reward_amount(reward_rate: felt252, sale_rate: u128) -> u128 {
    muldiv(reward_rate.into(), sale_rate.into(), constants::X128, false)
        .unwrap()
        .try_into()
        .expect('REWARD_AMOUNT_OVERFLOW_U128')
}

pub fn calculate_next_sqrt_ratio(
    sqrt_ratio: u256,
    liquidity: u128,
    token0_sale_rate: u128,
    token1_sale_rate: u128,
    time_elapsed: u32,
    fee: u128
) -> u256 {
    let sale_ratio = (u256 { high: token1_sale_rate, low: 0 } / token0_sale_rate.into());
    let sqrt_sale_ratio: u256 = if (sale_ratio.high.is_zero()) {
        u256_sqrt(u256 { high: sale_ratio.low, low: 0 }).into()
    } else {
        u256_sqrt(sale_ratio).into() * constants::X64_u256
    };

    // round towards the current price
    let round_up = sqrt_ratio > sqrt_sale_ratio;

    let (c, sign) = calculate_c(sqrt_ratio, sqrt_sale_ratio, round_up);

    let sqrt_ratio_next = if (c.is_zero() || liquidity.is_zero()) {
        // current sale ratio is the price
        sqrt_sale_ratio
    } else {
        let sqrt_sale_rate_without_fee = u256_sqrt(
            token0_sale_rate.into() * token1_sale_rate.into()
        );
        let sqrt_sale_rate = sqrt_sale_rate_without_fee
            - compute_fee(sqrt_sale_rate_without_fee, fee);

        // calculate e
        // sqrt_sale_rate * 2 * t
        let (high, low) = u128_wide_mul(sqrt_sale_rate, (0x200000000 * time_elapsed.into()));

        let l: u256 = liquidity.into();
        let exponent = div(
            u256 { high: high, low: low }, l.try_into().expect('DIV_ZERO_LIQUIDITY'), round_up
        );

        if (exponent.low > constants::EXPONENT_LIMIT || exponent.high.is_non_zero()) {
            // sale_rate * t >> liquidity
            sqrt_sale_ratio
        } else {
            let e = exp::exp(exponent.low);

            let term1 = e - c;
            let term2 = e + c;

            let scale: u256 = if (sign) {
                muldiv(term2, constants::X128, term1, round_up)
                    .expect('NEXT_SQRT_RATIO_TERM2_OVERFLOW')
            } else {
                muldiv(term1, constants::X128, term2, round_up)
                    .expect('NEXT_SQRT_RATIO_TERM1_OVERFLOW')
            };

            muldiv(sqrt_sale_ratio, scale, constants::X128, round_up)
                .expect('NEXT_SQRT_RATIO_OVERFLOW')
        }
    };

    // largest sqrt_sale_ratio possible is sqrt((2**256 / 2**28)) * 2**64
    assert(sqrt_ratio_next < max_sqrt_ratio(), 'SQRT_RATIO_NEXT_TOO_HIGH');
    // smallest sqrt_sale_ratio possible is sqrt(2**28 * 2**128)
    assert(sqrt_ratio_next >= min_sqrt_ratio(), 'SQRT_RATIO_NEXT_TOO_LOW');

    sqrt_ratio_next
}

// c = (sqrt_sale_ratio - sqrt_ratio) / (sqrt_sale_ratio + sqrt_ratio)
pub fn calculate_c(sqrt_ratio: u256, sqrt_sale_ratio: u256, round_up: bool) -> (u256, bool) {
    if (sqrt_ratio == sqrt_sale_ratio) {
        (0, false)
    } else if (sqrt_ratio.is_zero()) {
        // early return 1, if current price is zero
        (constants::X128, false)
    } else {
        let (numerator, sign) = if (sqrt_ratio > sqrt_sale_ratio) {
            (sqrt_ratio - sqrt_sale_ratio, true)
        } else {
            (sqrt_sale_ratio - sqrt_ratio, false)
        };

        (
            muldiv(numerator, constants::X128, sqrt_sale_ratio + sqrt_ratio, round_up)
                .expect('C_MULDIV_OVERFLOW'),
            sign
        )
    }
}
