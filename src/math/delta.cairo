use ekubo::types::i129::i129;
use ekubo::math::muldiv::{muldiv, div};
use integer::{u256_wide_mul};
use zeroable::{Zeroable};

fn ordered_non_zero<
    T,
    impl TPartialEq: PartialOrd<T>,
    impl TZeroable: Zeroable<T>,
    impl TDrop: Drop<T>,
    impl TCopy: Copy<T>
>(
    x: T, y: T
) -> (T, T) {
    let (lower, upper) = if x < y {
        (x, y)
    } else {
        (y, x)
    };
    assert(x.is_non_zero(), 'NONZERO');
    (lower, upper)
}

// Compute the difference in amount of token0 between two ratios, rounded as specified
fn amount0_delta(sqrt_ratio_a: u256, sqrt_ratio_b: u256, liquidity: u128, round_up: bool) -> u128 {
    // we do this ordering here because it's easier
    let (sqrt_ratio_lower, sqrt_ratio_upper) = ordered_non_zero(sqrt_ratio_a, sqrt_ratio_b);

    if (liquidity.is_zero() | (sqrt_ratio_lower == sqrt_ratio_upper)) {
        return Zeroable::zero();
    }

    let (result_0, result_0_overflow) = muldiv(
        u256 { low: 0, high: liquidity },
        sqrt_ratio_upper - sqrt_ratio_lower,
        sqrt_ratio_upper,
        round_up
    );

    assert(!result_0_overflow, 'OVERFLOW_AMOUNT0_DELTA_0');
    let result = div(result_0, sqrt_ratio_lower, round_up);
    assert(result.high.is_zero(), 'OVERFLOW_AMOUNT0_DELTA');

    return result.low;
}

// Compute the difference in amount of token1 between two ratios, rounded as specified
fn amount1_delta(sqrt_ratio_a: u256, sqrt_ratio_b: u256, liquidity: u128, round_up: bool) -> u128 {
    // we do this ordering here because it's easier than branching in 
    let (sqrt_ratio_lower, sqrt_ratio_upper) = ordered_non_zero(sqrt_ratio_a, sqrt_ratio_b);

    if (liquidity.is_zero() | (sqrt_ratio_lower == sqrt_ratio_upper)) {
        return Zeroable::zero();
    }

    let result = u256_wide_mul(
        u256 { low: liquidity, high: 0 }, sqrt_ratio_upper - sqrt_ratio_lower
    );

    assert(result.limb3.is_zero() & result.limb2.is_zero(), 'OVERFLOW');

    if (round_up & result.limb0.is_non_zero()) {
        result.limb1 + 1
    } else {
        result.limb1
    }
}

