use core::array::{ArrayTrait};
use core::serde::{Serde};
use ekubo::interfaces::core::{UpdatePositionParameters, SwapParameters, IExtension};
use ekubo::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
use ekubo::types::delta::{Delta};
use ekubo::types::i129::{i129};
use ekubo::types::keys::{PoolKey, PositionKey, SavedBalanceKey};
use starknet::{ContractAddress};

#[derive(Copy, Drop, Serde)]
pub enum Action {
    AssertLockerId: u32,
    Relock: (u32, u32), // expected id, number of relocks
    UpdatePosition: (PoolKey, UpdatePositionParameters, ContractAddress),
    Swap: (PoolKey, SwapParameters, ContractAddress),
    // save that amount of balance to the given address
    SaveBalance: (SavedBalanceKey, u128),
    // loads the balance to the address
    LoadBalance: (ContractAddress, felt252, u128, ContractAddress),
    // accumulates some tokens as fees
    AccumulateAsFees: (PoolKey, u128, u128),
    FlashBorrow: (ContractAddress, u128, u128),
}

#[derive(Copy, Drop, Serde)]
pub enum ActionResult {
    AssertLockerId,
    Relock,
    UpdatePosition: Delta,
    Swap: Delta,
    SaveBalance: u128,
    LoadBalance: u128,
    AccumulateAsFees: (),
    FlashBorrow: (),
}

#[starknet::interface]
pub trait ICoreLocker<TStorage> {
    fn call(ref self: TStorage, action: Action) -> ActionResult;
}

#[starknet::contract]
pub mod CoreLocker {
    use core::array::ArrayTrait;
    use core::num::traits::{Zero};
    use core::option::{Option, OptionTrait};
    use core::serde::Serde;
    use ekubo::components::shared_locker::{
        call_core_with_callback, consume_callback_data, handle_delta
    };
    use ekubo::components::util::{serialize};
    use ekubo::interfaces::core::{ICoreDispatcher, ICoreDispatcherTrait, ILocker};
    use ekubo::mock_erc20::{IMockERC20Dispatcher, IMockERC20DispatcherTrait};
    use ekubo::types::call_points::{CallPoints};
    use starknet::{
        ContractAddress, get_caller_address, get_contract_address, contract_address_const
    };
    use super::{
        Action, ActionResult, Delta, IERC20Dispatcher, IERC20DispatcherTrait, ICoreLockerDispatcher,
        ICoreLockerDispatcherTrait, i129, ICoreLocker, IExtension, SwapParameters,
        UpdatePositionParameters, PoolKey
    };

    #[storage]
    struct Storage {
        core: ICoreDispatcher
    }

    #[constructor]
    fn constructor(ref self: ContractState, core: ICoreDispatcher) {
        self.core.write(core);
    }

    #[abi(embed_v0)]
    impl ExtensionImpl of IExtension<ContractState> {
        fn before_initialize_pool(
            ref self: ContractState, caller: ContractAddress, pool_key: PoolKey, initial_tick: i129
        ) -> CallPoints {
            Default::default()
        }
        fn after_initialize_pool(
            ref self: ContractState, caller: ContractAddress, pool_key: PoolKey, initial_tick: i129
        ) {
            assert(false, 'never called');
        }

        fn before_swap(
            ref self: ContractState,
            caller: ContractAddress,
            pool_key: PoolKey,
            params: SwapParameters
        ) {
            assert(false, 'never called');
        }
        fn after_swap(
            ref self: ContractState,
            caller: ContractAddress,
            pool_key: PoolKey,
            params: SwapParameters,
            delta: Delta
        ) {
            assert(false, 'never called');
        }

        fn before_update_position(
            ref self: ContractState,
            caller: ContractAddress,
            pool_key: PoolKey,
            params: UpdatePositionParameters
        ) {
            assert(false, 'never called');
        }
        fn after_update_position(
            ref self: ContractState,
            caller: ContractAddress,
            pool_key: PoolKey,
            params: UpdatePositionParameters,
            delta: Delta
        ) {
            assert(false, 'never called');
        }
    }

    #[abi(embed_v0)]
    impl CoreLockerLockedImpl of ILocker<ContractState> {
        fn locked(ref self: ContractState, id: u32, data: Span<felt252>) -> Span<felt252> {
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

                    if (relock_count != Zero::zero()) {
                        // relock
                        ICoreLockerDispatcher { contract_address: get_contract_address() }
                            .call(Action::Relock((locker_id + 1, relock_count - 1)));
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
                            .nonzero_delta_count == ((if delta.amount0 == Zero::zero() {
                                0
                            } else {
                                1
                            })
                                + (if delta.amount1 == Zero::zero() {
                                    0
                                } else {
                                    1
                                })),
                        'deltas'
                    );

                    handle_delta(core, pool_key.token0, delta.amount0, recipient);

                    state = core.get_locker_state(id);
                    assert(
                        state
                            .nonzero_delta_count == (if delta.amount1 == Zero::zero() {
                                0
                            } else {
                                1
                            }),
                        'deltas'
                    );

                    handle_delta(core, pool_key.token1, delta.amount1, recipient);

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
                            .nonzero_delta_count == ((if delta.amount0 == Zero::zero() {
                                0
                            } else {
                                1
                            })
                                + (if delta.amount1 == Zero::zero() {
                                    0
                                } else {
                                    1
                                })),
                        'deltas'
                    );

                    handle_delta(core, pool_key.token0, delta.amount0, recipient);

                    state = core.get_locker_state(id);
                    assert(
                        state
                            .nonzero_delta_count == (if delta.amount1 == Zero::zero() {
                                0
                            } else {
                                1
                            }),
                        'deltas'
                    );

                    handle_delta(core, pool_key.token1, delta.amount1, recipient);

                    state = core.get_locker_state(id);
                    assert(state.nonzero_delta_count == 0, 'deltas');

                    ActionResult::Swap(delta)
                },
                Action::SaveBalance((
                    key, amount
                )) => {
                    let balance_next = core.save(key, amount);

                    let mut state = core.get_locker_state(id);
                    assert(state.address == get_contract_address(), 'is locker');
                    assert(state.nonzero_delta_count == 1, '1 delta');

                    handle_delta(core, key.token, i129 { mag: amount, sign: false }, Zero::zero());

                    state = core.get_locker_state(id);
                    assert(state.nonzero_delta_count == 0, '0 delta');

                    ActionResult::SaveBalance(balance_next)
                },
                Action::LoadBalance((
                    token, salt, amount, recipient
                )) => {
                    let balance_next = core.load(token, salt, amount);

                    let mut state = core.get_locker_state(id);
                    assert(state.address == get_contract_address(), 'is locker');
                    assert(state.nonzero_delta_count == 1, '1 delta');

                    handle_delta(core, token, i129 { mag: amount, sign: true }, recipient);

                    state = core.get_locker_state(id);
                    assert(state.nonzero_delta_count == 0, '0 delta');

                    ActionResult::LoadBalance(balance_next)
                },
                Action::AccumulateAsFees((
                    pool_key, amount0, amount1
                )) => {
                    core.accumulate_as_fees(pool_key, amount0, amount1);

                    handle_delta(
                        core,
                        pool_key.token0,
                        i129 { mag: amount0, sign: false },
                        contract_address_const::<0>()
                    );
                    handle_delta(
                        core,
                        pool_key.token1,
                        i129 { mag: amount1, sign: false },
                        contract_address_const::<0>()
                    );

                    ActionResult::AccumulateAsFees
                },
                Action::FlashBorrow((
                    token, amount_borrow, amount_repay
                )) => {
                    if (amount_borrow.is_non_zero()) {
                        core.withdraw(token, get_contract_address(), amount_borrow);
                    }

                    if (amount_repay.is_non_zero()) {
                        IERC20Dispatcher { contract_address: token }
                            .approve(core.contract_address, amount_repay.into());
                        core.pay(token);
                    }

                    ActionResult::FlashBorrow(())
                }
            };

            serialize(@result).span()
        }
    }

    #[abi(embed_v0)]
    impl CoreLockerImpl of ICoreLocker<ContractState> {
        fn call(ref self: ContractState, action: Action) -> ActionResult {
            call_core_with_callback(self.core.read(), @action)
        }
    }
}
