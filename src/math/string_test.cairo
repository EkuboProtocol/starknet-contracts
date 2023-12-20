use core::debug::PrintTrait;
use ekubo::math::string::{to_decimal, append};
use core::option::OptionTrait;

#[test]
#[available_gas(50000000)]
fn test_to_decimal() {
    assert(to_decimal(0).unwrap() == '0', '0');
    assert(to_decimal(12345).unwrap() == '12345', '12345');
    assert(to_decimal(1000).unwrap() == '1000', '1000');
    assert(to_decimal(2394828150).unwrap() == '2394828150', '2394828150');
}


#[test]
#[available_gas(50000000)]
fn test_large_numbers_to_decimal() {
    assert(to_decimal(12345678901234567890).unwrap() == '12345678901234567890', '20 decimals');
    assert(
        to_decimal(123456789012345678901234567890).unwrap() == '123456789012345678901234567890',
        '30 decimals'
    );
    assert(
        to_decimal(1234567890123456789012345678901).unwrap() == '1234567890123456789012345678901',
        '31 decimals'
    );
    assert(
        to_decimal(9999999999999999999999999999999).unwrap() == '9999999999999999999999999999999',
        '31 decimals_max'
    );
}

#[test]
#[available_gas(50000000)]
fn test_number_too_large() {
    assert(to_decimal(10000000000000000000000000000000).is_none(), 'number');
}

#[test]
#[available_gas(50000000)]
fn test_append() {
    assert(append('abc', 'def').unwrap() == 'abcdef', 'abc+def');
    assert(append('', 'def').unwrap() == 'def', '+def');
    assert(append('abc', '').unwrap() == 'abc', 'abc+');
    assert(append('ab', 'cdef').unwrap() == 'abcdef', 'ab+cdef');
    assert(append('abcd', 'ef').unwrap() == 'abcdef', 'abcd+ef');
    assert(
        append('0123456789012345', '012345678901234').unwrap() == '0123456789012345012345678901234',
        '16+15'
    );
    assert(
        append('012345678901234', '0123456789012345').unwrap() == '0123456789012340123456789012345',
        '15+16'
    );
    assert(
        append('0123456789012345012345678901234', '').unwrap() == '0123456789012345012345678901234',
        '31+0'
    );
    assert(
        append('', '0123456789012345012345678901234').unwrap() == '0123456789012345012345678901234',
        '0+31'
    );

    assert(append('0123456789012345', '0123456789012345').is_none(), '16+16');
    assert(append('01234567890123456', '0123456789012345').is_none(), '17+16');
    assert(append('0123456789012345', '01234567890123456').is_none(), '16+17');
    assert(append('0123456789012345012345678901234', '1').is_none(), '31+1');
    assert(append('1', '0123456789012345012345678901234').is_none(), '1+31');

    assert(
        append('ekubo/', to_decimal(12345678).unwrap()).unwrap() == 'ekubo/12345678',
        'ekubo/+12345678'
    );
}
