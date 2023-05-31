use parlay::math::fee::{compute_fee, amount_with_fee, accumulate_fee_amount};
use debug::PrintTrait;
use parlay::types::i129::i129;

const MAX_FEE: u128 = 0xffffffffffffffffffffffffffffffff;
const FIFTY_PERCENT_FEE: u128 = 0x80000000000000000000000000000000;

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
fn test_amount_with_fee() {
    assert(
        amount_with_fee(i129 { mag: 1000, sign: false }, FIFTY_PERCENT_FEE) == i129 {
            mag: 500, sign: false
        },
        'max'
    );
    assert(
        amount_with_fee(i129 { mag: 1000, sign: false }, FIFTY_PERCENT_FEE / 2) == i129 {
            mag: 750, sign: false
        },
        'max/2'
    );
    assert(
        amount_with_fee(i129 { mag: 1000, sign: false }, FIFTY_PERCENT_FEE / 30) == i129 {
            mag: 983, sign: false
        },
        'max/30'
    );
    assert(
        amount_with_fee(i129 { mag: 1000, sign: true }, FIFTY_PERCENT_FEE) == i129 {
            mag: 1500, sign: true
        },
        'max'
    );
    assert(
        amount_with_fee(i129 { mag: 1000, sign: true }, FIFTY_PERCENT_FEE / 2) == i129 {
            mag: 1250, sign: true
        },
        'max/2'
    );
    assert(
        amount_with_fee(i129 { mag: 1000, sign: true }, FIFTY_PERCENT_FEE / 30) == i129 {
            mag: 1017, sign: true
        },
        'max/30'
    );
}

#[test]
fn test_accumulate_fee_amount() {
    assert(accumulate_fee_amount(0, 1) == 1, '0+1');
    assert(accumulate_fee_amount(1, 0) == 1, '1+0');
    assert(accumulate_fee_amount(1, 1) == 2, '1+1');
    assert(
        accumulate_fee_amount(
            0xffffffffffffffffffffffffffffffff_u128, 1
        ) == 0xffffffffffffffffffffffffffffffff_u128,
        'max+1'
    );
    assert(
        accumulate_fee_amount(
            1, 0xffffffffffffffffffffffffffffffff_u128
        ) == 0xffffffffffffffffffffffffffffffff_u128,
        '1+max'
    );
    assert(
        accumulate_fee_amount(
            0xffffffffffffffffffffffffffffffff_u128, 0xffffffffffffffffffffffffffffffff_u128
        ) == 0xffffffffffffffffffffffffffffffff_u128,
        'max+max'
    );
}
