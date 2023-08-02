use ekubo::interfaces::positions::{IPositionsDispatcher, IPositionsDispatcherTrait};
use ekubo::interfaces::core::{ICoreDispatcherTrait, ICoreDispatcher};
use ekubo::extensions::limit_orders::{ILimitOrdersDispatcher, ILimitOrdersDispatcherTrait};
use ekubo::tests::mocks::mock_erc20::{IMockERC20Dispatcher, IMockERC20DispatcherTrait};
use ekubo::tests::helper::{
    deploy_core, deploy_positions, deploy_limit_orders, deploy_two_mock_tokens, swap_inner,
    deploy_locker
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

fn setup_pool_with_extension(
    initial_tick: i129
) -> (ICoreDispatcher, ILimitOrdersDispatcher, PoolKey) {
    let core = deploy_core();
    let limit_orders = deploy_limit_orders(core);
    let (token0, token1) = deploy_two_mock_tokens();

    let key = PoolKey {
        token0: token0.contract_address,
        token1: token1.contract_address,
        fee: 0,
        tick_spacing: 1,
        extension: limit_orders.contract_address,
    };

    core.initialize_pool(key, initial_tick);

    (core, ILimitOrdersDispatcher { contract_address: limit_orders.contract_address }, key)
}

#[test]
#[available_gas(3000000000)]
#[should_panic(expected: ('ZERO_FEE_ONLY', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED'))]
fn test_before_initialize_pool_fee_must_be_zero() {
    let core = deploy_core();
    let limit_orders = deploy_limit_orders(core);
    let (token0, token1) = deploy_two_mock_tokens();

    core
        .initialize_pool(
            PoolKey {
                token0: token0.contract_address,
                token1: token1.contract_address,
                fee: 1,
                tick_spacing: 1,
                extension: limit_orders.contract_address,
            },
            Zeroable::zero()
        );
}

#[test]
#[available_gas(3000000000)]
#[should_panic(expected: ('TICK_SPACING_ONE_ONLY', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED'))]
fn test_before_initialize_pool_tick_spacing_must_be_one() {
    let core = deploy_core();
    let limit_orders = deploy_limit_orders(core);
    let (token0, token1) = deploy_two_mock_tokens();

    core
        .initialize_pool(
            PoolKey {
                token0: token0.contract_address,
                token1: token1.contract_address,
                fee: 0,
                tick_spacing: 2,
                extension: limit_orders.contract_address,
            },
            Zeroable::zero()
        );
}
#[test]
#[available_gas(3000000000)]
fn test_before_initialize_pool_sets_call_points() {
    let core = deploy_core();
    let limit_orders = deploy_limit_orders(core);
    let (token0, token1) = deploy_two_mock_tokens();

    let key = PoolKey {
        token0: token0.contract_address,
        token1: token1.contract_address,
        fee: 0,
        tick_spacing: 1,
        extension: limit_orders.contract_address,
    };
    core.initialize_pool(key, i129 { mag: 12345, sign: true });

    let price = core.get_pool_price(key);
    assert(
        price.call_points == CallPoints {
            after_initialize_pool: false,
            before_swap: false,
            after_swap: true,
            before_update_position: true,
            after_update_position: false,
        },
        'call_points'
    );
}

#[test]
#[available_gas(3000000000)]
fn test_place_order() {
    let (core, lo, pk) = setup_pool_with_extension(Zeroable::zero());

    let t0 = IMockERC20Dispatcher { contract_address: pk.token0 };
    t0.increase_balance(lo.contract_address, 100);
    let id = lo
        .place_order(
            sell_token: pk.token0, buy_token: pk.token1, tick: i129 { mag: 2, sign: false }
        );
    assert(id == 1, 'id');

    let oi = lo.get_order_info(id);
    assert(oi.owner == get_contract_address(), 'owner');
    assert(oi.liquidity == 200000350, 'liquidity');

    let position = core
        .get_position(
            pk,
            PositionKey {
                salt: 0, owner: lo.contract_address, bounds: Bounds {
                    lower: i129 { mag: 2, sign: false }, upper: i129 { mag: 3, sign: false }
                },
            }
        );
    assert(position.liquidity == 200000350, 'position created');
}
