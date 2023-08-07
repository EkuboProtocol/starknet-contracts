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
    Swap: (PoolKey, SwapParameters, ContractAddress),
    // save that amount of balance to the given address
    SaveBalance: (ContractAddress, u64, ContractAddress, u128),
    // loads the balance to the address
    LoadBalance: (ContractAddress, u64, ContractAddress, u128),
    // accumulates some tokens as fees
    AccumulateAsFees: (PoolKey, u128, u128),
}

#[derive(Copy, Drop, Serde)]
enum ActionResult {
    AssertLockerId: (),
    Relock: (),
    UpdatePosition: Delta,
    Swap: Delta,
    SaveBalance: u128,
    LoadBalance: u128,
    AccumulateAsFees: Delta,
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
    use starknet::{
        ContractAddress, get_caller_address, get_contract_address, contract_address_const
    };
    use array::ArrayTrait;
    use ekubo::interfaces::core::{ICoreDispatcher, ICoreDispatcherTrait, ILocker};
    use ekubo::tests::mocks::mock_erc20::{IMockERC20Dispatcher, IMockERC20DispatcherTrait};
    use ekubo::shared_locker::{call_core_with_callback, consume_callback_data};

    use option::{Option, OptionTrait};

    #[storage]
    struct Storage {
        core: ICoreDispatcher
    }

    #[constructor]
    fn constructor(ref self: ContractState, core: ICoreDispatcher) {
        self.core.write(core);
    }

    #[generate_trait]
    impl Internal of CoreLocker {
        fn handle_delta(
            ref self: ContractState,
            core: ICoreDispatcher,
            token: ContractAddress,
            delta: i129,
            recipient: ContractAddress
        ) {
            if (delta > Zeroable::zero()) {
                // transfer the token from self (assumes we have the balance)
                IERC20Dispatcher {
                    contract_address: token
                }.transfer(core.contract_address, u256 { low: delta.mag, high: 0 });
                // then call pay
                assert(core.deposit(token) == delta.mag, 'DEPOSIT_FAILED');
            } else if (delta < Zeroable::zero()) {
                // withdraw to recipient
                core.withdraw(token, recipient, delta.mag);
            }
        }
    }

    #[external(v0)]
    impl CoreLockerLockedImpl of ILocker<ContractState> {
        fn locked(ref self: ContractState, id: u32, data: Array<felt252>) -> Array<felt252> {
            let core = self.core.read();

            let result = match consume_callback_data::<Action>(core, data) {
                Action::AssertLockerId(locker_id) => {
                    assert(locker_id == id, 'INVALID_LOCKER_ID');

                    let state = core.get_locker_state(id);

                    assert(state.address == get_contract_address(), 'is locker');
                    assert(state.nonzero_delta_count == 0, 'no deltas');

                    ActionResult::AssertLockerId(())
                },
                Action::Relock((
                    locker_id, relock_count
                )) => {
                    assert(locker_id == id, 'RL_INVALID_LOCKER_ID');

                    let state = core.get_locker_state(id);
                    assert(state.address == get_contract_address(), 'is locker');
                    assert(state.nonzero_delta_count == 0, 'no deltas');

                    if (id != 0) {
                        let prev_state = core.get_locker_state(id - 1);
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
                    let mut state = core.get_locker_state(id);
                    assert(state.address == get_contract_address(), 'is locker');
                    assert(state.nonzero_delta_count == 0, 'no deltas');

                    let delta = core.update_position(pool_key, params);

                    state = core.get_locker_state(id);
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

                    self.handle_delta(core, pool_key.token0, delta.amount0, recipient);

                    state = core.get_locker_state(id);
                    assert(
                        state
                            .nonzero_delta_count == (if delta.amount1 == Zeroable::zero() {
                                0
                            } else {
                                1
                            }),
                        'deltas'
                    );

                    self.handle_delta(core, pool_key.token1, delta.amount1, recipient);

                    state = core.get_locker_state(id);
                    assert(state.nonzero_delta_count == 0, 'deltas');

                    ActionResult::UpdatePosition(delta)
                },
                Action::Swap((
                    pool_key, params, recipient
                )) => {
                    let mut state = core.get_locker_state(id);
                    assert(state.address == get_contract_address(), 'is locker');
                    assert(state.nonzero_delta_count == 0, 'no deltas');

                    let delta = core.swap(pool_key, params);

                    state = core.get_locker_state(id);
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

                    self.handle_delta(core, pool_key.token0, delta.amount0, recipient);

                    state = core.get_locker_state(id);
                    assert(
                        state
                            .nonzero_delta_count == (if delta.amount1 == Zeroable::zero() {
                                0
                            } else {
                                1
                            }),
                        'deltas'
                    );

                    self.handle_delta(core, pool_key.token1, delta.amount1, recipient);

                    state = core.get_locker_state(id);
                    assert(state.nonzero_delta_count == 0, 'deltas');

                    ActionResult::Swap(delta)
                },
                Action::SaveBalance((
                    token, cache_key, recipient, amount
                )) => {
                    let balance_next = core.save(token, cache_key, recipient, amount);

                    let mut state = core.get_locker_state(id);
                    assert(state.address == get_contract_address(), 'is locker');
                    assert(state.nonzero_delta_count == 1, '1 delta');

                    self.handle_delta(core, token, i129 { mag: amount, sign: false }, recipient);

                    state = core.get_locker_state(id);
                    assert(state.nonzero_delta_count == 0, '0 delta');

                    ActionResult::SaveBalance(balance_next)
                },
                Action::LoadBalance((
                    token, cache_key, recipient, amount
                )) => {
                    let balance_next = core.load(token, cache_key, amount);

                    let mut state = core.get_locker_state(id);
                    assert(state.address == get_contract_address(), 'is locker');
                    assert(state.nonzero_delta_count == 1, '1 delta');

                    self.handle_delta(core, token, i129 { mag: amount, sign: true }, recipient);

                    state = core.get_locker_state(id);
                    assert(state.nonzero_delta_count == 0, '0 delta');

                    ActionResult::LoadBalance(balance_next)
                },
                Action::AccumulateAsFees((
                    pool_key, amount0, amount1
                )) => {
                    let delta = core.accumulate_as_fees(pool_key, amount0, amount1);

                    assert(delta.amount0.mag == amount0, 'delta0.amount');
                    assert(!delta.amount0.sign, 'delta0.sign');
                    assert(delta.amount1.mag == amount1, 'delta1.amount');
                    assert(!delta.amount1.sign, 'delta1.sign');

                    self
                        .handle_delta(
                            core, pool_key.token0, delta.amount0, contract_address_const::<0>()
                        );
                    self
                        .handle_delta(
                            core, pool_key.token1, delta.amount1, contract_address_const::<0>()
                        );

                    ActionResult::AccumulateAsFees(delta)
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
