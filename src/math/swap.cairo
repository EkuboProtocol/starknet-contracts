use core::num::traits::Zero;
use core::option::OptionTrait;
use crate::math::delta::{amount0_delta, amount1_delta};
use crate::math::fee::{amount_before_fee, compute_fee};
use crate::math::sqrt_ratio::{next_sqrt_ratio_from_amount0, next_sqrt_ratio_from_amount1};
use crate::types::i129::i129;

// consumed_amount is how much of the amount was used in this step, including the amount that was
// paid to fees calculated_amount is how much of the other token is given
// sqrt_ratio_next is the next ratio, limited to the given sqrt_ratio_limit
// fee_amount is the amount of fee collected, always in terms of the specified amount
#[derive(Copy, Drop, PartialEq)]
pub struct SwapResult {
    pub consumed_amount: i129,
    pub calculated_amount: u128,
    pub sqrt_ratio_next: u256,
    pub fee_amount: u128,
}

pub fn is_price_increasing(exact_output: bool, is_token1: bool) -> bool {
    // sqrt_ratio is expressed in token1/token0, thus:
    // negative token0 = true ^ false = true = increasing
    // negative token1 = true ^ true = false = decreasing
    // positive token0 = false ^ false = false = decreasing
    // positive token1 = false ^ true = true = increasing
    exact_output ^ is_token1
}

pub fn no_op_swap_result(next_sqrt_ratio: u256) -> SwapResult {
    SwapResult {
        consumed_amount: Zero::zero(),
        calculated_amount: Zero::zero(),
        fee_amount: Zero::zero(),
        sqrt_ratio_next: next_sqrt_ratio,
    }
}


// Compute the result of swapping some amount in/out of either token0/token1 against the liquidity
pub fn swap_result(
    sqrt_ratio: u256,
    liquidity: u128,
    sqrt_ratio_limit: u256,
    amount: i129,
    is_token1: bool,
    fee: u128,
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

    // this amount is what moves the price
    let price_impact_amount = if (amount.sign) {
        amount
    } else {
        amount - i129 { mag: compute_fee(amount.mag, fee), sign: false }
    };

    // compute the next sqrt_ratio resulting from trading the entire input/output amount
    let sqrt_ratio_next_from_amount = if (is_token1) {
        next_sqrt_ratio_from_amount1(sqrt_ratio, liquidity, price_impact_amount)
    } else {
        next_sqrt_ratio_from_amount0(sqrt_ratio, liquidity, price_impact_amount)
    };

    let limited = match sqrt_ratio_next_from_amount {
        Option::Some(next) => (next > sqrt_ratio_limit) == increasing,
        Option::None => true,
    };

    // if we exceeded the limit, then adjust the delta to be the amount spent to reach the limit
    if (limited) {
        let (specified_amount_delta, calculated_amount_delta) = if (is_token1) {
            (
                i129 {
                    mag: amount1_delta(sqrt_ratio_limit, sqrt_ratio, liquidity, !amount.sign),
                    sign: amount.sign,
                },
                amount0_delta(sqrt_ratio_limit, sqrt_ratio, liquidity, amount.sign),
            )
        } else {
            (
                i129 {
                    mag: amount0_delta(sqrt_ratio_limit, sqrt_ratio, liquidity, !amount.sign),
                    sign: amount.sign,
                },
                amount1_delta(sqrt_ratio_limit, sqrt_ratio, liquidity, amount.sign),
            )
        };

        let (consumed_amount, calculated_amount, fee_amount) = if amount.sign {
            let before_fee = amount_before_fee(calculated_amount_delta, fee);
            (specified_amount_delta, before_fee, before_fee - calculated_amount_delta)
        } else {
            let before_fee = amount_before_fee(specified_amount_delta.mag, fee);
            (
                i129 { mag: before_fee, sign: false },
                calculated_amount_delta,
                before_fee - specified_amount_delta.mag,
            )
        };

        return SwapResult {
            consumed_amount, calculated_amount, sqrt_ratio_next: sqrt_ratio_limit, fee_amount,
        };
    }

    let sqrt_ratio_next = sqrt_ratio_next_from_amount.unwrap();

    // amount was not enough to move the price, so consume everything as a fee
    if (sqrt_ratio_next == sqrt_ratio) {
        // this scenario should only happen with very small input amounts that do not overcome
        // rounding output amounts should round s.t. they always move by at least one
        assert(!amount.sign, 'INPUT_SMALL_AMOUNT');

        return SwapResult {
            consumed_amount: amount,
            calculated_amount: 0,
            sqrt_ratio_next: sqrt_ratio,
            fee_amount: amount.mag,
        };
    }

    // rounds down for calculated == output, up for calculated == input
    let calculated_amount_excluding_fee = if (is_token1) {
        amount0_delta(sqrt_ratio_next, sqrt_ratio, liquidity, amount.sign)
    } else {
        amount1_delta(sqrt_ratio_next, sqrt_ratio, liquidity, amount.sign)
    };

    // add on the fee to calculated amount for exact output
    let (calculated_amount, fee_amount) = if (amount.sign) {
        let including_fee = amount_before_fee(calculated_amount_excluding_fee, fee);
        (including_fee, including_fee - calculated_amount_excluding_fee)
    } else {
        (calculated_amount_excluding_fee, (amount - price_impact_amount).mag)
    };

    return SwapResult { consumed_amount: amount, calculated_amount, sqrt_ratio_next, fee_amount };
}
