use ekubo::types::i129::i129;
use integer::{u128_wide_mul};

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

#[inline(always)]
fn accumulate_fee_amount(a: u128, b: u128) -> u128 {
    if (a > (0xffffffffffffffffffffffffffffffff_u128 - b)) {
        return 0xffffffffffffffffffffffffffffffff_u128;
    }
    return a + b;
}
