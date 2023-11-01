use starknet::{class_hash_const, ClassHash};
use starknet::testing::{set_contract_address, pop_log};
use ekubo::owner::owner;
use ekubo::tests::helper::{deploy_mock_upgradeable};
use ekubo::tests::mocks::mock_upgradeable::{
    MockUpgradeable, IMockUpgradeableDispatcher, IMockUpgradeableDispatcherTrait
};

#[test]
#[available_gas(2000000)]
fn test_replace_class_hash() {
    let mock_upgradeable = deploy_mock_upgradeable();
    let class_hash: ClassHash = MockUpgradeable::TEST_CLASS_HASH.try_into().unwrap();
    set_contract_address(owner());
    IMockUpgradeableDispatcher { contract_address: mock_upgradeable.contract_address }
        .replace_class_hash(class_hash);

    let event: ekubo::upgradeable::Upgradeable::ClassHashReplaced = pop_log(
        mock_upgradeable.contract_address
    )
        .unwrap();
    assert(event.new_class_hash == class_hash, 'event.class_hash');
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected: ('INVALID_CLASS_HASH', 'ENTRYPOINT_FAILED'))]
fn test_replace_zero_class_hash() {
    let mock_upgradeable = deploy_mock_upgradeable();
    IMockUpgradeableDispatcher { contract_address: mock_upgradeable.contract_address }
        .replace_class_hash(class_hash_const::<0>());
}

