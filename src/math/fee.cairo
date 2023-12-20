use ekubo::types::i129::i129;
use core::integer::{u128_wide_mul, u256_safe_divmod, u256_as_non_zero};
use core::zeroable::{Zeroable};

// Returns the fee to charge based on the amount, which is the fee (a 0.128 number) times the amount, rounded up
#[inline(always)]
fn compute_fee(amount: u128, fee: u128) -> u128 {
    let (high, low) = u128_wide_mul(amount, fee);
    if (low == 0) {
        high
    } else {
        high + 1
    }
}

// Returns the amount before the fee is applied, which is the amount minus the fee, rounded up
fn amount_before_fee(after_fee: u128, fee: u128) -> u128 {
    let (quotient, remainder, _) = u256_safe_divmod(
        u256 { high: after_fee, low: 0 },
        u256_as_non_zero(0x100000000000000000000000000000000_u256 - u256 { high: 0, low: fee })
    );

    assert(quotient.high.is_zero(), 'AMOUNT_BEFORE_FEE_OVERFLOW');

    if remainder.is_zero() {
        quotient.low
    } else {
        quotient.low + 1
    }
}

#[inline(always)]
fn accumulate_fee_amount(a: u128, b: u128) -> u128 {
    if (a > (0xffffffffffffffffffffffffffffffff_u128 - b)) {
        return 0xffffffffffffffffffffffffffffffff_u128;
    }
    return a + b;
}
