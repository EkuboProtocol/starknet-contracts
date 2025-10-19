use starknet::ClassHash;
use starknet::testing::{pop_log, set_contract_address};
use crate::components::owned::{IOwnedDispatcher, IOwnedDispatcherTrait};
use crate::interfaces::upgradeable::IUpgradeableDispatcherTrait;
use crate::tests::helper::{Deployer, DeployerTrait, default_owner};
use crate::tests::mocks::mock_upgradeable::MockUpgradeable;

#[test]
fn test_replace_class_hash() {
    let mut d: Deployer = Default::default();
    let mock_upgradeable = d.deploy_mock_upgradeable();
    let class_hash: ClassHash = MockUpgradeable::TEST_CLASS_HASH.try_into().unwrap();
    set_contract_address(default_owner());
    mock_upgradeable.replace_class_hash(class_hash);

    pop_log::<
        crate::components::owned::Owned::OwnershipTransferred,
    >(mock_upgradeable.contract_address)
        .unwrap();
    let event: crate::components::upgradeable::Upgradeable::ClassHashReplaced = pop_log(
        mock_upgradeable.contract_address,
    )
        .unwrap();
    assert(event.new_class_hash == class_hash, 'event.class_hash');
}

#[test]
#[should_panic(expected: ('OWNER_ONLY', 'ENTRYPOINT_FAILED'))]
fn test_replace_class_hash_not_owner_after_transfer() {
    let mut d: Deployer = Default::default();
    let mock_upgradeable = d.deploy_mock_upgradeable();
    let owned = IOwnedDispatcher { contract_address: mock_upgradeable.contract_address };
    let class_hash: ClassHash = MockUpgradeable::TEST_CLASS_HASH.try_into().unwrap();
    set_contract_address(default_owner());
    owned.transfer_ownership(12345678.try_into().unwrap());
    mock_upgradeable.replace_class_hash(class_hash);
}

#[test]
fn test_replace_class_hash_after_owner_change() {
    let mut d: Deployer = Default::default();
    let mock_upgradeable = d.deploy_mock_upgradeable();
    let owned = IOwnedDispatcher { contract_address: mock_upgradeable.contract_address };
    let class_hash: ClassHash = MockUpgradeable::TEST_CLASS_HASH.try_into().unwrap();
    set_contract_address(default_owner());
    let new_owner = 12345678.try_into().unwrap();
    owned.transfer_ownership(new_owner);
    set_contract_address(new_owner);
    mock_upgradeable.replace_class_hash(class_hash);
}

#[test]
#[should_panic(expected: ('INVALID_CLASS_HASH', 'ENTRYPOINT_FAILED'))]
fn test_replace_zero_class_hash() {
    let mut d: Deployer = Default::default();
    let mock_upgradeable = d.deploy_mock_upgradeable();
    set_contract_address(default_owner());
    mock_upgradeable.replace_class_hash(0.try_into().unwrap());
}

#[test]
#[should_panic(expected: ('OWNER_ONLY', 'ENTRYPOINT_FAILED'))]
fn test_replace_non_zero_class_hash_not_owner() {
    let mut d: Deployer = Default::default();
    let mock_upgradeable = d.deploy_mock_upgradeable();
    mock_upgradeable.replace_class_hash(1.try_into().unwrap());
}


#[test]
#[should_panic(expected: ('MISSING_PRIMARY_INTERFACE_ID', 'ENTRYPOINT_FAILED'))]
fn test_replace_non_zero_class_hash_without_interface_id() {
    let mut d: Deployer = Default::default();
    let mock_upgradeable = d.deploy_mock_upgradeable();
    set_contract_address(default_owner());
    mock_upgradeable.replace_class_hash(0xabcdef.try_into().unwrap());
}

