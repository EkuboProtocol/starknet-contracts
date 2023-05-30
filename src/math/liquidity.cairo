use parlay::math::delta::{amount0_delta, amount1_delta};
use parlay::types::i129::i129;
use parlay::math::ticks::tick_to_sqrt_ratio;

// Returns the token0, token1 delta owed for a given change in liquidity
fn liquidity_delta_to_amount_delta(
    sqrt_ratio: u256, liquidity_delta: i129, tick_lower: i129, tick_upper: i129
) -> (i129, i129) {
    let ratio_lower = tick_to_sqrt_ratio(tick_lower);
    let ratio_upper = tick_to_sqrt_ratio(tick_upper);

    // if liquidity is being added, we round up by adding one, otherwise we round down by subtracting one
    // there may be a case where it underflows preventing withdrawal, but that's ok because that would mean zero loss
    let ONE = i129 { mag: 1, sign: false };
    let ZERO = i129 { mag: 0, sign: false };

    if (sqrt_ratio < ratio_lower) {
        return (
            i129 {
                mag: amount0_delta(ratio_lower, ratio_upper, liquidity_delta.mag),
                sign: liquidity_delta.sign
            } + ONE, ZERO
        );
    } else if (sqrt_ratio < ratio_upper) {
        return (
            i129 {
                mag: amount0_delta(ratio_lower, sqrt_ratio, liquidity_delta.mag),
                sign: liquidity_delta.sign
                } + ONE, i129 {
                mag: amount1_delta(sqrt_ratio, ratio_upper, liquidity_delta.mag),
                sign: liquidity_delta.sign
            } + ONE
        );
    } else {
        return (
            ZERO, i129 {
                mag: amount1_delta(ratio_lower, ratio_upper, liquidity_delta.mag),
                sign: liquidity_delta.sign
            } + ONE
        );
    }
}

