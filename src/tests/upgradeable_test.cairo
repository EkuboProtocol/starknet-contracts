use ekubo::components::owned::{Owned::{default_owner}};
use ekubo::interfaces::upgradeable::{IUpgradeableDispatcher, IUpgradeableDispatcherTrait};
use ekubo::tests::helper::{deploy_mock_upgradeable};
use ekubo::tests::mocks::mock_upgradeable::{MockUpgradeable};
use starknet::testing::{set_contract_address, pop_log};
use starknet::{class_hash_const, ClassHash};

#[test]
fn test_replace_class_hash() {
    let mock_upgradeable = deploy_mock_upgradeable();
    let class_hash: ClassHash = MockUpgradeable::TEST_CLASS_HASH.try_into().unwrap();
    set_contract_address(default_owner());
    mock_upgradeable.replace_class_hash(class_hash);

    let event: ekubo::components::upgradeable::Upgradeable::ClassHashReplaced = pop_log(
        mock_upgradeable.contract_address
    )
        .unwrap();
    assert(event.new_class_hash == class_hash, 'event.class_hash');
}

#[test]
#[should_panic(expected: ('INVALID_CLASS_HASH', 'ENTRYPOINT_FAILED'))]
fn test_replace_zero_class_hash() {
    let mock_upgradeable = deploy_mock_upgradeable();
    set_contract_address(default_owner());
    mock_upgradeable.replace_class_hash(class_hash_const::<0>());
}

#[test]
#[should_panic(expected: ('OWNER_ONLY', 'ENTRYPOINT_FAILED'))]
fn test_replace_non_zero_class_hash_not_owner() {
    let mock_upgradeable = deploy_mock_upgradeable();
    mock_upgradeable.replace_class_hash(class_hash_const::<1>());
}


#[test]
#[should_panic(expected: ('MISSING_PRIMARY_INTERFACE_ID', 'ENTRYPOINT_FAILED'))]
fn test_replace_non_zero_class_hash_without_interface_id() {
    let mock_upgradeable = deploy_mock_upgradeable();
    set_contract_address(default_owner());
    mock_upgradeable.replace_class_hash(class_hash_const::<0xabcdef>());
}

