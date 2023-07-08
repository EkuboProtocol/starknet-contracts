use ekubo::interfaces::positions::{IPositionsDispatcher, IPositionsDispatcherTrait};
use ekubo::interfaces::core::{ICoreDispatcherTrait, ICoreDispatcher};
use ekubo::extensions::oracle::{IOracleDispatcher, IOracleDispatcherTrait};
use ekubo::tests::mocks::mock_erc20::{IMockERC20Dispatcher, IMockERC20DispatcherTrait};
use ekubo::tests::helper::{
    deploy_core, deploy_positions, deploy_oracle, deploy_two_mock_tokens, swap_inner, deploy_locker
};
use ekubo::types::keys::{PoolKey, PositionKey};
use ekubo::types::i129::{i129};
use ekubo::types::bounds::{Bounds};
use ekubo::types::call_points::{CallPoints};
use starknet::{get_contract_address, get_block_timestamp, contract_address_const};
use starknet::testing::{set_contract_address, set_block_timestamp};
use option::{OptionTrait};
use traits::{TryInto};
use zeroable::{Zeroable};
use ekubo::math::liquidity::{liquidity_delta_to_amount_delta};
use ekubo::math::ticks::{tick_to_sqrt_ratio};
use debug::PrintTrait;

fn setup_pool_with_extension(initial_tick: i129) -> (ICoreDispatcher, IOracleDispatcher, PoolKey) {
    let core = deploy_core();
    let oracle = deploy_oracle(core);
    let (token0, token1) = deploy_two_mock_tokens();

    let key = PoolKey {
        token0: token0.contract_address,
        token1: token1.contract_address,
        fee: 0,
        tick_spacing: 1,
        extension: oracle.contract_address,
    };

    core.initialize_pool(key, initial_tick);

    (core, IOracleDispatcher { contract_address: oracle.contract_address }, key)
}

#[test]
#[available_gas(300000000)]
fn test_before_initialize_call_points() {
    let (core, oracle, key) = setup_pool_with_extension(initial_tick: i129 { mag: 3, sign: true });

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

    assert(oracle.get_tick_cumulative(key).is_zero(), '0 cumulative');
    // no position here
    assert(
        oracle
            .get_seconds_per_liquidity_inside(
                key,
                Bounds { lower: i129 { mag: 3, sign: true }, upper: i129 { mag: 3, sign: false } }
            )
            .is_zero(),
        '0 seconds per liquidity'
    );

    set_block_timestamp(get_block_timestamp() + 10);
    assert(oracle.get_tick_cumulative(key) == i129 { mag: 30, sign: true }, '30 cumulative');
}

fn deposit(
    core: ICoreDispatcher,
    positions: IPositionsDispatcher,
    pool_key: PoolKey,
    bounds: Bounds,
    min_liquidity: u128
) -> (u256, u128) {
    let token_id = positions
        .mint(recipient: get_contract_address(), pool_key: pool_key, bounds: bounds, );

    let pool = core.get_pool(pool_key);
    let delta = liquidity_delta_to_amount_delta(
        pool.sqrt_ratio,
        i129 { mag: min_liquidity, sign: false },
        tick_to_sqrt_ratio(bounds.lower),
        tick_to_sqrt_ratio(bounds.upper)
    );

    assert(
        IMockERC20Dispatcher {
            contract_address: pool_key.token0
        }.balanceOf(address: positions.contract_address) == 0,
        'token0 balance'
    );
    assert(
        IMockERC20Dispatcher {
            contract_address: pool_key.token1
        }.balanceOf(address: positions.contract_address) == 0,
        'token1 balance'
    );

    IMockERC20Dispatcher {
        contract_address: pool_key.token0
    }.increase_balance(address: positions.contract_address, amount: delta.amount0.mag);
    IMockERC20Dispatcher {
        contract_address: pool_key.token1
    }.increase_balance(address: positions.contract_address, amount: delta.amount1.mag);

    let liquidity_calculated = positions
        .deposit_last(pool_key: pool_key, bounds: bounds, min_liquidity: min_liquidity);

    // todo: why isn't this exactly equal?
    // assert(min_liquidity == liquidity_calculated, 'liquidity');

    (token_id, liquidity_calculated)
}

#[test]
#[available_gas(300000000)]
fn test_time_passes_seconds_per_liquidity_global() {
    let (core, oracle, key) = setup_pool_with_extension(initial_tick: i129 { mag: 5, sign: true });

    let positions = deploy_positions(core);

    let bounds = Bounds {
        lower: i129 { mag: 100, sign: true }, upper: i129 { mag: 100, sign: false }
    };

    let token_id = deposit(
        core: core, positions: positions, pool_key: key, bounds: bounds, min_liquidity: 0xb5a81a9, 
    );

    assert(
        oracle.get_seconds_per_liquidity_inside(pool_key: key, bounds: bounds) == 0,
        'seconds_per_liquidity'
    );
    assert(oracle.get_tick_cumulative(key).is_zero(), 'tick_cumulative');

    set_block_timestamp(get_block_timestamp() + 100);

    assert(
        oracle
            .get_seconds_per_liquidity_inside(
                pool_key: key, bounds: bounds
            ) == 0x8cecd9bbcf132ce54865c3086aa, // 100 * 2**128 / 0xb5a81a9
        'seconds_per_liquidity'
    );
    assert(oracle.get_tick_cumulative(key) == i129 { mag: 500, sign: true }, 'tick_cumulative');
}

#[test]
#[available_gas(300000000)]
fn test_time_passed_position_out_of_range_only() {
    let (core, oracle, key) = setup_pool_with_extension(initial_tick: Zeroable::zero());

    let positions = deploy_positions(core);

    let bounds_above = Bounds {
        lower: i129 { mag: 1, sign: false }, upper: i129 { mag: 100, sign: false }
    };
    let bounds_below = Bounds {
        lower: i129 { mag: 100, sign: true }, upper: i129 { mag: 0, sign: true }
    };

    let (token_id_1, _) = deposit(
        core: core,
        positions: positions,
        pool_key: key,
        bounds: bounds_above,
        min_liquidity: 0xb5a81a9,
    );
    let (token_id_2, _) = deposit(
        core: core,
        positions: positions,
        pool_key: key,
        bounds: bounds_below,
        min_liquidity: 0xb5a81a9,
    );

    assert(
        oracle.get_seconds_per_liquidity_inside(pool_key: key, bounds: bounds_above) == 0,
        'seconds_per_liquidity'
    );
    assert(
        oracle.get_seconds_per_liquidity_inside(pool_key: key, bounds: bounds_below) == 0,
        'seconds_per_liquidity'
    );
    assert(oracle.get_tick_cumulative(key).is_zero(), 'tick_cumulative');

    set_block_timestamp(get_block_timestamp() + 100);

    assert(
        oracle.get_seconds_per_liquidity_inside(pool_key: key, bounds: bounds_above) == 0,
        'seconds_per_liquidity'
    );
    assert(
        oracle.get_seconds_per_liquidity_inside(pool_key: key, bounds: bounds_below) == 0,
        'seconds_per_liquidity'
    );
    assert(oracle.get_tick_cumulative(key).is_zero(), 'tick_cumulative');
}


#[test]
#[available_gas(300000000)]
fn test_swap_into_liquidity_time_passed() {
    let (core, oracle, key) = setup_pool_with_extension(initial_tick: Zeroable::zero());
    let locker = deploy_locker(core);
    let positions = deploy_positions(core);

    let bounds = Bounds {
        lower: i129 { mag: 1, sign: false }, upper: i129 { mag: 100, sign: false }
    };

    let (token_id_1, _) = deposit(
        core: core, positions: positions, pool_key: key, bounds: bounds, min_liquidity: 0xb5a81a9, 
    );

    IMockERC20Dispatcher {
        contract_address: key.token1
    }.increase_balance(locker.contract_address, 10000000);

    set_block_timestamp(get_block_timestamp() + 75);

    swap_inner(
        core: core,
        pool_key: key,
        locker: locker,
        amount: i129 { mag: 0xffffffffffffffffffffffffffffffff, sign: false },
        is_token1: true,
        sqrt_ratio_limit: tick_to_sqrt_ratio(i129 { mag: 50, sign: false }),
        recipient: contract_address_const::<23456>(),
        skip_ahead: 0
    );

    assert(
        oracle.get_seconds_per_liquidity_inside(pool_key: key, bounds: bounds) == 0,
        'seconds_per_liquidity'
    );
    assert(oracle.get_tick_cumulative(key).is_zero(), 'tick_cumulative');

    set_block_timestamp(get_block_timestamp() + 100);

    assert(
        oracle
            .get_seconds_per_liquidity_inside(
                pool_key: key, bounds: bounds
            ) == 0x8ceb28181e1775c7aa9c4f8a190,
        'seconds_per_liquidity after'
    );
    assert(
        oracle.get_tick_cumulative(key) == i129 { mag: 5000, sign: false }, 'tick_cumulative after'
    );
}

#[test]
#[available_gas(300000000)]
fn test_swap_through_liquidity_time_passed() {
    let (core, oracle, key) = setup_pool_with_extension(initial_tick: Zeroable::zero());
    let locker = deploy_locker(core);
    let positions = deploy_positions(core);

    let bounds = Bounds {
        lower: i129 { mag: 1, sign: false }, upper: i129 { mag: 100, sign: false }
    };

    let (token_id_1, _) = deposit(
        core: core, positions: positions, pool_key: key, bounds: bounds, min_liquidity: 0xb5a81a9, 
    );

    IMockERC20Dispatcher {
        contract_address: key.token1
    }.increase_balance(locker.contract_address, 10000000);

    set_block_timestamp(get_block_timestamp() + 75);

    swap_inner(
        core: core,
        pool_key: key,
        locker: locker,
        amount: i129 { mag: 0xffffffffffffffffffffffffffffffff, sign: false },
        is_token1: true,
        sqrt_ratio_limit: tick_to_sqrt_ratio(i129 { mag: 100, sign: false }),
        recipient: contract_address_const::<23456>(),
        skip_ahead: 0
    );

    assert(
        oracle.get_seconds_per_liquidity_inside(pool_key: key, bounds: bounds) == 0,
        'seconds_per_liquidity'
    );
    assert(oracle.get_tick_cumulative(key).is_zero(), 'tick_cumulative');

    set_block_timestamp(get_block_timestamp() + 100);

    assert(
        oracle.get_seconds_per_liquidity_inside(pool_key: key, bounds: bounds) == 0,
        'seconds_per_liquidity after'
    );
    assert(
        oracle.get_tick_cumulative(key) == i129 { mag: 10000, sign: false }, 'tick_cumulative after'
    );

    IMockERC20Dispatcher {
        contract_address: key.token0
    }.increase_balance(locker.contract_address, 10000000);
    swap_inner(
        core: core,
        pool_key: key,
        locker: locker,
        amount: i129 { mag: 0xffffffffffffffffffffffffffffffff, sign: false },
        is_token1: false,
        sqrt_ratio_limit: tick_to_sqrt_ratio(i129 { mag: 100, sign: true }),
        recipient: contract_address_const::<23456>(),
        skip_ahead: 0
    );

    assert(
        oracle.get_seconds_per_liquidity_inside(pool_key: key, bounds: bounds) == 0,
        'seconds_per_liquidity 2'
    );
    assert(
        oracle.get_tick_cumulative(key) == i129 { mag: 10000, sign: false }, 'cumulative tick 2'
    );
    set_block_timestamp(get_block_timestamp() + 10);

    assert(
        oracle.get_seconds_per_liquidity_inside(pool_key: key, bounds: bounds) == 0,
        'seconds_per_liquidity 3'
    );
    assert(oracle.get_tick_cumulative(key) == i129 { mag: 9000, sign: false }, 'cumulative tick 3');
}
