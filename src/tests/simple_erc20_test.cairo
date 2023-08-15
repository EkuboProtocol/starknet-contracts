use ekubo::tests::helper::{deploy_simple_erc20};
use starknet::{
    get_contract_address, contract_address_const, testing::{set_contract_address, pop_log}
};
use ekubo::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
use ekubo::simple_erc20::SimpleERC20::{Transfer};
use option::{OptionTrait};

#[test]
#[available_gas(30000000)]
fn test_constructor() {
    let erc20 = deploy_simple_erc20();
    assert(
        erc20.balanceOf(get_contract_address()) == 0xffffffffffffffffffffffffffffffff,
        'balance of this'
    );
}

#[test]
#[available_gas(30000000)]
fn test_transfer() {
    let erc20 = deploy_simple_erc20();
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
