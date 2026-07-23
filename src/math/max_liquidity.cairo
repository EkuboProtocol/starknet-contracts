use core::integer::u512_safe_div_rem_by_u256;
use core::num::traits::{OverflowingAdd, WideMul, Zero};

// Returns the max amount of liquidity that can be deposited based on amount of token0
// This function is the inverse of the amount0_delta function
// In other words, it computes the amount of liquidity corresponding to a given amount of token0
// being sold between the prices of sqrt_ratio_lower and sqrt_ratio_upper
pub fn max_liquidity_for_token0(
    sqrt_ratio_lower: u256, sqrt_ratio_upper: u256, amount: u128,
) -> u128 {
    if (amount.is_zero()) {
        return Zero::zero();
    }

    let sqrt_ratio_product = WideMul::<u256, u256>::wide_mul(sqrt_ratio_lower, sqrt_ratio_upper);
    assert(sqrt_ratio_product.limb3.is_zero(), 'OVERFLOW_MLFT0_0');

    // Compute floor(amount * sqrt_ratio_lower * sqrt_ratio_upper / 2**128) before
    // dividing by the ratio difference. This avoids truncating the fractional Q128
    // part of the sqrt ratio product before it is multiplied by amount.
    let product_above_q128 = u256 { low: sqrt_ratio_product.limb1, high: sqrt_ratio_product.limb2 };
    let mut numerator = WideMul::<u256, u256>::wide_mul(product_above_q128, amount.into());
    let product_below_q128 = WideMul::<u128, u128>::wide_mul(sqrt_ratio_product.limb0, amount);

    let (limb0, carry0) = OverflowingAdd::overflowing_add(numerator.limb0, product_below_q128.high);
    let (limb1, carry1) = OverflowingAdd::overflowing_add(
        numerator.limb1, if carry0 {
            1
        } else {
            0
        },
    );
    let (limb2, carry2) = OverflowingAdd::overflowing_add(
        numerator.limb2, if carry1 {
            1
        } else {
            0
        },
    );
    let (limb3, carry3) = OverflowingAdd::overflowing_add(
        numerator.limb3, if carry2 {
            1
        } else {
            0
        },
    );
    assert(!carry3, 'OVERFLOW_MLFT0_0');
    numerator.limb0 = limb0;
    numerator.limb1 = limb1;
    numerator.limb2 = limb2;
    numerator.limb3 = limb3;

    let (result, _) = u512_safe_div_rem_by_u256(
        numerator, (sqrt_ratio_upper - sqrt_ratio_lower).try_into().expect('OVERFLOW_MLFT0_1'),
    );
    assert(result.limb3.is_zero() & result.limb2.is_zero(), 'OVERFLOW_MLFT0_1');
    assert(result.limb1.is_zero(), 'OVERFLOW_MLFT0_2');

    result.limb0
}

// Returns the max amount of liquidity that can be deposited based on amount of token1
// This function is the inverse of the amount1_delta function
// In other words, it computes the amount of liquidity corresponding to a given amount of token1
// being sold between the prices of sqrt_ratio_lower and sqrt_ratio_upper
pub fn max_liquidity_for_token1(
    sqrt_ratio_lower: u256, sqrt_ratio_upper: u256, amount: u128,
) -> u128 {
    if (amount.is_zero()) {
        return Zero::zero();
    }
    let result = u256 { high: amount, low: 0 } / (sqrt_ratio_upper - sqrt_ratio_lower);
    assert(result.high == 0, 'OVERFLOW_MLFT1');
    result.low
}

// Return the max liquidity that can be deposited based on the price bounds and the amounts of
// token0 and token1
pub fn max_liquidity(
    sqrt_ratio: u256, sqrt_ratio_lower: u256, sqrt_ratio_upper: u256, amount0: u128, amount1: u128,
) -> u128 {
    assert(sqrt_ratio_lower < sqrt_ratio_upper, 'SQRT_RATIO_ORDER');
    assert(sqrt_ratio_lower.is_non_zero(), 'SQRT_RATIO_ZERO');

    if (sqrt_ratio <= sqrt_ratio_lower) {
        return max_liquidity_for_token0(sqrt_ratio_lower, sqrt_ratio_upper, amount0);
    } else if (sqrt_ratio < sqrt_ratio_upper) {
        let max_from_token0 = max_liquidity_for_token0(sqrt_ratio, sqrt_ratio_upper, amount0);
        let max_from_token1 = max_liquidity_for_token1(sqrt_ratio_lower, sqrt_ratio, amount1);
        return if max_from_token0 < max_from_token1 {
            max_from_token0
        } else {
            max_from_token1
        };
    } else {
        return max_liquidity_for_token1(sqrt_ratio_lower, sqrt_ratio_upper, amount1);
    }
}
