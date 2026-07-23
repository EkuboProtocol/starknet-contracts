use core::integer::{u512, u512_safe_div_rem_by_u256};
use core::num::traits::{OverflowingAdd, OverflowingMul, OverflowingSub, WideMul, Zero};
use core::option::Option;
use crate::math::muldiv::muldiv;
use crate::types::i129::i129;

const TWO_POW_64: u128 = 0x10000000000000000;

fn u256_from_u128_limbs_shifted_right_64(low: u128, high: u128) -> u128 {
    (low / TWO_POW_64) + ((high % TWO_POW_64) * TWO_POW_64)
}

fn u512_lt(a: u512, b: u512) -> bool {
    if a.limb3 != b.limb3 {
        a.limb3 < b.limb3
    } else if a.limb2 != b.limb2 {
        a.limb2 < b.limb2
    } else if a.limb1 != b.limb1 {
        a.limb1 < b.limb1
    } else {
        a.limb0 < b.limb0
    }
}

fn u512_sub(a: u512, b: u512) -> u512 {
    let (limb0, borrow0) = OverflowingSub::overflowing_sub(a.limb0, b.limb0);
    let (limb1_p0, borrow1_p0) = OverflowingSub::overflowing_sub(a.limb1, b.limb1);
    let (limb1, borrow1_p1) = OverflowingSub::overflowing_sub(
        limb1_p0, if borrow0 {
            1
        } else {
            0
        },
    );
    let borrow1 = borrow1_p0 | borrow1_p1;
    let (limb2_p0, borrow2_p0) = OverflowingSub::overflowing_sub(a.limb2, b.limb2);
    let (limb2, borrow2_p1) = OverflowingSub::overflowing_sub(
        limb2_p0, if borrow1 {
            1
        } else {
            0
        },
    );
    let borrow2 = borrow2_p0 | borrow2_p1;
    let (limb3_p0, borrow3_p0) = OverflowingSub::overflowing_sub(a.limb3, b.limb3);
    let (limb3, borrow3_p1) = OverflowingSub::overflowing_sub(
        limb3_p0, if borrow2 {
            1
        } else {
            0
        },
    );
    assert(!(borrow3_p0 | borrow3_p1), 'U512_SUB_UNDERFLOW');
    u512 { limb0, limb1, limb2, limb3 }
}

fn u512_mul_u128(value: u512, multiplier: u128) -> Option<u512> {
    let product0 = WideMul::<u128, u128>::wide_mul(value.limb0, multiplier);
    let product1 = WideMul::<u128, u128>::wide_mul(value.limb1, multiplier);
    let product2 = WideMul::<u128, u128>::wide_mul(value.limb2, multiplier);
    let product3 = WideMul::<u128, u128>::wide_mul(value.limb3, multiplier);

    let (limb1, carry1) = OverflowingAdd::overflowing_add(product0.high, product1.low);
    let (limb2_p0, carry2_p0) = OverflowingAdd::overflowing_add(product1.high, product2.low);
    let (limb2, carry2_p1) = OverflowingAdd::overflowing_add(limb2_p0, if carry1 {
        1
    } else {
        0
    });
    let (limb3_p0, carry3_p0) = OverflowingAdd::overflowing_add(product2.high, product3.low);
    let (limb3_p1, carry3_p1) = OverflowingAdd::overflowing_add(
        limb3_p0, if carry2_p0 {
            1
        } else {
            0
        },
    );
    let (limb3, carry3_p2) = OverflowingAdd::overflowing_add(
        limb3_p1, if carry2_p1 {
            1
        } else {
            0
        },
    );

    if product3.high.is_non_zero() | carry3_p0 | carry3_p1 | carry3_p2 {
        Option::None(())
    } else {
        Option::Some(u512 { limb0: product0.low, limb1, limb2, limb3 })
    }
}

// Computes ceil(numerator1 * sqrt_ratio / (numerator1 + amount * sqrt_ratio))
// without truncating numerator1 / sqrt_ratio. numerator1 is liquidity * 2**128.
fn next_sqrt_ratio_from_amount0_input(
    sqrt_ratio: u256, numerator1: u256, amount: u128,
) -> Option<u256> {
    let amount_times_ratio = WideMul::<
        u256, u256,
    >::wide_mul(u256 { low: amount, high: 0 }, sqrt_ratio);
    let (denominator_limb1, carry1) = OverflowingAdd::overflowing_add(
        amount_times_ratio.limb1, numerator1.high,
    );
    let (denominator_limb2, carry2) = OverflowingAdd::overflowing_add(
        amount_times_ratio.limb2, if carry1 {
            1
        } else {
            0
        },
    );
    let (denominator_limb3, carry3) = OverflowingAdd::overflowing_add(
        amount_times_ratio.limb3, if carry2 {
            1
        } else {
            0
        },
    );
    if carry3 {
        return Option::None(());
    }
    let denominator = u512 {
        limb0: amount_times_ratio.limb0,
        limb1: denominator_limb1,
        limb2: denominator_limb2,
        limb3: denominator_limb3,
    };

    // The common case has a u256 denominator and can use the checked 512-bit mul-div directly.
    if denominator.limb3.is_zero() & denominator.limb2.is_zero() {
        return muldiv(
            numerator1, sqrt_ratio, u256 { low: denominator.limb0, high: denominator.limb1 }, true,
        );
    }

    // At supported ratios sqrt_ratio < 2**192, so the denominator is less than 2**320.
    // Retain the remainder from numerator1 / sqrt_ratio and use it to correct the quotient
    // instead of dropping it as the previous implementation did.
    if denominator.limb3.is_non_zero() | ((denominator.limb2 / TWO_POW_64) != 0) {
        return Option::None(());
    }
    let (ratio_quotient, ratio_remainder) = DivRem::div_rem(
        numerator1, sqrt_ratio.try_into().unwrap(),
    );
    let (provisional_denominator, provisional_denominator_overflow) =
        OverflowingAdd::overflowing_add(
        ratio_quotient, u256 { low: amount, high: 0 },
    );
    if provisional_denominator_overflow {
        return Option::None(());
    }
    let (provisional_quotient, provisional_remainder) = DivRem::div_rem(
        numerator1, provisional_denominator.try_into().unwrap(),
    );

    // numerator1 * sqrt_ratio - provisional_quotient * denominator equals
    // provisional_remainder * sqrt_ratio - provisional_quotient * ratio_remainder.
    let remainder_times_ratio = WideMul::<u256, u256>::wide_mul(provisional_remainder, sqrt_ratio);
    let quotient_times_remainder = WideMul::<
        u256, u256,
    >::wide_mul(provisional_quotient, ratio_remainder);
    if !u512_lt(remainder_times_ratio, quotient_times_remainder) {
        return if remainder_times_ratio == quotient_times_remainder {
            Option::Some(provisional_quotient)
        } else {
            let (result, overflow) = OverflowingAdd::overflowing_add(provisional_quotient, 1_u256);
            if overflow {
                Option::None(())
            } else {
                Option::Some(result)
            }
        };
    }

    // The provisional quotient is high. If E is its excess numerator, then
    // ceil((numerator1 * sqrt_ratio) / denominator) =
    // provisional_quotient - floor(E / denominator).
    let excess = u512_sub(quotient_times_remainder, remainder_times_ratio);
    let shifted_denominator = u256 {
        low: u256_from_u128_limbs_shifted_right_64(denominator.limb0, denominator.limb1),
        high: u256_from_u128_limbs_shifted_right_64(denominator.limb1, denominator.limb2),
    };
    let shifted_excess = u512 {
        limb0: u256_from_u128_limbs_shifted_right_64(excess.limb0, excess.limb1),
        limb1: u256_from_u128_limbs_shifted_right_64(excess.limb1, excess.limb2),
        limb2: u256_from_u128_limbs_shifted_right_64(excess.limb2, excess.limb3),
        limb3: excess.limb3 / TWO_POW_64,
    };
    let (correction_wide, _) = u512_safe_div_rem_by_u256(
        shifted_excess, shifted_denominator.try_into().unwrap(),
    );
    if correction_wide.limb3.is_non_zero()
        | correction_wide.limb2.is_non_zero()
        | correction_wide.limb1.is_non_zero() {
        return Option::None(());
    }
    let mut correction = correction_wide.limb0;
    let correction_product = u512_mul_u128(denominator, correction)?;
    if u512_lt(excess, correction_product) {
        correction -= 1;
    } else {
        let (next_correction, overflow) = OverflowingAdd::overflowing_add(correction, 1);
        if !overflow {
            let next_correction_product = u512_mul_u128(denominator, next_correction)?;
            if !u512_lt(excess, next_correction_product) {
                correction = next_correction;
            }
        }
    }

    let (result, underflow) = OverflowingSub::overflowing_sub(
        provisional_quotient, u256 { low: correction, high: 0 },
    );
    if underflow {
        Option::None(())
    } else {
        Option::Some(result)
    }
}

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
        next_sqrt_ratio_from_amount0_input(sqrt_ratio, numerator1, amount.mag)
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
