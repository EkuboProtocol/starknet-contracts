use result::ResultTrait;
use ekubo::math::delta::{amount0_delta, amount1_delta};
use ekubo::math::muldiv::{muldiv};
use ekubo::types::i129::i129;
use ekubo::types::delta::Delta;
use ekubo::math::ticks::tick_to_sqrt_ratio;
use integer::{
    u512, u256_wide_mul, u512_safe_div_rem_by_u256, u256_overflowing_add, u256_as_non_zero,
    u128_overflowing_add
};
use zeroable::Zeroable;

// Returns the token0, token1 delta owed for a given change in liquidity
fn liquidity_delta_to_amount_delta(
    sqrt_ratio: u256, liquidity_delta: i129, sqrt_ratio_lower: u256, sqrt_ratio_upper: u256
) -> Delta {
    // handle the 0 case so we do not return 1 for 0 liquidity delta
    if (liquidity_delta == Zeroable::zero()) {
        return Zeroable::zero();
    }

    // we always add one to the delta so that we never give more tokens than is owed or receive less than is needed
    // there may be a case where the addition overflows preventing withdrawal, but the user can always do partial withdrawals
    let ZERO = Zeroable::zero();
    // if the pool is losing liquidity, we round the amount down
    let round_up = !liquidity_delta.sign;

    if (sqrt_ratio <= sqrt_ratio_lower) {
        return Delta {
            amount0: i129 {
                mag: amount0_delta(
                    sqrt_ratio_lower, sqrt_ratio_upper, liquidity_delta.mag, round_up
                ),
                sign: liquidity_delta.sign
            }, amount1: ZERO
        };
    } else if (sqrt_ratio < sqrt_ratio_upper) {
        return Delta {
            amount0: i129 {
                mag: amount0_delta(sqrt_ratio, sqrt_ratio_upper, liquidity_delta.mag, round_up),
                sign: liquidity_delta.sign
                }, amount1: i129 {
                mag: amount1_delta(sqrt_ratio_lower, sqrt_ratio, liquidity_delta.mag, round_up),
                sign: liquidity_delta.sign
            }
        };
    } else {
        return Delta {
            amount0: ZERO, amount1: i129 {
                mag: amount1_delta(
                    sqrt_ratio_lower, sqrt_ratio_upper, liquidity_delta.mag, round_up
                ),
                sign: liquidity_delta.sign
            }
        };
    }
}


// Returns the max amount of liquidity that can be deposited based on amount of token0
// This function is the inverse of the amount0_delta function
// In other words, it computes the amount of liquidity corresponding to a given amount of token0 being sold between the prices of sqrt_ratio_lower and sqrt_ratio_upper
fn max_liquidity_for_token0(sqrt_ratio_lower: u256, sqrt_ratio_upper: u256, amount: u128) -> u128 {
    if (amount == 0) {
        return 0;
    }

    let mul1 = u256_wide_mul(
        u256 { low: amount, high: 0 }, sqrt_ratio_lower
    ); // amount * sqrt_ratio_lower
    let mul2 = u256_wide_mul(
        u256 { low: mul1.limb0, high: mul1.limb1 }, sqrt_ratio_upper
    ); // ((amount * sqrt_ratio_lower) % 2**256) * sqrt_ratio_upper
    let mul3 = u256_wide_mul(
        u256 { low: mul1.limb2, high: mul1.limb3 }, sqrt_ratio_upper
    ); // ((amount * sqrt_ratio_lower) / 2**256) * sqrt_ratio_upper

    let mut result = u512 { limb0: mul2.limb0, limb1: mul2.limb1, limb2: 0, limb3: 0 };
    // Initialize carry as u128
    let mut carry: u128 = 0;

    // Add the upper limbs of mul2 and mul3 with carry handling
    match u128_overflowing_add(mul2.limb2, mul3.limb0) {
        Result::Ok(x) => result.limb2 = x,
        Result::Err(x) => {
            result.limb2 = x;
            carry += 1;
        },
    };

    match u128_overflowing_add(mul2.limb3, mul3.limb1) {
        Result::Ok(x) => result.limb3 = x,
        Result::Err(x) => {
            result.limb3 = x;
            carry += 1;
        },
    };

    // If there's a carry from the last addition, add it to the most significant limb
    if carry > 0 {
        result.limb3 = u128_overflowing_add(result.limb3, carry).expect('CARRY_OVERFLOW');
    }

    let (quotient, _) = u512_safe_div_rem_by_u256(
        result, u256_as_non_zero(sqrt_ratio_upper - sqrt_ratio_lower)
    );

    assert((quotient.limb3 == 0) & (quotient.limb2 == 0), 'OVERFLOW_MLFT0');
    // we throw away limb0 because the quotient stores an x128 number
    quotient.limb1
}

// Returns the max amount of liquidity that can be deposited based on amount of token1
// This function is the inverse of the amount1_delta function
// In other words, it computes the amount of liquidity corresponding to a given amount of token1 being sold between the prices of sqrt_ratio_lower and sqrt_ratio_upper
fn max_liquidity_for_token1(sqrt_ratio_lower: u256, sqrt_ratio_upper: u256, amount: u128) -> u128 {
    if (amount == 0) {
        return 0;
    }
    let result = (u256 { high: amount, low: 0 } / (sqrt_ratio_upper - sqrt_ratio_lower));
    assert(result.high == 0, 'OVERFLOW_MLFT1');
    result.low
}

// Return the max liquidity that can be deposited based on the price bounds and the amounts of token0 and token1
fn max_liquidity(
    sqrt_ratio: u256, sqrt_ratio_lower: u256, sqrt_ratio_upper: u256, amount0: u128, amount1: u128
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
