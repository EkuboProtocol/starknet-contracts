use core::num::traits::Zero;
use core::option::OptionTrait;
use starknet::testing::pop_log;
use starknet::{ContractAddress, get_contract_address};
use crate::tests::helper::{Deployer, DeployerTrait};
use crate::tests::mock_erc20::MockERC20::Transfer;
use crate::tests::mock_erc20::MockERC20IERC20ImplTrait;


#[test]
fn test_constructor() {
    let mut d: Deployer = Default::default();

    let erc20 = d
        .deploy_mock_token_with_balance(
            1234.try_into().unwrap(), 0xffffffffffffffffffffffffffffffff,
        );
    assert(
        erc20.balanceOf(1234.try_into().unwrap()) == 0xffffffffffffffffffffffffffffffff,
        'balance of this',
    );
    let transfer: Transfer = OptionTrait::unwrap(pop_log(erc20.contract_address));
    assert(transfer.from.is_zero(), 'transfer from');
    assert(transfer.to == 1234.try_into().unwrap(), 'transfer to');
    assert(transfer.amount == 0xffffffffffffffffffffffffffffffff, 'transfer amount');
}

#[test]
fn test_transfer() {
    let mut d: Deployer = Default::default();
    let erc20 = d
        .deploy_mock_token_with_balance(get_contract_address(), 0xffffffffffffffffffffffffffffffff);
    OptionTrait::expect(pop_log::<Transfer>(erc20.contract_address), 'CONSTRUCTOR');

    let recipient: ContractAddress = 0x1234.try_into().unwrap();
    let amount = 1234_u256;
    assert(erc20.transfer(recipient, amount) == true, 'transfer');
    assert(
        erc20.balanceOf(get_contract_address()) == (0xffffffffffffffffffffffffffffffff - 1234),
        'balance sender',
    );
    assert(erc20.balanceOf(recipient) == amount, 'balance recipient');
    let transfer: Transfer = OptionTrait::unwrap(pop_log(erc20.contract_address));
    assert(transfer.from == get_contract_address(), 'transfer from');
    assert(transfer.to == recipient, 'transfer to');
    assert(transfer.amount == amount, 'transfer amount');
}
