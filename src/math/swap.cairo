use parlay::types::i129::{i129};
use parlay::math::delta::{
    next_sqrt_ratio_from_amount0, next_sqrt_ratio_from_amount1, amount0_delta, amount1_delta
};
use parlay::math::fee::{compute_fee, amount_with_fee};
use traits::Into;

// consumed_amount is how much of the amount was used in this step
// calculated_amount is how much of the other token is given
// sqrt_ratio_next is the next ratio, limited to the given sqrt_ratio_limit
// fee_amount is the amount of fee collected, always in terms of the specified amount
#[derive(Copy, Drop)]
struct SwapResult {
    consumed_amount: i129,
    calculated_amount: u128,
    sqrt_ratio_next: u256,
    fee_amount: u128
}

#[inline(always)]
fn is_price_increasing(exact_output: bool, is_token1: bool) -> bool {
    exact_output ^ is_token1
}

// Compute the result of swapping some amount in/out of either token0/token1 against the liquidity
fn swap_result(
    sqrt_ratio: u256,
    liquidity: u128,
    sqrt_ratio_limit: u256,
    amount: i129,
    is_token1: bool,
    fee: u128
) -> SwapResult {
    // if we are at the final price already, or the liquidity is 0, early exit with the next price
    // note sqrt_ratio_limit is the sqrt_ratio_next in both cases
    if ((liquidity == 0) | (sqrt_ratio == sqrt_ratio_limit)) {
        return SwapResult {
            consumed_amount: Default::default(),
            calculated_amount: 0,
            fee_amount: 0,
            sqrt_ratio_next: sqrt_ratio_limit
        };
    }

    // no amount traded means no-op, price doesn't move
    if (amount.mag == 0) {
        return SwapResult {
            consumed_amount: Default::default(),
            calculated_amount: 0,
            fee_amount: 0,
            sqrt_ratio_next: sqrt_ratio
        };
    }

    // sqrt_ratio is token1/token0, thus:
    // negative token0 = true ^ false = true = increasing
    // positive token0 = false ^ false = false = decreasing
    // negative token1 = true ^ true = false = decreasing
    // negative token0 = true ^ false = true = increasing
    let increasing = is_price_increasing(amount.sign, is_token1);

    // we know limit != sqrt_ratio because of the early return, so this ensures that the limit is in the correct direction
    assert((sqrt_ratio_limit > sqrt_ratio) == increasing, 'DIRECTION');

    // todo: below this line still under construction

    // this amount is what moves the price. fee is always taken on the specified amount
    let with_fee = amount_with_fee(amount, fee);

    // compute the next sqrt_ratio resulting from trading the entire input/output amount
    let mut sqrt_ratio_next: u256 = if (is_token1) {
        next_sqrt_ratio_from_amount1(sqrt_ratio, liquidity, with_fee)
    } else {
        next_sqrt_ratio_from_amount0(sqrt_ratio, liquidity, with_fee)
    };

    // if we exceeded the limit, then adjust the delta to be the amount spent to reach the limit
    if ((sqrt_ratio_next > sqrt_ratio_limit) == increasing) {
        sqrt_ratio_next = sqrt_ratio_limit;

        let (consumed_amount, calculated_amount) = if (is_token1) {
            (
                i129 {
                    mag: amount1_delta(sqrt_ratio_next, sqrt_ratio, liquidity, true),
                    sign: amount.sign
                }, amount0_delta(sqrt_ratio_next, sqrt_ratio, liquidity, false)
            )
        } else {
            (
                i129 {
                    mag: amount0_delta(sqrt_ratio_next, sqrt_ratio, liquidity, true),
                    sign: amount.sign
                }, amount1_delta(sqrt_ratio_next, sqrt_ratio, liquidity, false)
            )
        };

        return SwapResult {
            consumed_amount,
            calculated_amount,
            sqrt_ratio_next,
            fee_amount: (amount_with_fee(consumed_amount, fee) - consumed_amount).mag
        };
    }

    // amount was not enough to move the price, so consume everything as a fee
    if (sqrt_ratio_next == sqrt_ratio) {
        return SwapResult {
            consumed_amount: amount,
            calculated_amount: 0,
            sqrt_ratio_next: sqrt_ratio,
            fee_amount: amount.mag
        };
    }

    // rounds down
    let calculated_amount = if (is_token1) {
        amount0_delta(sqrt_ratio_next, sqrt_ratio, liquidity, false)
    } else {
        amount1_delta(sqrt_ratio_next, sqrt_ratio, liquidity, false)
    };

    // otherwise, the consumed amount is the input amount, we just computed the next ratio and fee
    return SwapResult {
        consumed_amount: amount,
        calculated_amount,
        sqrt_ratio_next,
        fee_amount: (with_fee - amount).mag
    };
}
