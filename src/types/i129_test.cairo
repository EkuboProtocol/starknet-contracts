use ekubo::types::i129::{i129};
use traits::{Into};
use zeroable::Zeroable;
use option::{Option, OptionTrait};
use starknet::storage_access::{storage_base_address_const, StorePacking, Store};
use starknet::{SyscallResult, SyscallResultTrait};


#[test]
fn test_zeroable() {
    assert(Zeroable::<i129>::zero() == i129 { mag: 0, sign: false }, 'zero()');
    assert(Zeroable::<i129>::zero().is_zero(), '0.is_zero()');
    assert(!Zeroable::<i129>::zero().is_non_zero(), '0.is_non_zero()');
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
        i129 {
            mag: 15, sign: false
            } / i129 {
            mag: 4, sign: false
            } == i129 {
            mag: 3, sign: false
        },
        '15/4'
    );
    assert(
        i129 { mag: 15, sign: true } / i129 { mag: 4, sign: false } == i129 { mag: 3, sign: true },
        '-15/4'
    );
    assert(
        i129 { mag: 15, sign: false } / i129 { mag: 4, sign: true } == i129 { mag: 3, sign: true },
        '15/-4'
    );
    assert(
        i129 { mag: 15, sign: true } / i129 { mag: 4, sign: true } == i129 { mag: 3, sign: false },
        '-15/-4'
    );
}

#[test]
fn test_gt() {
    assert((Zeroable::zero() > i129 { mag: 0, sign: true }) == false, '0 > -0');
    assert((i129 { mag: 1, sign: false } > i129 { mag: 0, sign: true }) == true, '1 > -0');
    assert((i129 { mag: 1, sign: true } > i129 { mag: 0, sign: true }) == false, '-1 > -0');
    assert((i129 { mag: 1, sign: true } > Zeroable::zero()) == false, '-1 > 0');
    assert((i129 { mag: 1, sign: false } > i129 { mag: 1, sign: false }) == false, '1 > 1');
}

#[test]
fn test_lt() {
    assert((Zeroable::zero() < i129 { mag: 0, sign: true }) == false, '0 < -0');
    assert((Zeroable::zero() < i129 { mag: 1, sign: true }) == false, '0 < -1');
    assert((i129 { mag: 1, sign: false } < i129 { mag: 1, sign: false }) == false, '1 < 1');

    assert((i129 { mag: 1, sign: true } < Zeroable::zero()) == true, '-1 < 0');
    assert((i129 { mag: 1, sign: true } < i129 { mag: 0, sign: true }) == true, '-1 < -0');
    assert((Zeroable::zero() < i129 { mag: 1, sign: false }) == true, '0 < 1');
    assert((i129 { mag: 1, sign: false } < i129 { mag: 2, sign: false }) == true, '1 < 2');
}

#[test]
fn test_gte() {
    assert((Zeroable::zero() >= i129 { mag: 0, sign: true }) == true, '0 >= -0');
    assert((i129 { mag: 1, sign: false } >= i129 { mag: 0, sign: true }) == true, '1 >= -0');
    assert((i129 { mag: 1, sign: true } >= i129 { mag: 0, sign: true }) == false, '-1 >= -0');
    assert((i129 { mag: 1, sign: true } >= Zeroable::zero()) == false, '-1 >= 0');
    assert((Zeroable::<i129>::zero() >= Zeroable::zero()) == true, '0 >= 0');
}

#[test]
fn test_eq() {
    assert((Zeroable::zero() == i129 { mag: 0, sign: true }) == true, '0 == -0');
    assert((Zeroable::zero() == i129 { mag: 1, sign: true }) == false, '0 != -1');
    assert((i129 { mag: 1, sign: false } == i129 { mag: 1, sign: true }) == false, '1 != -1');
    assert((i129 { mag: 1, sign: true } == i129 { mag: 1, sign: true }) == true, '-1 = -1');
    assert((i129 { mag: 1, sign: false } == i129 { mag: 1, sign: false }) == true, '1 = 1');
}

#[test]
fn test_lte() {
    assert((Zeroable::zero() <= i129 { mag: 0, sign: true }) == true, '0 <= -0');
    assert((i129 { mag: 1, sign: false } <= i129 { mag: 0, sign: true }) == false, '1 <= -0');
    assert((i129 { mag: 1, sign: true } <= i129 { mag: 0, sign: true }) == true, '-1 <= -0');
    assert((i129 { mag: 1, sign: true } <= Zeroable::zero()) == true, '-1 <= 0');
    assert((Zeroable::<i129>::zero() <= Zeroable::zero()) == true, '0 <= 0');
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
#[available_gas(3000000)]
fn test_storage_access_write_read_1() {
    let packed = StorePacking::<i129, u128>::pack(i129 { mag: 1, sign: false });
    let unpacked = StorePacking::<i129, u128>::unpack(packed);
    assert(unpacked == i129 { mag: 1, sign: false }, 'read==write');
}

#[test]
#[available_gas(3000000)]
fn test_storage_access_write_read_negative_1() {
    let value = i129 { mag: 1, sign: true };
    let packed = StorePacking::<i129, u128>::pack(value);
    let unpacked = StorePacking::<i129, u128>::unpack(packed);
    assert(unpacked == value, 'read==write');
}

#[test]
#[available_gas(3000000)]
fn test_storage_access_write_read_0() {
    let value = i129 { mag: 0, sign: false };
    let packed = StorePacking::<i129, u128>::pack(value);
    let unpacked = StorePacking::<i129, u128>::unpack(packed);
    assert(unpacked == value, 'read==write');
}

#[test]
#[available_gas(3000000)]
fn test_storage_access_write_read_negative_0() {
    let value = i129 { mag: 0, sign: true };
    let packed = StorePacking::<i129, u128>::pack(value);
    let unpacked = StorePacking::<i129, u128>::unpack(packed);
    assert(unpacked == value, 'read==write');
}

#[test]
#[available_gas(3000000)]
fn test_storage_access_write_read_max_value() {
    let value = i129 { mag: 0x7fffffffffffffffffffffffffffffff, sign: false };
    let packed = StorePacking::<i129, u128>::pack(value);
    let unpacked = StorePacking::<i129, u128>::unpack(packed);
    assert(unpacked == value, 'read==write');
}

#[test]
#[available_gas(3000000)]
fn test_storage_access_write_read_min_value() {
    let value = i129 { mag: 0x7fffffffffffffffffffffffffffffff, sign: true };
    let packed = StorePacking::<i129, u128>::pack(value);
    let unpacked = StorePacking::<i129, u128>::unpack(packed);
    assert(unpacked == value, 'read==write');
}

#[test]
#[available_gas(6000000)]
#[should_panic(expected: ('i129_storage_overflow', ))]
fn test_storage_access_write_min_value_minus_one() {
    let base = storage_base_address_const::<0>();
    let write = Store::<i129>::write_at_offset(
        address_domain: 0,
        base: base,
        offset: 0_u8,
        value: i129 { mag: 0x80000000000000000000000000000000, sign: true }
    );
}

#[test]
#[available_gas(6000000)]
#[should_panic(expected: ('i129_storage_overflow', ))]
fn test_storage_access_write_max_value_plus_one() {
    let base = storage_base_address_const::<0>();
    let write = Store::<i129>::write_at_offset(
        address_domain: 0,
        base: base,
        offset: 0_u8,
        value: i129 { mag: 0x80000000000000000000000000000000, sign: false }
    );
}
