use array::{Array, ArrayTrait, SpanTrait};

use core::debug::PrintTrait;
use ekubo::interfaces::core::{ICoreDispatcherTrait, SwapParameters};
use ekubo::interfaces::positions::{IPositionsDispatcherTrait};
use ekubo::math::ticks::{min_sqrt_ratio, max_sqrt_ratio, min_tick, max_tick};
use ekubo::simple_swapper::{ISimpleSwapperDispatcher, ISimpleSwapperDispatcherTrait};
use ekubo::tests::helper::{
    deploy_core, deploy_simple_swapper, deploy_two_mock_tokens, deploy_positions, deploy_mock_token
};
use ekubo::tests::mocks::mock_erc20::{IMockERC20DispatcherTrait};
use ekubo::types::bounds::{Bounds};
use ekubo::types::i129::{i129};
use ekubo::types::keys::{PoolKey};
use starknet::testing::{set_contract_address};
use starknet::{ContractAddress, contract_address_const};
use core::zeroable::{Zeroable};

fn recipient() -> ContractAddress {
    contract_address_const::<0x12345678>()
}

#[test]
#[available_gas(300000000)]
#[should_panic(
    expected: (
        'NOT_INITIALIZED',
        'ENTRYPOINT_FAILED',
        'ENTRYPOINT_FAILED',
        'ENTRYPOINT_FAILED',
        'ENTRYPOINT_FAILED'
    )
)]
fn test_simple_swapper_swap_not_initialized_pool() {
    let core = deploy_core();
    let simple_swapper = deploy_simple_swapper(core);
    let (token0, token1) = deploy_two_mock_tokens();

    let pool_key = PoolKey {
        token0: token0.contract_address,
        token1: token1.contract_address,
        fee: 0xc49ba5e353f7ced916872b020c49ba, // 30 bips as a 0.128 number
        tick_spacing: 5982, // 60 bips tick spacing
        extension: Zeroable::zero(),
    };

    simple_swapper
        .swap(
            pool_key,
            SwapParameters {
                amount: i129 { mag: 100, sign: false },
                is_token1: false,
                sqrt_ratio_limit: min_sqrt_ratio(),
                skip_ahead: 0,
            },
            recipient(),
            0,
        );
}

#[test]
#[available_gas(300000000)]
fn test_simple_swapper_swap_initialized_pool_no_liquidity_token0_in() {
    let core = deploy_core();
    let simple_swapper = deploy_simple_swapper(core);
    let (token0, token1) = deploy_two_mock_tokens();

    let pool_key = PoolKey {
        token0: token0.contract_address,
        token1: token1.contract_address,
        fee: 0xc49ba5e353f7ced916872b020c49ba, // 30 bips as a 0.128 number
        tick_spacing: 5982, // 60 bips tick spacing
        extension: Zeroable::zero(),
    };

    core.initialize_pool(pool_key, Zeroable::zero());

    let delta = simple_swapper
        .swap(
            pool_key,
            SwapParameters {
                amount: i129 { mag: 100, sign: false },
                is_token1: false,
                sqrt_ratio_limit: min_sqrt_ratio(),
                skip_ahead: 0
            },
            recipient(),
            0,
        );

    assert(delta.amount0.is_zero(), 'no input');
    assert(delta.amount1.is_zero(), 'no output');

    let pp = core.get_pool_price(pool_key);
    assert(pp.sqrt_ratio == min_sqrt_ratio(), 'traded to end');
    assert(pp.tick == (min_tick() - i129 { mag: 1, sign: false }), 'traded to end');
}

#[test]
#[available_gas(300000000)]
fn test_simple_swapper_swap_initialized_pool_no_liquidity_token1_in() {
    let core = deploy_core();
    let simple_swapper = deploy_simple_swapper(core);
    let (token0, token1) = deploy_two_mock_tokens();

    let pool_key = PoolKey {
        token0: token0.contract_address,
        token1: token1.contract_address,
        fee: 0xc49ba5e353f7ced916872b020c49ba, // 30 bips as a 0.128 number
        tick_spacing: 5982, // 60 bips tick spacing
        extension: Zeroable::zero(),
    };

    core.initialize_pool(pool_key, Zeroable::zero());

    let delta = simple_swapper
        .swap(
            pool_key,
            SwapParameters {
                amount: i129 { mag: 100, sign: false },
                is_token1: true,
                sqrt_ratio_limit: max_sqrt_ratio(),
                skip_ahead: 0
            },
            recipient(),
            0,
        );

    assert(delta.amount0.is_zero(), 'no input');
    assert(delta.amount1.is_zero(), 'no output');

    let pp = core.get_pool_price(pool_key);

    assert(pp.sqrt_ratio == max_sqrt_ratio(), 'traded to end');
    assert(pp.tick == max_tick(), 'traded to end');
}


fn setup_for_swapping() -> (ISimpleSwapperDispatcher, PoolKey, PoolKey) {
    let core = deploy_core();
    let simple_swapper = deploy_simple_swapper(core);
    let positions = deploy_positions(core);
    let (token0, token1) = deploy_two_mock_tokens();
    let token2 = deploy_mock_token();

    let pool_key_a = PoolKey {
        token0: token0.contract_address,
        token1: token1.contract_address,
        fee: 0xc49ba5e353f7ced916872b020c49ba, // 30 bips as a 0.128 number
        tick_spacing: 5982, // 60 bips tick spacing
        extension: Zeroable::zero(),
    };

    let pool_key_b = PoolKey {
        token0: token1.contract_address,
        token1: token2.contract_address,
        fee: 0xc49ba5e353f7ced916872b020c49ba, // 30 bips as a 0.128 number
        tick_spacing: 5982, // 60 bips tick spacing
        extension: Zeroable::zero(),
    };

    let bounds = Bounds {
        lower: i129 { mag: 5982, sign: true }, upper: i129 { mag: 5982, sign: false }
    };

    core.initialize_pool(pool_key_a, Zeroable::zero());
    core.initialize_pool(pool_key_b, Zeroable::zero());

    let caller = contract_address_const::<1>();
    set_contract_address(caller);

    token0.increase_balance(positions.contract_address, 10000);
    token1.increase_balance(positions.contract_address, 10000);
    let token_id_a = positions.mint(pool_key: pool_key_a, bounds: bounds);
    let deposited_liquidity_a = positions
        .deposit_last(pool_key: pool_key_a, bounds: bounds, min_liquidity: 0,);

    token1.increase_balance(positions.contract_address, 10000);
    token2.increase_balance(positions.contract_address, 10000);
    let token_id_b = positions.mint(pool_key: pool_key_b, bounds: bounds);
    let deposited_liquidity_b = positions
        .deposit_last(pool_key: pool_key_b, bounds: bounds, min_liquidity: 0,);

    (simple_swapper, pool_key_a, pool_key_b)
}
