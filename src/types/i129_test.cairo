use parlay::types::i129::{i129, Felt252IntoI129, U128IntoI129};
use traits::{Into, TryInto};
use option::{Option, OptionTrait};

#[test]
fn test_into_felt252_0() {
    let x: felt252 = i129 { mag: 0, sign: false }.into();
    assert(x == 0, 'x');
}

#[test]
fn test_into_felt252_one() {
    let x: felt252 = i129 { mag: 1, sign: false }.into();
    assert(x == 1, 'x');

    let y: i129 = x.into();
    assert(y == i129 { mag: 1, sign: false }, 'y');
}

#[test]
fn test_into_felt252_negative_one() {
    let x: felt252 = i129 { mag: 1, sign: true }.into();
    assert(x == 0x100000000000000000000000000000001, 'x');

    let y: i129 = x.into();
    assert(y == i129 { mag: 1, sign: true }, 'y');
}

#[test]
fn test_into_felt252_max() {
    let x: felt252 = i129 { mag: 0xffffffffffffffffffffffffffffffff, sign: false }.into();
    assert(x == 0xffffffffffffffffffffffffffffffff, 'x');

    let y: i129 = x.into();
    assert(y == i129 { mag: 0xffffffffffffffffffffffffffffffff, sign: false }, 'y');
}

#[test]
fn test_into_felt252_negative_max() {
    let x: felt252 = i129 { mag: 0xffffffffffffffffffffffffffffffff, sign: true }.into();
    assert(x == 0x1ffffffffffffffffffffffffffffffff, 'x');

    let y: i129 = x.into();
    assert(y == i129 { mag: 0xffffffffffffffffffffffffffffffff, sign: true }, 'y');
}

#[test]
fn test_try_into_u128() {
    assert(i129 { mag: 0, sign: false }.try_into().expect('') == 0, '0');
    assert(i129 { mag: 123, sign: false }.try_into().expect('') == 123, '123');
    assert(
        i129 {
            mag: 0xffffffffffffffffffffffffffffffff, sign: false
        }.try_into().expect('') == 0xffffffffffffffffffffffffffffffff,
        'max'
    );

    assert(i129 { mag: 0, sign: true }.try_into().is_none(), '-0');
    assert(i129 { mag: 123, sign: true }.try_into().is_none(), '-123');
    assert(
        i129 { mag: 0xffffffffffffffffffffffffffffffff, sign: true }.try_into().is_none(), '-max'
    );
}


#[test]
fn test_u128_into_i129() {
    assert(0_u128.into() == i129 { mag: 0, sign: false }, '0');
    assert(123_u128.into() == i129 { mag: 123, sign: false }, '123');
    assert(
        0xffffffffffffffffffffffffffffffff_u128.into() == i129 {
            mag: 0xffffffffffffffffffffffffffffffff, sign: false
        },
        'max'
    );
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
    assert((i129 { mag: 0, sign: false } > i129 { mag: 0, sign: true }) == false, '0 > -0');
    assert((i129 { mag: 1, sign: false } > i129 { mag: 0, sign: true }) == true, '1 > -0');
    assert((i129 { mag: 1, sign: true } > i129 { mag: 0, sign: true }) == false, '-1 > -0');
    assert((i129 { mag: 1, sign: true } > i129 { mag: 0, sign: false }) == false, '-1 > 0');
}


#[test]
fn test_eq() {
    assert((i129 { mag: 0, sign: false } == i129 { mag: 0, sign: true }) == true, '0 == -0');
    assert((i129 { mag: 0, sign: false } == i129 { mag: 1, sign: true }) == false, '0 != -1');
    assert((i129 { mag: 1, sign: false } == i129 { mag: 1, sign: true }) == false, '1 != -1');
    assert((i129 { mag: 1, sign: true } == i129 { mag: 1, sign: true }) == true, '-1 = -1');
    assert((i129 { mag: 1, sign: false } == i129 { mag: 1, sign: false }) == true, '1 = 1');
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
