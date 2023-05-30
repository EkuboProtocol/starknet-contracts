use parlay::types::i129::i129;
use parlay::math::utils::{unsafe_sub, add_delta, ContractAddressOrder};
use starknet::{contract_address_const};

#[test]
fn test_unsafe_sub() {
    assert(
        unsafe_sub(u256 { low: 0, high: 1 }, u256 { low: 0, high: 1 }) == u256 { low: 0, high: 0 },
        'regular sub'
    );

    assert(
        unsafe_sub(u256 { low: 0, high: 0 }, u256 { low: 0, high: 1 }) == u256 {
            low: 0, high: 0xffffffffffffffffffffffffffffffff
        },
        'underflow sub'
    );

    assert(
        unsafe_sub(u256 { low: 0, high: 0 }, u256 { low: 1, high: 0 }) == u256 {
            low: 0xffffffffffffffffffffffffffffffff, high: 0xffffffffffffffffffffffffffffffff
        },
        'underflow sub'
    );
}


#[test]
fn test_add_delta_no_overflow() {
    assert(add_delta(1, i129 { mag: 1, sign: false }) == 2, '1+1');
    assert(add_delta(1, i129 { mag: 1, sign: true }) == 0, '1-1');
    assert(add_delta(1, i129 { mag: 2, sign: false }) == 3, '1+2');
    assert(
        add_delta(
            0xfffffffffffffffffffffffffffffffe, i129 { mag: 1, sign: false }
        ) == 0xffffffffffffffffffffffffffffffff,
        'max-1 +1'
    );
    assert(
        add_delta(
            0xffffffffffffffffffffffffffffffff, i129 { mag: 0, sign: false }
        ) == 0xffffffffffffffffffffffffffffffff,
        'max+0'
    );
}

#[test]
#[should_panic(expected: ('DELTA_UNDERFLOW', ))]
fn test_add_delta_panics_underflow() {
    add_delta(1, i129 { mag: 2, sign: true });
}

#[test]
#[should_panic(expected: ('DELTA_UNDERFLOW', ))]
fn test_add_delta_panics_underflow_max() {
    add_delta(
        0xfffffffffffffffffffffffffffffffe,
        i129 { mag: 0xffffffffffffffffffffffffffffffff, sign: true }
    );
}

#[test]
#[should_panic(expected: ('u128_add Overflow', ))]
fn test_add_delta_panics_overflow() {
    add_delta(0xffffffffffffffffffffffffffffffff, i129 { mag: 1, sign: false });
}

#[test]
#[should_panic(expected: ('u128_add Overflow', ))]
fn test_add_delta_panics_overflow_reverse() {
    add_delta(1, i129 { mag: 0xffffffffffffffffffffffffffffffff, sign: false });
}


#[test]
fn test_contract_address_order() {
    assert((contract_address_const::<1>() < contract_address_const::<2>()) == true, '1<2');
    assert((contract_address_const::<2>() < contract_address_const::<2>()) == false, '2<2');
    assert((contract_address_const::<3>() < contract_address_const::<2>()) == false, '3<2');

    assert((contract_address_const::<3>() > contract_address_const::<2>()) == true, '3>2');
    assert((contract_address_const::<2>() > contract_address_const::<2>()) == false, '2>2');
    assert((contract_address_const::<1>() > contract_address_const::<2>()) == false, '1>2');


    assert((contract_address_const::<1>() <= contract_address_const::<2>()) == true, '1<=2');
    assert((contract_address_const::<2>() <= contract_address_const::<2>()) == true, '2<=2');
    assert((contract_address_const::<3>() <= contract_address_const::<2>()) == false, '3<=2');

    assert((contract_address_const::<3>() >= contract_address_const::<2>()) == true, '3>=2');
    assert((contract_address_const::<2>() >= contract_address_const::<2>()) == true, '2>=2');
    assert((contract_address_const::<1>() >= contract_address_const::<2>()) == false, '1>=2');
}
