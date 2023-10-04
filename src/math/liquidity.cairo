use ekubo::math::delta::{amount0_delta, amount1_delta};
use ekubo::math::muldiv::{muldiv};
use ekubo::math::ticks::{tick_to_sqrt_ratio};
use ekubo::types::delta::{Delta};
use ekubo::types::i129::{i129, i129Trait};
use integer::{
    u512, u256_wide_mul, u512_safe_div_rem_by_u256, u256_overflowing_add, u256_as_non_zero,
    u128_overflowing_add
};
use result::{ResultTrait};
use zeroable::{Zeroable};

// Returns the token0, token1 delta owed for a given change in liquidity
fn liquidity_delta_to_amount_delta(
    sqrt_ratio: u256, liquidity_delta: i129, sqrt_ratio_lower: u256, sqrt_ratio_upper: u256
) -> Delta {
    // skip the maths for the 0 case
    if (liquidity_delta.is_zero()) {
        return Zeroable::zero();
    }

    // if the pool is losing liquidity, we round the amount down
    let round_up = !liquidity_delta.is_negative();

    if (sqrt_ratio <= sqrt_ratio_lower) {
        return Delta {
            amount0: i129 {
                mag: amount0_delta(
                    sqrt_ratio_lower, sqrt_ratio_upper, liquidity_delta.mag, round_up
                ),
                sign: liquidity_delta.sign
            },
            amount1: Zeroable::zero()
        };
    } else if (sqrt_ratio < sqrt_ratio_upper) {
        return Delta {
            amount0: i129 {
                mag: amount0_delta(sqrt_ratio, sqrt_ratio_upper, liquidity_delta.mag, round_up),
                sign: liquidity_delta.sign
            },
            amount1: i129 {
                mag: amount1_delta(sqrt_ratio_lower, sqrt_ratio, liquidity_delta.mag, round_up),
                sign: liquidity_delta.sign
            }
        };
    } else {
        return Delta {
            amount0: Zeroable::zero(),
            amount1: i129 {
                mag: amount1_delta(
                    sqrt_ratio_lower, sqrt_ratio_upper, liquidity_delta.mag, round_up
                ),
                sign: liquidity_delta.sign
            }
        };
    }
}
