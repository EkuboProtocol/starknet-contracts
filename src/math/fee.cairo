use integer::{u256_safe_divmod, u256_as_non_zero};
use ekubo::types::i129::i129;

// Returns the fee to charge based on the amount, which is the fee (a 0.128 number) times the amount, rounded up
#[inline(always)]
fn compute_fee(amount: u128, fee: u128) -> u128 {
    let num = u256 { low: amount, high: 0 } * u256 { low: fee, high: 0 };
    if (num.low == 0) {
        num.high
    } else {
        num.high + 1
    }
}

#[inline(always)]
fn amount_with_fee(amount: i129, fee: u128) -> i129 {
    let fee_amount = compute_fee(amount.mag, fee);
    // for exact output, we get more output
    // for exact input, we spend less input
    amount - i129 { mag: fee_amount, sign: false }
}

#[inline(always)]
fn accumulate_fee_amount(a: u128, b: u128) -> u128 {
    if (a > (0xffffffffffffffffffffffffffffffff_u128 - b)) {
        return 0xffffffffffffffffffffffffffffffff_u128;
    }
    return a + b;
}
