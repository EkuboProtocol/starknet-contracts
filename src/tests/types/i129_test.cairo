use core::hash::LegacyHash;
use core::num::traits::Zero;
use starknet::storage_access::StorePacking;
use crate::tests::store_packing_test::assert_round_trip;
use crate::tests::types::keys_test::check_hashes_differ;
use crate::types::i129::{AddDeltaTrait, i129};

#[test]
fn test_legacy_hash_i129() {
    check_hashes_differ(i129 { mag: 0, sign: false }, i129 { mag: 1, sign: false });
    check_hashes_differ(i129 { mag: 1, sign: true }, i129 { mag: 1, sign: false });
    check_hashes_differ(i129 { mag: 1, sign: true }, i129 { mag: 0, sign: false });

    assert(
        LegacyHash::hash(
            0, i129 { mag: 0, sign: false },
        ) == LegacyHash::hash(0, i129 { mag: 0, sign: true }),
        'hash of 0',
    );
}

#[test]
fn test_zero() {
    assert(Zero::<i129>::zero() == i129 { mag: 0, sign: false }, 'zero()');
    assert(Zero::<i129>::zero().is_zero(), '0.is_zero()');
    assert(!Zero::<i129>::zero().is_non_zero(), '0.is_non_zero()');
    assert(i129 { mag: 0, sign: true }.is_zero(), '-0.is_zero()');
    assert(!i129 { mag: 0, sign: true }.is_non_zero(), '-0.is_non_zero()');

    assert(!i129 { mag: 1, sign: true }.is_zero(), '-1.is_zero()');
    assert(i129 { mag: 1, sign: true }.is_non_zero(), '-1.is_non_zero()');

    assert(!i129 { mag: 1, sign: false }.is_zero(), '1.is_zero()');
    assert(i129 { mag: 1, sign: false }.is_non_zero(), '1.is_non_zero()');
}

#[test]
fn test_div_i129() {
    assert(
        i129 { mag: 15, sign: false }
            / i129 { mag: 4, sign: false } == i129 { mag: 3, sign: false },
        '15/4',
    );
    assert(
        i129 { mag: 15, sign: true } / i129 { mag: 4, sign: false } == i129 { mag: 3, sign: true },
        '-15/4',
    );
    assert(
        i129 { mag: 15, sign: false } / i129 { mag: 4, sign: true } == i129 { mag: 3, sign: true },
        '15/-4',
    );
    assert(
        i129 { mag: 15, sign: true } / i129 { mag: 4, sign: true } == i129 { mag: 3, sign: false },
        '-15/-4',
    );
}

#[test]
fn test_gt() {
    assert((Zero::zero() > i129 { mag: 0, sign: true }) == false, '0 > -0');
    assert((i129 { mag: 1, sign: false } > i129 { mag: 0, sign: true }) == true, '1 > -0');
    assert((i129 { mag: 1, sign: true } > i129 { mag: 0, sign: true }) == false, '-1 > -0');
    assert((i129 { mag: 1, sign: true } > Zero::zero()) == false, '-1 > 0');
    assert((i129 { mag: 1, sign: false } > i129 { mag: 1, sign: false }) == false, '1 > 1');
}

#[test]
fn test_lt() {
    assert((Zero::zero() < i129 { mag: 0, sign: true }) == false, '0 < -0');
    assert((Zero::zero() < i129 { mag: 1, sign: true }) == false, '0 < -1');
    assert((i129 { mag: 1, sign: false } < i129 { mag: 1, sign: false }) == false, '1 < 1');

    assert((i129 { mag: 1, sign: true } < Zero::zero()) == true, '-1 < 0');
    assert((i129 { mag: 1, sign: true } < i129 { mag: 0, sign: true }) == true, '-1 < -0');
    assert((Zero::zero() < i129 { mag: 1, sign: false }) == true, '0 < 1');
    assert((i129 { mag: 1, sign: false } < i129 { mag: 2, sign: false }) == true, '1 < 2');
}

#[test]
fn test_gte() {
    assert((Zero::zero() >= i129 { mag: 0, sign: true }) == true, '0 >= -0');
    assert((i129 { mag: 1, sign: false } >= i129 { mag: 0, sign: true }) == true, '1 >= -0');
    assert((i129 { mag: 1, sign: true } >= i129 { mag: 0, sign: true }) == false, '-1 >= -0');
    assert((i129 { mag: 1, sign: true } >= Zero::zero()) == false, '-1 >= 0');
    assert((Zero::<i129>::zero() >= Zero::zero()) == true, '0 >= 0');
}

#[test]
fn test_eq() {
    assert((Zero::zero() == i129 { mag: 0, sign: true }) == true, '0 == -0');
    assert((Zero::zero() == i129 { mag: 1, sign: true }) == false, '0 != -1');
    assert((i129 { mag: 1, sign: false } == i129 { mag: 1, sign: true }) == false, '1 != -1');
    assert((i129 { mag: 1, sign: true } == i129 { mag: 1, sign: true }) == true, '-1 = -1');
    assert((i129 { mag: 1, sign: false } == i129 { mag: 1, sign: false }) == true, '1 = 1');
}

#[test]
fn test_lte() {
    assert((Zero::zero() <= i129 { mag: 0, sign: true }) == true, '0 <= -0');
    assert((i129 { mag: 1, sign: false } <= i129 { mag: 0, sign: true }) == false, '1 <= -0');
    assert((i129 { mag: 1, sign: true } <= i129 { mag: 0, sign: true }) == true, '-1 <= -0');
    assert((i129 { mag: 1, sign: true } <= Zero::zero()) == true, '-1 <= 0');
    assert((Zero::<i129>::zero() <= Zero::zero()) == true, '0 <= 0');
}

#[test]
fn test_mul_negative_negative() {
    let x: i129 = i129 { mag: 0x1, sign: true } * i129 { mag: 0x1, sign: true };
    assert(x == i129 { mag: 0x1, sign: false }, '-1 * -1 = 1');
}

#[test]
fn test_mul_negative_positive() {
    let x: i129 = i129 { mag: 0x1, sign: true } * i129 { mag: 0x1, sign: false };
    assert(x == i129 { mag: 0x1, sign: true }, '-1 * 1 = -1');
}

#[test]
fn test_mul_positive_negative() {
    let x: i129 = i129 { mag: 0x1, sign: false } * i129 { mag: 0x1, sign: true };
    assert(x == i129 { mag: 0x1, sign: true }, '1 * -1 = -1');
}

#[test]
fn test_round_trip_many_values() {
    assert_round_trip(i129 { mag: 0, sign: false });
    assert_round_trip(i129 { mag: 0, sign: true });
    assert_round_trip(i129 { mag: 1, sign: false });
    assert_round_trip(i129 { mag: 1, sign: true });
    assert_round_trip(i129 { mag: 0x7fffffffffffffffffffffffffffffff, sign: true });
    assert_round_trip(i129 { mag: 0x7fffffffffffffffffffffffffffffff, sign: false });
}

#[test]
fn test_store_write_read_1() {
    let packed = StorePacking::<i129, felt252>::pack(i129 { mag: 1, sign: false });
    let unpacked = StorePacking::<i129, felt252>::unpack(packed);
    assert(unpacked == i129 { mag: 1, sign: false }, 'read==write');
}

#[test]
fn test_store_write_read_negative_1() {
    let value = i129 { mag: 1, sign: true };
    let packed = StorePacking::<i129, felt252>::pack(value);
    let unpacked = StorePacking::<i129, felt252>::unpack(packed);
    assert(unpacked == value, 'read==write');
}

#[test]
fn test_store_write_read_0() {
    let value = i129 { mag: 0, sign: false };
    let packed = StorePacking::<i129, felt252>::pack(value);
    let unpacked = StorePacking::<i129, felt252>::unpack(packed);
    assert(unpacked == value, 'read==write');
}

#[test]
fn test_store_write_read_negative_0() {
    let value = i129 { mag: 0, sign: true };
    let packed = StorePacking::<i129, felt252>::pack(value);
    let unpacked = StorePacking::<i129, felt252>::unpack(packed);
    assert(unpacked == value, 'read==write');
    assert(!unpacked.sign, 'sign');
}

#[test]
fn test_store_write_read_max_value() {
    let value = i129 { mag: 0x7fffffffffffffffffffffffffffffff, sign: false };
    let packed = StorePacking::<i129, felt252>::pack(value);
    let unpacked = StorePacking::<i129, felt252>::unpack(packed);
    assert(unpacked == value, 'read==write');
}

#[test]
fn test_store_write_read_min_value() {
    let value = i129 { mag: 0x7fffffffffffffffffffffffffffffff, sign: true };
    let packed = StorePacking::<i129, felt252>::pack(value);
    let unpacked = StorePacking::<i129, felt252>::unpack(packed);
    assert(unpacked == value, 'read==write');
}

#[test]
#[should_panic(expected: ('i129_store_overflow',))]
fn test_store_write_min_value_minus_one() {
    StorePacking::<
        i129, felt252,
    >::pack(i129 { mag: 0x80000000000000000000000000000000, sign: true });
}

#[test]
#[should_panic(expected: ('i129_store_overflow',))]
fn test_store_write_max_value_plus_one() {
    StorePacking::<
        i129, felt252,
    >::pack(i129 { mag: 0x80000000000000000000000000000000, sign: false });
}


#[test]
fn test_add_delta_no_overflow() {
    assert(1.add(i129 { mag: 1, sign: false }) == 2, '1+1');
    assert(1.add(i129 { mag: 1, sign: true }) == 0, '1-1');
    assert(1.add(i129 { mag: 2, sign: false }) == 3, '1+2');
    assert(
        0xfffffffffffffffffffffffffffffffe
            .add(i129 { mag: 1, sign: false }) == 0xffffffffffffffffffffffffffffffff,
        'max-1 +1',
    );
    assert(
        0xffffffffffffffffffffffffffffffff.add(Zero::zero()) == 0xffffffffffffffffffffffffffffffff,
        'max+0',
    );
}

#[test]
#[should_panic(expected: ('ADD_DELTA',))]
fn test_add_delta_panics_underflow() {
    1.add(i129 { mag: 2, sign: true });
}

#[test]
#[should_panic(expected: ('ADD_DELTA',))]
fn test_add_delta_panics_underflow_max() {
    0xfffffffffffffffffffffffffffffffe
        .add(i129 { mag: 0xffffffffffffffffffffffffffffffff, sign: true });
}

#[test]
fn test_add_delta_max_inputs() {
    assert(
        0xffffffffffffffffffffffffffffffff
            .add(i129 { mag: 0xffffffffffffffffffffffffffffffff, sign: true }) == 0,
        'max-max',
    );
}

#[test]
#[should_panic(expected: ('u128_add Overflow',))]
fn test_add_delta_panics_overflow() {
    0xffffffffffffffffffffffffffffffff.add(i129 { mag: 1, sign: false });
}

#[test]
#[should_panic(expected: ('u128_add Overflow',))]
fn test_add_delta_panics_overflow_reverse() {
    1.add(i129 { mag: 0xffffffffffffffffffffffffffffffff, sign: false });
}
