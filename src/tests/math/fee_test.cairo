use crate::math::fee::{accumulate_fee_amount, amount_before_fee, compute_fee};

const MAX_FEE: u128 = 0xffffffffffffffffffffffffffffffff;
const FIFTY_PERCENT_FEE: u128 = 0x80000000000000000000000000000000;

#[test]
#[fuzzer]
fn fuzz_compute_fee_is_bounded_and_monotonic(amount: u128, fee: u128) {
    let computed = compute_fee(amount, fee);
    assert(computed <= amount, 'fee <= amount');

    if fee != MAX_FEE {
        assert(computed <= compute_fee(amount, fee + 1), 'fee monotonic');
    }
}

#[test]
#[fuzzer]
fn fuzz_amount_before_fee_round_trip(after_fee_seed: u64, fee_seed: u128) {
    // At most 50% ensures the gross amount for any u64 seed always fits u128.
    let fee = fee_seed % (FIFTY_PERCENT_FEE + 1);
    let after_fee: u128 = after_fee_seed.into();
    let before_fee = amount_before_fee(after_fee, fee);

    assert(before_fee >= after_fee, 'gross >= net');
    assert_eq!(before_fee - compute_fee(before_fee, fee), after_fee);
}

#[test]
fn test_compute_fee() {
    assert(compute_fee(1000, MAX_FEE) == 1000, 'max fee');
    assert(compute_fee(MAX_FEE, MAX_FEE) == MAX_FEE, 'max fee max amount');
    assert(compute_fee(1000, FIFTY_PERCENT_FEE) == 500, '50%');
    assert(compute_fee(1000, FIFTY_PERCENT_FEE / 2) == 250, '25%');
    assert(compute_fee(1000, FIFTY_PERCENT_FEE / 30) == 17, '1.666...% fee');
    assert(compute_fee(2000, FIFTY_PERCENT_FEE / 30) == 34, '1.666...% fee on 2x amt');
    assert(compute_fee(3000, FIFTY_PERCENT_FEE / 30) == 50, '1.666...% fee on 3x amt');
}

#[test]
fn test_amount_before_fee() {
    assert_eq!(amount_before_fee(1000, FIFTY_PERCENT_FEE / 2), 1334); // 25% fee
    assert_eq!(amount_before_fee(1000, FIFTY_PERCENT_FEE), 2000);
    assert_eq!(amount_before_fee(1000, (FIFTY_PERCENT_FEE / 2) * 3), 4000); // 75% fee
}

#[test]
fn test_accumulate_fee_amount() {
    assert(accumulate_fee_amount(0, 1) == 1, '0+1');
    assert(accumulate_fee_amount(1, 0) == 1, '1+0');
    assert(accumulate_fee_amount(1, 1) == 2, '1+1');
    assert(
        accumulate_fee_amount(
            0xffffffffffffffffffffffffffffffff_u128, 1,
        ) == 0xffffffffffffffffffffffffffffffff_u128,
        'max+1',
    );
    assert(
        accumulate_fee_amount(
            1, 0xffffffffffffffffffffffffffffffff_u128,
        ) == 0xffffffffffffffffffffffffffffffff_u128,
        '1+max',
    );
    assert(
        accumulate_fee_amount(
            0xffffffffffffffffffffffffffffffff_u128, 0xffffffffffffffffffffffffffffffff_u128,
        ) == 0xffffffffffffffffffffffffffffffff_u128,
        'max+max',
    );
}
