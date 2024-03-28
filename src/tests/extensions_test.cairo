use core::num::traits::{Zero};
use ekubo::interfaces::core::{
    ICoreDispatcher, ICoreDispatcherTrait, IExtensionDispatcher, IExtensionDispatcherTrait,
    SwapParameters, UpdatePositionParameters
};
use ekubo::tests::helper::{Deployer, DeployerTrait, swap_inner, update_position_inner};
use ekubo::tests::mocks::locker::{ICoreLockerDispatcher, ICoreLockerDispatcherTrait};
use ekubo::tests::mocks::mock_extension::{
    MockExtension, IMockExtensionDispatcher, IMockExtensionDispatcherTrait, ExtensionCalled
};
use ekubo::types::bounds::{Bounds, max_bounds};
use ekubo::types::call_points::{CallPoints, all_call_points};
use ekubo::types::delta::Delta;
use ekubo::types::i129::{i129};
use ekubo::types::keys::{PoolKey};
use starknet::testing::{set_contract_address};
use starknet::{get_contract_address};

fn setup(
    ref deployer: Deployer, fee: u128, tick_spacing: u128, call_points: CallPoints
) -> (
    ICoreDispatcher, IMockExtensionDispatcher, IExtensionDispatcher, ICoreLockerDispatcher, PoolKey
) {
    let mut d: Deployer = Default::default();
    let core = d.deploy_core();
    let locker = d.deploy_locker(core);
    let extension = d.deploy_mock_extension(core, call_points);
    let (token0, token1) = d.deploy_two_mock_tokens();
    (
        core,
        extension,
        IExtensionDispatcher { contract_address: extension.contract_address },
        locker,
        PoolKey {
            token0: token0.contract_address,
            token1: token1.contract_address,
            fee,
            tick_spacing,
            extension: extension.contract_address
        }
    )
}

#[test]
#[should_panic(expected: ('CORE_ONLY', 'ENTRYPOINT_FAILED'))]
fn test_mock_extension_cannot_be_called_directly() {
    let mut deployer: Deployer = Default::default();
    let (_, _, extension, _, pool_key) = setup(
        ref deployer: deployer, fee: 0, tick_spacing: 1, call_points: all_call_points()
    );
    extension.before_initialize_pool(Zero::zero(), pool_key, Zero::zero());
}

#[test]
fn test_mock_extension_can_be_called_by_core() {
    let mut deployer: Deployer = Default::default();

    let (core, _, extension, _, pool_key) = setup(
        ref deployer: deployer, fee: 0, tick_spacing: 1, call_points: all_call_points()
    );
    set_contract_address(core.contract_address);
    extension.before_initialize_pool(Zero::zero(), pool_key, Zero::zero());
}

#[test]
#[should_panic(expected: ('EXTENSION_ONLY', 'ENTRYPOINT_FAILED'))]
fn test_core_cannot_change_call_points() {
    let mut deployer: Deployer = Default::default();

    let (core, _, _, _, pool_key) = setup(
        ref deployer: deployer, fee: 0, tick_spacing: 1, call_points: all_call_points()
    );
    core.change_call_points(pool_key, Default::default());
}

#[test]
#[should_panic(expected: ('NOT_INITIALIZED', 'ENTRYPOINT_FAILED'))]
fn test_cannot_change_call_points_not_initialized() {
    let mut deployer: Deployer = Default::default();

    let (core, _, extension, _, pool_key) = setup(
        ref deployer: deployer, fee: 0, tick_spacing: 1, call_points: all_call_points()
    );
    set_contract_address(extension.contract_address);
    core.change_call_points(pool_key, Default::default());
}

#[test]
fn test_extension_can_call_change_call_points() {
    let mut deployer: Deployer = Default::default();

    let (core, _, extension, _, pool_key) = setup(
        ref deployer: deployer, fee: 0, tick_spacing: 1, call_points: all_call_points()
    );
    core.initialize_pool(pool_key, Zero::zero());
    set_contract_address(extension.contract_address);
    assert_eq!(core.get_pool_price(pool_key).call_points, all_call_points());
    core.change_call_points(pool_key, Default::default());
    assert_eq!(core.get_pool_price(pool_key).call_points, Default::default());
}

#[test]
fn test_extension_can_call_change_call_points_from_extension() {
    let mut deployer: Deployer = Default::default();

    let (core, mock_extension, _, _, pool_key) = setup(
        ref deployer: deployer, fee: 0, tick_spacing: 1, call_points: all_call_points()
    );
    core.initialize_pool(pool_key, Zero::zero());
    assert_eq!(core.get_pool_price(pool_key).call_points, all_call_points());
    mock_extension.change_call_points(pool_key, Default::default());
    assert_eq!(core.get_pool_price(pool_key).call_points, Default::default());
}


fn check_matches_pool_key(call: ExtensionCalled, pool_key: PoolKey) {
    assert(call.token0 == pool_key.token0, 'token0 matches');
    assert(call.token1 == pool_key.token1, 'token1 matches');
    assert(call.fee == pool_key.fee, 'fee matches');
    assert(call.tick_spacing == pool_key.tick_spacing, 'tick_spacing matches');
}

#[test]
fn test_mock_extension_initialize_pool_is_called() {
    let mut deployer: Deployer = Default::default();
    let (core, mock, _, _, pool_key) = setup(
        ref deployer: deployer, fee: 0, tick_spacing: 1, call_points: all_call_points()
    );
    core.initialize_pool(pool_key, Zero::zero());
    assert(mock.get_num_calls() == 2, '2 calls made');

    let before = mock.get_call(0);
    assert(before.caller == get_contract_address(), 'caller');
    assert(before.call_point == 0, 'called before');
    check_matches_pool_key(before, pool_key);

    let after = mock.get_call(1);
    assert(after.caller == get_contract_address(), 'caller');
    assert(after.call_point == 1, 'called after');
    check_matches_pool_key(before, pool_key);
}


#[test]
fn test_mock_extension_swap_is_called() {
    let mut deployer: Deployer = Default::default();
    let (core, mock, _, locker, pool_key) = setup(
        ref deployer: deployer, fee: 0, tick_spacing: 1, call_points: all_call_points()
    );
    core.initialize_pool(pool_key, Zero::zero());
    let delta = swap_inner(
        core: core,
        pool_key: pool_key,
        locker: locker,
        amount: i129 { mag: 1, sign: false },
        is_token1: false,
        sqrt_ratio_limit: 0x100000000000000000000000000000000_u256,
        recipient: Zero::zero(),
        skip_ahead: 0,
    );
    assert(delta.is_zero(), 'no change');

    assert(mock.get_num_calls() == 4, '4 calls made');

    let before = mock.get_call(2);
    assert(before.caller == locker.contract_address, 'caller');
    assert(before.call_point == 2, 'called before');
    check_matches_pool_key(before, pool_key);

    let after = mock.get_call(3);
    assert(after.caller == locker.contract_address, 'caller');
    assert(after.call_point == 3, 'called after');
    check_matches_pool_key(before, pool_key);
}

#[test]
fn test_mock_extension_update_position_is_called() {
    let mut deployer: Deployer = Default::default();
    let (core, mock, _, locker, pool_key) = setup(
        ref deployer: deployer, fee: 0, tick_spacing: 1, call_points: all_call_points()
    );
    core.initialize_pool(pool_key, Zero::zero());
    let delta = update_position_inner(
        core: core,
        pool_key: pool_key,
        locker: locker,
        bounds: max_bounds(1),
        liquidity_delta: Zero::zero(),
        recipient: Zero::zero(),
    );
    assert(delta.is_zero(), 'no change');

    assert(mock.get_num_calls() == 4, '4 calls made');

    let before = mock.get_call(2);
    assert(before.caller == locker.contract_address, 'caller');
    assert(before.call_point == 4, 'called before');
    check_matches_pool_key(before, pool_key);

    let after = mock.get_call(3);
    assert(after.caller == locker.contract_address, 'caller');
    assert(after.call_point == 5, 'called after');
    check_matches_pool_key(before, pool_key);
}

#[test]
fn test_mock_extension_no_call_points() {
    let mut deployer: Deployer = Default::default();
    let (core, mock, _, locker, pool_key) = setup(
        ref deployer: deployer, fee: 0, tick_spacing: 1, call_points: Default::default()
    );
    core.initialize_pool(pool_key, Zero::zero());
    let delta = update_position_inner(
        core: core,
        pool_key: pool_key,
        locker: locker,
        bounds: max_bounds(1),
        liquidity_delta: Zero::zero(),
        recipient: Zero::zero(),
    );
    assert(delta.is_zero(), 'no change');
    let delta = swap_inner(
        core: core,
        pool_key: pool_key,
        locker: locker,
        amount: i129 { mag: 1, sign: false },
        is_token1: false,
        sqrt_ratio_limit: 0x100000000000000000000000000000000_u256,
        recipient: Zero::zero(),
        skip_ahead: 0,
    );
    assert(delta.is_zero(), 'no change');

    assert(mock.get_num_calls() == 1, '1 call made');

    let call = mock.get_call(0);
    assert(call.caller == get_contract_address(), 'caller');
    assert(call.call_point == 0, 'called');
    check_matches_pool_key(call, pool_key);
}

#[test]
fn test_mock_extension_after_initialize_pool_only() {
    let mut deployer: Deployer = Default::default();
    let (core, mock, _, locker, pool_key) = setup(
        ref deployer: deployer,
        fee: 0,
        tick_spacing: 1,
        call_points: CallPoints {
            after_initialize_pool: true,
            before_swap: false,
            after_swap: false,
            before_update_position: false,
            after_update_position: false,
            before_collect_fees: false,
            after_collect_fees: false,
        }
    );

    core.initialize_pool(pool_key, Zero::zero());
    let delta = update_position_inner(
        core: core,
        pool_key: pool_key,
        locker: locker,
        bounds: max_bounds(1),
        liquidity_delta: Zero::zero(),
        recipient: Zero::zero(),
    );
    assert(delta.is_zero(), 'no change');
    let delta = swap_inner(
        core: core,
        pool_key: pool_key,
        locker: locker,
        amount: i129 { mag: 1, sign: false },
        is_token1: false,
        sqrt_ratio_limit: 0x100000000000000000000000000000000_u256,
        recipient: Zero::zero(),
        skip_ahead: 0,
    );
    assert(delta.is_zero(), 'no change');

    assert(mock.get_num_calls() == 2, '2 call made');

    let call = mock.get_call(1);
    assert(call.caller == get_contract_address(), 'caller');
    assert(call.call_point == 1, 'called');
    check_matches_pool_key(call, pool_key);
}


#[test]
fn test_mock_extension_before_swap_only() {
    let mut deployer: Deployer = Default::default();
    let (core, mock, _, locker, pool_key) = setup(
        ref deployer: deployer,
        fee: 0,
        tick_spacing: 1,
        call_points: CallPoints {
            after_initialize_pool: false,
            before_swap: true,
            after_swap: false,
            before_update_position: false,
            after_update_position: false,
            before_collect_fees: false,
            after_collect_fees: false,
        }
    );

    core.initialize_pool(pool_key, Zero::zero());
    let delta = update_position_inner(
        core: core,
        pool_key: pool_key,
        locker: locker,
        bounds: max_bounds(1),
        liquidity_delta: Zero::zero(),
        recipient: Zero::zero(),
    );
    assert(delta.is_zero(), 'no change');
    let delta = swap_inner(
        core: core,
        pool_key: pool_key,
        locker: locker,
        amount: i129 { mag: 1, sign: false },
        is_token1: false,
        sqrt_ratio_limit: 0x100000000000000000000000000000000_u256,
        recipient: Zero::zero(),
        skip_ahead: 0,
    );
    assert(delta.is_zero(), 'no change');

    assert(mock.get_num_calls() == 2, '2 call made');

    let call = mock.get_call(1);
    assert(call.caller == locker.contract_address, 'caller');
    assert(call.call_point == 2, 'called');
    check_matches_pool_key(call, pool_key);
}

#[test]
fn test_mock_extension_after_swap_only() {
    let mut deployer: Deployer = Default::default();
    let (core, mock, _, locker, pool_key) = setup(
        ref deployer: deployer,
        fee: 0,
        tick_spacing: 1,
        call_points: CallPoints {
            after_initialize_pool: false,
            before_swap: false,
            after_swap: true,
            before_update_position: false,
            after_update_position: false,
            before_collect_fees: false,
            after_collect_fees: false,
        }
    );

    core.initialize_pool(pool_key, Zero::zero());
    let delta = update_position_inner(
        core: core,
        pool_key: pool_key,
        locker: locker,
        bounds: max_bounds(1),
        liquidity_delta: Zero::zero(),
        recipient: Zero::zero(),
    );
    assert(delta.is_zero(), 'no change');
    let delta = swap_inner(
        core: core,
        pool_key: pool_key,
        locker: locker,
        amount: i129 { mag: 1, sign: false },
        is_token1: false,
        sqrt_ratio_limit: 0x100000000000000000000000000000000_u256,
        recipient: Zero::zero(),
        skip_ahead: 0,
    );
    assert(delta.is_zero(), 'no change');

    assert(mock.get_num_calls() == 2, '2 call made');

    let call = mock.get_call(1);
    assert(call.caller == locker.contract_address, 'caller');
    assert(call.call_point == 3, 'called');
    check_matches_pool_key(call, pool_key);
}


#[test]
fn test_mock_extension_before_update_position_only() {
    let mut deployer: Deployer = Default::default();

    let (core, mock, _, locker, pool_key) = setup(
        ref deployer: deployer,
        fee: 0,
        tick_spacing: 1,
        call_points: CallPoints {
            after_initialize_pool: false,
            before_swap: false,
            after_swap: false,
            before_update_position: true,
            after_update_position: false,
            before_collect_fees: false,
            after_collect_fees: false,
        }
    );

    core.initialize_pool(pool_key, Zero::zero());
    let delta = update_position_inner(
        core: core,
        pool_key: pool_key,
        locker: locker,
        bounds: max_bounds(1),
        liquidity_delta: Zero::zero(),
        recipient: Zero::zero(),
    );
    assert(delta.is_zero(), 'no change');
    let delta = swap_inner(
        core: core,
        pool_key: pool_key,
        locker: locker,
        amount: i129 { mag: 1, sign: false },
        is_token1: false,
        sqrt_ratio_limit: 0x100000000000000000000000000000000_u256,
        recipient: Zero::zero(),
        skip_ahead: 0,
    );
    assert(delta.is_zero(), 'no change');

    assert(mock.get_num_calls() == 2, '2 call made');

    let call = mock.get_call(1);
    assert(call.caller == locker.contract_address, 'caller');
    assert(call.call_point == 4, 'called');
    check_matches_pool_key(call, pool_key);
}

#[test]
fn test_mock_extension_after_update_position_only() {
    let mut deployer: Deployer = Default::default();
    let (core, mock, _, locker, pool_key) = setup(
        ref deployer: deployer,
        fee: 0,
        tick_spacing: 1,
        call_points: CallPoints {
            after_initialize_pool: false,
            before_swap: false,
            after_swap: false,
            before_update_position: false,
            after_update_position: true,
            before_collect_fees: false,
            after_collect_fees: false,
        }
    );

    core.initialize_pool(pool_key, Zero::zero());
    let delta = update_position_inner(
        core: core,
        pool_key: pool_key,
        locker: locker,
        bounds: max_bounds(1),
        liquidity_delta: Zero::zero(),
        recipient: Zero::zero(),
    );
    assert(delta.is_zero(), 'no change');
    let delta = swap_inner(
        core: core,
        pool_key: pool_key,
        locker: locker,
        amount: i129 { mag: 1, sign: false },
        is_token1: false,
        sqrt_ratio_limit: 0x100000000000000000000000000000000_u256,
        recipient: Zero::zero(),
        skip_ahead: 0,
    );
    assert(delta.is_zero(), 'no change');

    assert(mock.get_num_calls() == 2, '2 call made');

    let call = mock.get_call(1);
    assert(call.caller == locker.contract_address, 'caller');
    assert(call.call_point == 5, 'called');
    check_matches_pool_key(call, pool_key);
}

#[test]
fn test_mock_extension_is_called_back_into_other_pool() {
    let mut deployer: Deployer = Default::default();
    let (core, mock, _, _, pool_key) = setup(
        ref deployer: deployer, fee: 0, tick_spacing: 1, call_points: all_call_points()
    );

    // shadow the mock variable
    let other_mock = deployer.deploy_mock_extension(core, all_call_points());

    core.initialize_pool(pool_key, Zero::zero());

    // because the other mock is calling into the pool, the extension should get hit every time
    other_mock.call_into_pool(pool_key);

    assert(mock.get_num_calls() == 8, '# calls made');

    let call = mock.get_call(0);
    assert(call.caller == get_contract_address(), 'before initialize caller');
    assert(call.call_point == 0, 'before init');
    check_matches_pool_key(call, pool_key);

    let call = mock.get_call(1);
    assert(call.caller == get_contract_address(), 'after initialize caller');
    assert(call.call_point == 1, 'after init');
    check_matches_pool_key(call, pool_key);

    let call = mock.get_call(2);
    assert(call.caller == other_mock.contract_address, 'before swap caller');
    assert(call.call_point == 2, 'before swap');
    check_matches_pool_key(call, pool_key);

    let call = mock.get_call(3);
    assert(call.caller == other_mock.contract_address, 'after swap caller');
    assert(call.call_point == 3, 'after init');
    check_matches_pool_key(call, pool_key);

    let call = mock.get_call(4);
    assert(call.caller == other_mock.contract_address, 'before update caller');
    assert(call.call_point == 4, 'before update');
    check_matches_pool_key(call, pool_key);

    let call = mock.get_call(5);
    assert(call.caller == other_mock.contract_address, 'after update caller');
    assert(call.call_point == 5, 'after update');
    check_matches_pool_key(call, pool_key);

    let call = mock.get_call(6);
    assert(call.caller == other_mock.contract_address, 'before collect fees caller');
    assert(call.call_point == 6, 'before collect fees call point');
    check_matches_pool_key(call, pool_key);

    let call = mock.get_call(7);
    assert(call.caller == other_mock.contract_address, 'after collect fees caller');
    assert(call.call_point == 7, 'after collect fees call point');
    check_matches_pool_key(call, pool_key);
}

#[test]
fn test_mock_extension_not_called_back_into_own_pool() {
    let mut deployer: Deployer = Default::default();
    let (core, mock, _, _, pool_key) = setup(
        ref deployer: deployer, fee: 0, tick_spacing: 1, call_points: all_call_points()
    );

    core.initialize_pool(pool_key, Zero::zero());

    mock.call_into_pool(pool_key);

    assert(mock.get_num_calls() == 2, '2 call made');

    let call = mock.get_call(0);
    assert(call.caller == get_contract_address(), 'before initialize caller');
    assert(call.call_point == 0, 'before init');
    check_matches_pool_key(call, pool_key);

    let call = mock.get_call(1);
    assert(call.caller == get_contract_address(), 'after initialize caller');
    assert(call.call_point == 1, 'after init');
    check_matches_pool_key(call, pool_key);
}
