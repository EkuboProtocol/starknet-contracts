use ekubo::types::keys::{PoolKey, PositionKey};
use ekubo::types::i129::i129;
use starknet::ContractAddress;
use serde::Serde;
use ekubo::core::{
    UpdatePositionParameters, SwapParameters, Delta, IERC20Dispatcher, IERC20DispatcherTrait
};


#[derive(Copy, Drop, Serde)]
enum Action {
    AssertLockerId: felt252,
    UpdatePosition: (PoolKey, UpdatePositionParameters, ContractAddress),
    Swap: (PoolKey, SwapParameters, ContractAddress)
}

#[derive(Copy, Drop, Serde)]
enum ActionResult {
    AssertLockerId: (),
    UpdatePosition: Delta,
    Swap: Delta
}

#[abi]
trait ICoreLocker {
    #[external]
    fn call(action: Action) -> ActionResult;
}

#[contract]
mod CoreLocker {
    use super::{Action, ActionResult, Delta, IERC20Dispatcher, IERC20DispatcherTrait, i129};
    use serde::Serde;
    use starknet::{ContractAddress, get_caller_address};
    use array::ArrayTrait;
    use ekubo::core::{IParlayDispatcher, IParlayDispatcherTrait};
    use tests::mocks::mock_erc20::{IMockERC20Dispatcher, IMockERC20DispatcherTrait};
    use option::{Option, OptionTrait};

    struct Storage {
        core: ContractAddress
    }

    #[constructor]
    fn constructor(_core: ContractAddress) {
        core::write(_core);
    }

    #[external]
    fn call(action: Action) -> ActionResult {
        let mut arr: Array<felt252> = Default::default();
        Serde::<Action>::serialize(@action, ref arr);

        let result = IParlayDispatcher { contract_address: core::read() }.lock(arr);

        let mut result_data = result.span();
        let mut action_result: ActionResult = Serde::<ActionResult>::deserialize(ref result_data)
            .expect('DESERIALIZE_RESULT_FAILED');

        action_result
    }

    #[internal]
    fn handle_delta(
        core: ContractAddress, token: ContractAddress, delta: i129, recipient: ContractAddress
    ) {
        if (delta > Default::default()) {
            // transfer the token from self (assumes we have the balance)
            IERC20Dispatcher {
                contract_address: token
            }.transfer(core, u256 { low: delta.mag, high: 0 });
            // then call pay
            assert(IParlayDispatcher { contract_address: core }.deposit(token) == delta.mag, 'DEPOSIT_FAILED');
        } else if (delta < Default::default()) {
            // withdraw to recipient
            IParlayDispatcher { contract_address: core }.withdraw(token, recipient, delta.mag);
        }
    }

    #[external]
    fn locked(id: felt252, data: Array<felt252>) -> Array<felt252> {
        let caller = get_caller_address();
        assert(caller == core::read(), 'UNAUTHORIZED_CALLBACK');

        let mut action_data = data.span();
        let mut action: Action = Serde::<Action>::deserialize(ref action_data)
            .expect('DESERIALIZE_FAILED');

        let result = match action {
            Action::AssertLockerId(locker_id) => {
                assert(locker_id == id, 'INVALID_LOCKER_ID');

                ActionResult::AssertLockerId(())
            },
            Action::UpdatePosition((
                pool_key, params, recipient
            )) => {
                let delta = IParlayDispatcher {
                    contract_address: caller
                }.update_position(pool_key, params);

                handle_delta(caller, pool_key.token0, delta.amount0_delta, recipient);
                handle_delta(caller, pool_key.token1, delta.amount1_delta, recipient);

                ActionResult::UpdatePosition(delta)
            },
            Action::Swap((
                pool_key, params, recipient
            )) => {
                let delta = IParlayDispatcher { contract_address: caller }.swap(pool_key, params);

                handle_delta(caller, pool_key.token0, delta.amount0_delta, recipient);
                handle_delta(caller, pool_key.token1, delta.amount1_delta, recipient);

                ActionResult::Swap(delta)
            }
        };

        let mut arr: Array<felt252> = Default::default();
        Serde::<ActionResult>::serialize(@result, ref arr);
        arr
    }
}
