use core::array::{Array, ArrayTrait, SpanTrait};

use core::num::traits::{Zero};
use ekubo::interfaces::core::{ICoreDispatcherTrait, SwapParameters};
use ekubo::interfaces::positions::{IPositionsDispatcherTrait};
use ekubo::math::ticks::{min_sqrt_ratio, max_sqrt_ratio, min_tick, max_tick};
use ekubo::mock_erc20::{IMockERC20DispatcherTrait};
use ekubo::router::{IRouterDispatcher, IRouterDispatcherTrait, TokenAmount, RouteNode, Depth, Swap};
use ekubo::tests::helper::{
    deploy_core, deploy_router, deploy_two_mock_tokens, deploy_positions, deploy_mock_token
};
use ekubo::types::bounds::{Bounds};
use ekubo::types::i129::{i129};
use ekubo::types::keys::{PoolKey};
use starknet::testing::{set_contract_address};
use starknet::{ContractAddress, contract_address_const};

fn recipient() -> ContractAddress {
    contract_address_const::<0x12345678>()
}

#[test]
#[should_panic(
    expected: (
        'NOT_INITIALIZED',
        'ENTRYPOINT_FAILED',
        'ENTRYPOINT_FAILED',
        'ENTRYPOINT_FAILED',
        'ENTRYPOINT_FAILED'
    )
)]
fn test_router_quote_not_initialized_pool() {
    let core = deploy_core();
    let router = deploy_router(core);
    let (token0, token1) = deploy_two_mock_tokens();

    let pool_key = PoolKey {
        token0: token0.contract_address,
        token1: token1.contract_address,
        fee: 0xc49ba5e353f7ced916872b020c49ba, // 30 bips as a 0.128 number
        tick_spacing: 5982, // 60 bips tick spacing
        extension: Zero::zero(),
    };

    router
        .quote(
            swaps: array![
                Swap {
                    route: array![
                        RouteNode {
                            pool_key: pool_key, sqrt_ratio_limit: min_sqrt_ratio(), skip_ahead: 0
                        }
                    ],
                    token_amount: TokenAmount {
                        token: token0.contract_address, amount: i129 { mag: 100, sign: false }
                    },
                }
            ]
        );
}

#[test]
fn test_router_quote_initialized_pool_no_liquidity() {
    let core = deploy_core();
    let router = deploy_router(core);
    let (token0, token1) = deploy_two_mock_tokens();

    let pool_key = PoolKey {
        token0: token0.contract_address,
        token1: token1.contract_address,
        fee: 0xc49ba5e353f7ced916872b020c49ba, // 30 bips as a 0.128 number
        tick_spacing: 5982, // 60 bips tick spacing
        extension: Zero::zero(),
    };

    core.initialize_pool(pool_key, Zero::zero());

    let mut result = router
        .quote(
            swaps: array![
                Swap {
                    route: array![
                        RouteNode {
                            pool_key: pool_key, sqrt_ratio_limit: min_sqrt_ratio(), skip_ahead: 0
                        }
                    ],
                    token_amount: TokenAmount {
                        token: token0.contract_address, amount: i129 { mag: 100, sign: false }
                    },
                }
            ]
        );

    let result = result.pop_front().unwrap();

    assert(result.len() == 1, 'one delta');
    assert(result.at(0).is_zero(), 'delta is zero');
}


fn setup_for_routing() -> (IRouterDispatcher, PoolKey, PoolKey) {
    let core = deploy_core();
    let router = deploy_router(core);
    let positions = deploy_positions(core);
    let (token0, token1) = deploy_two_mock_tokens();
    let token2 = deploy_mock_token();

    let pool_key_a = PoolKey {
        token0: token0.contract_address,
        token1: token1.contract_address,
        fee: 0xc49ba5e353f7ced916872b020c49ba, // 30 bips as a 0.128 number
        tick_spacing: 5982, // 60 bips tick spacing
        extension: Zero::zero(),
    };

    let pool_key_b = PoolKey {
        token0: token1.contract_address,
        token1: token2.contract_address,
        fee: 0xc49ba5e353f7ced916872b020c49ba, // 30 bips as a 0.128 number
        tick_spacing: 5982, // 60 bips tick spacing
        extension: Zero::zero(),
    };

    let bounds = Bounds {
        lower: i129 { mag: 5982, sign: true }, upper: i129 { mag: 5982, sign: false }
    };

    core.initialize_pool(pool_key_a, Zero::zero());
    core.initialize_pool(pool_key_b, Zero::zero());

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

    (router, pool_key_a, pool_key_b)
}


#[test]
fn test_router_quote_initialized_pool_with_liquidity() {
    let (router, pool_key, _) = setup_for_routing();

    let mut result = router
        .quote(
            swaps: array![
                Swap {
                    route: array![
                        RouteNode { pool_key, sqrt_ratio_limit: min_sqrt_ratio(), skip_ahead: 0 }
                    ],
                    token_amount: TokenAmount {
                        amount: i129 { mag: 100, sign: false }, token: pool_key.token0
                    },
                }
            ]
        );

    assert(result.at(0).at(0).amount1 == @i129 { mag: 0x62, sign: true }, '100 token0 in.amount1');

    result = router
        .quote(
            swaps: array![
                Swap {
                    route: array![
                        RouteNode { pool_key, sqrt_ratio_limit: max_sqrt_ratio(), skip_ahead: 0 }
                    ],
                    token_amount: TokenAmount {
                        amount: i129 { mag: 100, sign: true }, token: pool_key.token0
                    },
                }
            ]
        );
    assert(
        result.at(0).at(0).amount1 == @i129 { mag: 0x66, sign: false }, '100 token0 out.amount1'
    );

    result = router
        .quote(
            swaps: array![
                Swap {
                    route: array![
                        RouteNode { pool_key, sqrt_ratio_limit: max_sqrt_ratio(), skip_ahead: 0 }
                    ],
                    token_amount: TokenAmount {
                        amount: i129 { mag: 100, sign: false }, token: pool_key.token1
                    },
                }
            ]
        );
    assert(result.at(0).at(0).amount0 == @i129 { mag: 0x62, sign: true }, '100 token1 in.amount0');
    assert(result.at(0).at(0).amount1 == @i129 { mag: 100, sign: false }, '100 token1 in.amount1');

    result = router
        .quote(
            swaps: array![
                Swap {
                    route: array![
                        RouteNode { pool_key, sqrt_ratio_limit: min_sqrt_ratio(), skip_ahead: 0 }
                    ],
                    token_amount: TokenAmount {
                        amount: i129 { mag: 100, sign: true }, token: pool_key.token1
                    },
                }
            ]
        );
    assert(
        result.at(0).at(0).amount0 == @i129 { mag: 0x66, sign: false }, '100 token1 out.amount0'
    );
}


#[test]
fn test_router_quote_to_delta() {
    let (router, pool_key, _) = setup_for_routing();

    let mut delta = router
        .get_delta_to_sqrt_ratio(
            pool_key: pool_key, sqrt_ratio: 0x100000000000000000000000000000000_u256
        );
    assert(delta.amount0.is_zero(), 'amount0');
    assert(delta.amount1.is_zero(), 'amount1');

    delta = router
        .get_delta_to_sqrt_ratio(pool_key: pool_key, sqrt_ratio: u256 { low: 0, high: 2 });
    assert(delta.amount0 == i129 { mag: 0x270f, sign: true }, 'amount0');
    assert(delta.amount1 == i129 { mag: 0x274d, sign: false }, 'amount1');

    delta = router
        .get_delta_to_sqrt_ratio(
            pool_key: pool_key,
            sqrt_ratio: u256 { low: 170141183460469231731687303715884105728, high: 0 }
        );
    assert(delta.amount0 == i129 { mag: 0x274d, sign: false }, 'amount0');
    assert(delta.amount1 == i129 { mag: 0x270f, sign: true }, 'amount1');
}

#[test]
fn test_router_quote_multihop_routes() {
    let (router, pool_key_a, pool_key_b) = setup_for_routing();

    let mut result = router
        .quote(
            swaps: array![
                Swap {
                    route: array![
                        RouteNode { pool_key: pool_key_a, sqrt_ratio_limit: 0, skip_ahead: 0 },
                        RouteNode { pool_key: pool_key_b, sqrt_ratio_limit: 0, skip_ahead: 0 }
                    ],
                    token_amount: TokenAmount {
                        amount: i129 { mag: 100, sign: false }, token: pool_key_a.token0
                    },
                }
            ]
        );
    assert(result.at(0).at(1).amount1 == @i129 { mag: 0x60, sign: true }, '100 token0 in');

    result = router
        .quote(
            swaps: array![
                Swap {
                    route: array![
                        RouteNode { pool_key: pool_key_a, sqrt_ratio_limit: 0, skip_ahead: 0 },
                        RouteNode { pool_key: pool_key_b, sqrt_ratio_limit: 0, skip_ahead: 0 }
                    ],
                    token_amount: TokenAmount {
                        amount: i129 { mag: 100, sign: true }, token: pool_key_a.token0
                    },
                }
            ]
        );
    assert(result.at(0).at(1).amount1 == @i129 { mag: 0x68, sign: false }, '100 token0 out');

    result = router
        .quote(
            swaps: array![
                Swap {
                    route: array![
                        RouteNode { pool_key: pool_key_b, sqrt_ratio_limit: 0, skip_ahead: 0 },
                        RouteNode { pool_key: pool_key_a, sqrt_ratio_limit: 0, skip_ahead: 0 }
                    ],
                    token_amount: TokenAmount {
                        amount: i129 { mag: 100, sign: false }, token: pool_key_b.token1
                    },
                }
            ]
        );
    assert(result.at(0).at(1).amount0 == @i129 { mag: 0x60, sign: true }, '100 token2 in');

    result = router
        .quote(
            swaps: array![
                Swap {
                    route: array![
                        RouteNode { pool_key: pool_key_b, sqrt_ratio_limit: 0, skip_ahead: 0 },
                        RouteNode { pool_key: pool_key_a, sqrt_ratio_limit: 0, skip_ahead: 0 }
                    ],
                    token_amount: TokenAmount {
                        amount: i129 { mag: 100, sign: true }, token: pool_key_b.token1
                    },
                }
            ]
        );
    assert(result.at(0).at(1).amount0 == @i129 { mag: 0x68, sign: false }, '100 token2 out');
}


#[test]
#[should_panic(
    expected: (
        'NOT_INITIALIZED',
        'ENTRYPOINT_FAILED',
        'ENTRYPOINT_FAILED',
        'ENTRYPOINT_FAILED',
        'ENTRYPOINT_FAILED'
    )
)]
fn test_router_swap_not_initialized_pool() {
    let core = deploy_core();
    let router = deploy_router(core);
    let (token0, token1) = deploy_two_mock_tokens();

    let pool_key = PoolKey {
        token0: token0.contract_address,
        token1: token1.contract_address,
        fee: 0xc49ba5e353f7ced916872b020c49ba, // 30 bips as a 0.128 number
        tick_spacing: 5982, // 60 bips tick spacing
        extension: Zero::zero(),
    };

    router
        .multihop_swap(
            route: array![RouteNode { pool_key, sqrt_ratio_limit: 0, skip_ahead: 0 }],
            token_amount: TokenAmount {
                amount: i129 { mag: 100, sign: false }, token: pool_key.token0,
            },
        );
}

#[test]
fn test_router_swap_initialized_pool_no_liquidity_token0_in() {
    let core = deploy_core();
    let router = deploy_router(core);
    let (token0, token1) = deploy_two_mock_tokens();

    let pool_key = PoolKey {
        token0: token0.contract_address,
        token1: token1.contract_address,
        fee: 0xc49ba5e353f7ced916872b020c49ba, // 30 bips as a 0.128 number
        tick_spacing: 5982, // 60 bips tick spacing
        extension: Zero::zero(),
    };

    core.initialize_pool(pool_key, Zero::zero());

    let token_amount = router
        .multihop_swap(
            route: array![RouteNode { pool_key, sqrt_ratio_limit: 0, skip_ahead: 0 }],
            token_amount: TokenAmount {
                amount: i129 { mag: 100, sign: false }, token: pool_key.token0,
            },
        );

    assert(token_amount.at(0).is_zero(), 'no output');

    let pp = core.get_pool_price(pool_key);
    assert(pp.sqrt_ratio == min_sqrt_ratio(), 'traded to end');
    assert(pp.tick == (min_tick() - i129 { mag: 1, sign: false }), 'traded to end');
}

#[test]
fn test_router_swap_initialized_pool_no_liquidity_token1_in() {
    let core = deploy_core();
    let router = deploy_router(core);
    let (token0, token1) = deploy_two_mock_tokens();

    let pool_key = PoolKey {
        token0: token0.contract_address,
        token1: token1.contract_address,
        fee: 0xc49ba5e353f7ced916872b020c49ba, // 30 bips as a 0.128 number
        tick_spacing: 5982, // 60 bips tick spacing
        extension: Zero::zero(),
    };

    core.initialize_pool(pool_key, Zero::zero());

    let delta = router
        .multihop_swap(
            route: array![
                RouteNode { pool_key, sqrt_ratio_limit: max_sqrt_ratio(), skip_ahead: 0 }
            ],
            token_amount: TokenAmount {
                amount: i129 { mag: 100, sign: false }, token: pool_key.token1,
            },
        );

    assert(delta.at(0).is_zero(), 'no input');

    let pp = core.get_pool_price(pool_key);

    assert(pp.sqrt_ratio == max_sqrt_ratio(), 'traded to end');
    assert(pp.tick == max_tick(), 'traded to end');
}


#[test]
fn test_router_get_market_depth() {
    let (router, pool_key_a, pool_key_b) = setup_for_routing();

    assert_eq!( // +/-0%
    router.get_market_depth(pool_key_a, 0), Depth { token0: 0, token1: 0 });

    assert_eq!(
        // +/-0.01%
        router.get_market_depth(pool_key_a, 17013693014354590797691252010145372),
        Depth { token0: 167, token1: 167 }
    );

    assert_eq!(
        // +/-0.1%
        router.get_market_depth(pool_key_a, 170098669418969064647561320363379535),
        Depth { token0: 1672, token1: 1672 }
    );

    assert_eq!(
        // +/-2%
        router.get_market_depth(pool_key_a, 3385977594616997568912048723923598803),
        Depth { token0: 9999, token1: 9999 }
    );

    assert_eq!(
        // +/-max%
        router.get_market_depth(pool_key_a, 0xffffffffffffffffffffffffffffffff),
        Depth { token0: 9999, token1: 9999 }
    );
}

#[test]
fn test_router_get_market_depth_v2() {
    let (router, pool_key_a, pool_key_b) = setup_for_routing();

    assert_eq!( // +/-0%
    router.get_market_depth_v2(pool_key_a, 0), Depth { token0: 0, token1: 0 });

    assert_eq!(
        // +/-0.01%
        router.get_market_depth_v2(pool_key_a, 1844674407370955), Depth { token0: 167, token1: 167 }
    );

    assert_eq!(
        // +/-0.01%
        router.get_market_depth_v2(pool_key_a, 1844674407370955), Depth { token0: 167, token1: 167 }
    );

    assert_eq!(
        // +/-0.1%
        router.get_market_depth_v2(pool_key_a, 18446744073709551),
        Depth { token0: 1672, token1: 1672 }
    );

    assert_eq!(
        // +/-2%
        router.get_market_depth_v2(pool_key_a, 368934881474191032),
        Depth { token0: 9999, token1: 9999 }
    );

    assert_eq!(
        // +/-max%
        router.get_market_depth_v2(pool_key_a, 0xffffffffffffffffffffffffffffffff),
        Depth { token0: 9999, token1: 9999 }
    );
}
