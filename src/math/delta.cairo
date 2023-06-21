use ekubo::types::i129::i129;
use ekubo::math::muldiv::{muldiv, div};
use integer::{u256_wide_mul};
use zeroable::{Zeroable};

// Compute the difference in amount of token0 between two ratios, rounded as specified
fn amount0_delta(sqrt_ratio_a: u256, sqrt_ratio_b: u256, liquidity: u128, round_up: bool) -> u128 {
    let (sqrt_ratio_lower, sqrt_ratio_upper) = if sqrt_ratio_a < sqrt_ratio_b {
        (sqrt_ratio_a, sqrt_ratio_b)
    } else {
        (sqrt_ratio_b, sqrt_ratio_a)
    };

    assert(sqrt_ratio_lower.is_non_zero(), 'NONZERO_RATIO');

    if (liquidity.is_zero() | (sqrt_ratio_a == sqrt_ratio_b)) {
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
    let (sqrt_ratio_lower, sqrt_ratio_upper) = if sqrt_ratio_a < sqrt_ratio_b {
        (sqrt_ratio_a, sqrt_ratio_b)
    } else {
        (sqrt_ratio_b, sqrt_ratio_a)
    };

    assert(sqrt_ratio_lower.is_non_zero(), 'NONZERO_RATIO');

    if (liquidity.is_zero() | (sqrt_ratio_a == sqrt_ratio_b)) {
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

