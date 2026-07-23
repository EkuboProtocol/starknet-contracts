use core::option::OptionTrait;
use crate::math::sqrt_ratio::{next_sqrt_ratio_from_amount0, next_sqrt_ratio_from_amount1};
use crate::math::ticks::{max_tick, min_sqrt_ratio, tick_to_sqrt_ratio};
use crate::types::i129::i129;

#[test]
fn test_next_sqrt_ratio_from_amount0_add_price_goes_down() {
    // adding amount0 means price goes down
    let next_ratio = next_sqrt_ratio_from_amount0(
        0x100000000000000000000000000000000_u256, 1000000, i129 { mag: 1000, sign: false },
    )
        .unwrap();
    assert(next_ratio == u256 { low: 339942424496442021441932674757011200256, high: 0 }, 'price');
}

#[test]
fn test_next_sqrt_ratio_from_amount0_exact_input_high_price_full_precision() {
    let sqrt_ratio = tick_to_sqrt_ratio(max_tick() - i129 { mag: 1, sign: false });
    let next_ratio = next_sqrt_ratio_from_amount0(
        sqrt_ratio, 0x8000000000000000, i129 { mag: 1, sign: false },
    )
        .unwrap();

    assert(
        next_ratio == 2092366731423230380742239773058784341020777786053236834275,
        'full precision ratio',
    );
}

#[test]
fn test_next_sqrt_ratio_from_amount0_exact_input_wide_denominator() {
    let next_ratio = next_sqrt_ratio_from_amount0(
        2664380729359047878130455396782445615002136682488425930791,
        42531265332720989308560689227437612046,
        i129 { mag: 7478763362817280620612385270656745576, sign: false },
    )
        .unwrap();

    assert(next_ratio == 1935164803785000531764469386445244376423, 'wide denominator ratio');
}

#[test]
fn test_next_sqrt_ratio_from_amount0_exact_input_rounds_towards_current_price() {
    let next_ratio = next_sqrt_ratio_from_amount0(
        0x100000000000000000000000000000000, 100, i129 { mag: 100, sign: false },
    )
        .unwrap();

    assert(next_ratio == 0x80000000000000000000000000000000, 'exact ratio');
}

#[test]
fn test_next_sqrt_ratio_from_amount0_exact_out_overflow() {
    // adding amount0 means price goes down
    assert(
        next_sqrt_ratio_from_amount0(
            sqrt_ratio: 0x100000000000000000000000000000000_u256,
            liquidity: 1,
            amount: i129 { mag: 100000000000000, sign: true },
        )
            .is_none(),
        'impossible to get output',
    );
}

#[test]
fn test_next_sqrt_ratio_from_amount0_exact_in_cant_underflow() {
    let x = next_sqrt_ratio_from_amount0(
        sqrt_ratio: min_sqrt_ratio(),
        liquidity: 1,
        amount: i129 { mag: 0xffffffffffffffffffffffffffffffff, sign: false },
    )
        .unwrap();

    assert(x == 1_u256, 'no underflow');
}

#[test]
fn test_next_sqrt_ratio_from_amount0_sub_price_goes_up() {
    // adding amount0 means price goes down
    let next_ratio = next_sqrt_ratio_from_amount0(
        0x100000000000000000000000000000000_u256, 100000000000, i129 { mag: 1000, sign: true },
    )
        .unwrap();
    assert(next_ratio == u256 { low: 3402823703237621667009962744418, high: 1 }, 'price');
}

#[test]
fn test_next_sqrt_ratio_from_amount1_add_price_goes_up() {
    let next_ratio = next_sqrt_ratio_from_amount1(
        0x100000000000000000000000000000000_u256, 1000000, i129 { mag: 1000, sign: false },
    )
        .unwrap();
    assert(next_ratio == u256 { low: 340282366920938463463374607431768211, high: 1 }, 'price');
}

#[test]
fn test_next_sqrt_ratio_from_amount1_sub_price_goes_down() {
    let next_ratio = next_sqrt_ratio_from_amount1(
        0x100000000000000000000000000000000_u256, 1000000, i129 { mag: 1000, sign: true },
    )
        .unwrap();
    assert(next_ratio == u256 { low: 339942084554017524999911232824336443244, high: 0 }, 'price');
}

#[test]
fn test_next_sqrt_ratio_from_amount1_exact_out_overflow() {
    assert(
        next_sqrt_ratio_from_amount1(
            sqrt_ratio: 0x100000000000000000000000000000000_u256,
            liquidity: 1,
            amount: i129 { mag: 1000000, sign: true },
        )
            .is_none(),
        'impossible to get output',
    );
}

#[test]
fn test_next_sqrt_ratio_from_amount1_exact_in_overflow() {
    assert(
        next_sqrt_ratio_from_amount1(
            sqrt_ratio: 0x100000000000000000000000000000000_u256,
            liquidity: 1,
            amount: i129 { mag: 0xffffffffffffffffffffffffffffffff, sign: false },
        )
            .is_none(),
        'overflow with input',
    );
}
