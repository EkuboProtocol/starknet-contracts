use core::num::traits::{WideMul, Zero};

// Returns the fee to charge based on the amount, which is the fee (a 0.128 number) times the
// amount, rounded up
pub fn compute_fee(amount: u128, fee: u128) -> u128 {
    let result = WideMul::<u128, u128>::wide_mul(amount, fee);
    if (result.low == 0) {
        result.high
    } else {
        result.high + 1
    }
}

// Returns the amount before the fee is applied, which is the amount minus the fee, rounded up
pub fn amount_before_fee(after_fee: u128, fee: u128) -> u128 {
    let (quotient, remainder) = DivRem::div_rem(
        u256 { high: after_fee, low: 0 },
        (0x100000000000000000000000000000000_u256 - fee.into()).try_into().unwrap(),
    );

    assert(quotient.high.is_zero(), 'AMOUNT_BEFORE_FEE_OVERFLOW');

    if remainder.is_zero() {
        quotient.low
    } else {
        quotient.low + 1
    }
}

pub fn accumulate_fee_amount(a: u128, b: u128) -> u128 {
    if (a > (0xffffffffffffffffffffffffffffffff_u128 - b)) {
        return 0xffffffffffffffffffffffffffffffff_u128;
    }
    return a + b;
}
