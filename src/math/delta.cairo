use core::num::traits::{WideMul, Zero};
use core::option::OptionTrait;
use core::traits::Into;
use crate::math::muldiv::{div, muldiv};

// Compute the difference in amount of token0 between two ratios, rounded as specified
pub fn amount0_delta(
    sqrt_ratio_a: u256, sqrt_ratio_b: u256, liquidity: u128, round_up: bool,
) -> u128 {
    // we do this ordering here because it's easier than branching in swap
    let (sqrt_ratio_lower, sqrt_ratio_upper) = if sqrt_ratio_a < sqrt_ratio_b {
        (sqrt_ratio_a, sqrt_ratio_b)
    } else {
        (sqrt_ratio_b, sqrt_ratio_a)
    };
    assert(sqrt_ratio_lower.is_non_zero(), 'NONZERO');

    if (liquidity.is_zero() | (sqrt_ratio_lower == sqrt_ratio_upper)) {
        return Zero::zero();
    }

    let result_0 = muldiv(
        u256 { low: 0, high: liquidity },
        sqrt_ratio_upper - sqrt_ratio_lower,
        sqrt_ratio_upper,
        round_up,
    )
        .expect('OVERFLOW_AMOUNT0_DELTA_0');

    let result = div(result_0, sqrt_ratio_lower.try_into().unwrap(), round_up);
    assert(result.high.is_zero(), 'OVERFLOW_AMOUNT0_DELTA');

    return result.low;
}

// Compute the difference in amount of token1 between two ratios, rounded as specified
pub fn amount1_delta(
    sqrt_ratio_a: u256, sqrt_ratio_b: u256, liquidity: u128, round_up: bool,
) -> u128 {
    // we do this ordering here because it's easier than branching in swap
    let (sqrt_ratio_lower, sqrt_ratio_upper) = if sqrt_ratio_a < sqrt_ratio_b {
        (sqrt_ratio_a, sqrt_ratio_b)
    } else {
        (sqrt_ratio_b, sqrt_ratio_a)
    };
    assert(sqrt_ratio_lower.is_non_zero(), 'NONZERO');

    if (liquidity.is_zero() | (sqrt_ratio_lower == sqrt_ratio_upper)) {
        return Zero::zero();
    }

    let result = WideMul::<
        u256, u256,
    >::wide_mul(sqrt_ratio_upper - sqrt_ratio_lower, liquidity.into());

    // todo: result.limb3 is always zero. we can optimize out its computation
    assert(result.limb2.is_zero(), 'OVERFLOW_AMOUNT1_DELTA');

    if (round_up & result.limb0.is_non_zero()) {
        result.limb1 + 1
    } else {
        result.limb1
    }
}

