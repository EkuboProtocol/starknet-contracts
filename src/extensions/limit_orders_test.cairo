use debug::PrintTrait;
use ekubo::enumerable_owned_nft::{
    IEnumerableOwnedNFTDispatcher, IEnumerableOwnedNFTDispatcherTrait
};
use ekubo::extensions::limit_orders::{
    ILimitOrdersDispatcher, ILimitOrdersDispatcherTrait, OrderKey, OrderState
};
use ekubo::interfaces::core::{ICoreDispatcherTrait, ICoreDispatcher, SwapParameters};
use ekubo::interfaces::erc721::{IERC721Dispatcher, IERC721DispatcherTrait};
use ekubo::interfaces::positions::{IPositionsDispatcher, IPositionsDispatcherTrait};
use ekubo::math::liquidity::{liquidity_delta_to_amount_delta};
use ekubo::math::ticks::{tick_to_sqrt_ratio};
use ekubo::simple_swapper::{ISimpleSwapperDispatcherTrait};
use ekubo::tests::helper::{
    deploy_core, deploy_positions, deploy_limit_orders, deploy_two_mock_tokens, swap_inner,
    deploy_locker, deploy_simple_swapper
};
use ekubo::tests::mocks::mock_erc20::{IMockERC20Dispatcher, IMockERC20DispatcherTrait};
use ekubo::types::bounds::{Bounds};
use ekubo::types::call_points::{CallPoints};
use ekubo::types::i129::{i129};
use ekubo::types::keys::{PoolKey, PositionKey};
use ekubo::types::keys_test::{check_hashes_differ};
use option::{OptionTrait};
use starknet::testing::{set_contract_address, set_block_timestamp};
use starknet::{get_contract_address, get_block_timestamp, contract_address_const};
use traits::{TryInto, Into};
use zeroable::{Zeroable};

fn setup_pool_with_extension() -> (ICoreDispatcher, ILimitOrdersDispatcher, PoolKey) {
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

    (core, ILimitOrdersDispatcher { contract_address: limit_orders.contract_address }, key)
}

#[test]
fn test_order_key_hash() {
    let base: OrderKey = OrderKey {
        sell_token: Zeroable::zero(), buy_token: Zeroable::zero(), tick: Zeroable::zero(),
    };

    let mut other_sell = base;
    other_sell.sell_token = contract_address_const::<1>();

    let mut other_buy = base;
    other_buy.buy_token = contract_address_const::<1>();

    let mut other_tick = base;
    other_tick.tick = i129 { mag: 1, sign: false };

    check_hashes_differ(base, other_sell);
    check_hashes_differ(base, other_buy);
    check_hashes_differ(base, other_tick);

    check_hashes_differ(other_sell, other_buy);
    check_hashes_differ(other_sell, other_tick);

    check_hashes_differ(other_buy, other_tick);
}

#[test]
#[available_gas(3000000000)]
#[should_panic(expected: ('ONLY_FROM_PLACE_ORDER', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED'))]
fn test_before_initialize_pool_not_from_extension() {
    let core = deploy_core();
    let limit_orders = deploy_limit_orders(core);
    let (token0, token1) = deploy_two_mock_tokens();

    core
        .initialize_pool(
            PoolKey {
                token0: token0.contract_address,
                token1: token1.contract_address,
                fee: 0,
                tick_spacing: 1,
                extension: limit_orders.contract_address,
            },
            Zeroable::zero()
        );
}

#[test]
#[available_gas(3000000000)]
fn test_place_order_sell_token0_initializes_pool_above_tick() {
    let (core, lo, pk) = setup_pool_with_extension();
    assert(core.get_pool_price(pk).sqrt_ratio.is_zero(), 'not initialized');
    let t0 = IMockERC20Dispatcher { contract_address: pk.token0 };
    t0.increase_balance(lo.contract_address, 100);
    let order_key = OrderKey {
        sell_token: pk.token0, buy_token: pk.token1, tick: Zeroable::zero()
    };
    lo.place_order(order_key, 100);
    let price = core.get_pool_price(pk);
    assert(price.tick.is_zero() & price.sqrt_ratio.is_non_zero(), 'initialized');
}

#[test]
#[available_gas(3000000000)]
fn test_place_order_sell_token1_initializes_pool_above_tick() {
    let (core, lo, pk) = setup_pool_with_extension();
    assert(core.get_pool_price(pk).sqrt_ratio.is_zero(), 'not initialized');
    let t1 = IMockERC20Dispatcher { contract_address: pk.token1 };
    t1.increase_balance(lo.contract_address, 100);
    let order_key = OrderKey {
        sell_token: pk.token1, buy_token: pk.token0, tick: i129 { mag: 1, sign: false }
    };
    lo.place_order(order_key, 100);
    let price = core.get_pool_price(pk);
    assert(
        (price.tick == i129 { mag: 2, sign: false }) & price.sqrt_ratio.is_non_zero(), 'initialized'
    );
}

#[test]
#[available_gas(3000000000)]
fn test_place_order_token0_creates_position_at_tick() {
    let (core, lo, pk) = setup_pool_with_extension();

    let t0 = IMockERC20Dispatcher { contract_address: pk.token0 };
    t0.increase_balance(lo.contract_address, 100);
    let order_key = OrderKey {
        sell_token: pk.token0, buy_token: pk.token1, tick: i129 { mag: 2, sign: false }
    };
    let id = lo.place_order(order_key, 100);
    assert(id == 1, 'id');

    t0.increase_balance(lo.contract_address, 200);
    let id_2 = lo.place_order(order_key, 200);
    assert(id_2 == 2, 'id_2');

    let oi_1 = lo.get_order_state(order_key, id);
    let nft = IERC721Dispatcher { contract_address: lo.get_nft_address() };
    assert(nft.ownerOf(id.into()) == get_contract_address(), 'owner of 1');

    let oi_2 = lo.get_order_state(order_key, id_2);
    assert(nft.ownerOf(id_2.into()) == get_contract_address(), 'owner of 2');

    let position = core
        .get_position(
            pk,
            PositionKey {
                salt: 0,
                owner: lo.contract_address,
                bounds: Bounds {
                    lower: i129 { mag: 2, sign: false }, upper: i129 { mag: 3, sign: false }
                },
            }
        );
    assert(position.liquidity == (oi_1.liquidity + oi_2.liquidity), 'position liquidity sum');
}

#[test]
#[available_gas(3000000000)]
fn test_place_order_token1_creates_position_at_tick() {
    let (core, lo, pk) = setup_pool_with_extension();

    let t1 = IMockERC20Dispatcher { contract_address: pk.token1 };
    t1.increase_balance(lo.contract_address, 100);
    let order_key = OrderKey {
        sell_token: pk.token1, buy_token: pk.token0, tick: i129 { mag: 1, sign: false }
    };
    let id = lo.place_order(order_key, 100);
    assert(id == 1, 'id');

    t1.increase_balance(lo.contract_address, 200);
    let id_2 = lo.place_order(order_key, 200);
    assert(id_2 == 2, 'id_2');

    let oi_1 = lo.get_order_state(order_key, id);
    let nft = IERC721Dispatcher { contract_address: lo.get_nft_address() };
    assert(nft.ownerOf(id.into()) == get_contract_address(), 'owner of 1');

    let oi_2 = lo.get_order_state(order_key, id_2);
    assert(nft.ownerOf(id_2.into()) == get_contract_address(), 'owner of 2');

    let position = core
        .get_position(
            pk,
            PositionKey {
                salt: 0,
                owner: lo.contract_address,
                bounds: Bounds {
                    lower: i129 { mag: 1, sign: false }, upper: i129 { mag: 2, sign: false }
                },
            }
        );
    assert(position.liquidity == (oi_1.liquidity + oi_2.liquidity), 'liquidity sum');
}

#[test]
#[available_gas(3000000000)]
fn test_limit_order_is_pulled_after_swap_token0_input() {
    let (core, lo, pk) = setup_pool_with_extension();
    let simple_swapper = deploy_simple_swapper(core);

    let t0 = IMockERC20Dispatcher { contract_address: pk.token0 };
    let t1 = IMockERC20Dispatcher { contract_address: pk.token1 };
    t1.increase_balance(lo.contract_address, 100);
    let order_key = OrderKey {
        sell_token: pk.token1, buy_token: pk.token0, tick: i129 { mag: 1, sign: false }
    };
    lo.place_order(order_key, 100);

    t0.increase_balance(simple_swapper.contract_address, 200);
    let delta = simple_swapper
        .swap(
            pool_key: pk,
            swap_params: SwapParameters {
                amount: i129 { mag: 200, sign: false },
                is_token1: false,
                sqrt_ratio_limit: tick_to_sqrt_ratio(i129 { mag: 0, sign: false }),
                skip_ahead: 0,
            },
            recipient: contract_address_const::<1>(),
            calculated_amount_threshold: 0
        );

    let position = core
        .get_position(
            pk,
            PositionKey {
                salt: 0,
                owner: lo.contract_address,
                bounds: Bounds {
                    lower: i129 { mag: 1, sign: false }, upper: i129 { mag: 2, sign: false }
                },
            }
        );

    assert(position.liquidity.is_zero(), 'position liquidity pulled');
}

#[test]
#[available_gas(3000000000)]
fn test_limit_order_is_pulled_after_swap_token1_input() {
    let (core, lo, pk) = setup_pool_with_extension();
    let simple_swapper = deploy_simple_swapper(core);

    let t0 = IMockERC20Dispatcher { contract_address: pk.token0 };
    let t1 = IMockERC20Dispatcher { contract_address: pk.token1 };
    t0.increase_balance(lo.contract_address, 100);
    let order_key = OrderKey {
        sell_token: pk.token0, buy_token: pk.token1, tick: Zeroable::zero()
    };
    lo.place_order(order_key, 100);

    t1.increase_balance(simple_swapper.contract_address, 200);
    let delta = simple_swapper
        .swap(
            pool_key: pk,
            swap_params: SwapParameters {
                amount: i129 { mag: 200, sign: false },
                is_token1: true,
                sqrt_ratio_limit: tick_to_sqrt_ratio(i129 { mag: 2, sign: false }),
                skip_ahead: 0,
            },
            recipient: contract_address_const::<1>(),
            calculated_amount_threshold: 0
        );

    delta.print();

    let position = core
        .get_position(
            pk,
            PositionKey {
                salt: 0,
                owner: lo.contract_address,
                bounds: Bounds { lower: Zeroable::zero(), upper: i129 { mag: 1, sign: false } },
            }
        );

    assert(position.liquidity.is_zero(), 'position liquidity pulled');
}

#[test]
#[available_gas(3000000000)]
#[should_panic(expected: ('TICK_EVEN_ODD', 'ENTRYPOINT_FAILED'))]
fn test_place_order_fails_odd_tick_sell_token0() {
    let (core, lo, pk) = setup_pool_with_extension();

    lo
        .place_order(
            OrderKey {
                sell_token: pk.token0, buy_token: pk.token1, tick: i129 { mag: 1, sign: false }
            },
            0
        );
}

#[test]
#[available_gas(3000000000)]
#[should_panic(expected: ('TICK_EVEN_ODD', 'ENTRYPOINT_FAILED'))]
fn test_place_order_fails_even_tick_sell_token1() {
    let (core, lo, pk) = setup_pool_with_extension();

    lo
        .place_order(
            OrderKey {
                sell_token: pk.token1, buy_token: pk.token0, tick: i129 { mag: 0, sign: false }
            },
            0
        );
}

#[test]
#[available_gas(3000000000)]
#[should_panic(expected: ('SELL_AMOUNT_TOO_SMALL', 'ENTRYPOINT_FAILED'))]
fn test_place_order_fails_zero_token0() {
    let (core, lo, pk) = setup_pool_with_extension();

    lo
        .place_order(
            OrderKey { sell_token: pk.token0, buy_token: pk.token1, tick: Zeroable::zero() }, 0
        );
}

#[test]
#[available_gas(3000000000)]
#[should_panic(expected: ('SELL_AMOUNT_TOO_SMALL', 'ENTRYPOINT_FAILED'))]
fn test_place_order_fails_zero_token1() {
    let (core, lo, pk) = setup_pool_with_extension();

    lo
        .place_order(
            OrderKey {
                sell_token: pk.token1, buy_token: pk.token0, tick: i129 { mag: 1, sign: false }
            },
            0
        );
}
