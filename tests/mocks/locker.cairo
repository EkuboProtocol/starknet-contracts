use parlay::types::keys::{PoolKey, PositionKey};
use parlay::types::i129::i129;
use starknet::ContractAddress;
use serde::Serde;

#[derive(Copy, Drop, Serde)]
enum Action {
    NoOp: (),
    AssertLockerId: felt252,
    UpdatePosition: (PoolKey, i129, i129, i129),
    Swap: (PoolKey, i129, bool, u256)
}

#[contract]
mod CoreLocker {
    use super::Action;
    use serde::Serde;
    use starknet::{ContractAddress, get_caller_address};
    use array::ArrayTrait;
    use parlay::core::{IParlayDispatcher, IParlayDispatcherTrait};
    use option::{Option, OptionTrait};

    #[external]
    fn call_core(core_address: ContractAddress, action: Action) -> Array<felt252> {
        let mut arr: Array<felt252> = Default::default();
        Serde::<Action>::serialize(@action, ref arr);
        IParlayDispatcher { contract_address: core_address }.lock(arr)
    }

    #[external]
    fn locked(id: felt252, data: Array<felt252>) -> Array<felt252> {
        let core = get_caller_address();
        let mut action_data = data.span();
        let mut action: Action = Serde::<Action>::deserialize(ref action_data)
            .expect('DESERIALIZE_FAILED');

        match action {
            Action::NoOp(_) => {},
            Action::AssertLockerId(locker_id) => {
                assert(locker_id == id, 'INVALID_LOCKER_ID');
            },
            Action::UpdatePosition((
                pool_key, tick_lower, tick_upper, liquidity_delta
            )) => {
                let (amount0_delta, amount1_delta) = IParlayDispatcher {
                    contract_address: core
                }.update_position(pool_key, tick_lower, tick_upper, liquidity_delta);
            },
            Action::Swap((
                pool_key, amount, is_token1, sqrt_ratio_limit
            )) => {
                let (amount0_delta, amount1_delta) = IParlayDispatcher {
                    contract_address: core
                }.swap(pool_key, amount, is_token1, sqrt_ratio_limit);
            }
        }

        Default::default()
    }
}
