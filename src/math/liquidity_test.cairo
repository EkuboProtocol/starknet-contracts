use ekubo::math::liquidity::{
    liquidity_delta_to_amount_delta, max_liquidity_for_token0, max_liquidity_for_token1,
    max_liquidity
};
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


#[test]
#[available_gas(2000000)]
fn test_max_liquidity_for_token0_max_at_full_range() {
    let result = max_liquidity_for_token0(
        min_sqrt_ratio(), max_sqrt_ratio(), 0xffffffffffffffffffffffffffffffff
    );
    assert(result == 18446748437148339061, 'max at full range');
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected: ('OVERFLOW_MLFT0', ))]
fn test_max_liquidity_for_token0_max_lower_half_range() {
    let result = max_liquidity_for_token0(
        tick_to_sqrt_ratio(i129 { mag: 0, sign: false }),
        max_sqrt_ratio(),
        0xffffffffffffffffffffffffffffffff
    );
}

#[test]
#[available_gas(2000000)]
fn test_max_liquidity_for_token0_max_upper_half_range() {
    let result = max_liquidity_for_token0(
        min_sqrt_ratio(),
        tick_to_sqrt_ratio(i129 { mag: 0, sign: false }),
        0xffffffffffffffffffffffffffffffff
    );
    assert(result == 18446748437148339062, 'max at half range');
}

#[test]
#[available_gas(2000000)]
fn test_max_liquidity_for_token1_max_at_full_range() {
    let result = max_liquidity_for_token1(
        min_sqrt_ratio(), max_sqrt_ratio(), 0xffffffffffffffffffffffffffffffff
    );
    assert(result == 18446748437148339061, 'max at full range');
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected: ('OVERFLOW_MLFT1', ))]
fn test_max_liquidity_for_token1_max_lower_half_range() {
    let result = max_liquidity_for_token1(
        min_sqrt_ratio(),
        tick_to_sqrt_ratio(i129 { mag: 0, sign: false }),
        0xffffffffffffffffffffffffffffffff
    );
}

#[test]
#[available_gas(2000000)]
fn test_max_liquidity_for_token1_max_upper_half_range() {
    let result = max_liquidity_for_token1(
        tick_to_sqrt_ratio(i129 { mag: 0, sign: false }),
        max_sqrt_ratio(),
        0xffffffffffffffffffffffffffffffff
    );
    assert(result == 18446748437148339062, 'max at half range');
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected: ('SQRT_RATIO_ORDER', ))]
fn test_max_liquidity_panics_order_ratios() {
    max_liquidity(
        u256 { low: 0, high: 1 },
        max_sqrt_ratio(),
        min_sqrt_ratio(),
        0xffffffffffffffffffffffffffffffff,
        0xffffffffffffffffffffffffffffffff
    );
}

#[test]
#[available_gas(2000000)]
fn test_max_liquidity_concentrated_example() {
    let liquidity = max_liquidity(
        u256 { low: 0, high: 1 },
        u256 { low: 324446506639056680081293727153829971379, high: 0 },
        u256 { low: 16608790382023884626048492437444757061, high: 1 },
        100,
        200
    );
    assert(liquidity == 2148, 'liquidity');
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected: ('SQRT_RATIO_ORDER', ))]
fn test_max_liquidity_panics_equal_ratios() {
    max_liquidity(
        u256 { low: 0, high: 1 },
        min_sqrt_ratio(),
        min_sqrt_ratio(),
        0xffffffffffffffffffffffffffffffff,
        0xffffffffffffffffffffffffffffffff
    );
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected: ('SQRT_RATIO_ZERO', ))]
fn test_max_liquidity_panics_zero_ratio_lower() {
    max_liquidity(
        u256 { low: 0, high: 1 },
        u256 { low: 0, high: 0 },
        min_sqrt_ratio(),
        0xffffffffffffffffffffffffffffffff,
        0xffffffffffffffffffffffffffffffff
    );
}

#[test]
#[available_gas(2000000)]
fn test_max_liquidity_less_than_liquidity_deltas() {
    let amount0 = 100000000;
    let amount1 = 100000000;
    let sqrt_ratio = u256 { low: 0, high: 1 };
    let sqrt_ratio_lower = min_sqrt_ratio();
    let sqrt_ratio_upper = max_sqrt_ratio();

    let liquidity = max_liquidity(sqrt_ratio, sqrt_ratio_lower, sqrt_ratio_upper, amount0, amount1);

    let (amount0_delta, amount1_delta) = liquidity_delta_to_amount_delta(
        sqrt_ratio,
        liquidity_delta: i129 { mag: liquidity, sign: false },
        sqrt_ratio_lower: sqrt_ratio_lower,
        sqrt_ratio_upper: sqrt_ratio_upper
    );
    amount0_delta.print();
    amount1_delta.print();
    assert(amount0_delta.mag <= amount0, 'amount0.mag');
    assert(amount0_delta.sign == false, 'amount0.sign');
    assert(amount1_delta.mag <= amount1, 'amount1.mag');
    assert(amount1_delta.sign == false, 'amount1.sign');
}
