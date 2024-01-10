use core::num::traits::{Zero};
use core::option::{OptionTrait};
use core::traits::{TryInto, Into};
use ekubo::components::owner::owner;
use ekubo::extensions::limit_orders::{
    LimitOrders, ILimitOrdersDispatcher, ILimitOrdersDispatcherTrait, OrderKey, OrderState,
    PoolState, GetOrderInfoRequest, GetOrderInfoResult, LimitOrders::{LIMIT_ORDER_TICK_SPACING}
};
use ekubo::interfaces::core::{ICoreDispatcherTrait, ICoreDispatcher, SwapParameters};
use ekubo::interfaces::erc721::{IERC721Dispatcher, IERC721DispatcherTrait};
use ekubo::interfaces::positions::{IPositionsDispatcher, IPositionsDispatcherTrait};
use ekubo::interfaces::upgradeable::{IUpgradeableDispatcher, IUpgradeableDispatcherTrait};
use ekubo::math::liquidity::{liquidity_delta_to_amount_delta};
use ekubo::math::ticks::{tick_to_sqrt_ratio};
use ekubo::mock_erc20::{IMockERC20Dispatcher, IMockERC20DispatcherTrait};
use ekubo::owned_nft::{IOwnedNFTDispatcher, IOwnedNFTDispatcherTrait};
use ekubo::router::{IRouterDispatcher, IRouterDispatcherTrait, TokenAmount, RouteNode};
use ekubo::tests::helper::{
    deploy_core, deploy_positions, deploy_limit_orders, deploy_two_mock_tokens, swap_inner,
    deploy_locker, deploy_router
};
use ekubo::tests::store_packing_test::{assert_round_trip};
use ekubo::types::bounds::{Bounds};
use ekubo::types::call_points::{CallPoints};
use ekubo::types::i129::{i129};
use ekubo::types::keys::{PoolKey, PositionKey};
use ekubo::types::keys_test::{check_hashes_differ};
use starknet::testing::{set_contract_address, set_block_timestamp, pop_log};
use starknet::{get_contract_address, get_block_timestamp, contract_address_const, ClassHash};

fn setup_pool_with_extension() -> (ICoreDispatcher, ILimitOrdersDispatcher, PoolKey) {
    let core = deploy_core();
    let limit_orders = deploy_limit_orders(core);
    let (token0, token1) = deploy_two_mock_tokens();

    let key = PoolKey {
        token0: token0.contract_address,
        token1: token1.contract_address,
        fee: 0,
        tick_spacing: LIMIT_ORDER_TICK_SPACING,
        extension: limit_orders.contract_address,
    };

    (core, ILimitOrdersDispatcher { contract_address: limit_orders.contract_address }, key)
}

#[test]
fn test_round_trip_order_state() {
    assert_round_trip(
        OrderState { liquidity: Zero::zero(), ticks_crossed_at_create: Zero::zero() }
    );

    assert_round_trip(OrderState { liquidity: 0, ticks_crossed_at_create: 1 });
    assert_round_trip(OrderState { liquidity: 1, ticks_crossed_at_create: 0 });
    assert_round_trip(OrderState { liquidity: 1, ticks_crossed_at_create: 1 });

    assert_round_trip(OrderState { liquidity: 1, ticks_crossed_at_create: 2 });
    assert_round_trip(OrderState { liquidity: 2, ticks_crossed_at_create: 1 });
    assert_round_trip(OrderState { liquidity: 0, ticks_crossed_at_create: 2 });
    assert_round_trip(OrderState { liquidity: 2, ticks_crossed_at_create: 0 });
    assert_round_trip(OrderState { liquidity: 2, ticks_crossed_at_create: 2 });
    assert_round_trip(
        OrderState {
            liquidity: 0xffffffffffffffffffffffffffffffff,
            ticks_crossed_at_create: 0xffffffffffffffff
        }
    );
    assert_round_trip(
        OrderState {
            liquidity: 0xffffffffffffffffffffffffffffffff - 1,
            ticks_crossed_at_create: 0xffffffffffffffff
        }
    );
    assert_round_trip(
        OrderState {
            liquidity: 0xffffffffffffffffffffffffffffffff,
            ticks_crossed_at_create: 0xffffffffffffffff - 1
        }
    );
}

#[test]
fn test_round_trip_pool_state() {
    assert_round_trip(PoolState { ticks_crossed: 0, last_tick: Zero::zero() });
    assert_round_trip(PoolState { ticks_crossed: 1, last_tick: Zero::zero() });
    assert_round_trip(PoolState { ticks_crossed: 0, last_tick: i129 { mag: 1, sign: false } });
    assert_round_trip(PoolState { ticks_crossed: 1, last_tick: i129 { mag: 1, sign: true } });
    assert_round_trip(PoolState { ticks_crossed: 123, last_tick: i129 { mag: 0, sign: true } });

    assert_round_trip(
        PoolState {
            ticks_crossed: 0xffffffffffffffff,
            last_tick: i129 { mag: 0x7fffffffffffffffffffffffffffffff, sign: true }
        }
    );

    assert_round_trip(
        PoolState {
            ticks_crossed: 0xffffffffffffffff,
            last_tick: i129 { mag: 0x7fffffffffffffffffffffffffffffff, sign: false }
        }
    );

    assert_round_trip(
        PoolState {
            ticks_crossed: 0xffffffffffffffff,
            last_tick: i129 { mag: 0x7fffffffffffffffffffffffffffffff, sign: true }
        }
    );

    assert_round_trip(
        PoolState {
            ticks_crossed: 0xffffffffffffffff,
            last_tick: i129 { mag: 0xffffffffffffffffffffffffffffffff, sign: false }
        }
    );
    assert_round_trip(
        PoolState {
            ticks_crossed: 0xffffffffffffffff,
            last_tick: i129 { mag: 0xffffffffffffffffffffffffffffffff, sign: true }
        }
    );

    assert_round_trip(
        PoolState {
            ticks_crossed: 0,
            last_tick: i129 { mag: 0xffffffffffffffffffffffffffffffff, sign: false }
        }
    );
    assert_round_trip(
        PoolState {
            ticks_crossed: 0,
            last_tick: i129 { mag: 0xffffffffffffffffffffffffffffffff, sign: true }
        }
    );
}

#[test]
fn test_order_key_hash() {
    let base: OrderKey = OrderKey {
        token0: Zero::zero(), token1: Zero::zero(), tick: Zero::zero(),
    };

    let mut other_token0 = base;
    other_token0.token0 = contract_address_const::<1>();

    let mut other_token1 = base;
    other_token1.token1 = contract_address_const::<1>();

    let mut other_tick = base;
    other_tick.tick = i129 { mag: 1, sign: false };

    check_hashes_differ(base, other_token0);
    check_hashes_differ(base, other_token1);
    check_hashes_differ(base, other_tick);

    check_hashes_differ(other_token0, other_token1);
    check_hashes_differ(other_token0, other_tick);

    check_hashes_differ(other_token1, other_tick);
}

#[test]
fn test_replace_class_hash_can_be_called_by_owner() {
    let core = deploy_core();
    let limit_orders = deploy_limit_orders(core);

    let class_hash: ClassHash = LimitOrders::TEST_CLASS_HASH.try_into().unwrap();

    set_contract_address(owner());
    IUpgradeableDispatcher { contract_address: limit_orders.contract_address }
        .replace_class_hash(class_hash);

    let event: ekubo::components::upgradeable::Upgradeable::ClassHashReplaced = pop_log(
        limit_orders.contract_address
    )
        .unwrap();
    assert(event.new_class_hash == class_hash, 'event.class_hash');
}

#[test]
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
                tick_spacing: LIMIT_ORDER_TICK_SPACING,
                extension: limit_orders.contract_address,
            },
            Zero::zero()
        );
}

#[test]
fn test_place_order_sell_token0_initializes_pool_above_tick() {
    let (core, lo, pk) = setup_pool_with_extension();
    assert(core.get_pool_price(pk).sqrt_ratio.is_zero(), 'not initialized');
    let t0 = IMockERC20Dispatcher { contract_address: pk.token0 };
    t0.increase_balance(lo.contract_address, 100);
    let order_key = OrderKey { token0: pk.token0, token1: pk.token1, tick: Zero::zero() };
    lo.place_order(order_key, 100);
    let price = core.get_pool_price(pk);
    assert(price.tick.is_zero() & price.sqrt_ratio.is_non_zero(), 'initialized');
}

#[test]
fn test_place_order_sell_token1_initializes_pool_above_tick() {
    let (core, lo, pk) = setup_pool_with_extension();
    assert(core.get_pool_price(pk).sqrt_ratio.is_zero(), 'not initialized');
    let t1 = IMockERC20Dispatcher { contract_address: pk.token1 };
    t1.increase_balance(lo.contract_address, 100);
    let order_key = OrderKey {
        token0: pk.token0,
        token1: pk.token1,
        tick: i129 { mag: LIMIT_ORDER_TICK_SPACING, sign: false }
    };
    lo.place_order(order_key, 100);
    let price = core.get_pool_price(pk);
    assert(
        (price.tick == i129 { mag: 2 * LIMIT_ORDER_TICK_SPACING, sign: false })
            & price.sqrt_ratio.is_non_zero(),
        'initialized'
    );
}

#[test]
fn test_place_order_on_both_sides_token1_first() {
    let (core, lo, pk) = setup_pool_with_extension();
    assert(core.get_pool_price(pk).sqrt_ratio.is_zero(), 'not initialized');
    let t1 = IMockERC20Dispatcher { contract_address: pk.token1 };
    let t0 = IMockERC20Dispatcher { contract_address: pk.token0 };

    let ok1 = OrderKey {
        token0: pk.token0,
        token1: pk.token1,
        tick: i129 { mag: LIMIT_ORDER_TICK_SPACING, sign: false }
    };
    let ok2 = OrderKey {
        token0: pk.token0,
        token1: pk.token1,
        tick: i129 { mag: 2 * LIMIT_ORDER_TICK_SPACING, sign: false }
    };

    t1.increase_balance(lo.contract_address, 100);
    let id1 = lo.place_order(ok1, 100);
    t0.increase_balance(lo.contract_address, 200);
    let id2 = lo.place_order(ok2, 200);

    let mut results = lo
        .get_order_info(
            array![
                GetOrderInfoRequest { order_key: ok1, id: id1 },
                GetOrderInfoRequest { order_key: ok2, id: id2 }
            ]
        );

    let status1 = results.pop_front().unwrap();
    let status2 = results.pop_front().unwrap();
    assert(results.is_empty(), 'results empty');
    assert(!status1.executed, '1.executed');
    assert(status1.amount0 == 0, '1.amount0');
    assert(status1.amount1 == 99, '1.amount1');

    assert(!status2.executed, '2.executed');
    assert(status2.amount0 == 199, '2.amount0');
    assert(status2.amount1 == 0, '2.amount1');
}

#[test]
fn test_place_order_on_both_sides_token0_first() {
    let (core, lo, pk) = setup_pool_with_extension();
    assert(core.get_pool_price(pk).sqrt_ratio.is_zero(), 'not initialized');

    let t1 = IMockERC20Dispatcher { contract_address: pk.token1 };
    let t0 = IMockERC20Dispatcher { contract_address: pk.token0 };

    let ok1 = OrderKey {
        token0: pk.token0,
        token1: pk.token1,
        tick: i129 { mag: 2 * LIMIT_ORDER_TICK_SPACING, sign: false }
    };
    let ok2 = OrderKey {
        token0: pk.token0,
        token1: pk.token1,
        tick: i129 { mag: LIMIT_ORDER_TICK_SPACING, sign: false }
    };

    t0.increase_balance(lo.contract_address, 100);
    let id1 = lo.place_order(ok1, 100);
    t1.increase_balance(lo.contract_address, 200);
    let id2 = lo.place_order(ok2, 200);

    let mut results = lo
        .get_order_info(
            array![
                GetOrderInfoRequest { order_key: ok1, id: id1 },
                GetOrderInfoRequest { order_key: ok2, id: id2 }
            ]
        );

    let status1 = results.pop_front().unwrap();
    let status2 = results.pop_front().unwrap();
    assert(results.is_empty(), 'results empty');
    assert(!status1.executed, '1.executed');
    assert(status1.amount0 == 99, '1.amount0');
    assert(status1.amount1 == 0, '1.amount1');

    assert(!status2.executed, '2.executed');
    assert(status2.amount0 == 0, '2.amount0');
    assert(status2.amount1 == 199, '2.amount1');
}

#[test]
fn test_place_order_token0_creates_position_at_tick() {
    let (core, lo, pk) = setup_pool_with_extension();

    let t0 = IMockERC20Dispatcher { contract_address: pk.token0 };
    t0.increase_balance(lo.contract_address, 100);
    let order_key = OrderKey {
        token0: pk.token0,
        token1: pk.token1,
        tick: i129 { mag: 2 * LIMIT_ORDER_TICK_SPACING, sign: false }
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
                    lower: i129 { mag: 2 * LIMIT_ORDER_TICK_SPACING, sign: false },
                    upper: i129 { mag: 3 * LIMIT_ORDER_TICK_SPACING, sign: false }
                },
            }
        );
    assert(position.liquidity == (oi_1.liquidity + oi_2.liquidity), 'position liquidity sum');
}

#[test]
fn test_place_order_token1_creates_position_at_tick() {
    let (core, lo, pk) = setup_pool_with_extension();

    let t1 = IMockERC20Dispatcher { contract_address: pk.token1 };
    t1.increase_balance(lo.contract_address, 100);
    let order_key = OrderKey {
        token0: pk.token0,
        token1: pk.token1,
        tick: i129 { mag: LIMIT_ORDER_TICK_SPACING, sign: false }
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
                    lower: i129 { mag: LIMIT_ORDER_TICK_SPACING, sign: false },
                    upper: i129 { mag: 2 * LIMIT_ORDER_TICK_SPACING, sign: false }
                },
            }
        );
    assert(position.liquidity == (oi_1.liquidity + oi_2.liquidity), 'liquidity sum');
}

#[test]
fn test_limit_order_combined_complex_scenario_swap_token0_input() {
    let (core, lo, pk) = setup_pool_with_extension();
    let router = deploy_router(core);

    let t0 = IMockERC20Dispatcher { contract_address: pk.token0 };
    let t1 = IMockERC20Dispatcher { contract_address: pk.token1 };
    t1.increase_balance(lo.contract_address, 1000);
    let ok_1 = OrderKey {
        token0: pk.token0,
        token1: pk.token1,
        tick: i129 { mag: LIMIT_ORDER_TICK_SPACING, sign: false }
    };
    let ok_3 = OrderKey {
        token0: pk.token0,
        token1: pk.token1,
        tick: i129 { mag: LIMIT_ORDER_TICK_SPACING, sign: true }
    };
    let ok_5 = OrderKey {
        token0: pk.token0,
        token1: pk.token1,
        tick: i129 { mag: 3 * LIMIT_ORDER_TICK_SPACING, sign: true }
    };
    let id_1 = lo.place_order(ok_1, 100);
    let id_2 = lo.place_order(ok_3, 50);
    let id_3 = lo.place_order(ok_3, 250);
    let id_4 = lo.place_order(ok_5, 100);

    t0.increase_balance(router.contract_address, 2000);
    let delta = router
        .swap(
            node: RouteNode {
                pool_key: pk,
                // halfway between -3 and -2
                sqrt_ratio_limit: (tick_to_sqrt_ratio(
                    i129 { mag: 3 * LIMIT_ORDER_TICK_SPACING, sign: true }
                )
                    * 10000005)
                    / 10000000,
                skip_ahead: 0,
            },
            token_amount: TokenAmount { token: pk.token0, amount: i129 { mag: 2000, sign: false } },
        );

    lo.close_order(ok_1, id_1, recipient: contract_address_const::<1>());
    lo.close_order(ok_3, id_2, recipient: contract_address_const::<1>());
    lo.close_order(ok_3, id_3, recipient: contract_address_const::<1>());
    lo.close_order(ok_5, id_4, recipient: contract_address_const::<1>());
}

#[test]
fn test_limit_order_combined_complex_scenario_swap_token1_input() {
    let (core, lo, pk) = setup_pool_with_extension();
    let router = deploy_router(core);

    let t0 = IMockERC20Dispatcher { contract_address: pk.token0 };
    let t1 = IMockERC20Dispatcher { contract_address: pk.token1 };
    t0.increase_balance(lo.contract_address, 1000);
    let ok_1 = OrderKey {
        token0: pk.token0,
        token1: pk.token1,
        tick: i129 { mag: 2 * LIMIT_ORDER_TICK_SPACING, sign: true }
    };
    let ok_3 = OrderKey {
        token0: pk.token0, token1: pk.token1, tick: i129 { mag: 0, sign: false }
    };
    let ok_5 = OrderKey {
        token0: pk.token0,
        token1: pk.token1,
        tick: i129 { mag: 2 * LIMIT_ORDER_TICK_SPACING, sign: false }
    };
    let id_1 = lo.place_order(ok_1, 100);
    let id_2 = lo.place_order(ok_3, 50);
    let id_3 = lo.place_order(ok_3, 250);
    let id_4 = lo.place_order(ok_5, 100);

    t1.increase_balance(router.contract_address, 2000);
    let delta = router
        .swap(
            node: RouteNode {
                pool_key: pk,
                // halfway between -3 and -2
                sqrt_ratio_limit: (tick_to_sqrt_ratio(
                    i129 { mag: LIMIT_ORDER_TICK_SPACING, sign: false }
                )
                    * 10000005)
                    / 10000000,
                skip_ahead: 0,
            },
            token_amount: TokenAmount { token: pk.token1, amount: i129 { mag: 2000, sign: false } },
        );

    lo.close_order(ok_1, id_1, recipient: contract_address_const::<1>());
    lo.close_order(ok_3, id_2, recipient: contract_address_const::<1>());
    lo.close_order(ok_3, id_3, recipient: contract_address_const::<1>());
    lo.close_order(ok_5, id_4, recipient: contract_address_const::<1>());
}

#[test]
fn test_limit_order_is_pulled_after_swap_token0_input() {
    let (core, lo, pk) = setup_pool_with_extension();
    let router = deploy_router(core);

    let t0 = IMockERC20Dispatcher { contract_address: pk.token0 };
    let t1 = IMockERC20Dispatcher { contract_address: pk.token1 };
    t1.increase_balance(lo.contract_address, 100);
    let order_key = OrderKey {
        token0: pk.token0,
        token1: pk.token1,
        tick: i129 { mag: LIMIT_ORDER_TICK_SPACING, sign: false }
    };
    let id = lo.place_order(order_key, 100);

    let position_key = PositionKey {
        salt: 0,
        owner: lo.contract_address,
        bounds: Bounds {
            lower: i129 { mag: LIMIT_ORDER_TICK_SPACING, sign: false },
            upper: i129 { mag: 2 * LIMIT_ORDER_TICK_SPACING, sign: false }
        },
    };
    assert(
        core.get_position(pk, position_key).liquidity.is_non_zero(), 'position liquidity nonzero'
    );

    t0.increase_balance(router.contract_address, 200);
    let delta = router
        .swap(
            node: RouteNode {
                pool_key: pk,
                sqrt_ratio_limit: tick_to_sqrt_ratio(i129 { mag: 0, sign: false }),
                skip_ahead: 0,
            },
            token_amount: TokenAmount { token: pk.token0, amount: i129 { mag: 200, sign: false }, },
        );

    assert(core.get_position(pk, position_key).liquidity.is_zero(), 'position liquidity pulled');

    lo.close_order(order_key, id, recipient: contract_address_const::<1>());
}

#[test]
fn test_limit_order_is_pulled_after_swap_token1_input() {
    let (core, lo, pk) = setup_pool_with_extension();
    let router = deploy_router(core);

    let t0 = IMockERC20Dispatcher { contract_address: pk.token0 };
    let t1 = IMockERC20Dispatcher { contract_address: pk.token1 };
    t0.increase_balance(lo.contract_address, 100);
    let order_key = OrderKey { token0: pk.token0, token1: pk.token1, tick: Zero::zero() };
    let id = lo.place_order(order_key, 100);

    let position_key = PositionKey {
        salt: 0,
        owner: lo.contract_address,
        bounds: Bounds {
            lower: Zero::zero(), upper: i129 { mag: LIMIT_ORDER_TICK_SPACING, sign: false }
        },
    };
    assert(
        core.get_position(pk, position_key).liquidity.is_non_zero(), 'position liquidity nonzero'
    );

    t1.increase_balance(router.contract_address, 200);
    let delta = router
        .swap(
            node: RouteNode {
                pool_key: pk,
                sqrt_ratio_limit: tick_to_sqrt_ratio(
                    i129 { mag: 2 * LIMIT_ORDER_TICK_SPACING, sign: false }
                ),
                skip_ahead: 0,
            },
            token_amount: TokenAmount { token: pk.token1, amount: i129 { mag: 200, sign: false }, },
        );

    assert(core.get_position(pk, position_key).liquidity.is_zero(), 'position liquidity pulled');

    lo.close_order(order_key, id, recipient: contract_address_const::<1>());
}

#[test]
fn test_limit_order_is_not_pulled_after_partial_swap_token0_input() {
    let (core, lo, pk) = setup_pool_with_extension();
    let router = deploy_router(core);

    let t0 = IMockERC20Dispatcher { contract_address: pk.token0 };
    let t1 = IMockERC20Dispatcher { contract_address: pk.token1 };
    t1.increase_balance(lo.contract_address, 100);
    let order_key = OrderKey {
        token0: pk.token0,
        token1: pk.token1,
        tick: i129 { mag: LIMIT_ORDER_TICK_SPACING, sign: false }
    };
    let id = lo.place_order(order_key, 100);

    let position_key = PositionKey {
        salt: 0,
        owner: lo.contract_address,
        bounds: Bounds {
            lower: i129 { mag: LIMIT_ORDER_TICK_SPACING, sign: false },
            upper: i129 { mag: 2 * LIMIT_ORDER_TICK_SPACING, sign: false }
        },
    };
    assert(
        core.get_position(pk, position_key).liquidity.is_non_zero(), 'position liquidity nonzero'
    );

    t0.increase_balance(router.contract_address, 50);
    let delta = router
        .swap(
            node: RouteNode {
                pool_key: pk,
                sqrt_ratio_limit: tick_to_sqrt_ratio(i129 { mag: 0, sign: false }),
                skip_ahead: 0,
            },
            token_amount: TokenAmount { token: pk.token0, amount: i129 { mag: 50, sign: false }, },
        );

    assert(
        core.get_position(pk, position_key).liquidity.is_non_zero(), 'position liquidity not pulled'
    );

    lo.close_order(order_key, id, recipient: contract_address_const::<1>());

    assert(core.get_position(pk, position_key).liquidity.is_zero(), 'order closed');
}

#[test]
fn test_limit_order_is_not_pulled_after_partial_swap_token1_input() {
    let (core, lo, pk) = setup_pool_with_extension();
    let router = deploy_router(core);

    let t0 = IMockERC20Dispatcher { contract_address: pk.token0 };
    let t1 = IMockERC20Dispatcher { contract_address: pk.token1 };
    t0.increase_balance(lo.contract_address, 100);
    let order_key = OrderKey { token0: pk.token0, token1: pk.token1, tick: Zero::zero() };
    let id = lo.place_order(order_key, 100);

    let position_key = PositionKey {
        salt: 0,
        owner: lo.contract_address,
        bounds: Bounds {
            lower: Zero::zero(), upper: i129 { mag: LIMIT_ORDER_TICK_SPACING, sign: false }
        },
    };
    assert(
        core.get_position(pk, position_key).liquidity.is_non_zero(), 'position liquidity nonzero'
    );

    t1.increase_balance(router.contract_address, 200);
    let delta = router
        .swap(
            node: RouteNode {
                pool_key: pk,
                sqrt_ratio_limit: tick_to_sqrt_ratio(
                    i129 { mag: 2 * LIMIT_ORDER_TICK_SPACING, sign: false }
                ),
                skip_ahead: 0,
            },
            token_amount: TokenAmount { token: pk.token1, amount: i129 { mag: 50, sign: false }, },
        );

    assert(
        core.get_position(pk, position_key).liquidity.is_non_zero(), 'position liquidity not pulled'
    );

    lo.close_order(order_key, id, recipient: contract_address_const::<1>());

    assert(core.get_position(pk, position_key).liquidity.is_zero(), 'order closed');
}

#[test]
fn test_limit_order_is_pulled_swap_exactly_to_limit_token0_input() {
    let (core, lo, pk) = setup_pool_with_extension();
    let router = deploy_router(core);

    let t0 = IMockERC20Dispatcher { contract_address: pk.token0 };
    let t1 = IMockERC20Dispatcher { contract_address: pk.token1 };
    t1.increase_balance(lo.contract_address, 100);
    let order_key = OrderKey {
        token0: pk.token0,
        token1: pk.token1,
        tick: i129 { mag: LIMIT_ORDER_TICK_SPACING, sign: false }
    };
    let id = lo.place_order(order_key, 100);

    let position_key = PositionKey {
        salt: 0,
        owner: lo.contract_address,
        bounds: Bounds {
            lower: i129 { mag: LIMIT_ORDER_TICK_SPACING, sign: false },
            upper: i129 { mag: 2 * LIMIT_ORDER_TICK_SPACING, sign: false }
        },
    };
    assert(
        core.get_position(pk, position_key).liquidity.is_non_zero(), 'position liquidity nonzero'
    );

    t0.increase_balance(router.contract_address, 200);
    let delta = router
        .swap(
            node: RouteNode {
                pool_key: pk,
                sqrt_ratio_limit: tick_to_sqrt_ratio(
                    i129 { mag: LIMIT_ORDER_TICK_SPACING, sign: false }
                ),
                skip_ahead: 0,
            },
            token_amount: TokenAmount { token: pk.token0, amount: i129 { mag: 200, sign: false }, },
        );

    assert(
        core.get_pool_price(pk).tick == i129 { mag: LIMIT_ORDER_TICK_SPACING, sign: false }
            - i129 { mag: 1, sign: false },
        'tick after'
    );

    assert(core.get_position(pk, position_key).liquidity.is_zero(), 'position liquidity pulled');

    assert(lo.close_order(order_key, id, recipient: contract_address_const::<1>()) == (99, 0), '');
}

#[test]
fn test_limit_order_is_pulled_swap_exactly_to_limit_token1_input() {
    let (core, lo, pk) = setup_pool_with_extension();
    let router = deploy_router(core);

    let t0 = IMockERC20Dispatcher { contract_address: pk.token0 };
    let t1 = IMockERC20Dispatcher { contract_address: pk.token1 };
    t0.increase_balance(lo.contract_address, 100);
    let order_key = OrderKey { token0: pk.token0, token1: pk.token1, tick: Zero::zero() };
    let id = lo.place_order(order_key, 100);

    let position_key = PositionKey {
        salt: 0,
        owner: lo.contract_address,
        bounds: Bounds {
            lower: Zero::zero(), upper: i129 { mag: LIMIT_ORDER_TICK_SPACING, sign: false }
        },
    };
    assert(
        core.get_position(pk, position_key).liquidity.is_non_zero(), 'position liquidity nonzero'
    );

    t1.increase_balance(router.contract_address, 200);
    let delta = router
        .swap(
            node: RouteNode {
                pool_key: pk,
                sqrt_ratio_limit: tick_to_sqrt_ratio(
                    i129 { mag: LIMIT_ORDER_TICK_SPACING, sign: false }
                ),
                skip_ahead: 0,
            },
            token_amount: TokenAmount { token: pk.token1, amount: i129 { mag: 200, sign: false }, },
        );

    assert(
        core.get_pool_price(pk).tick == i129 { mag: LIMIT_ORDER_TICK_SPACING, sign: false },
        'tick after'
    );

    assert(core.get_position(pk, position_key).liquidity.is_zero(), 'position liquidity pulled');

    assert(lo.close_order(order_key, id, recipient: contract_address_const::<1>()) == (0, 100), '');
}

#[test]
fn test_limit_order_is_pulled_for_one_order_and_not_another_sell_token0() {
    let (core, lo, pk) = setup_pool_with_extension();
    let router = deploy_router(core);

    let t0 = IMockERC20Dispatcher { contract_address: pk.token0 };
    let t1 = IMockERC20Dispatcher { contract_address: pk.token1 };

    t0.increase_balance(lo.contract_address, 100);
    let ok1 = OrderKey { token0: pk.token0, token1: pk.token1, tick: Zero::zero() };
    let id1 = lo.place_order(ok1, 100);

    t1.increase_balance(router.contract_address, 200);
    assert(
        router
            .swap(
                node: RouteNode {
                    pool_key: pk,
                    sqrt_ratio_limit: tick_to_sqrt_ratio(
                        i129 { mag: LIMIT_ORDER_TICK_SPACING, sign: false }
                    ),
                    skip_ahead: 0,
                },
                token_amount: TokenAmount {
                    token: pk.token1, amount: i129 { mag: 200, sign: false },
                },
            )
            .is_non_zero(),
        'swap forward'
    );
    assert(
        router
            .swap(
                node: RouteNode {
                    pool_key: pk,
                    sqrt_ratio_limit: tick_to_sqrt_ratio(i129 { mag: 0, sign: false }),
                    skip_ahead: 0,
                },
                token_amount: TokenAmount {
                    token: pk.token0, amount: i129 { mag: 200, sign: false },
                },
            )
            .is_zero(),
        'zero swap back'
    );

    t0.increase_balance(lo.contract_address, 100);
    let id2 = lo.place_order(ok1, 100);

    let (amount0, amount1) = lo.close_order(ok1, id1, recipient: contract_address_const::<1>());
    assert(amount0 == 0, 'co1.amount0');
    assert(amount1 == 100, 'co1.amount1');

    let (amount0, amount1) = lo.close_order(ok1, id2, recipient: contract_address_const::<1>());
    assert(amount0 == 99, 'co2.amount0');
    assert(amount1 == 0, 'co2.amount1');
}

#[test]
fn test_limit_order_is_pulled_for_one_order_and_not_another_sell_token1() {
    let (core, lo, pk) = setup_pool_with_extension();
    let router = deploy_router(core);

    let t0 = IMockERC20Dispatcher { contract_address: pk.token0 };
    let t1 = IMockERC20Dispatcher { contract_address: pk.token1 };

    t1.increase_balance(lo.contract_address, 100);
    let ok1 = OrderKey {
        token0: pk.token0,
        token1: pk.token1,
        tick: i129 { mag: LIMIT_ORDER_TICK_SPACING, sign: false }
    };
    let id1 = lo.place_order(ok1, 100);

    t0.increase_balance(router.contract_address, 200);
    assert(
        router
            .swap(
                node: RouteNode {
                    pool_key: pk,
                    sqrt_ratio_limit: tick_to_sqrt_ratio(
                        i129 { mag: LIMIT_ORDER_TICK_SPACING, sign: false }
                    ),
                    skip_ahead: 0,
                },
                token_amount: TokenAmount {
                    token: pk.token0, amount: i129 { mag: 200, sign: false },
                },
            )
            .is_non_zero(),
        'swap forward'
    );
    assert(
        router
            .swap(
                node: RouteNode {
                    pool_key: pk,
                    sqrt_ratio_limit: tick_to_sqrt_ratio(
                        i129 { mag: 2 * LIMIT_ORDER_TICK_SPACING, sign: false }
                    ),
                    skip_ahead: 0,
                },
                token_amount: TokenAmount {
                    token: pk.token1, amount: i129 { mag: 200, sign: false },
                },
            )
            .is_zero(),
        'zero swap back'
    );

    t1.increase_balance(lo.contract_address, 100);
    let id2 = lo.place_order(ok1, 100);

    let (amount0, amount1) = lo.close_order(ok1, id1, recipient: contract_address_const::<1>());
    assert(amount0 == 99, 'co1.amount0');
    assert(amount1 == 0, 'co1.amount1');

    let (amount0, amount1) = lo.close_order(ok1, id2, recipient: contract_address_const::<1>());
    assert(amount0 == 0, 'co2.amount0');
    assert(amount1 == 99, 'co2.amount1');
}

#[test]
#[should_panic(expected: ('INVALID_ORDER_KEY', 'ENTRYPOINT_FAILED'))]
fn test_close_order_twice_fails_sell_token0() {
    let (core, lo, pk) = setup_pool_with_extension();
    let router = deploy_router(core);

    let t0 = IMockERC20Dispatcher { contract_address: pk.token0 };

    t0.increase_balance(lo.contract_address, 100);
    let ok1 = OrderKey { token0: pk.token0, token1: pk.token1, tick: i129 { mag: 0, sign: false } };
    let id1 = lo.place_order(ok1, 100);
    lo.close_order(ok1, id1, recipient: contract_address_const::<1>());
    lo.close_order(ok1, id1, recipient: contract_address_const::<1>());
}

#[test]
#[should_panic(expected: ('INVALID_ORDER_KEY', 'ENTRYPOINT_FAILED'))]
fn test_close_order_twice_fails_sell_token1() {
    let (core, lo, pk) = setup_pool_with_extension();
    let router = deploy_router(core);

    let t1 = IMockERC20Dispatcher { contract_address: pk.token1 };

    t1.increase_balance(lo.contract_address, 100);
    let ok1 = OrderKey {
        token0: pk.token0,
        token1: pk.token1,
        tick: i129 { mag: LIMIT_ORDER_TICK_SPACING, sign: false }
    };
    let id1 = lo.place_order(ok1, 100);
    lo.close_order(ok1, id1, recipient: contract_address_const::<1>());
    lo.close_order(ok1, id1, recipient: contract_address_const::<1>());
}

#[test]
#[should_panic(
    expected: ('TICK_WRONG_SIDE', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED',)
)]
fn test_place_order_fails_wrong_side_token1() {
    let (core, lo, pk) = setup_pool_with_extension();

    let t0 = IMockERC20Dispatcher { contract_address: pk.token0 };
    t0.increase_balance(lo.contract_address, 100);
    lo.place_order(OrderKey { token0: pk.token0, token1: pk.token1, tick: Zero::zero() }, 100);
    lo
        .place_order(
            OrderKey {
                token0: pk.token0,
                token1: pk.token1,
                tick: i129 { mag: LIMIT_ORDER_TICK_SPACING, sign: false }
            },
            100
        );
}

#[test]
#[should_panic(
    expected: ('TICK_WRONG_SIDE', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED',)
)]
fn test_place_order_fails_wrong_side_token0() {
    let (core, lo, pk) = setup_pool_with_extension();

    let t1 = IMockERC20Dispatcher { contract_address: pk.token1 };
    t1.increase_balance(lo.contract_address, 100);
    lo
        .place_order(
            OrderKey {
                token0: pk.token0,
                token1: pk.token1,
                tick: i129 { mag: LIMIT_ORDER_TICK_SPACING, sign: false }
            },
            100
        );
    lo.place_order(OrderKey { token0: pk.token0, token1: pk.token1, tick: Zero::zero() }, 100);
}

#[test]
#[should_panic(expected: ('SELL_AMOUNT_TOO_SMALL', 'ENTRYPOINT_FAILED'))]
fn test_place_order_fails_zero_token0() {
    let (core, lo, pk) = setup_pool_with_extension();

    lo.place_order(OrderKey { token0: pk.token0, token1: pk.token1, tick: Zero::zero() }, 0);
}

#[test]
#[should_panic(expected: ('SELL_AMOUNT_TOO_SMALL', 'ENTRYPOINT_FAILED'))]
fn test_place_order_fails_zero_token1() {
    let (core, lo, pk) = setup_pool_with_extension();

    lo
        .place_order(
            OrderKey {
                token0: pk.token0,
                token1: pk.token1,
                tick: i129 { mag: LIMIT_ORDER_TICK_SPACING, sign: false }
            },
            0
        );
}
