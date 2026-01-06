use core::num::traits::Zero;
use starknet::ContractAddress;
use starknet::syscalls::deploy_syscall;
use starknet::testing::set_contract_address;
use crate::components::util::serialize;
use crate::extensions::privacy::Privacy;
use crate::interfaces::extensions::privacy::{
    IPrivacyExtensionDispatcher, IPrivacyExtensionDispatcherTrait,
};
use crate::tests::helper::{Deployer, DeployerTrait, default_owner};

fn deploy_privacy_extension(ref d: Deployer) -> IPrivacyExtensionDispatcher {
    let core = d.deploy_core();
    let (address, _) = deploy_syscall(
        Privacy::TEST_CLASS_HASH.try_into().unwrap(),
        0, // salt
        serialize(@(default_owner(), core.contract_address)).span(),
        true,
    )
        .expect('privacy deploy failed');
    IPrivacyExtensionDispatcher { contract_address: address }
}

#[test]
fn test_register_account() {
    let mut d: Deployer = Default::default();
    let extension = deploy_privacy_extension(ref d);

    // Set caller as owner
    set_contract_address(default_owner());

    // Register an account
    let account: ContractAddress = 0x123.try_into().unwrap();
    extension.register_account(account);

    // Verify account is registered
    assert(extension.is_authorized(account), 'Should be authorized');
}

#[test]
fn test_unregister_account() {
    let mut d: Deployer = Default::default();
    let extension = deploy_privacy_extension(ref d);

    set_contract_address(default_owner());

    // Register and then unregister
    let account: ContractAddress = 0x123.try_into().unwrap();
    extension.register_account(account);
    extension.unregister_account(account);

    // Verify account is no longer registered
    assert(!extension.is_authorized(account), 'Not authorized');
}

#[test]
#[should_panic(expected: ('OWNER_ONLY', 'ENTRYPOINT_FAILED'))]
fn test_register_account_not_owner() {
    let mut d: Deployer = Default::default();
    let extension = deploy_privacy_extension(ref d);

    // Set caller as non-owner
    set_contract_address(0x456.try_into().unwrap());

    let account: ContractAddress = 0x123.try_into().unwrap();
    extension.register_account(account);
}

#[test]
#[should_panic(expected: ('ALREADY_REGISTERED', 'ENTRYPOINT_FAILED'))]
fn test_register_account_twice() {
    let mut d: Deployer = Default::default();
    let extension = deploy_privacy_extension(ref d);

    set_contract_address(default_owner());

    let account: ContractAddress = 0x123.try_into().unwrap();
    extension.register_account(account);
    extension.register_account(account); // Should fail
}

#[test]
#[should_panic(expected: ('NOT_REGISTERED', 'ENTRYPOINT_FAILED'))]
fn test_unregister_not_registered() {
    let mut d: Deployer = Default::default();
    let extension = deploy_privacy_extension(ref d);

    set_contract_address(default_owner());

    let account: ContractAddress = 0x123.try_into().unwrap();
    extension.unregister_account(account); // Should fail - not registered
}

#[test]
#[should_panic(expected: ('ZERO_ADDRESS', 'ENTRYPOINT_FAILED'))]
fn test_register_zero_address() {
    let mut d: Deployer = Default::default();
    let extension = deploy_privacy_extension(ref d);

    set_contract_address(default_owner());

    let account: ContractAddress = Zero::zero();
    extension.register_account(account);
}

#[test]
fn test_swap_count_initial() {
    let mut d: Deployer = Default::default();
    let extension = deploy_privacy_extension(ref d);

    assert(extension.get_swap_count() == 0, 'Initial count 0');
}

#[test]
fn test_multiple_accounts() {
    let mut d: Deployer = Default::default();
    let extension = deploy_privacy_extension(ref d);

    set_contract_address(default_owner());

    let account1: ContractAddress = 0x111.try_into().unwrap();
    let account2: ContractAddress = 0x222.try_into().unwrap();
    let account3: ContractAddress = 0x333.try_into().unwrap();

    extension.register_account(account1);
    extension.register_account(account2);
    extension.register_account(account3);

    assert(extension.is_authorized(account1), 'Acc1 authorized');
    assert(extension.is_authorized(account2), 'Acc2 authorized');
    assert(extension.is_authorized(account3), 'Acc3 authorized');

    // Unregister one
    extension.unregister_account(account2);

    assert(extension.is_authorized(account1), 'Acc1 still ok');
    assert(!extension.is_authorized(account2), 'Acc2 not ok');
    assert(extension.is_authorized(account3), 'Acc3 still ok');
}
