use ekubo::tests::helper::{setup_pool, swap, update_position, SetupPoolResult, FEE_ONE_PERCENT};
use starknet::{contract_address_const};
use ekubo::types::i129::i129;


#[test]
#[available_gas(2000000)]
fn test_router_get_optimal_route() {
    let setup = setup_pool(
        owner: contract_address_const::<1>(),
        fee: FEE_ONE_PERCENT,
        tick_spacing: 100,
        initial_tick: i129 { mag: 0, sign: false }
    );
// todo: test routing

}
