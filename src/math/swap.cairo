use ekubo::types::i129::{i129};
use ekubo::math::sqrt_ratio::{next_sqrt_ratio_from_amount0, next_sqrt_ratio_from_amount1};
use ekubo::math::delta::{amount0_delta, amount1_delta};
use ekubo::math::fee::{compute_fee, amount_with_fee};
use traits::Into;
use zeroable::Zeroable;

// consumed_amount is how much of the amount was used in this step, including the amount that was paid to fees
// calculated_amount is how much of the other token is given
// sqrt_ratio_next is the next ratio, limited to the given sqrt_ratio_limit
// fee_amount is the amount of fee collected, always in terms of the specified amount
#[derive(Copy, Drop, PartialEq)]
struct SwapResult {
    consumed_amount: i129,
    calculated_amount: u128,
    sqrt_ratio_next: u256,
    fee_amount: u128
}

#[inline(always)]
fn is_price_increasing(exact_output: bool, is_token1: bool) -> bool {
    // sqrt_ratio is expressed in token1/token0, thus:
    // negative token0 = true ^ false = true = increasing
    // positive token0 = false ^ false = false = decreasing
    // negative token1 = true ^ true = false = decreasing
    // negative token0 = true ^ false = true = increasing
    exact_output ^ is_token1
}

#[inline(always)]
fn no_op_swap_result(next_sqrt_ratio: u256) -> SwapResult {
    SwapResult {
        consumed_amount: Zeroable::zero(),
        calculated_amount: Zeroable::zero(),
        fee_amount: Zeroable::zero(),
        sqrt_ratio_next: next_sqrt_ratio
    }
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
    // no amount traded means no-op, price doesn't move
    // also if the limit is the current price, price cannot move
    if (amount.is_zero() | (sqrt_ratio == sqrt_ratio_limit)) {
        return no_op_swap_result(sqrt_ratio);
    }

    let increasing = is_price_increasing(amount.sign, is_token1);

    // we know sqrt_ratio != sqrt_ratio_limit because of the early return,
    // so this ensures that the limit is in the correct direction
    assert((sqrt_ratio_limit > sqrt_ratio) == increasing, 'DIRECTION');

    // if liquidity is 0, early exit with the next price because there is nothing to trade against
    if (liquidity.is_zero()) {
        return no_op_swap_result(sqrt_ratio_limit);
    }

    // this amount is what moves the price. fee is always taken on the specified amount
    // if the user is buying a token, then they pay a fee on the purchased amount
    // if the user is selling a token, then they pay a fee on the sold amount
    let price_impact_amount = amount_with_fee(amount, fee);

    // compute the next sqrt_ratio resulting from trading the entire input/output amount
    let mut sqrt_ratio_next: u256 = if (is_token1) {
        match next_sqrt_ratio_from_amount1(sqrt_ratio, liquidity, price_impact_amount) {
            Option::Some(next) => next,
            Option::None => sqrt_ratio_limit
        }
    } else {
        match next_sqrt_ratio_from_amount0(sqrt_ratio, liquidity, price_impact_amount) {
            Option::Some(next) => next,
            Option::None => sqrt_ratio_limit
        }
    };

    // if we exceeded the limit, then adjust the delta to be the amount spent to reach the limit
    if ((sqrt_ratio_next > sqrt_ratio_limit) == increasing) {
        sqrt_ratio_next = sqrt_ratio_limit;

        let (consumed_amount, calculated_amount) = if (is_token1) {
            (
                i129 {
                    mag: amount1_delta(sqrt_ratio_next, sqrt_ratio, liquidity, !amount.sign),
                    sign: amount.sign
                }, amount0_delta(sqrt_ratio_next, sqrt_ratio, liquidity, amount.sign)
            )
        } else {
            (
                i129 {
                    mag: amount0_delta(sqrt_ratio_next, sqrt_ratio, liquidity, !amount.sign),
                    sign: amount.sign
                }, amount1_delta(sqrt_ratio_next, sqrt_ratio, liquidity, amount.sign)
            )
        };

        let fee_amount = compute_fee(consumed_amount.mag, fee);

        return SwapResult {
            consumed_amount: consumed_amount + i129 {
                mag: fee_amount, sign: false
            }, calculated_amount, sqrt_ratio_next, fee_amount
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
        fee_amount: (price_impact_amount - amount).mag
    };
}
