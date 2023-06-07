use ekubo::types::i129::i129;
use ekubo::math::muldiv::{muldiv, div};
use integer::{u256_wide_mul, u256_safe_divmod, u256_as_non_zero};

// Compute the next ratio from a delta amount0, rounded towards starting price for input, and away from starting price for output
fn next_sqrt_ratio_from_amount0(sqrt_ratio: u256, liquidity: u128, amount: i129) -> u256 {
    if (amount.mag == 0) {
        return sqrt_ratio;
    }

    assert(liquidity != 0, 'NO_LIQUIDITY');

    let numerator1 = u256 { high: liquidity, low: 0 };

    if (amount.sign) {
        // this will revert on overflow, which is fine because it also means the denominator underflows on line 17
        let product = u256 { low: amount.mag, high: 0 } * sqrt_ratio;

        let denominator = numerator1 - product;

        return muldiv(numerator1, sqrt_ratio, denominator, true);
    } else {
        // adding amount0, taking out amount1, price is less than sqrt_ratio and should round up
        let denominator = (numerator1 / sqrt_ratio) + u256 { high: 0, low: amount.mag };

        // we know denominator is non-zero because amount.mag is non-zero
        let (quotient, remainder) = u256_safe_divmod(numerator1, u256_as_non_zero(denominator));
        return if (remainder != u256 { low: 0, high: 0 }) {
            quotient + u256 { low: 1, high: 0 }
        } else {
            quotient
        };
    }
}

// Compute the next ratio from a delta amount1, rounded towards the starting price
fn next_sqrt_ratio_from_amount1(sqrt_ratio: u256, liquidity: u128, amount: i129) -> u256 {
    if (amount.mag == 0) {
        return sqrt_ratio;
    }

    assert(liquidity != 0, 'NO_LIQUIDITY');

    let (quotient, remainder) = u256_safe_divmod(
        u256 { low: 0, high: amount.mag }, u256_as_non_zero(u256 { low: liquidity, high: 0 })
    );

    // because quotient is rounded down, this price movement is also rounded towards sqrt_ratio
    if (amount.sign) {
        // adding amount1, taking out amount0
        return if (remainder != u256 { low: 0, high: 0 }) {
            sqrt_ratio - quotient
        } else {
            sqrt_ratio - quotient - u256 { low: 1, high: 0 }
        };
    } else {
        // adding amount1, taking out amount0, price goes up
        return sqrt_ratio + quotient;
    }
}

// Compute the difference in amount of token0 between two ratios, rounded down
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

    let numerator1 = u256 { low: 0, high: liquidity };
    let numerator2 = sqrt_ratio_upper - sqrt_ratio_lower;

    let result_0 = muldiv(numerator1, numerator2, sqrt_ratio_upper, round_up);
    let result = div(result_0, sqrt_ratio_lower, round_up);
    assert(result.high == 0, 'OVERFLOW_AMOUNT0_DELTA');

    return result.low;
}

// Compute the difference in amount of token1 between two ratios, rounded down
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

    let result = muldiv(
        u256 { low: liquidity, high: 0 },
        sqrt_ratio_upper - sqrt_ratio_lower,
        u256 { high: 1, low: 0 },
        round_up
    );
    assert(result.high == 0, 'OVERFLOW');

    return result.low;
}

