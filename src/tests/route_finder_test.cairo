use ekubo::tests::helper::{deploy_core, deploy_route_finder};
use ekubo::route_finder::{
    FindParameters, FindResult, IRouteFinderDispatcher, IRouteFinderDispatcherTrait
};
use zeroable::Zeroable;
use array::{Array, ArrayTrait};
use ekubo::types::keys::PoolKey;


#[test]
#[available_gas(300000000)]
fn test_route_finder_empty() {
    let core = deploy_core();
    let route_finder = deploy_route_finder(core);

    let pool_keys_to_consider: Array<PoolKey> = Default::default();

    let result = route_finder
        .find(
            FindParameters {
                amount: Zeroable::zero(),
                specified_token: Zeroable::zero(),
                other_token: Zeroable::zero(),
                pool_keys: pool_keys_to_consider.span(),
            }
        );
    assert(result.found == true, 'found');
}
