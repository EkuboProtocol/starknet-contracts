use core::num::traits::{Zero};
use core::option::{OptionTrait};
use ekubo::tests::mock_erc20::{MockERC20::{Transfer}, MockERC20IERC20ImplTrait};
use ekubo::tests::helper::{Deployer, DeployerTrait};
use starknet::{contract_address_const, get_contract_address, testing::{pop_log}};


#[test]
fn test_constructor() {
    let mut d: Deployer = Default::default();

    let erc20 = d
        .deploy_mock_token_with_balance(
            contract_address_const::<1234>(), 0xffffffffffffffffffffffffffffffff,
        );
    assert(
        erc20.balanceOf(contract_address_const::<1234>()) == 0xffffffffffffffffffffffffffffffff,
        'balance of this',
    );
    let transfer: Transfer = pop_log(erc20.contract_address).unwrap();
    assert(transfer.from.is_zero(), 'transfer from');
    assert(transfer.to == contract_address_const::<1234>(), 'transfer to');
    assert(transfer.amount == 0xffffffffffffffffffffffffffffffff, 'transfer amount');
}

#[test]
fn test_transfer() {
    let mut d: Deployer = Default::default();
    let erc20 = d
        .deploy_mock_token_with_balance(get_contract_address(), 0xffffffffffffffffffffffffffffffff);
    pop_log::<Transfer>(erc20.contract_address).expect('CONSTRUCTOR');

    let recipient = contract_address_const::<0x1234>();
    let amount = 1234_u256;
    assert(erc20.transfer(recipient, amount) == true, 'transfer');
    assert(
        erc20.balanceOf(get_contract_address()) == (0xffffffffffffffffffffffffffffffff - 1234),
        'balance sender',
    );
    assert(erc20.balanceOf(recipient) == amount, 'balance recipient');
    let transfer: Transfer = pop_log(erc20.contract_address).unwrap();
    assert(transfer.from == get_contract_address(), 'transfer from');
    assert(transfer.to == recipient, 'transfer to');
    assert(transfer.amount == amount, 'transfer amount');
}
