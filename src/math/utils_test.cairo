use ekubo::types::i129::i129;
use ekubo::math::utils::{unsafe_sub, ContractAddressOrder, u128_max};
use starknet::{contract_address_const};
use zeroable::Zeroable;

#[test]
fn test_unsafe_sub() {
    assert(unsafe_sub(u256 { low: 0, high: 1 }, u256 { low: 0, high: 1 }).is_zero(), 'regular sub');

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


#[test]
fn test_u128_max() {
    assert(u128_max(1, 2) == 2, '1,2');
    assert(u128_max(2, 1) == 2, '2,1');
    assert(u128_max(1, 1) == 1, '1,1');
    assert(u128_max(0, 0) == 0, '0,0');
    assert(u128_max(0, 1) == 1, '0,1');
    assert(u128_max(1, 0) == 1, '1,0');
    assert(
        u128_max(0xffffffffffffffffffffffffffffffff, 0) == 0xffffffffffffffffffffffffffffffff,
        'max,0'
    );
    assert(
        u128_max(0, 0xffffffffffffffffffffffffffffffff) == 0xffffffffffffffffffffffffffffffff,
        '0,max'
    );
    assert(
        u128_max(
            0xffffffffffffffffffffffffffffffff, 0xffffffffffffffffffffffffffffffff
        ) == 0xffffffffffffffffffffffffffffffff,
        'max,max'
    );
}
