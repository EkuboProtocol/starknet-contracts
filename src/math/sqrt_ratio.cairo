use core::num::traits::{OverflowingAdd, OverflowingMul, OverflowingSub, Zero};
use core::option::Option;
use crate::math::muldiv::muldiv;
use crate::types::i129::i129;

// Compute the next ratio from a delta amount0, always rounded towards starting price for input, and
// away from starting price for output An empty option is returned on overflow/underflow which means
// the price exceeded the u256 bounds
pub fn next_sqrt_ratio_from_amount0(
    sqrt_ratio: u256, liquidity: u128, amount: i129,
) -> Option<u256> {
    if (amount.is_zero()) {
        return Option::Some(sqrt_ratio);
    }

    assert(liquidity.is_non_zero(), 'NO_LIQUIDITY');

    let numerator1 = u256 { high: liquidity, low: 0 };

    if (amount.sign) {
        // this will revert on overflow, which is fine because it also means the denominator
        // underflows on line 17
        let (product, overflow_mul) = OverflowingMul::overflowing_mul(
            u256 { low: amount.mag, high: 0 }, sqrt_ratio,
        );

        if (overflow_mul) {
            return Option::None(());
        }

        let (denominator, overflow_sub) = OverflowingSub::overflowing_sub(numerator1, product);
        if (overflow_sub | denominator.is_zero()) {
            return Option::None(());
        }

        muldiv(numerator1, sqrt_ratio, denominator, true)
    } else {
        // adding amount0, taking out amount1, price is less than sqrt_ratio and should round up
        let (denominator_p1, _) = DivRem::div_rem(numerator1, sqrt_ratio.try_into().unwrap());
        let denominator = denominator_p1 + u256 { high: 0, low: amount.mag };

        // we know denominator is non-zero because amount.mag is non-zero
        let (quotient, remainder) = DivRem::div_rem(numerator1, denominator.try_into().unwrap());
        return if (remainder.is_zero()) {
            Option::Some(quotient)
        } else {
            let (result, overflow) = OverflowingAdd::overflowing_add(quotient, 1);
            if (overflow) {
                return Option::None(());
            }
            Option::Some(result)
        };
    }
}

// Compute the next ratio from a delta amount1, always rounded towards starting price for input, and
// away from starting price for output An empty option is returned on overflow/underflow which means
// the price exceeded the u256 bounds
pub fn next_sqrt_ratio_from_amount1(
    sqrt_ratio: u256, liquidity: u128, amount: i129,
) -> Option<u256> {
    if (amount.is_zero()) {
        return Option::Some(sqrt_ratio);
    }

    assert(liquidity.is_non_zero(), 'NO_LIQUIDITY');

    let (quotient, remainder) = DivRem::div_rem(
        u256 { low: 0, high: amount.mag }, u256 { low: liquidity, high: 0 }.try_into().unwrap(),
    );

    // because quotient is rounded down, this price movement is also rounded towards sqrt_ratio
    if (amount.sign) {
        // adding amount1, taking out amount0
        let (res, overflow) = OverflowingSub::overflowing_sub(sqrt_ratio, quotient);
        if (overflow) {
            return Option::None(());
        }

        return if (remainder.is_zero()) {
            Option::Some(res)
        } else {
            if (res.is_non_zero()) {
                Option::Some(res - 1_u256)
            } else {
                Option::None(())
            }
        };
    } else {
        // adding amount1, taking out amount0, price goes up
        let (res, overflow) = OverflowingAdd::overflowing_add(sqrt_ratio, quotient);
        if (overflow) {
            return Option::None(());
        }
        return Option::Some(res);
    }
}
