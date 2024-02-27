mod exp;

use core::cmp::{max};
use core::integer::{u256_overflow_mul};
use core::integer::{u512, u256_wide_mul, u512_safe_div_rem_by_u256, u128_wide_mul, u256_sqrt};
use core::num::traits::{Zero};
use core::traits::{Into, TryInto};
use ekubo::math::bits::{msb};
use ekubo::math::exp2::{exp2};
use ekubo::math::muldiv::{div, muldiv};
use ekubo::types::delta::{Delta};
use ekubo::types::i129::{i129, i129Trait};

pub mod constants {
    pub const LOG_SCALE_FACTOR: u8 = 4;
    pub const BITMAP_SPACING: u64 = 16;

    // 2**32
    pub const MAX_DURATION: u64 = 0x100000000_u64;
    pub const X32_u128: u128 = 0x100000000_u128;
    pub const X32_u256: u256 = 0x100000000_u256;

    // 2**64
    pub const X64_u128: u128 = 0x10000000000000000_u128;
    pub const X64_u256: u256 = 0x10000000000000000_u256;

    // 2**128
    pub const X128: u256 = 0x100000000000000000000000000000000_u256;

    // ~ ln(2**128) * 2**64
    pub const EXPONENT_LIMIT: u128 = 1623313478486440542208;
}

pub fn calculate_sale_rate(amount: u128, start_time: u64, end_time: u64) -> u128 {
    let sale_rate: u128 = ((amount.into() * constants::X32_u256) / (end_time - start_time).into())
        .try_into()
        .expect('SALE_RATE_OVERFLOW');

    assert(sale_rate.is_non_zero(), 'SALE_RATE_ZERO');

    sale_rate
}

pub fn calculate_amount_from_sale_rate(
    sale_rate: u128, start_time: u64, end_time: u64, round_up: bool
) -> u128 {
    div(
        sale_rate.into() * (end_time - start_time).into(),
        constants::X32_u256.try_into().unwrap(),
        round_up
    )
        .try_into()
        .unwrap()
}

pub fn calculate_reward_amount(reward_rate: felt252, sale_rate: u128) -> u128 {
    // this should never overflow since total_sale_rate <= sale_rate 
    muldiv(reward_rate.into(), sale_rate.into(), constants::X128, false)
        .unwrap()
        .try_into()
        .expect('REWARD_AMOUNT_OVERFLOW')
}

pub fn calculate_reward_rate(amount: u128, sale_rate: u128) -> felt252 {
    // avoid locking pools by defaulting to 0 on overflow
    (u256 { high: amount, low: 0 } / sale_rate.into()).try_into().unwrap_or_default()
}

// Timestamps specified in order keys must be a multiple of a base that depends on how close they are to now
#[inline(always)]
pub(crate) fn is_time_valid(now: u64, time: u64) -> bool {
    // = 16**(max(1, floor(log_16(time-now))))
    let step = if time <= (now + constants::BITMAP_SPACING) {
        constants::BITMAP_SPACING.into()
    } else {
        exp2(constants::LOG_SCALE_FACTOR * (msb((time - now).into()) / constants::LOG_SCALE_FACTOR))
    };

    (time.into() % step).is_zero()
}

pub(crate) fn validate_time(now: u64, time: u64) {
    assert(is_time_valid(now, time), 'INVALID_TIME');
}

pub fn calculate_next_sqrt_ratio(
    sqrt_ratio: u256,
    liquidity: u128,
    token0_sale_rate: u128,
    token1_sale_rate: u128,
    time_elapsed: u64
) -> u256 {
    let sale_ratio = (u256 { high: token1_sale_rate, low: 0 } / token0_sale_rate.into());
    let sqrt_sale_ratio: u256 = if (sale_ratio.high.is_zero()) {
        u256_sqrt(u256 { high: sale_ratio.low, low: 0 }).into()
    } else {
        u256_sqrt(sale_ratio).into() * constants::X64_u256
    };

    let (c, sign) = calculate_c(sqrt_ratio, sqrt_sale_ratio);

    let sqrt_ratio_next = if (c.is_zero() || liquidity.is_zero()) {
        // current sale ratio is the price
        sqrt_sale_ratio
    } else {
        let sqrt_sale_rate = u256_sqrt(token0_sale_rate.into() * token1_sale_rate.into());

        // calculate e
        // sqrt_sale_rate * 2 * t
        let (high, low) = u128_wide_mul(sqrt_sale_rate, (0x200000000 * time_elapsed.into()));

        let l: u256 = liquidity.into();
        let exponent = div(
            u256 { high: high, low: low }, l.try_into().expect('DIV_ZERO_LIQUIDITY'), false
        );

        if (exponent.low > constants::EXPONENT_LIMIT || exponent.high.is_non_zero()) {
            // sale_rate * t >> liquidity
            sqrt_sale_ratio
        } else {
            let e = exp::exp(exponent.low);

            let term1 = e - c;
            let term2 = e + c;

            let scale: u256 = if (sign) {
                muldiv(term2, constants::X128, term1, false)
                    .expect('NEXT_SQRT_RATIO_TERM2_OVERFLOW')
            } else {
                muldiv(term1, constants::X128, term2, false)
                    .expect('NEXT_SQRT_RATIO_TERM1_OVERFLOW')
            };

            muldiv(sqrt_sale_ratio, scale, constants::X128, false)
                .expect('NEXT_SQRT_RATIO_OVERFLOW')
        }
    };

    sqrt_ratio_next
}

// c = (sqrt_sale_ratio - sqrt_ratio) / (sqrt_sale_ratio + sqrt_ratio)
pub fn calculate_c(sqrt_ratio: u256, sqrt_sale_ratio: u256) -> (u256, bool) {
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
            muldiv(numerator, constants::X128, sqrt_sale_ratio + sqrt_ratio, false)
                .expect('C_MULDIV_OVERFLOW'),
            sign
        )
    }
}
