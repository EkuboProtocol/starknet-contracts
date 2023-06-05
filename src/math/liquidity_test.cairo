use ekubo::math::liquidity::liquidity_delta_to_amount_delta;
use ekubo::math::ticks::{
    min_sqrt_ratio, max_sqrt_ratio, min_tick, max_tick, constants, tick_to_sqrt_ratio
};
use ekubo::types::i129::{i129};
use debug::PrintTrait;

#[test]
#[available_gas(15000000)]
fn test_liquidity_delta_to_amount_delta_full_range_mid_price() {
    let (amount0, amount1) = liquidity_delta_to_amount_delta(
        u256 { low: 0, high: 1 },
        i129 { mag: 10000, sign: false },
        min_sqrt_ratio(),
        max_sqrt_ratio()
    );

    assert(amount0 == i129 { mag: 184467397102717963084345, sign: false }, 'amount0');
    assert(amount1 == i129 { mag: 184467397102717963084345, sign: false }, 'amount1');
}

#[test]
#[available_gas(15000000)]
fn test_liquidity_delta_to_amount_delta_full_range_mid_price_withdraw() {
    let (amount0, amount1) = liquidity_delta_to_amount_delta(
        u256 { low: 0, high: 1 },
        i129 { mag: 10000, sign: true },
        min_sqrt_ratio(),
        max_sqrt_ratio()
    );

    assert(amount0 == i129 { mag: 184467397102717963084344, sign: true }, 'amount0');
    assert(amount1 == i129 { mag: 184467397102717963084344, sign: true }, 'amount1');
}

#[test]
#[available_gas(15000000)]
fn test_liquidity_delta_to_amount_delta_low_price_in_range() {
    let (amount0, amount1) = liquidity_delta_to_amount_delta(
        u256 { low: 79228162514264337593543950336, high: 0 },
        i129 { mag: 10000, sign: false },
        min_sqrt_ratio(),
        max_sqrt_ratio()
    );

    assert(amount0 == i129 { mag: 184467397059768290134345, sign: false }, 'amount0');
    assert(amount1 == i129 { mag: 184467397102717963094345, sign: false }, 'amount1');
}

#[test]
#[available_gas(15000000)]
fn test_liquidity_delta_to_amount_delta_low_price_in_range_withdraw() {
    let (amount0, amount1) = liquidity_delta_to_amount_delta(
        u256 { low: 79228162514264337593543950336, high: 0 },
        i129 { mag: 10000, sign: true },
        min_sqrt_ratio(),
        max_sqrt_ratio()
    );

    assert(amount0 == i129 { mag: 184467397059768290134344, sign: true }, 'amount0');
    assert(amount1 == i129 { mag: 184467397102717963094344, sign: true }, 'amount1');
}

#[test]
#[available_gas(15000000)]
fn test_liquidity_delta_to_amount_delta_high_price_in_range() {
    let (amount0, amount1) = liquidity_delta_to_amount_delta(
        u256 { low: 0, high: 4294967296 },
        i129 { mag: 10000, sign: false },
        min_sqrt_ratio(),
        max_sqrt_ratio()
    );

    assert(amount0 == i129 { mag: 184467397102717963094345, sign: false }, 'amount0');
    assert(amount1 == i129 { mag: 184467397059768290134345, sign: false }, 'amount1');
}

#[test]
#[available_gas(15000000)]
fn test_liquidity_delta_to_amount_delta_concentrated_mid_price() {
    let (amount0, amount1) = liquidity_delta_to_amount_delta(
        u256 { low: 0, high: 1 },
        i129 { mag: 10000, sign: false },
        tick_to_sqrt_ratio(i129 { mag: constants::TICKS_IN_DOUBLE_SQRT_RATIO, sign: true }),
        tick_to_sqrt_ratio(i129 { mag: constants::TICKS_IN_DOUBLE_SQRT_RATIO, sign: false })
    );

    assert(amount0 == i129 { mag: 10000, sign: false }, 'amount0');
    assert(amount1 == i129 { mag: 10000, sign: false }, 'amount1');
}

#[test]
#[available_gas(15000000)]
fn test_liquidity_delta_to_amount_delta_concentrated_out_of_range_low() {
    let (amount0, amount1) = liquidity_delta_to_amount_delta(
        u256 { low: 79228162514264337593543950336, high: 0 },
        i129 { mag: 10000, sign: false },
        tick_to_sqrt_ratio(i129 { mag: constants::TICKS_IN_DOUBLE_SQRT_RATIO, sign: true }),
        tick_to_sqrt_ratio(i129 { mag: constants::TICKS_IN_DOUBLE_SQRT_RATIO, sign: false })
    );

    assert(amount0 == i129 { mag: 15000, sign: false }, 'amount0');
    assert(amount1 == i129 { mag: 0, sign: false }, 'amount1');
}

#[test]
#[available_gas(15000000)]
fn test_liquidity_delta_to_amount_delta_concentrated_out_of_range_high() {
    let (amount0, amount1) = liquidity_delta_to_amount_delta(
        u256 { low: 0, high: 4294967296 },
        i129 { mag: 10000, sign: false },
        tick_to_sqrt_ratio(i129 { mag: constants::TICKS_IN_DOUBLE_SQRT_RATIO, sign: true }),
        tick_to_sqrt_ratio(i129 { mag: constants::TICKS_IN_DOUBLE_SQRT_RATIO, sign: false })
    );

    assert(amount0 == i129 { mag: 0, sign: false }, 'amount0');
    assert(amount1 == i129 { mag: 15000, sign: false }, 'amount1');
}

#[test]
#[available_gas(15000000)]
fn test_liquidity_delta_to_amount_delta_concentrated_in_range() {
    let (amount0, amount1) = liquidity_delta_to_amount_delta(
        tick_to_sqrt_ratio(i129 { mag: 0, sign: false }),
        i129 { mag: 1000000000, sign: false },
        tick_to_sqrt_ratio(i129 { mag: 10, sign: true }),
        tick_to_sqrt_ratio(i129 { mag: 10, sign: false })
    );

    assert(amount0 == i129 { mag: 5001, sign: false }, 'amount0');
    assert(amount1 == i129 { mag: 5001, sign: false }, 'amount1');
}
