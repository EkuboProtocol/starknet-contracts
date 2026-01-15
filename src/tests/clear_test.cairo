use starknet::ContractAddress;
use snforge_std::{
    declare, start_cheat_caller_address, stop_cheat_caller_address, ContractClassTrait,
    DeclareResultTrait,
};
use crate::components::clear::{IClearDispatcher, IClearDispatcherTrait};
use crate::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
use crate::tests::helper::{Deployer, DeployerTrait};

#[starknet::contract]
mod TestContract {
    #[abi(embed_v0)]
    impl Clear = crate::components::clear::ClearImpl<ContractState>;

    #[storage]
    struct Storage {}
}

fn setup() -> (IClearDispatcher, IERC20Dispatcher, ContractAddress) {
    let mut d: Deployer = Default::default();

    let contract = declare("TestContract").unwrap().contract_class();
    let (test_contract, _) = contract.deploy(@array![]).expect('test contract deploy failed');

    let token = d.deploy_mock_token_with_balance(owner: test_contract, starting_balance: 100);

    let caller = 123456.try_into().unwrap();
    // Only cheat the caller for the test contract so nested token calls keep the contract caller.
    stop_cheat_caller_address(test_contract);
    start_cheat_caller_address(test_contract, caller);

    (
        IClearDispatcher { contract_address: test_contract },
        IERC20Dispatcher { contract_address: token.contract_address },
        caller,
    )
}

#[test]
fn test_clear() {
    let (test_contract, erc20, caller) = setup();

    assert_eq!(erc20.balanceOf(test_contract.contract_address), 100);
    assert_eq!(erc20.balanceOf(caller), 0);
    test_contract.clear(erc20);
    assert_eq!(erc20.balanceOf(test_contract.contract_address), 0);
    assert_eq!(erc20.balanceOf(caller), 100);
}

#[test]
fn test_clear_minimum_success() {
    let (test_contract, erc20, caller) = setup();

    assert_eq!(erc20.balanceOf(test_contract.contract_address), 100);
    assert_eq!(erc20.balanceOf(caller), 0);
    test_contract.clear_minimum(erc20, 100);
    assert_eq!(erc20.balanceOf(test_contract.contract_address), 0);
    assert_eq!(erc20.balanceOf(caller), 100);
}

#[test]
#[should_panic(expected: 'CLEAR_AT_LEAST_MINIMUM')]
fn test_clear_minimum_fails_nonzero() {
    let (test_contract, erc20, caller) = setup();

    assert_eq!(erc20.balanceOf(test_contract.contract_address), 100);
    assert_eq!(erc20.balanceOf(caller), 0);
    test_contract.clear_minimum(erc20, 101);
    assert_eq!(erc20.balanceOf(test_contract.contract_address), 0);
    assert_eq!(erc20.balanceOf(caller), 100);
}

#[test]
#[should_panic(expected: 'CLEAR_AT_LEAST_MINIMUM')]
fn test_clear_minimum_fails_zero() {
    let (test_contract, erc20, caller) = setup();

    // first empty balance
    test_contract.clear(erc20);

    assert_eq!(erc20.balanceOf(caller), 100);
    assert_eq!(erc20.balanceOf(test_contract.contract_address), 0);
    test_contract.clear_minimum(erc20, 1);
}

#[test]
fn test_clear_minimum_to_recipient() {
    let (test_contract, erc20, _) = setup();

    let recipient = 1234567.try_into().unwrap();

    assert_eq!(erc20.balanceOf(recipient), 0);
    assert_eq!(erc20.balanceOf(test_contract.contract_address), 100);
    test_contract.clear_minimum_to_recipient(erc20, 100, recipient);
    assert_eq!(erc20.balanceOf(recipient), 100);
    assert_eq!(erc20.balanceOf(test_contract.contract_address), 0);
}

#[test]
#[should_panic(expected: 'CLEAR_AT_LEAST_MINIMUM')]
fn test_clear_minimum_to_recipient_fails() {
    let (test_contract, erc20, _) = setup();

    let recipient = 1234567.try_into().unwrap();

    assert_eq!(erc20.balanceOf(recipient), 0);
    assert_eq!(erc20.balanceOf(test_contract.contract_address), 100);
    test_contract.clear_minimum_to_recipient(erc20, 101, recipient);
}

#[test]
#[should_panic(expected: 'CLEAR_AT_LEAST_MINIMUM')]
fn test_clear_minimum_to_recipient_fails_zero_balance() {
    let (test_contract, erc20, _) = setup();

    test_contract.clear(erc20);

    let recipient = 1234567.try_into().unwrap();

    assert_eq!(erc20.balanceOf(test_contract.contract_address), 0);
    test_contract.clear_minimum_to_recipient(erc20, 100, recipient);
}
