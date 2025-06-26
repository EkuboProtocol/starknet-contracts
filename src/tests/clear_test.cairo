use ekubo::components::clear::{IClearDispatcher, IClearDispatcherTrait};
use ekubo::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
use ekubo::tests::helper::{Deployer, DeployerTrait};
use starknet::ContractAddress;
use starknet::syscalls::deploy_syscall;
use starknet::testing::set_contract_address;

#[starknet::contract]
mod TestContract {
    #[abi(embed_v0)]
    impl Clear = ekubo::components::clear::ClearImpl<ContractState>;

    #[storage]
    struct Storage {}
}

fn setup() -> (IClearDispatcher, IERC20Dispatcher, ContractAddress) {
    let mut d: Deployer = Default::default();

    let (test_contract, _) = deploy_syscall(
        TestContract::TEST_CLASS_HASH.try_into().unwrap(),
        d.get_next_nonce(),
        array![].span(),
        true,
    )
        .unwrap();

    let token = d.deploy_mock_token_with_balance(owner: test_contract, starting_balance: 100);

    let caller = 123456.try_into().unwrap();
    set_contract_address(caller);

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
#[should_panic(expected: ('CLEAR_AT_LEAST_MINIMUM', 'ENTRYPOINT_FAILED'))]
fn test_clear_minimum_fails_nonzero() {
    let (test_contract, erc20, caller) = setup();

    assert_eq!(erc20.balanceOf(test_contract.contract_address), 100);
    assert_eq!(erc20.balanceOf(caller), 0);
    test_contract.clear_minimum(erc20, 101);
    assert_eq!(erc20.balanceOf(test_contract.contract_address), 0);
    assert_eq!(erc20.balanceOf(caller), 100);
}

#[test]
#[should_panic(expected: ('CLEAR_AT_LEAST_MINIMUM', 'ENTRYPOINT_FAILED'))]
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
#[should_panic(expected: ('CLEAR_AT_LEAST_MINIMUM', 'ENTRYPOINT_FAILED'))]
fn test_clear_minimum_to_recipient_fails() {
    let (test_contract, erc20, _) = setup();

    let recipient = 1234567.try_into().unwrap();

    assert_eq!(erc20.balanceOf(recipient), 0);
    assert_eq!(erc20.balanceOf(test_contract.contract_address), 100);
    test_contract.clear_minimum_to_recipient(erc20, 101, recipient);
}

#[test]
#[should_panic(expected: ('CLEAR_AT_LEAST_MINIMUM', 'ENTRYPOINT_FAILED'))]
fn test_clear_minimum_to_recipient_fails_zero_balance() {
    let (test_contract, erc20, _) = setup();

    test_contract.clear(erc20);

    let recipient = 1234567.try_into().unwrap();

    assert_eq!(erc20.balanceOf(test_contract.contract_address), 0);
    test_contract.clear_minimum_to_recipient(erc20, 100, recipient);
}

