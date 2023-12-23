use core::array::{Array, ArrayTrait, SpanTrait};
use core::zeroable::Zeroable;
use ekubo::interfaces::core::ICoreDispatcherTrait;
use ekubo::interfaces::positions::IPositionsDispatcherTrait;
use ekubo::quoter::{
    IQuoterDispatcher, IQuoterDispatcherTrait, Route, QuoteParameters, QuoteSingleParameters
};
use ekubo::tests::helper::{
    deploy_core, deploy_quoter, deploy_two_mock_tokens, deploy_positions, deploy_mock_token
};
use ekubo::tests::mocks::mock_erc20::IMockERC20DispatcherTrait;
use ekubo::types::bounds::Bounds;
use ekubo::types::i129::i129;
use ekubo::types::keys::PoolKey;
use starknet::testing::{set_contract_address};
use starknet::{contract_address_const};


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
fn test_quoter_quote_not_initialized_pool() {
    let core = deploy_core();
    let quoter = deploy_quoter(core);
    let (token0, token1) = deploy_two_mock_tokens();

    let pool_key = PoolKey {
        token0: token0.contract_address,
        token1: token1.contract_address,
        fee: 0xc49ba5e353f7ced916872b020c49ba, // 30 bips as a 0.128 number
        tick_spacing: 5982, // 60 bips tick spacing
        extension: Zeroable::zero(),
    };

    let mut pool_keys: Array<PoolKey> = Default::default();
    pool_keys.append(pool_key);
    let route = Route { pool_keys: pool_keys.span() };

    quoter
        .quote(
            QuoteParameters {
                amount: i129 { mag: 100, sign: false },
                specified_token: token0.contract_address,
                route: route,
            }
        );
}

#[test]
fn test_quoter_quote_initialized_pool_no_liquidity() {
    let core = deploy_core();
    let quoter = deploy_quoter(core);
    let (token0, token1) = deploy_two_mock_tokens();

    let pool_key = PoolKey {
        token0: token0.contract_address,
        token1: token1.contract_address,
        fee: 0xc49ba5e353f7ced916872b020c49ba, // 30 bips as a 0.128 number
        tick_spacing: 5982, // 60 bips tick spacing
        extension: Zeroable::zero(),
    };

    core.initialize_pool(pool_key, Zeroable::zero());

    let mut pool_keys: Array<PoolKey> = Default::default();
    pool_keys.append(pool_key);
    let route = Route { pool_keys: pool_keys.span() };

    let result = quoter
        .quote(
            QuoteParameters {
                amount: i129 { mag: 100, sign: false },
                specified_token: token0.contract_address,
                route: route,
            }
        );

    assert(result.amount.is_zero(), 'no output');
    assert(result.other_token == pool_key.token1, 'token');
}


fn setup_for_routing() -> (IQuoterDispatcher, PoolKey, PoolKey) {
    let core = deploy_core();
    let quoter = deploy_quoter(core);
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

    (quoter, pool_key_a, pool_key_b)
}


#[test]
fn test_quoter_quote_initialized_pool_with_liquidity() {
    let (quoter, pool_key, _) = setup_for_routing();

    let mut pool_keys: Array<PoolKey> = Default::default();
    pool_keys.append(pool_key);
    let route = Route { pool_keys: pool_keys.span() };

    let mut result = quoter
        .quote(
            QuoteParameters {
                amount: i129 { mag: 100, sign: false },
                specified_token: pool_key.token0,
                route: route,
            }
        );
    assert(result.amount == i129 { mag: 0x62, sign: true }, '100 token0 in');
    assert(result.other_token == pool_key.token1, 'tokena');
    result = quoter
        .quote(
            QuoteParameters {
                amount: i129 { mag: 100, sign: true },
                specified_token: pool_key.token0,
                route: route,
            }
        );
    assert(result.amount == i129 { mag: 0x66, sign: false }, '100 token0 out');
    assert(result.other_token == pool_key.token1, 'tokenb');

    result = quoter
        .quote(
            QuoteParameters {
                amount: i129 { mag: 100, sign: false },
                specified_token: pool_key.token1,
                route: route,
            }
        );
    assert(result.amount == i129 { mag: 0x62, sign: true }, '100 token1 in');
    assert(result.other_token == pool_key.token0, 'tokenc');
    result = quoter
        .quote(
            QuoteParameters {
                amount: i129 { mag: 100, sign: true },
                specified_token: pool_key.token1,
                route: route,
            }
        );
    assert(result.amount == i129 { mag: 0x66, sign: false }, '100 token1 out');
    assert(result.other_token == pool_key.token0, 'tokend');
}


#[test]
fn test_quoter_quote_single_same_result_initialized_pool_with_liquidity() {
    let (quoter, pool_key, _) = setup_for_routing();

    let mut result = quoter
        .quote_single(
            QuoteSingleParameters {
                amount: i129 { mag: 100, sign: false },
                specified_token: pool_key.token0,
                pool_key: pool_key,
            }
        );
    assert(result.amount == i129 { mag: 0x62, sign: true }, '100 token0 in');
    assert(result.other_token == pool_key.token1, 'tokena');
    result = quoter
        .quote_single(
            QuoteSingleParameters {
                amount: i129 { mag: 100, sign: true },
                specified_token: pool_key.token0,
                pool_key: pool_key,
            }
        );
    assert(result.amount == i129 { mag: 0x66, sign: false }, '100 token0 out');
    assert(result.other_token == pool_key.token1, 'tokenb');

    result = quoter
        .quote_single(
            QuoteSingleParameters {
                amount: i129 { mag: 100, sign: false },
                specified_token: pool_key.token1,
                pool_key: pool_key,
            }
        );
    assert(result.amount == i129 { mag: 0x62, sign: true }, '100 token1 in');
    assert(result.other_token == pool_key.token0, 'tokenc');
    result = quoter
        .quote_single(
            QuoteSingleParameters {
                amount: i129 { mag: 100, sign: true },
                specified_token: pool_key.token1,
                pool_key: pool_key,
            }
        );
    assert(result.amount == i129 { mag: 0x66, sign: false }, '100 token1 out');
    assert(result.other_token == pool_key.token0, 'tokend');
}


#[test]
fn test_quoter_quote_to_delta() {
    let (quoter, pool_key, _) = setup_for_routing();

    let mut delta = quoter
        .delta_to_sqrt_ratio(
            pool_key: pool_key, sqrt_ratio: 0x100000000000000000000000000000000_u256
        );
    assert(delta.amount0.is_zero(), 'amount0');
    assert(delta.amount1.is_zero(), 'amount1');

    delta = quoter.delta_to_sqrt_ratio(pool_key: pool_key, sqrt_ratio: u256 { low: 0, high: 2 });
    assert(delta.amount0 == i129 { mag: 0x270f, sign: true }, 'amount0');
    assert(delta.amount1 == i129 { mag: 0x274d, sign: false }, 'amount1');

    delta = quoter
        .delta_to_sqrt_ratio(
            pool_key: pool_key,
            sqrt_ratio: u256 { low: 170141183460469231731687303715884105728, high: 0 }
        );
    assert(delta.amount0 == i129 { mag: 0x274d, sign: false }, 'amount0');
    assert(delta.amount1 == i129 { mag: 0x270f, sign: true }, 'amount1');
}

#[test]
fn test_quoter_quote_multihop_routes() {
    let (quoter, pool_key_a, pool_key_b) = setup_for_routing();

    let mut pool_keys: Array<PoolKey> = Default::default();
    pool_keys.append(pool_key_a);
    pool_keys.append(pool_key_b);
    let route = Route { pool_keys: pool_keys.span() };

    let mut pool_keys_reverse: Array<PoolKey> = Default::default();
    pool_keys_reverse.append(pool_key_b);
    pool_keys_reverse.append(pool_key_a);
    let route_reverse = Route { pool_keys: pool_keys_reverse.span() };

    let mut result = quoter
        .quote(
            QuoteParameters {
                amount: i129 { mag: 100, sign: false },
                specified_token: pool_key_a.token0,
                route: route,
            }
        );
    assert(result.amount == i129 { mag: 0x60, sign: true }, '100 token0 in');
    assert(result.other_token == pool_key_b.token1, '100 token0 in other');

    result = quoter
        .quote(
            QuoteParameters {
                amount: i129 { mag: 100, sign: true },
                specified_token: pool_key_a.token0,
                route: route,
            }
        );
    assert(result.amount == i129 { mag: 0x68, sign: false }, '100 token0 out');
    assert(result.other_token == pool_key_b.token1, '100 token0 out other');

    result = quoter
        .quote(
            QuoteParameters {
                amount: i129 { mag: 100, sign: false },
                specified_token: pool_key_b.token1,
                route: route_reverse,
            }
        );
    assert(result.amount == i129 { mag: 0x60, sign: true }, '100 token2 in');
    assert(result.other_token == pool_key_a.token0, '100 token2 in other');

    result = quoter
        .quote(
            QuoteParameters {
                amount: i129 { mag: 100, sign: true },
                specified_token: pool_key_b.token1,
                route: route_reverse,
            }
        );
    assert(result.amount == i129 { mag: 0x68, sign: false }, '100 token2 out');
    assert(result.other_token == pool_key_a.token0, '100 token2 out other');
}
