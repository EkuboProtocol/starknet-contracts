use ekubo::tests::helper::{deploy_mock_extension, deploy_core, deploy_locker, deploy_mock_token};
use ekubo::tests::mocks::mock_extension::{
    MockExtension, IMockExtensionDispatcher, IMockExtensionDispatcherTrait
};
use ekubo::interfaces::core::{
    ICoreDispatcher, ICoreDispatcherTrait, IExtensionDispatcher, IExtensionDispatcherTrait
};
use ekubo::tests::mocks::locker::{ICoreLockerDispatcher, ICoreLockerDispatcherTrait};
use ekubo::types::keys::PoolKey;
use starknet::testing::{set_contract_address};

fn setup(
    fee: u128, tick_spacing: u128
) -> (
    ICoreDispatcher, IMockExtensionDispatcher, IExtensionDispatcher, ICoreLockerDispatcher, PoolKey
) {
    let core = deploy_core(Zeroable::zero());
    let locker = deploy_locker(core);
    let extension = deploy_mock_extension(core, locker);
    let token0 = deploy_mock_token();
    let token1 = deploy_mock_token();
    (
        core, extension, IExtensionDispatcher {
            contract_address: extension.contract_address
            }, locker, PoolKey {
            token0: token0.contract_address,
            token1: token1.contract_address,
            fee,
            tick_spacing,
            extension: extension.contract_address
        }
    )
}

#[test]
#[available_gas(30000000)]
#[should_panic(expected: ('CORE_ONLY', 'ENTRYPOINT_FAILED'))]
fn test_mock_extension_cannot_be_called_directly() {
    let (core, mock, extension, locker, pool_key) = setup(fee: 0, tick_spacing: 1);
    extension.before_initialize_pool(pool_key, Zeroable::zero());
}

#[test]
#[available_gas(30000000)]
fn test_mock_extension_can_be_called_by_core() {
    let (core, mock, extension, locker, pool_key) = setup(fee: 0, tick_spacing: 1);
    set_contract_address(core.contract_address);
    extension.before_initialize_pool(pool_key, Zeroable::zero());
}

