use ekubo::types::i129::i129;
use ekubo::math::muldiv::{muldiv, div};
use option::Option;
use integer::{
    u256_wide_mul, u256_safe_divmod, u256_as_non_zero, u256_overflow_mul, u256_overflow_sub,
    u256_overflowing_add
};

// Compute the next ratio from a delta amount0, always rounded towards starting price for input, and away from starting price for output
// An empty option is returned on overflow/underflow which means the price exceeded the u256 bounds
fn next_sqrt_ratio_from_amount0(sqrt_ratio: u256, liquidity: u128, amount: i129) -> Option<u256> {
    if (amount.mag == 0) {
        return Option::Some(sqrt_ratio);
    }

    assert(liquidity != 0, 'NO_LIQUIDITY');

    let numerator1 = u256 { high: liquidity, low: 0 };

    if (amount.sign) {
        // this will revert on overflow, which is fine because it also means the denominator underflows on line 17
        let (product, overflow_mul) = u256_overflow_mul(
            u256 { low: amount.mag, high: 0 }, sqrt_ratio
        );

        if (overflow_mul) {
            return Option::None(());
        }

        let (denominator, overflow_sub) = u256_overflow_sub(numerator1, product);
        if (overflow_sub) {
            return Option::None(());
        }

        let (result, overflows) = muldiv(numerator1, sqrt_ratio, denominator, true);
        if (overflows) {
            return Option::None(());
        }
        return Option::Some(result);
    } else {
        // adding amount0, taking out amount1, price is less than sqrt_ratio and should round up
        let denominator = (numerator1 / sqrt_ratio) + u256 { high: 0, low: amount.mag };

        // we know denominator is non-zero because amount.mag is non-zero
        let (quotient, remainder) = u256_safe_divmod(numerator1, u256_as_non_zero(denominator));
        return if (remainder == u256 { low: 0, high: 0 }) {
            Option::Some(quotient)
        } else {
            let (result, overflow) = u256_overflowing_add(quotient, u256 { low: 1, high: 0 });
            if (overflow) {
                return Option::None(());
            }
            Option::Some(result)
        };
    }
}

// Compute the next ratio from a delta amount1, always rounded towards starting price for input, and away from starting price for output
// An empty option is returned on overflow/underflow which means the price exceeded the u256 bounds
fn next_sqrt_ratio_from_amount1(sqrt_ratio: u256, liquidity: u128, amount: i129) -> Option<u256> {
    if (amount.mag == 0) {
        return Option::Some(sqrt_ratio);
    }

    assert(liquidity != 0, 'NO_LIQUIDITY');

    let (quotient, remainder) = u256_safe_divmod(
        u256 { low: 0, high: amount.mag }, u256_as_non_zero(u256 { low: liquidity, high: 0 })
    );

    // because quotient is rounded down, this price movement is also rounded towards sqrt_ratio
    if (amount.sign) {
        // adding amount1, taking out amount0
        let (res, overflow) = u256_overflow_sub(sqrt_ratio, quotient);
        if (overflow) {
            return Option::None(());
        }

        return if (remainder == u256 { low: 0, high: 0 }) {
            Option::Some(res)
        } else {
            if (res != u256 { low: 0, high: 0 }) {
                Option::Some(res - u256 { low: 1, high: 0 })
            } else {
                Option::None(())
            }
        };
    } else {
        // adding amount1, taking out amount0, price goes up
        let (res, overflow) = u256_overflowing_add(sqrt_ratio, quotient);
        if (overflow) {
            return Option::None(());
        }
        return Option::Some(res);
    }
}

// Compute the difference in amount of token0 between two ratios, rounded as specified
fn amount0_delta(sqrt_ratio_a: u256, sqrt_ratio_b: u256, liquidity: u128, round_up: bool) -> u128 {
    let (sqrt_ratio_lower, sqrt_ratio_upper) = if sqrt_ratio_a < sqrt_ratio_b {
        (sqrt_ratio_a, sqrt_ratio_b)
    } else {
        (sqrt_ratio_b, sqrt_ratio_a)
    };

    assert((sqrt_ratio_lower.high != 0) | (sqrt_ratio_lower.low != 0), 'NONZERO_RATIO');

    if ((liquidity == 0) | (sqrt_ratio_a == sqrt_ratio_b)) {
        return 0;
    }

    let (result_0, result_0_overflow) = muldiv(
        u256 { low: 0, high: liquidity },
        sqrt_ratio_upper - sqrt_ratio_lower,
        sqrt_ratio_upper,
        round_up
    );
    assert(!result_0_overflow, 'OVERFLOW_AMOUNT0_DELTA_0');
    let result = div(result_0, sqrt_ratio_lower, round_up);
    assert(result.high == 0, 'OVERFLOW_AMOUNT0_DELTA');

    return result.low;
}

// Compute the difference in amount of token1 between two ratios, rounded as specified
fn amount1_delta(sqrt_ratio_a: u256, sqrt_ratio_b: u256, liquidity: u128, round_up: bool) -> u128 {
    let (sqrt_ratio_lower, sqrt_ratio_upper) = if sqrt_ratio_a < sqrt_ratio_b {
        (sqrt_ratio_a, sqrt_ratio_b)
    } else {
        (sqrt_ratio_b, sqrt_ratio_a)
    };

    assert((sqrt_ratio_lower.high != 0) | (sqrt_ratio_lower.low != 0), 'NONZERO_RATIO');

    if ((liquidity == 0) | (sqrt_ratio_a == sqrt_ratio_b)) {
        return 0;
    }

    let result = u256_wide_mul(
        u256 { low: liquidity, high: 0 }, sqrt_ratio_upper - sqrt_ratio_lower
    );

    assert((result.limb3 == 0) & (result.limb2 == 0), 'OVERFLOW');

    if (round_up & (result.limb0 != 0)) {
        result.limb1 + 1
    } else {
        result.limb1
    }
}

