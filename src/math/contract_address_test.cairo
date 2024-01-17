use core::num::traits::{Zero};

use ekubo::math::contract_address::{ContractAddressOrder};
use ekubo::types::i129::i129;
use starknet::{contract_address_const};


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

