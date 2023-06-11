use ekubo::types::keys::{PoolKey, PositionKey};
use ekubo::types::i129::i129;
use starknet::ContractAddress;
use array::ArrayTrait;
use serde::Serde;
use ekubo::interfaces::core::{UpdatePositionParameters, SwapParameters, Delta};
use ekubo::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};


#[derive(Copy, Drop, Serde)]
enum Action {
    AssertLockerId: felt252,
    Relock: (felt252, felt252), // expected id, number of relocks
    UpdatePosition: (PoolKey, UpdatePositionParameters, ContractAddress),
    Swap: (PoolKey, SwapParameters, ContractAddress)
}

#[derive(Copy, Drop, Serde)]
enum ActionResult {
    AssertLockerId: (),
    Relock: (),
    UpdatePosition: Delta,
    Swap: Delta
}

#[starknet::interface]
trait ICoreLocker<TStorage> {
    fn call(ref self: TStorage, action: Action) -> ActionResult;
    fn locked(ref self: TStorage, id: felt252, data: Array<felt252>) -> Array<felt252>;
}

#[starknet::contract]
mod CoreLocker {
    use super::{
        Action, ActionResult, Delta, IERC20Dispatcher, IERC20DispatcherTrait, ICoreLockerDispatcher,
        ICoreLockerDispatcherTrait, i129, ICoreLocker
    };
    use serde::Serde;
    use starknet::{ContractAddress, get_caller_address, get_contract_address};
    use array::ArrayTrait;
    use ekubo::interfaces::core::{ICoreDispatcher, ICoreDispatcherTrait};
    use ekubo::tests::mocks::mock_erc20::{IMockERC20Dispatcher, IMockERC20DispatcherTrait};
    use option::{Option, OptionTrait};

    #[storage]
    struct Storage {
        core: ContractAddress
    }

    #[constructor]
    fn constructor(ref self: ContractState, _core: ContractAddress) {
        self.core.write(_core);
    }

    #[generate_trait]
    impl Internal of CoreLocker {
        fn handle_delta(
            ref self: ContractState,
            core: ContractAddress,
            token: ContractAddress,
            delta: i129,
            recipient: ContractAddress
        ) {
            if (delta > Default::default()) {
                // transfer the token from self (assumes we have the balance)
                IERC20Dispatcher {
                    contract_address: token
                }.transfer(core, u256 { low: delta.mag, high: 0 });
                // then call pay
                assert(
                    ICoreDispatcher { contract_address: core }.deposit(token) == delta.mag,
                    'DEPOSIT_FAILED'
                );
            } else if (delta < Default::default()) {
                // withdraw to recipient
                ICoreDispatcher { contract_address: core }.withdraw(token, recipient, delta.mag);
            }
        }
    }

    #[external(v0)]
    impl CoreLockerImpl of ICoreLocker<ContractState> {
        fn call(ref self: ContractState, action: Action) -> ActionResult {
            let mut arr: Array<felt252> = ArrayTrait::new();
            Serde::<Action>::serialize(@action, ref arr);

            let result = ICoreDispatcher { contract_address: self.core.read() }.lock(arr);

            let mut result_data = result.span();
            let mut action_result: ActionResult = Serde::<ActionResult>::deserialize(
                ref result_data
            )
                .expect('DESERIALIZE_RESULT_FAILED');

            action_result
        }

        fn locked(ref self: ContractState, id: felt252, data: Array<felt252>) -> Array<felt252> {
            let caller = get_caller_address();
            assert(caller == self.core.read(), 'UNAUTHORIZED_CALLBACK');

            let mut action_data = data.span();
            let mut action: Action = Serde::<Action>::deserialize(ref action_data)
                .expect('DESERIALIZE_FAILED');

            let result = match action {
                Action::AssertLockerId(locker_id) => {
                    assert(locker_id == id, 'INVALID_LOCKER_ID');

                    let state = ICoreDispatcher { contract_address: caller }.get_locker_state(id);

                    assert(state.id == locker_id, 'locker id');
                    assert(state.address == get_contract_address(), 'is locker');
                    assert(state.nonzero_delta_count == 0, 'no deltas');

                    ActionResult::AssertLockerId(())
                },
                Action::Relock((
                    locker_id, relock_count
                )) => {
                    assert(locker_id == id, 'RL_INVALID_LOCKER_ID');

                    let state = ICoreDispatcher { contract_address: caller }.get_locker_state(id);
                    assert(state.id == locker_id, 'locker id');
                    assert(state.address == get_contract_address(), 'is locker');
                    assert(state.nonzero_delta_count == 0, 'no deltas');

                    if (id != 0) {
                        let prev_state = ICoreDispatcher {
                            contract_address: caller
                        }.get_locker_state(id - 1);
                        assert(prev_state.id == locker_id - 1, 'locker id');
                        assert(prev_state.address == get_contract_address(), 'is locker');
                        assert(prev_state.nonzero_delta_count == 0, 'no deltas');
                    }

                    if (relock_count != Default::default()) {
                        // relock
                        ICoreLockerDispatcher {
                            contract_address: get_contract_address()
                        }.call(Action::Relock((locker_id + 1, relock_count - 1)));
                    }

                    ActionResult::Relock(())
                },
                Action::UpdatePosition((
                    pool_key, params, recipient
                )) => {
                    let mut state = ICoreDispatcher {
                        contract_address: caller
                    }.get_locker_state(id);
                    assert(state.id == id, 'locker id');
                    assert(state.address == get_contract_address(), 'is locker');
                    assert(state.nonzero_delta_count == 0, 'no deltas');

                    let delta = ICoreDispatcher {
                        contract_address: caller
                    }.update_position(pool_key, params);

                    state = ICoreDispatcher { contract_address: caller }.get_locker_state(id);
                    assert(state.id == id, 'locker id');
                    assert(state.address == get_contract_address(), 'is locker');
                    assert(
                        state
                            .nonzero_delta_count == ((if delta.amount0_delta == Default::default() {
                                0
                            } else {
                                1
                            })
                                + (if delta.amount1_delta == Default::default() {
                                    0
                                } else {
                                    1
                                })),
                        'deltas'
                    );

                    self.handle_delta(caller, pool_key.token0, delta.amount0_delta, recipient);

                    state = ICoreDispatcher { contract_address: caller }.get_locker_state(id);
                    assert(
                        state
                            .nonzero_delta_count == (if delta.amount1_delta == Default::default() {
                                0
                            } else {
                                1
                            }),
                        'deltas'
                    );

                    self.handle_delta(caller, pool_key.token1, delta.amount1_delta, recipient);

                    state = ICoreDispatcher { contract_address: caller }.get_locker_state(id);
                    assert(state.nonzero_delta_count == 0, 'deltas');

                    ActionResult::UpdatePosition(delta)
                },
                Action::Swap((
                    pool_key, params, recipient
                )) => {
                    let mut state = ICoreDispatcher {
                        contract_address: caller
                    }.get_locker_state(id);
                    assert(state.id == id, 'locker id');
                    assert(state.address == get_contract_address(), 'is locker');
                    assert(state.nonzero_delta_count == 0, 'no deltas');

                    let delta = ICoreDispatcher { contract_address: caller }.swap(pool_key, params);

                    state = ICoreDispatcher { contract_address: caller }.get_locker_state(id);
                    assert(state.id == id, 'locker id');
                    assert(state.address == get_contract_address(), 'is locker');

                    assert(
                        state
                            .nonzero_delta_count == ((if delta.amount0_delta == Default::default() {
                                0
                            } else {
                                1
                            })
                                + (if delta.amount1_delta == Default::default() {
                                    0
                                } else {
                                    1
                                })),
                        'deltas'
                    );

                    self.handle_delta(caller, pool_key.token0, delta.amount0_delta, recipient);

                    state = ICoreDispatcher { contract_address: caller }.get_locker_state(id);
                    assert(
                        state
                            .nonzero_delta_count == (if delta.amount1_delta == Default::default() {
                                0
                            } else {
                                1
                            }),
                        'deltas'
                    );

                    self.handle_delta(caller, pool_key.token1, delta.amount1_delta, recipient);

                    state = ICoreDispatcher { contract_address: caller }.get_locker_state(id);
                    assert(state.nonzero_delta_count == 0, 'deltas');

                    ActionResult::Swap(delta)
                }
            };

            let mut arr: Array<felt252> = ArrayTrait::new();
            Serde::<ActionResult>::serialize(@result, ref arr);
            arr
        }
    }
}
