use ekubo::tests::helper::{deploy_mock_extension, deploy_core, deploy_locker, deploy_mock_token};
use ekubo::tests::mocks::mock_extension::{
    MockExtension, IMockExtensionDispatcher, IMockExtensionDispatcherTrait, ExtensionCalled
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


fn check_matches_pool_key(call: ExtensionCalled, pool_key: PoolKey) {
    assert(call.token0 == pool_key.token0, 'token0 matches');
    assert(call.token1 == pool_key.token1, 'token1 matches');
    assert(call.fee == pool_key.fee, 'fee matches');
    assert(call.tick_spacing == pool_key.tick_spacing, 'tick_spacing matches');
}

#[test]
#[available_gas(30000000)]
fn test_mock_extension_can_be_used_in_initialized_pool() {
    let (core, mock, extension, locker, pool_key) = setup(fee: 0, tick_spacing: 1);
    core.initialize_pool(pool_key, Zeroable::zero());
    assert(mock.get_num_calls() == 2, '2 calls made');

    let before = mock.get_call(0);
    assert(before.call_point == 0, 'called before');
    check_matches_pool_key(before, pool_key);

    let after = mock.get_call(1);
    assert(after.call_point == 1, 'called after');
    check_matches_pool_key(before, pool_key);
}
