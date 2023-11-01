use starknet::{class_hash_const, ClassHash};
use starknet::testing::{pop_log};
use ekubo::tests::helper::{deploy_upgradeable};
use ekubo::tests::mocks::mock_upgradeable::{MockUpgradeable, IMockUpgradeableDispatcher};

#[test]
#[available_gas(2000000)]
fn test_replace_class_hash() {
    let core = deploy_upgradeable();
    let class_hash: ClassHash = MockUpgradeable::TEST_CLASS_HASH.try_into().unwrap();
    IMockUpgradeableDispatcher { contract_address: core.contract_address }
        .replace_class_hash(class_hash);

    let event: ekubo::upgradeable::Upgradeable::ClassHashReplaced = pop_log(core.contract_address)
        .unwrap();
    assert(event.new_class_hash == class_hash, 'event.class_hash');
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected: ('INVALID_CLASS_HASH', 'ENTRYPOINT_FAILED'))]
fn test_replace_class_hash() {
    let core = deploy_upgradeable();
    IMockUpgradeableDispatcher { contract_address: core.contract_address }
        .replace_class_hash(class_hash_const::<0>());
}
