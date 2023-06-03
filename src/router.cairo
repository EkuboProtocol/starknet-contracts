use ekubo::types::keys::{PoolKey, PositionKey};
use ekubo::types::i129::i129;
use starknet::ContractAddress;
use serde::Serde;
use ekubo::core::{
    UpdatePositionParameters, SwapParameters, Delta, IERC20Dispatcher, IERC20DispatcherTrait
};


#[derive(Copy, Drop, Serde)]
enum AmountOrPercent {
    Amount: i129,
    Percent: u128
}

#[derive(Drop, Serde)]
struct Route {
    pool_key: PoolKey,
    specified_amount: AmountOrPercent,
    computed_minimum: Option<u128>,
    next: Array<Route>
}

#[abi]
trait IRouter {
    // Returns the optimal route to swap `amount` of `token` through the pools in `pool_keys`.
    #[view]
    fn get_optimal_route(
        pool_keys: Array<PoolKey>,
        amount: i129,
        token: ContractAddress,
        other_token: ContractAddress,
    ) -> Route;

    #[external]
    fn execute(route: Route);
}

#[contract]
mod Router {
    use serde::Serde;
    use starknet::{ContractAddress, get_caller_address};
    use array::ArrayTrait;
    use ekubo::core::{IParlayDispatcher, IParlayDispatcherTrait};
    use tests::mocks::mock_erc20::{IMockERC20Dispatcher, IMockERC20DispatcherTrait};
    use option::{Option, OptionTrait};
}
