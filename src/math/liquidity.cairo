use core::num::traits::{Zero};
use ekubo::math::delta::{amount0_delta, amount1_delta};
use ekubo::types::delta::{Delta};
use ekubo::types::i129::{i129, i129Trait};

// Returns the token0, token1 delta owed for a given change in liquidity
pub fn liquidity_delta_to_amount_delta(
    sqrt_ratio: u256, liquidity_delta: i129, sqrt_ratio_lower: u256, sqrt_ratio_upper: u256,
) -> Delta {
    // skip the maths for the 0 case
    if (liquidity_delta.is_zero()) {
        return Zero::zero();
    }

    // if the pool is losing liquidity, we round the amount down
    let round_up = !liquidity_delta.is_negative();

    if (sqrt_ratio <= sqrt_ratio_lower) {
        return Delta {
            amount0: i129 {
                mag: amount0_delta(
                    sqrt_ratio_lower, sqrt_ratio_upper, liquidity_delta.mag, round_up,
                ),
                sign: liquidity_delta.sign,
            },
            amount1: Zero::zero(),
        };
    } else if (sqrt_ratio < sqrt_ratio_upper) {
        return Delta {
            amount0: i129 {
                mag: amount0_delta(sqrt_ratio, sqrt_ratio_upper, liquidity_delta.mag, round_up),
                sign: liquidity_delta.sign,
            },
            amount1: i129 {
                mag: amount1_delta(sqrt_ratio_lower, sqrt_ratio, liquidity_delta.mag, round_up),
                sign: liquidity_delta.sign,
            },
        };
    } else {
        return Delta {
            amount0: Zero::zero(),
            amount1: i129 {
                mag: amount1_delta(
                    sqrt_ratio_lower, sqrt_ratio_upper, liquidity_delta.mag, round_up,
                ),
                sign: liquidity_delta.sign,
            },
        };
    }
}
