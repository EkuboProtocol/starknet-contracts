use ekubo::tests::helper::{deploy_core, deploy_route_finder, deploy_two_mock_tokens, deploy_locker};
use ekubo::route_finder::{
    FindParameters, FindResult, IRouteFinderDispatcher, IRouteFinderDispatcherTrait, Route,
    QuoteParameters,
};
use ekubo::types::i129::i129;
use zeroable::Zeroable;
use array::{Array, ArrayTrait, SpanTrait};
use ekubo::types::keys::PoolKey;


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
    let locker = deploy_locker(core);
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
