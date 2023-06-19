use ekubo::interfaces::positions::IPositionsDispatcherTrait;
use ekubo::tests::mocks::mock_erc20::IMockERC20DispatcherTrait;
use ekubo::interfaces::core::ICoreDispatcherTrait;
use ekubo::tests::helper::{
    deploy_core, deploy_route_finder, deploy_two_mock_tokens, deploy_positions
};
use ekubo::route_finder::{
    FindParameters, FindResult, IRouteFinderDispatcher, IRouteFinderDispatcherTrait, Route,
    QuoteParameters,
};
use ekubo::types::i129::i129;
use ekubo::types::bounds::Bounds;
use zeroable::Zeroable;
use array::{Array, ArrayTrait, SpanTrait};
use ekubo::types::keys::PoolKey;
use starknet::testing::{set_contract_address};
use starknet::{contract_address_const};


#[test]
#[available_gas(300000000)]
fn test_route_finder_find_empty() {
    let core = deploy_core();
    let route_finder = deploy_route_finder(core);
    let (token0, token1) = deploy_two_mock_tokens();

    let mut pool_keys_to_consider: Array<PoolKey> = Default::default();
    pool_keys_to_consider
        .append(
            PoolKey {
                token0: token0.contract_address,
                token1: token1.contract_address,
                fee: 0xc49ba5e353f7ced916872b020c49ba, // 30 bips as a 0.128 number
                tick_spacing: 5982, // 60 bips tick spacing
                extension: Zeroable::zero(),
            }
        );

    let result = route_finder
        .find(
            FindParameters {
                amount: i129 {
                    mag: 100, sign: true
                },
                specified_token: token0.contract_address,
                other_token: token1.contract_address,
                pool_keys: pool_keys_to_consider.span(),
            }
        );
    assert(result.route.pool_keys.len() == 1, 'path is 1');
    assert(result.other_token_amount.is_zero(), 'zero amount');
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
fn test_route_finder_quote_not_initialized_pool() {
    let core = deploy_core();
    let route_finder = deploy_route_finder(core);
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

    route_finder
        .quote(
            QuoteParameters {
                amount: i129 {
                    mag: 100, sign: false
                },
                specified_token: token0.contract_address,
                other_token: token1.contract_address,
                route: route,
            }
        );
}

#[test]
#[available_gas(300000000)]
fn test_route_finder_quote_initialized_pool_no_liquidity() {
    let core = deploy_core();
    let route_finder = deploy_route_finder(core);
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

    let result = route_finder
        .quote(
            QuoteParameters {
                amount: i129 {
                    mag: 100, sign: false
                },
                specified_token: token0.contract_address,
                other_token: token1.contract_address,
                route: route,
            }
        );

    assert(result.is_zero(), 'no output');
}


fn setup_for_routing() -> (IRouteFinderDispatcher, PoolKey) {
    let core = deploy_core();
    let route_finder = deploy_route_finder(core);
    let positions = deploy_positions(core);
    let (token0, token1) = deploy_two_mock_tokens();

    let pool_key = PoolKey {
        token0: token0.contract_address,
        token1: token1.contract_address,
        fee: 0xc49ba5e353f7ced916872b020c49ba, // 30 bips as a 0.128 number
        tick_spacing: 5982, // 60 bips tick spacing
        extension: Zeroable::zero(),
    };

    let bounds = Bounds {
        tick_lower: i129 { mag: 5982, sign: true }, tick_upper: i129 { mag: 5982, sign: false }
    };

    core.initialize_pool(pool_key, Zeroable::zero());
    set_contract_address(core.get_owner());
    core.set_reserves_limit(token0.contract_address, 0xffffffffffffffffffffffffffffffff);
    core.set_reserves_limit(token1.contract_address, 0xffffffffffffffffffffffffffffffff);

    let caller = contract_address_const::<1>();
    set_contract_address(caller);

    token0.increase_balance(positions.contract_address, 10000);
    token1.increase_balance(positions.contract_address, 10000);

    let token_id = positions.mint(recipient: caller, pool_key: pool_key, bounds: bounds);

    let deposited_liquidity = positions
        .deposit(
            token_id: token_id,
            pool_key: pool_key,
            bounds: bounds,
            min_liquidity: 0,
            collect_fees: false
        );

    (route_finder, pool_key)
}

#[test]
#[available_gas(300000000)]
fn test_route_finder_quote_initialized_pool_with_liquidity() {
    let (route_finder, pool_key) = setup_for_routing();

    let mut pool_keys: Array<PoolKey> = Default::default();
    pool_keys.append(pool_key);
    let route = Route { pool_keys: pool_keys.span() };

    let mut result = route_finder
        .quote(
            QuoteParameters {
                amount: i129 {
                    mag: 100, sign: false
                }, specified_token: pool_key.token0, other_token: pool_key.token1, route: route,
            }
        );
    assert(result.is_non_zero(), 'nonzero');
    result = route_finder
        .quote(
            QuoteParameters {
                amount: i129 {
                    mag: 100, sign: true
                }, specified_token: pool_key.token0, other_token: pool_key.token1, route: route,
            }
        );
    assert(result.is_non_zero(), 'nonzero');

    result = route_finder
        .quote(
            QuoteParameters {
                amount: i129 {
                    mag: 100, sign: false
                }, specified_token: pool_key.token0, other_token: pool_key.token1, route: route,
            }
        );
    assert(result.is_non_zero(), 'nonzero');
    result = route_finder
        .quote(
            QuoteParameters {
                amount: i129 {
                    mag: 100, sign: true
                }, specified_token: pool_key.token0, other_token: pool_key.token1, route: route,
            }
        );
    assert(result.is_non_zero(), 'nonzero');
}
