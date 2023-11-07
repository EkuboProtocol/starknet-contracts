use debug::PrintTrait;
use ekubo::owner::owner;
use ekubo::extensions::twamm::{ITWAMMDispatcher, ITWAMMDispatcherTrait,};
use ekubo::interfaces::core::{ICoreDispatcherTrait, ICoreDispatcher, SwapParameters};
use ekubo::interfaces::erc721::{IERC721Dispatcher, IERC721DispatcherTrait};
use ekubo::simple_swapper::{ISimpleSwapperDispatcherTrait};
use ekubo::tests::helper::{
    deploy_core, deploy_twamm, deploy_two_mock_tokens, deploy_positions, setup_pool_with_core,
    update_position
};
use ekubo::tests::mocks::mock_erc20::{IMockERC20Dispatcher, IMockERC20DispatcherTrait};
use ekubo::tests::mocks::mock_upgradeable::{
    MockUpgradeable, IMockUpgradeableDispatcher, IMockUpgradeableDispatcherTrait
};
use ekubo::tests::mocks::locker::{UpdatePositionParameters};
use ekubo::types::bounds::{Bounds, max_bounds};
use ekubo::interfaces::positions::{
    IPositionsDispatcher, IPositionsDispatcherTrait, GetTokenInfoResult, GetTokenInfoRequest
};
use ekubo::types::call_points::{CallPoints};
use ekubo::types::i129::{i129};
use ekubo::types::keys::{PoolKey};
use ekubo::math::ticks::{tick_to_sqrt_ratio};
use ekubo::math::ticks::constants::{MAX_TICK_SPACING, TICKS_IN_ONE_PERCENT};
use ekubo::math::max_liquidity::{max_liquidity};
use ekubo::math::ticks::{min_tick, max_tick};
use option::{OptionTrait};
use starknet::testing::{set_contract_address, set_block_timestamp, pop_log};
use starknet::{get_contract_address, get_block_timestamp, contract_address_const, ClassHash};
use traits::{TryInto, Into};
use zeroable::{Zeroable};

#[test]
#[available_gas(3000000000)]
fn test_replace_class_hash_can_be_called_by_owner() {
    let core = deploy_core();
    let twamm = deploy_twamm(core, 1_000_u64);

    let class_hash: ClassHash = MockUpgradeable::TEST_CLASS_HASH.try_into().unwrap();

    set_contract_address(owner());
    IMockUpgradeableDispatcher { contract_address: twamm.contract_address }
        .replace_class_hash(class_hash);

    let event: ekubo::upgradeable::Upgradeable::ClassHashReplaced = pop_log(twamm.contract_address)
        .unwrap();
    assert(event.new_class_hash == class_hash, 'event.class_hash');
}

#[test]
#[available_gas(3000000000)]
#[should_panic(expected: ('TICK_SPACING', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED'))]
fn test_before_initialize_pool_invalid_tick_spacing() {
    let core = deploy_core();
    let twamm = deploy_twamm(core, 1_000_u64);
    let (token0, token1) = deploy_two_mock_tokens();

    core
        .initialize_pool(
            PoolKey {
                token0: token0.contract_address,
                token1: token1.contract_address,
                fee: 0,
                tick_spacing: 1,
                extension: twamm.contract_address,
            },
            Zeroable::zero()
        );
}

#[test]
#[available_gas(3000000000)]
fn test_before_initialize_pool_valid_tick_spacing() {
    let core = deploy_core();
    let twamm = deploy_twamm(core, 1_000_u64);
    let (token0, token1) = deploy_two_mock_tokens();

    core
        .initialize_pool(
            PoolKey {
                token0: token0.contract_address,
                token1: token1.contract_address,
                fee: 0,
                tick_spacing: MAX_TICK_SPACING,
                extension: twamm.contract_address,
            },
            Zeroable::zero()
        );
}

#[test]
#[available_gas(3000000000)]
#[should_panic(
    expected: (
        'BOUNDS',
        'ENTRYPOINT_FAILED',
        'ENTRYPOINT_FAILED',
        'ENTRYPOINT_FAILED',
        'ENTRYPOINT_FAILED',
        'ENTRYPOINT_FAILED'
    )
)]
fn test_before_update_position_invalid_bounds() {
    let core = deploy_core();
    let twamm = deploy_twamm(core, 1_000_u64);

    let caller = contract_address_const::<42>();
    set_contract_address(caller);

    let setup = setup_pool_with_core(
        core,
        fee: 0,
        tick_spacing: MAX_TICK_SPACING,
        initial_tick: Zeroable::zero(),
        extension: twamm.contract_address,
    );
    let positions = deploy_positions(setup.core);
    let bounds = max_bounds(MAX_TICK_SPACING);

    setup.token0.increase_balance(positions.contract_address, 100_000_000);
    setup.token1.increase_balance(positions.contract_address, 100_000_000);

    let price = core.get_pool_price(pool_key: setup.pool_key);
    let max_liquidity = max_liquidity(
        price.sqrt_ratio,
        tick_to_sqrt_ratio(bounds.lower),
        tick_to_sqrt_ratio(bounds.upper),
        100_000_000,
        100_000_000,
    );

    let (token_id, liquidity) = positions
        .mint_and_deposit(pool_key: setup.pool_key, bounds: bounds, min_liquidity: max_liquidity);

    update_position(
        setup,
        bounds: Bounds {
            lower: i129 { mag: TICKS_IN_ONE_PERCENT * 1, sign: true },
            upper: i129 { mag: TICKS_IN_ONE_PERCENT * 10, sign: false },
        },
        liquidity_delta: i129 { mag: 1, sign: false },
        recipient: caller,
    );
}

#[test]
#[available_gas(3000000000)]
fn test_before_update_position_valid_bounds() {
    let core = deploy_core();
    let twamm = deploy_twamm(core, 1_000_u64);

    let caller = contract_address_const::<42>();
    set_contract_address(caller);

    let setup = setup_pool_with_core(
        core,
        fee: 0,
        tick_spacing: MAX_TICK_SPACING,
        initial_tick: Zeroable::zero(),
        extension: twamm.contract_address,
    );
    let positions = deploy_positions(setup.core);
    let bounds = max_bounds(MAX_TICK_SPACING);

    setup.token0.increase_balance(positions.contract_address, 100_000_000);
    setup.token1.increase_balance(positions.contract_address, 100_000_000);

    let price = core.get_pool_price(pool_key: setup.pool_key);
    let max_liquidity = max_liquidity(
        price.sqrt_ratio,
        tick_to_sqrt_ratio(bounds.lower),
        tick_to_sqrt_ratio(bounds.upper),
        100_000_000,
        100_000_000,
    );

    let (token_id, liquidity) = positions
        .mint_and_deposit(pool_key: setup.pool_key, bounds: bounds, min_liquidity: max_liquidity);

    setup.token0.increase_balance(setup.locker.contract_address, 100_000_000);
    setup.token1.increase_balance(setup.locker.contract_address, 100_000_000);
    update_position(
        setup, bounds, liquidity_delta: i129 { mag: max_liquidity, sign: false }, recipient: caller,
    );
}
