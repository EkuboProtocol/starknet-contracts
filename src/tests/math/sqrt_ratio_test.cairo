use core::num::traits::{OverflowingSub, Zero};
use core::option::OptionTrait;
use crate::math::delta::amount0_delta;
use crate::math::sqrt_ratio::{next_sqrt_ratio_from_amount0, next_sqrt_ratio_from_amount1};
use crate::math::ticks::{max_sqrt_ratio, max_tick, min_sqrt_ratio, tick_to_sqrt_ratio};
use crate::types::i129::i129;

fn assert_token0_exact_input_ratio_is_minimal(
    sqrt_ratio: u256, liquidity: u128, amount: u128,
) -> u256 {
    let next_ratio = next_sqrt_ratio_from_amount0(
        sqrt_ratio, liquidity, i129 { mag: amount, sign: false },
    )
        .unwrap();

    assert(next_ratio.is_non_zero(), 'next ratio is nonzero');
    assert(next_ratio <= sqrt_ratio, 'price does not increase');
    assert(
        amount0_delta(next_ratio, sqrt_ratio, liquidity, true) <= amount, 'next ratio fits input',
    );

    if next_ratio > 1_u256 {
        assert(
            amount0_delta(next_ratio - 1_u256, sqrt_ratio, liquidity, true) > amount,
            'next lower ratio exceeds input',
        );
    }

    next_ratio
}

#[test]
#[fuzzer(runs: 256)]
fn fuzz_next_sqrt_ratio_from_amount0_exact_input_is_minimal(
    sqrt_ratio_seed: u256, liquidity_seed: u64, amount: u128,
) {
    let ratio_span = max_sqrt_ratio() - min_sqrt_ratio() + 1_u256;
    let sqrt_ratio = min_sqrt_ratio() + (sqrt_ratio_seed % ratio_span);
    let liquidity = if liquidity_seed == 0 {
        1
    } else {
        liquidity_seed.into()
    };

    let next_ratio = assert_token0_exact_input_ratio_is_minimal(sqrt_ratio, liquidity, amount);

    if amount != 0xffffffffffffffffffffffffffffffff {
        let next_ratio_more_input = assert_token0_exact_input_ratio_is_minimal(
            sqrt_ratio, liquidity, amount + 1,
        );
        assert(next_ratio_more_input <= next_ratio, 'input is monotonic');
    }
}

#[test]
#[fuzzer(runs: 128)]
fn fuzz_next_sqrt_ratio_from_amount0_high_price_small_input(
    ratio_offset: u128, liquidity_seed: u64, amount_seed: u8,
) {
    // This is the regime where flooring (liquidity << 128) / sqrt_ratio loses all precision.
    let sqrt_ratio = max_sqrt_ratio() - u256 { low: ratio_offset, high: 0 };
    let liquidity: u128 = liquidity_seed.into() + 1;
    let amount: u128 = (amount_seed % 16).into() + 1;

    assert_token0_exact_input_ratio_is_minimal(sqrt_ratio, liquidity, amount);
}

#[test]
#[fuzzer(runs: 128)]
fn fuzz_next_sqrt_ratio_from_amount0_across_u256_denominator(
    ratio_offset: u128, liquidity_seed: u128,
) {
    // Keep the price near its supported maximum, where amount * sqrt_ratio crosses 256 bits.
    let sqrt_ratio = max_sqrt_ratio() - u256 { low: ratio_offset, high: 0 };
    let liquidity = if liquidity_seed == 0 {
        1
    } else {
        liquidity_seed
    };
    let numerator1 = u256 { low: 0, high: liquidity };

    // Since numerator1 is nonzero, wrapping subtraction yields 2**256 - numerator1.
    let (distance_to_u256_boundary, underflow) = OverflowingSub::overflowing_sub(
        0_u256, numerator1,
    );
    assert(underflow, 'boundary distance wraps');
    let (quotient, remainder) = DivRem::div_rem(
        distance_to_u256_boundary, sqrt_ratio.try_into().unwrap(),
    );
    assert(quotient.high.is_zero(), 'boundary amount fits u128');
    let crossing_amount = quotient.low + if remainder.is_zero() {
        0
    } else {
        1
    };
    assert(crossing_amount.is_non_zero(), 'boundary amount is nonzero');

    let ratio_before = assert_token0_exact_input_ratio_is_minimal(
        sqrt_ratio, liquidity, crossing_amount - 1,
    );
    let ratio_at = assert_token0_exact_input_ratio_is_minimal(
        sqrt_ratio, liquidity, crossing_amount,
    );
    assert(ratio_at <= ratio_before, 'boundary is monotonic');
}

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
