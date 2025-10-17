use core::num::traits::Zero;
use crate::math::muldiv::muldiv;

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
    // 64.128 * 64.128 >> 128 always fits into 256 bits
    let numerator_1 = muldiv(sqrt_ratio_lower, sqrt_ratio_upper, u256 { high: 1, low: 0 }, false)
        .expect('OVERFLOW_MLFT0_0');

    let result = muldiv(amount.into(), numerator_1, (sqrt_ratio_upper - sqrt_ratio_lower), false)
        .expect('OVERFLOW_MLFT0_1');

    assert(result.high.is_zero(), 'OVERFLOW_MLFT0_2');

    result.low
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
