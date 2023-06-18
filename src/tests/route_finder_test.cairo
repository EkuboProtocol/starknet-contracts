use ekubo::tests::helper::{deploy_core, deploy_route_finder};
use ekubo::route_finder::{
    FindParameters, FindResult, IRouteFinderDispatcher, IRouteFinderDispatcherTrait
};
use zeroable::Zeroable;


#[test]
#[available_gas(300000000)]
fn test_route_finder_empty() {
    let core = deploy_core();
    let route_finder = deploy_route_finder();

    let result = route_finder
        .find(
            core.contract_address,
            FindParameters {
                amount: Zeroable::zero(),
                specified_token: Zeroable::zero(),
                other_token: Zeroable::zero(),
            }
        );
    assert(result.found == true, 'found');
}
