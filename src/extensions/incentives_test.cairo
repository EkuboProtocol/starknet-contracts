use ekubo::interfaces::positions::IPositionsDispatcherTrait;
use ekubo::interfaces::core::{ICoreDispatcherTrait, ICoreDispatcher};
use ekubo::extensions::incentives::{IIncentivesDispatcher, IIncentivesDispatcherTrait};
use ekubo::tests::mocks::mock_erc20::{IMockERC20Dispatcher, IMockERC20DispatcherTrait};
use ekubo::tests::helper::{
    deploy_core, deploy_positions, deploy_incentives, deploy_two_mock_tokens
};
use ekubo::types::keys::{PoolKey, PositionKey};
use ekubo::types::i129::{i129};
use ekubo::types::bounds::{Bounds};
use ekubo::types::call_points::{CallPoints};
use starknet::{get_contract_address, get_block_timestamp};
use starknet::testing::{set_contract_address, set_block_timestamp};
use option::{OptionTrait};
use traits::{TryInto};
use zeroable::{Zeroable};
use debug::PrintTrait;

fn setup_pool_with_extension(
    initial_tick: i129
) -> (ICoreDispatcher, IIncentivesDispatcher, PoolKey) {
    let core = deploy_core();
    let incentives = deploy_incentives(core);
    let (token0, token1) = deploy_two_mock_tokens();

    let key = PoolKey {
        token0: token0.contract_address,
        token1: token1.contract_address,
        fee: 0,
        tick_spacing: 1,
        extension: incentives.contract_address,
    };

    core.initialize_pool(key, initial_tick);
    let old = get_contract_address();
    set_contract_address(core.get_owner());
    core.set_reserves_limit(key.token0, 0xffffffffffffffffffffffffffffffff);
    core.set_reserves_limit(key.token1, 0xffffffffffffffffffffffffffffffff);
    set_contract_address(old);

    (core, IIncentivesDispatcher { contract_address: incentives.contract_address }, key)
}

#[test]
#[available_gas(300000000)]
fn test_before_initialize_call_points() {
    let (core, _, key) = setup_pool_with_extension(initial_tick: Zeroable::zero());

    let pool = core.get_pool(key);

    assert(
        pool.call_points == CallPoints {
            after_initialize_pool: false,
            before_swap: true,
            after_swap: true,
            before_update_position: true,
            after_update_position: false,
        },
        'call points'
    );
}

#[test]
#[available_gas(300000000)]
fn test_add_liquidity() {
    let (core, incentives, key) = setup_pool_with_extension(
        initial_tick: i129 { mag: 5, sign: true }
    );

    let positions = deploy_positions(core);

    let bounds = Bounds {
        lower: i129 { mag: 100, sign: true }, upper: i129 { mag: 100, sign: false }
    };
    let token_id = positions
        .mint(recipient: get_contract_address(), pool_key: key, bounds: bounds, );

    IMockERC20Dispatcher {
        contract_address: key.token0
    }.increase_balance(address: positions.contract_address, amount: 10000);
    IMockERC20Dispatcher {
        contract_address: key.token1
    }.increase_balance(address: positions.contract_address, amount: 10000);
    positions.deposit_last(pool_key: key, bounds: bounds, min_liquidity: 100);

    let position_key = PositionKey {
        salt: token_id.try_into().unwrap(), owner: positions.contract_address, bounds: bounds, 
    };

    assert(
        incentives.get_seconds_per_liquidity_inside(pool_key: key, bounds: bounds) == 0,
        'seconds_per_liquidity'
    );
    assert(incentives.get_tick_cumulative(key).is_zero(), 'tick_cumulative');

    set_block_timestamp(get_block_timestamp() + 100);

    assert(
        incentives
            .get_seconds_per_liquidity_inside(
                pool_key: key, bounds: bounds
            ) == 0x8cecd9bbcf132ce54865c3086aa,
        'seconds_per_liquidity'
    );
    assert(incentives.get_tick_cumulative(key) == i129 { mag: 500, sign: true }, 'tick_cumulative');
}
