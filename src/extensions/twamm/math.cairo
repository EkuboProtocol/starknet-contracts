use core::integer::{
    u512, u256_wide_mul, u512_safe_div_rem_by_u256, u256_as_non_zero, u128_safe_divmod,
    u128_as_non_zero, u256_safe_div_rem, u128_wide_mul, u256_sqrt
};
use core::num::traits::{Zero};
use core::traits::{Into, TryInto};
use ekubo::interfaces::core::{Delta};
use ekubo::math::bits::{msb};
use ekubo::math::exp2::{exp2 as exp2_int};
use ekubo::math::ticks::internal::{log2};


mod constants {
    const LOG_SCALE_FACTOR: u8 = 4;
    const BITMAP_SPACING: u64 = 16;

    // sale rate is scaled by 2**32
    const X_32_u128: u128 = 0x100000000_u128;
    const X_32_u256: u256 = 0x100000000_u256;

    // 2**64
    const X_64: u128 = 0x10000000000000000_u128;

    // 2**128
    const X_128: u256 = 0x100000000000000000000000000000000_u256;

    // log_2(e) * 2**64
    const LOG2_E_X64: u128 = 26613026195688644984_u128;
}

fn calculate_sale_rate(amount: u128, end_time: u64, start_time: u64) -> u128 {
    let sale_rate: u128 = ((amount.into() * constants::X_32_u256)
        / (end_time - start_time).into())
        .try_into()
        .expect('SALE_RATE_OVERFLOW');

    assert(sale_rate > 0, 'SALE_RATE_ZERO');

    sale_rate
}

fn calculate_reward_rate_deltas(sale_rates: (u128, u128), delta: Delta) -> (felt252, felt252) {
    let (token0_sale_rate, token1_sale_rate) = sale_rates;

    let token0_reward_delta: felt252 = if (delta.amount0.mag > 0) {
        if (!delta.amount0.sign || token1_sale_rate == 0) {
            0
        } else {
            (u256 { high: delta.amount0.mag, low: 0 } / token1_sale_rate.into())
                .try_into()
                .expect('REWARD_DELTA_OVERFLOW')
        }
    } else {
        0
    };

    let token1_reward_delta: felt252 = if (delta.amount1.mag > 0) {
        if (!delta.amount1.sign || token0_sale_rate == 0) {
            0
        } else {
            (u256 { high: delta.amount1.mag, low: 0 } / token0_sale_rate.into())
                .try_into()
                .expect('REWARD_DELTA_OVERFLOW')
        }
    } else {
        0
    };

    (token0_reward_delta, token1_reward_delta)
}

fn calculate_reward_amount(reward_rate: felt252, sale_rate: u128) -> u128 {
    // this should never overflow since total_sale_rate <= sale_rate 
    ((reward_rate.into() * sale_rate.into()) / constants::X_128)
        .try_into()
        .expect('REWARD_AMOUNT_OVERFLOW')
}

fn validate_time(start_time: u64, end_time: u64) {
    assert(end_time > start_time, 'INVALID_END_TIME');

    // calculate the closest timestamp at which an order can expire
    // based on the step of the interval that the order expires in using
    // an approximation of
    // = 16**(floor(log_16(end_time-start_time)))
    // = 2**(4 * (floor(log_2(end_time-start_time)) / 4))
    let step = exp2_int(
        constants::LOG_SCALE_FACTOR
            * (msb((end_time - start_time).into()) / constants::LOG_SCALE_FACTOR)
    );

    assert(step >= constants::BITMAP_SPACING.into(), 'INVALID_SPACING');
    assert(end_time.into() % step == 0, 'INVALID_TIME');
}

fn calculate_next_sqrt_ratio(
    sqrt_ratio: u256,
    liquidity: u128,
    token0_sale_rate: u128,
    token1_sale_rate: u128,
    virtual_order_time_window: u64
) -> u256 {
    // sqrt sell ratio
    let sell_ratio = (u256 { high: token1_sale_rate, low: 0 } / token0_sale_rate.into());
    let sqrt_sell_ratio: u256 = u256_sqrt(sell_ratio).into();

    // c
    let (c, sign) = calculate_c(sqrt_ratio, sqrt_sell_ratio * constants::X_64.into());

    let sqrt_ratio_next = if (c.is_zero()) {
        sqrt_sell_ratio.try_into().expect('SQRT_RATIO_OVERFLOW')
    } else {
        // sqrt_sell_rate
        let sqrt_sell_rate = u256_sqrt(token0_sale_rate.into() * token1_sale_rate.into());

        let e = calculate_e(sqrt_sell_rate, virtual_order_time_window, liquidity);

        let term1 = e - (c / constants::X_64.into()).try_into().expect('TERM1_OVERFLOW');
        let term2 = e + (c / constants::X_64.into()).try_into().expect('TERM2_OVERFLOW');

        let scale: u256 = if (sign) {
            let (high, low) = u128_wide_mul(term2, constants::X_64);
            let (q, r) = u256_safe_div_rem(
                u256 { high: high, low: low }, u256_as_non_zero(term1.into())
            );
            // check remainder
            q
        } else {
            let (high, low) = u128_wide_mul(term1, constants::X_64);
            let (q, r) = u256_safe_div_rem(
                u256 { high: high, low: low }, u256_as_non_zero(term2.into())
            );
            // check remainder
            q
        };

        (sqrt_sell_ratio * scale)
    };

    sqrt_ratio_next
}

// c = (sqrt_sell_ratio - sqrt_ratio) / (sqrt_sell_ratio + sqrt_ratio)
fn calculate_c(sqrt_ratio: u256, sqrt_sell_ratio: u256) -> (u256, bool) {
    if (sqrt_ratio == sqrt_sell_ratio) {
        return (0, false);
    }

    let (num, sign) = if (sqrt_ratio > sqrt_sell_ratio) {
        (sqrt_ratio - sqrt_sell_ratio, true)
    } else {
        (sqrt_sell_ratio - sqrt_ratio, false)
    };

    // denominator cannot overflow
    let (div, _) = u512_safe_div_rem_by_u256(
        u256_wide_mul(num, constants::X_128), u256_as_non_zero(sqrt_sell_ratio + sqrt_ratio)
    );

    // value of c is between 0 and 1 scaled by 2**128, only the upper 256 bits are used
    assert(div.limb2 == 0 && div.limb3 == 0, 'C_DIV_OVERFLOW');

    (u256 { low: div.limb0, high: div.limb1 }, sign)
}

//  e = exp(2 * t * sqrt_sell_rate / liquidity) as 32.64
fn calculate_e(sqrt_sell_rate: u128, t: u64, liquidity: u128) -> u128 {
    // sqrt_sell_rate is 96.32
    // scaled t is 64.32
    // combined is 160.64
    // liquidity is 128
    // exponent is 32.64

    let (high, low) = u128_wide_mul((2 * constants::X_32_u128 * t.into()), sqrt_sell_rate);

    let (exponent, _) = u256_safe_div_rem(
        u256 { high: high, low: low }, u256_as_non_zero(liquidity.into())
    );

    // validate high is 0, integer piece should be < 128
    assert(exponent.high == 0, 'E_MUL_OVERFLOW');

    exp(exponent.low)
}

// calculates exp(x) as 2^(x * log_2(e))
fn exp(x: u128) -> u128 {
    // TODO: max precision we get from sqrt_sell_rate is x.32,
    // should we calculate exp(x) as x.32?
    if (x == 0) {
        return constants::X_64;
    }

    // multiply by scaled log_2(e), convert to 32.128
    let (high, low) = u128_wide_mul(x, constants::LOG2_E_X64);

    // scale back down to 32.64 before divmod
    let (int, frac) = u128_safe_divmod(
        (u256 { high: high, low: low } / constants::X_64.into()).try_into().expect('EXP_OVERFLOW'),
        u128_as_non_zero(constants::X_64.into())
    );

    let mut res_u = exp2_int(int.try_into().expect('EXP_INT_OVERFLOW'));

    if frac != 0 {
        let r8 = mul(41691949755436, frac);
        let r7 = mul((r8 + 231817862090993), frac);
        let r6 = mul((r7 + 2911875592466782), frac);
        let r5 = mul((r6 + 24539637786416367), frac);
        let r4 = mul((r5 + 177449490038807528), frac);
        let r3 = mul((r4 + 1023863119786103800), frac);
        let r2 = mul((r3 + 4431397849999009866), frac);
        let r1 = mul((r2 + 12786308590235521577), frac);
        res_u = res_u * (r1 + constants::X_64);
    }

    res_u.into()
}

fn mul(a: u128, b: u128) -> u128 {
    let (high, low) = u128_wide_mul(a, b);
    let (div, _) = u256_safe_div_rem(
        u256 { high: high, low: low }, u256_as_non_zero(u256 { high: 0, low: constants::X_64 })
    );

    assert(div.high == 0, 'MUL_OVERFLOW');

    div.low
}
