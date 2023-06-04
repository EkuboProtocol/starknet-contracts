use ekubo::types::keys::{PoolKey, PositionKey};
use ekubo::types::i129::i129;
use starknet::ContractAddress;
use serde::Serde;
use array::ArrayTrait;
use option::{Option, OptionTrait};
use ekubo::core::{
    UpdatePositionParameters, SwapParameters, Delta, IERC20Dispatcher, IERC20DispatcherTrait,
    ILockerDispatcher, ILockerDispatcherTrait, IEkuboDispatcher, IEkuboDispatcherTrait
};
use starknet::get_caller_address;

#[derive(Copy, Drop, Serde)]
enum AmountOrPercent {
    Amount: i129,
    Percent: u128
}

#[derive(Copy, Drop, Serde)]
enum RouteComponentTarget {
    recipient: ContractAddress,
    index: u128
}

#[derive(Copy, Drop, Serde)]
struct RouteComponent {
    pool_key: PoolKey,
    specified_amount: AmountOrPercent,
    computed_minimum: Option<u128>,
    into: RouteComponentTarget
}

#[derive(Drop, Serde)]
struct Route {
    components: Array<RouteComponent>
}

#[derive(Drop, Serde)]
struct GetOptimalRouteParams {
    pool_keys: Array<PoolKey>,
    amount: i129,
    token: ContractAddress,
    other_token: ContractAddress,
}

#[derive(Drop, Serde)]
struct ExecuteResult {
    consumed_amount: i129,
    computed_amount: i129
}

#[derive(Drop, Serde)]
enum CallbackData {
    GetOptimalRoute: GetOptimalRouteParams,
    Execute: (Route, ContractAddress)
}

#[abi]
trait IRouter {
    // Returns the optimal route to swap `amount` of `token` through the pools in `pool_keys`.
    #[external]
    fn get_optimal_route(params: GetOptimalRouteParams) -> Route;

    #[external]
    fn execute(route: Route, recipient: ContractAddress);
}

#[contract]
mod Router {
    use super::{
        ContractAddress, Serde, PoolKey, i129, IEkuboDispatcher, IEkuboDispatcherTrait,
        CallbackData, GetOptimalRouteParams, Route, ArrayTrait, Option, OptionTrait,
        IERC20Dispatcher, IERC20DispatcherTrait, ExecuteResult, get_caller_address
    };

    struct Storage {
        core: ContractAddress
    }

    #[constructor]
    fn constructor(_core: ContractAddress) {
        core::write(_core);
    }

    #[external]
    fn get_optimal_route(params: GetOptimalRouteParams) -> Route {
        let mut arr: Array<felt252> = Default::default();
        Serde::<CallbackData>::serialize(@CallbackData::GetOptimalRoute(params), ref arr);

        let result = IEkuboDispatcher { contract_address: core::read() }.lock(arr);

        let mut result_data = result.span();
        Serde::<Route>::deserialize(ref result_data).expect('DESERIALIZE')
    }

    #[external]
    fn execute(route: Route) {
        let mut arr: Array<felt252> = Default::default();
        Serde::<Route>::serialize(@route, ref arr);

        let result = IEkuboDispatcher { contract_address: core::read() }.lock(arr);

        let mut result_data = result.span();
        let mut action_result: ExecuteResult = Serde::<ExecuteResult>::deserialize(ref result_data)
            .expect('DESERIALIZE');
    }

    #[external]
    fn locked(id: felt252, data: Array<felt252>) -> Array<felt252> {
        let caller = get_caller_address();
        assert(caller == core::read(), 'UNAUTHORIZED_CALLBACK');

        let mut callback_data_raw = data.span();
        let mut callback_data: CallbackData = Serde::<CallbackData>::deserialize(
            ref callback_data_raw
        )
            .expect('DESERIALIZE_FAILED');

        match callback_data {
            CallbackData::GetOptimalRoute(params) => {
                let mut arr: Array<felt252> = Default::default();
                // Serde::<ActionResult>::serialize(@result, ref arr);
                arr
            },
            CallbackData::Execute(route) => {
                assert(false, 'todo');
                let mut arr: Array<felt252> = Default::default();
                // Serde::<ActionResult>::serialize(@result, ref arr);
                arr
            },
        }
    }

    #[internal]
    fn pay(core: ContractAddress, token: ContractAddress, amount: u128) {
        IERC20Dispatcher { contract_address: token }.transfer(core, u256 { low: amount, high: 0 });
        IEkuboDispatcher { contract_address: core }.deposit(token);
    }

    #[internal]
    fn take(
        core: ContractAddress, token: ContractAddress, amount: u128, recipient: ContractAddress
    ) {
        IEkuboDispatcher { contract_address: core }.withdraw(token, recipient, amount);
    }
}
