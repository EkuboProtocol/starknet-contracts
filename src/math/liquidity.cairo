use ekubo::math::delta::{amount0_delta, amount1_delta};
use ekubo::types::i129::i129;
use ekubo::math::ticks::tick_to_sqrt_ratio;

// Returns the token0, token1 delta owed for a given change in liquidity
fn liquidity_delta_to_amount_delta(
    sqrt_ratio: u256, liquidity_delta: i129, tick_lower: i129, tick_upper: i129
) -> (i129, i129) {
    // handle the 0 case so we do not return 1 for 0 liquidity delta
    if (liquidity_delta == Default::default()) {
        return (Default::default(), Default::default());
    }

    let ratio_lower = tick_to_sqrt_ratio(tick_lower);
    let ratio_upper = tick_to_sqrt_ratio(tick_upper);

    // we always add one to the delta so that we never give more tokens than is owed or receive less than is needed
    // there may be a case where the addition overflows preventing withdrawal, but the user can always do partial withdrawals
    let ZERO = i129 { mag: 0, sign: false };
    // if the pool is losing liquidity, we round the amount down
    let round_up = !liquidity_delta.sign;

    if (sqrt_ratio < ratio_lower) {
        return (
            i129 {
                mag: amount0_delta(
                    ratio_lower, ratio_upper, liquidity_delta.mag, round_up
                ),
                sign: liquidity_delta.sign
            }, ZERO
        );
    } else if (sqrt_ratio < ratio_upper) {
        return (
            i129 {
                mag: amount0_delta(
                    ratio_lower, sqrt_ratio, liquidity_delta.mag, round_up
                ),
                sign: liquidity_delta.sign
                }, i129 {
                mag: amount1_delta(
                    sqrt_ratio, ratio_upper, liquidity_delta.mag, round_up
                ),
                sign: liquidity_delta.sign
            }
        );
    } else {
        return (
            ZERO, i129 {
                mag: amount1_delta(
                    ratio_lower, ratio_upper, liquidity_delta.mag, round_up
                ),
                sign: liquidity_delta.sign
            }
        );
    }
}

