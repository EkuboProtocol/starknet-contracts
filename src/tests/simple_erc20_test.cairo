use ekubo::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
use ekubo::simple_erc20::SimpleERC20::{Transfer};
use ekubo::tests::helper::{deploy_simple_erc20};
use option::{OptionTrait};
use starknet::{
    get_contract_address, contract_address_const, testing::{set_contract_address, pop_log}
};
use zeroable::{Zeroable};


#[test]
#[available_gas(30000000)]
fn test_constructor() {
    let erc20 = deploy_simple_erc20(contract_address_const::<1234>());
    assert(
        erc20.balanceOf(contract_address_const::<1234>()) == 0xffffffffffffffffffffffffffffffff,
        'balance of this'
    );
    let transfer: Transfer = pop_log(erc20.contract_address).unwrap();
    assert(transfer.from.is_zero(), 'transfer from');
    assert(transfer.to == contract_address_const::<1234>(), 'transfer to');
    assert(transfer.amount == 0xffffffffffffffffffffffffffffffff, 'transfer amount');
}

#[test]
#[available_gas(30000000)]
fn test_transfer() {
    let erc20 = deploy_simple_erc20(get_contract_address());
    pop_log::<Transfer>(erc20.contract_address).expect('CONSTRUCTOR');

    let recipient = contract_address_const::<0x1234>();
    let amount = 1234_u256;
    assert(erc20.transfer(recipient, amount) == true, 'transfer');
    assert(
        erc20.balanceOf(get_contract_address()) == (0xffffffffffffffffffffffffffffffff - 1234),
        'balance sender'
    );
    assert(erc20.balanceOf(recipient) == amount, 'balance recipient');
    let transfer: Transfer = pop_log(erc20.contract_address).unwrap();
    assert(transfer.from == get_contract_address(), 'transfer from');
    assert(transfer.to == recipient, 'transfer to');
    assert(transfer.amount == amount, 'transfer amount');
}
