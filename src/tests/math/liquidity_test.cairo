use core::num::traits::Zero;
use ekubo::math::liquidity::liquidity_delta_to_amount_delta;
use ekubo::math::ticks::{max_sqrt_ratio, min_sqrt_ratio, tick_to_sqrt_ratio};
use ekubo::types::i129::i129;

const TICKS_IN_ONE_PERCENT: u128 = 9950;

#[test]
fn test_liquidity_delta_to_amount_delta_full_range_mid_price() {
    let delta = liquidity_delta_to_amount_delta(
        0x100000000000000000000000000000000_u256,
        i129 { mag: 10000, sign: false },
        min_sqrt_ratio(),
        max_sqrt_ratio(),
    );

    assert(delta.amount0 == i129 { mag: 10000, sign: false }, 'amount0');
    assert(delta.amount1 == i129 { mag: 10000, sign: false }, 'amount1');
}

#[test]
fn test_liquidity_delta_to_amount_delta_full_range_mid_price_withdraw() {
    let delta = liquidity_delta_to_amount_delta(
        0x100000000000000000000000000000000_u256,
        i129 { mag: 10000, sign: true },
        min_sqrt_ratio(),
        max_sqrt_ratio(),
    );

    assert(delta.amount0 == i129 { mag: 9999, sign: true }, 'amount0');
    assert(delta.amount1 == i129 { mag: 9999, sign: true }, 'amount1');
}

#[test]
fn test_liquidity_delta_to_amount_delta_low_price_in_range() {
    let delta = liquidity_delta_to_amount_delta(
        u256 { low: 79228162514264337593543950336, high: 0 },
        i129 { mag: 10000, sign: false },
        min_sqrt_ratio(),
        max_sqrt_ratio(),
    );

    assert(delta.amount0 == i129 { mag: 42949672960000, sign: false }, 'amount0');
    assert(delta.amount1 == i129 { mag: 1, sign: false }, 'amount1');
}

#[test]
fn test_liquidity_delta_to_amount_delta_low_price_in_range_withdraw() {
    let delta = liquidity_delta_to_amount_delta(
        u256 { low: 79228162514264337593543950336, high: 0 },
        i129 { mag: 10000, sign: true },
        min_sqrt_ratio(),
        max_sqrt_ratio(),
    );

    assert(delta.amount0 == i129 { mag: 42949672959999, sign: true }, 'amount0');
    assert(delta.amount1 == i129 { mag: 0, sign: true }, 'amount1');
}

#[test]
fn test_liquidity_delta_to_amount_delta_high_price_in_range() {
    let delta = liquidity_delta_to_amount_delta(
        u256 { low: 0, high: 4294967296 },
        i129 { mag: 10000, sign: false },
        min_sqrt_ratio(),
        max_sqrt_ratio(),
    );

    assert(delta.amount0 == i129 { mag: 1, sign: false }, 'amount0');
    assert(delta.amount1 == i129 { mag: 42949672960000, sign: false }, 'amount1');
}

#[test]
fn test_liquidity_delta_to_amount_delta_concentrated_mid_price() {
    let delta = liquidity_delta_to_amount_delta(
        sqrt_ratio: 0x100000000000000000000000000000000_u256,
        liquidity_delta: i129 { mag: 10000, sign: false },
        sqrt_ratio_lower: tick_to_sqrt_ratio(i129 { mag: TICKS_IN_ONE_PERCENT * 100, sign: true }),
        sqrt_ratio_upper: tick_to_sqrt_ratio(i129 { mag: TICKS_IN_ONE_PERCENT * 100, sign: false }),
    );

    assert(delta.amount0 == i129 { mag: 3920, sign: false }, 'amount0');
    assert(delta.amount1 == i129 { mag: 3920, sign: false }, 'amount1');
}

#[test]
fn test_liquidity_delta_to_amount_delta_concentrated_out_of_range_low() {
    let delta = liquidity_delta_to_amount_delta(
        u256 { low: 79228162514264337593543950336, high: 0 },
        i129 { mag: 10000, sign: false },
        tick_to_sqrt_ratio(i129 { mag: TICKS_IN_ONE_PERCENT * 100, sign: true }),
        tick_to_sqrt_ratio(i129 { mag: TICKS_IN_ONE_PERCENT * 100, sign: false }),
    );
    assert(delta.amount0 == i129 { mag: 10366, sign: false }, 'amount0');
    assert(delta.amount1.is_zero(), 'amount1');
}

#[test]
fn test_liquidity_delta_to_amount_delta_concentrated_out_of_range_high() {
    let delta = liquidity_delta_to_amount_delta(
        u256 { low: 0, high: 4294967296 },
        i129 { mag: 10000, sign: false },
        tick_to_sqrt_ratio(i129 { mag: TICKS_IN_ONE_PERCENT * 100, sign: true }),
        tick_to_sqrt_ratio(i129 { mag: TICKS_IN_ONE_PERCENT * 100, sign: false }),
    );
    assert(delta.amount0.is_zero(), 'amount0');
    assert(delta.amount1 == i129 { mag: 10366, sign: false }, 'amount1');
}

#[test]
fn test_liquidity_delta_to_amount_delta_concentrated_in_range() {
    let delta = liquidity_delta_to_amount_delta(
        tick_to_sqrt_ratio(Zero::zero()),
        i129 { mag: 1000000000, sign: false },
        tick_to_sqrt_ratio(i129 { mag: 10, sign: true }),
        tick_to_sqrt_ratio(i129 { mag: 10, sign: false }),
    );

    assert(delta.amount0 == i129 { mag: 5000, sign: false }, 'amount0');
    assert(delta.amount1 == i129 { mag: 5000, sign: false }, 'amount1');
}
