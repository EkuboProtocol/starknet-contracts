use ekubo::types::keys::{PoolKey, PositionKey};
use ekubo::types::i129::i129;
use starknet::ContractAddress;
use array::ArrayTrait;
use serde::Serde;
use ekubo::interfaces::core::{UpdatePositionParameters, SwapParameters, Delta};
use ekubo::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};

#[derive(Copy, Drop, Serde)]
enum Action {
    AssertLockerId: u32,
    Relock: (u32, u32), // expected id, number of relocks
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
    use ekubo::interfaces::core::{ICoreDispatcher, ICoreDispatcherTrait, ILocker};
    use ekubo::tests::mocks::mock_erc20::{IMockERC20Dispatcher, IMockERC20DispatcherTrait};
    use ekubo::shared_locker::call_core_with_callback;

    use option::{Option, OptionTrait};

    #[storage]
    struct Storage {
        core: ContractAddress
    }

    #[constructor]
    fn constructor(ref self: ContractState, core: ContractAddress) {
        self.core.write(core);
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
            if (delta > Zeroable::zero()) {
                // transfer the token from self (assumes we have the balance)
                IERC20Dispatcher {
                    contract_address: token
                }.transfer(core, u256 { low: delta.mag, high: 0 });
                // then call pay
                assert(
                    ICoreDispatcher { contract_address: core }.deposit(token) == delta.mag,
                    'DEPOSIT_FAILED'
                );
            } else if (delta < Zeroable::zero()) {
                // withdraw to recipient
                ICoreDispatcher { contract_address: core }.withdraw(token, recipient, delta.mag);
            }
        }
    }

    #[external(v0)]
    impl CoreLockerLockedImpl of ILocker<ContractState> {
        fn locked(ref self: ContractState, id: u32, data: Array<felt252>) -> Array<felt252> {
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

                    if (relock_count != Zeroable::zero()) {
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
                            .nonzero_delta_count == ((if delta.amount0 == Zeroable::zero() {
                                0
                            } else {
                                1
                            })
                                + (if delta.amount1 == Zeroable::zero() {
                                    0
                                } else {
                                    1
                                })),
                        'deltas'
                    );

                    self.handle_delta(caller, pool_key.token0, delta.amount0, recipient);

                    state = ICoreDispatcher { contract_address: caller }.get_locker_state(id);
                    assert(
                        state
                            .nonzero_delta_count == (if delta.amount1 == Zeroable::zero() {
                                0
                            } else {
                                1
                            }),
                        'deltas'
                    );

                    self.handle_delta(caller, pool_key.token1, delta.amount1, recipient);

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
                            .nonzero_delta_count == ((if delta.amount0 == Zeroable::zero() {
                                0
                            } else {
                                1
                            })
                                + (if delta.amount1 == Zeroable::zero() {
                                    0
                                } else {
                                    1
                                })),
                        'deltas'
                    );

                    self.handle_delta(caller, pool_key.token0, delta.amount0, recipient);

                    state = ICoreDispatcher { contract_address: caller }.get_locker_state(id);
                    assert(
                        state
                            .nonzero_delta_count == (if delta.amount1 == Zeroable::zero() {
                                0
                            } else {
                                1
                            }),
                        'deltas'
                    );

                    self.handle_delta(caller, pool_key.token1, delta.amount1, recipient);

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

    #[external(v0)]
    impl CoreLockerImpl of ICoreLocker<ContractState> {
        fn call(ref self: ContractState, action: Action) -> ActionResult {
            call_core_with_callback(self.core.read(), @action)
        }
    }
}
