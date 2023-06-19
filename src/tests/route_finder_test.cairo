use ekubo::tests::helper::{deploy_core, deploy_route_finder, deploy_two_mock_tokens};
use ekubo::route_finder::{
    FindParameters, FindResult, IRouteFinderDispatcher, IRouteFinderDispatcherTrait
};
use ekubo::types::i129::i129;
use zeroable::Zeroable;
use array::{Array, ArrayTrait};
use ekubo::types::keys::PoolKey;


#[test]
#[available_gas(300000000)]
fn test_route_finder_empty() {
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
                    mag: 255, sign: true
                },
                specified_token: token0.contract_address,
                other_token: token1.contract_address,
                pool_keys: pool_keys_to_consider.span(),
            }
        );
    assert(result.found == false, 'found');
    assert(result.relevant_pool_count == 1, 'relevant pool count');
}
