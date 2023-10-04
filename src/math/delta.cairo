use ekubo::math::muldiv::{muldiv, div};
use ekubo::types::i129::i129;
use integer::{u256_wide_mul};
use option::{OptionTrait};
use traits::{Into};
use zeroable::{Zeroable};

fn ordered_non_zero<T, +PartialOrd<T>, +Zeroable<T>, +Drop<T>, +Copy<T>>(x: T, y: T) -> (T, T) {
    let (lower, upper) = if x < y {
        (x, y)
    } else {
        (y, x)
    };
    assert(lower.is_non_zero(), 'NONZERO');
    (lower, upper)
}

// Compute the difference in amount of token0 between two ratios, rounded as specified
fn amount0_delta(sqrt_ratio_a: u256, sqrt_ratio_b: u256, liquidity: u128, round_up: bool) -> u128 {
    // we do this ordering here because it's easier than branching in swap
    let (sqrt_ratio_lower, sqrt_ratio_upper) = ordered_non_zero(sqrt_ratio_a, sqrt_ratio_b);

    if (liquidity.is_zero() | (sqrt_ratio_lower == sqrt_ratio_upper)) {
        return Zeroable::zero();
    }

    let result_0 = muldiv(
        u256 { low: 0, high: liquidity },
        sqrt_ratio_upper - sqrt_ratio_lower,
        sqrt_ratio_upper,
        round_up
    )
        .expect('OVERFLOW_AMOUNT0_DELTA_0');

    let result = div(result_0, sqrt_ratio_lower, round_up);
    assert(result.high.is_zero(), 'OVERFLOW_AMOUNT0_DELTA');

    return result.low;
}

// Compute the difference in amount of token1 between two ratios, rounded as specified
fn amount1_delta(sqrt_ratio_a: u256, sqrt_ratio_b: u256, liquidity: u128, round_up: bool) -> u128 {
    // we do this ordering here because it's easier than branching in swap
    let (sqrt_ratio_lower, sqrt_ratio_upper) = ordered_non_zero(sqrt_ratio_a, sqrt_ratio_b);

    if (liquidity.is_zero() | (sqrt_ratio_lower == sqrt_ratio_upper)) {
        return Zeroable::zero();
    }

    let result = u256_wide_mul(liquidity.into(), sqrt_ratio_upper - sqrt_ratio_lower);

    // todo: result.limb3 is always zero. we can optimize out its computation
    assert(result.limb2.is_zero(), 'OVERFLOW_AMOUNT1_DELTA');

    if (round_up & result.limb0.is_non_zero()) {
        result.limb1 + 1
    } else {
        result.limb1
    }
}

