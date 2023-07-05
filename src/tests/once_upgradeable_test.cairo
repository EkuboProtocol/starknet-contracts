use ekubo::interfaces::core::{ICoreDispatcher, ICoreDispatcherTrait};
use ekubo::core::{Core};
use ekubo::tests::helper::{deploy_core, deploy_once_upgradeable};
use ekubo::once_upgradeable::{
    OnceUpgradeable, IOnceUpgradeableDispatcher, IOnceUpgradeableDispatcherTrait
};
use starknet::class_hash::Felt252TryIntoClassHash;
use starknet::{ContractAddress, contract_address_const};
use starknet::testing::{set_contract_address};
use traits::{TryInto, Into};
use option::{OptionTrait};

#[test]
#[available_gas(3000000)]
fn test_once_upgradeable_deploy_owner_core() {
    let owner = contract_address_const::<123456>();
    let ou = deploy_once_upgradeable(owner);
    let core = deploy_core();
    set_contract_address(owner);
    ou.replace(Core::TEST_CLASS_HASH.try_into().unwrap());
    set_contract_address(Zeroable::zero());
    assert(ICoreDispatcher { contract_address: ou.contract_address }.get_owner() == owner, 'owner');
}

#[test]
#[available_gas(3000000)]
#[should_panic(expected: ('ONLY_OWNER', 'ENTRYPOINT_FAILED'))]
fn test_replace_callable_only_by_owner() {
    let owner = contract_address_const::<123456>();
    let ou = deploy_once_upgradeable(owner);
    let core = deploy_core();
    ou.replace(Core::TEST_CLASS_HASH.try_into().unwrap());
}
