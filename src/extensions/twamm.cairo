pub mod math;
#[cfg(test)]
pub(crate) mod twamm_math_test;

#[cfg(test)]
pub(crate) mod twamm_test;

use core::num::traits::{Zero};
use core::traits::{Into, TryInto};
use ekubo::types::i129::{i129, i129Trait};
use ekubo::types::keys::{PoolKey};
use starknet::{ContractAddress, ClassHash};

#[derive(Drop, Copy, Serde, Hash)]
pub struct OrderKey {
    pub sell_token: ContractAddress,
    pub buy_token: ContractAddress,
    pub fee: u128,
    pub start_time: u64,
    pub end_time: u64
}

#[derive(Drop, Copy, Serde, PartialEq)]
pub struct OrderState {
    sale_rate: u128,
    reward_rate: felt252,
    use_snapshot: bool
}

impl OrderStateStorePacking of starknet::storage_access::StorePacking<
    OrderState, (felt252, felt252)
> {
    fn pack(value: OrderState) -> (felt252, felt252) {
        (
            u256 { low: value.sale_rate, high: if value.use_snapshot {
                1
            } else {
                0
            } }
                .try_into()
                .unwrap(),
            value.reward_rate
        )
    }
    fn unpack(value: (felt252, felt252)) -> OrderState {
        let (sale_rate_use_snapshot, reward_rate) = value;
        let sale_rate_use_snapshot_u256: u256 = sale_rate_use_snapshot.into();

        OrderState {
            sale_rate: sale_rate_use_snapshot_u256.low,
            reward_rate,
            use_snapshot: sale_rate_use_snapshot_u256.high.is_non_zero(),
        }
    }
}

pub impl OrderStateZero of Zero<OrderState> {
    #[inline(always)]
    fn zero() -> OrderState {
        OrderState { sale_rate: Zero::zero(), reward_rate: Zero::zero(), use_snapshot: false }
    }

    #[inline(always)]
    fn is_zero(self: @OrderState) -> bool {
        self.sale_rate.is_zero()
    }

    #[inline(always)]
    fn is_non_zero(self: @OrderState) -> bool {
        !self.sale_rate.is_zero()
    }
}

#[derive(Serde, Drop, Copy, Hash)]
pub struct StateKey {
    pub token0: ContractAddress,
    pub token1: ContractAddress,
    pub fee: u128,
}

#[starknet::interface]
pub trait ITWAMM<TContractState> {
    // Return the stored order state
    fn get_order_state(
        self: @TContractState, owner: ContractAddress, order_key: OrderKey, id: felt252
    ) -> OrderState;

    // Returns the current sale rate 
    fn get_sale_rate(self: @TContractState, key: StateKey) -> (u128, u128);

    // Return the current reward rate
    fn get_reward_rate(self: @TContractState, key: StateKey) -> (felt252, felt252);

    // Return the sale rate net for a specific time
    fn get_sale_rate_net(self: @TContractState, key: StateKey, time: u64) -> (u128, u128);

    // Return the sale rate delta for a specific time
    fn get_sale_rate_delta(self: @TContractState, key: StateKey, time: u64) -> (i129, i129);

    // Return the next virtual order time
    fn get_next_virtual_order_time(
        self: @TContractState, key: StateKey, max_time: u64
    ) -> (u64, u64);

    // Update an existing twamm order
    fn update_order(
        ref self: TContractState, order_key: OrderKey, id: felt252, sale_rate_delta: i129
    );

    // Collect proceeds from a twamm order
    fn collect_proceeds(ref self: TContractState, order_key: OrderKey, id: felt252);

    // Execute virtual orders
    fn execute_virtual_orders(ref self: TContractState, key: StateKey);
}

#[starknet::contract]
pub mod TWAMM {
    use core::cmp::{max, min};
    use core::hash::{LegacyHash};
    use core::num::traits::{Zero};
    use core::option::{OptionTrait};
    use core::traits::{TryInto, Into};
    use ekubo::components::owned::{Owned as owned_component};
    use ekubo::components::shared_locker::{call_core_with_callback, consume_callback_data};
    use ekubo::components::upgradeable::{Upgradeable as upgradeable_component, IHasInterface};
    use ekubo::interfaces::core::{
        IExtension, SwapParameters, UpdatePositionParameters, ILocker, ICoreDispatcher,
        ICoreDispatcherTrait
    };
    use ekubo::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use ekubo::interfaces::upgradeable::{
        IUpgradeable, IUpgradeableDispatcher, IUpgradeableDispatcherTrait
    };
    use ekubo::math::bitmap::{Bitmap, BitmapTrait};
    use ekubo::math::fee::{compute_fee};
    use ekubo::math::ticks::constants::{MAX_TICK_SPACING};
    use ekubo::math::ticks::{min_sqrt_ratio, max_sqrt_ratio};
    use ekubo::owned_nft::{OwnedNFT, IOwnedNFTDispatcher, IOwnedNFTDispatcherTrait};
    use ekubo::types::bounds::{max_bounds};
    use ekubo::types::call_points::{CallPoints};
    use ekubo::types::delta::{Delta};
    use ekubo::types::i129::{i129, i129Trait, AddDeltaTrait};
    use ekubo::types::keys::{PoolKey, PoolKeyTrait, SavedBalanceKey};
    use starknet::{
        Store, get_contract_address, get_caller_address, syscalls::{replace_class_syscall},
        get_block_timestamp, ClassHash, storage_access::{storage_base_address_from_felt252}
    };
    use super::math::{
        constants, calculate_sale_rate, calculate_reward_rate_deltas, calculate_reward_amount,
        validate_time, calculate_next_sqrt_ratio, calculate_amount_from_sale_rate,
        calculate_reward_rate
    };
    use super::{ITWAMM, StateKey, ContractAddress, OrderKey, OrderState};

    #[abi(embed_v0)]
    impl Clear = ekubo::components::clear::ClearImpl<ContractState>;

    component!(path: owned_component, storage: owned, event: OwnedEvent);
    #[abi(embed_v0)]
    impl Owned = owned_component::OwnedImpl<ContractState>;
    impl OwnableImpl = owned_component::OwnableImpl<ContractState>;

    component!(path: upgradeable_component, storage: upgradeable, event: UpgradeableEvent);
    #[abi(embed_v0)]
    impl Upgradeable = upgradeable_component::UpgradeableImpl<ContractState>;

    #[storage]
    struct Storage {
        core: ICoreDispatcher,
        orders: LegacyMap<(ContractAddress, OrderKey, felt252), OrderState>,
        sale_rate: LegacyMap<StateKey, (u128, u128)>,
        time_sale_rate_net: LegacyMap<(StateKey, u64), (u128, u128)>,
        time_sale_rate_delta: LegacyMap<(StateKey, u64), (i129, i129)>,
        time_sale_rate_bitmaps: LegacyMap<(StateKey, u128), Bitmap>,
        reward_rate: LegacyMap<StateKey, (felt252, felt252)>,
        time_reward_rate: LegacyMap<(StateKey, u64), (felt252, felt252)>,
        last_virtual_order_time: LegacyMap<StateKey, u64>,
        #[substorage(v0)]
        upgradeable: upgradeable_component::Storage,
        #[substorage(v0)]
        owned: owned_component::Storage,
    }

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress, core: ICoreDispatcher) {
        self.initialize_owned(owner);
        self.core.write(core);
    }

    #[derive(starknet::Event, Drop)]
    pub struct OrderUpdated {
        pub owner: ContractAddress,
        pub order_key: OrderKey,
        pub id: felt252,
        pub sale_rate_delta: i129
    }

    #[derive(starknet::Event, Drop)]
    pub struct OrderProceedsWithdrawn {
        pub owner: ContractAddress,
        pub order_key: OrderKey,
        pub id: felt252,
        pub amount: u128
    }

    #[derive(starknet::Event, Drop)]
    pub struct VirtualOrdersExecuted {
        pub last_virtual_order_time: u64,
        pub next_virtual_order_time: u64,
        pub token0_sale_rate: u128,
        pub token1_sale_rate: u128,
        pub token0_reward_rate: felt252,
        pub token1_reward_rate: felt252
    }

    #[derive(starknet::Event, Drop)]
    #[event]
    enum Event {
        #[flat]
        UpgradeableEvent: upgradeable_component::Event,
        OwnedEvent: owned_component::Event,
        OrderUpdated: OrderUpdated,
        OrderProceedsWithdrawn: OrderProceedsWithdrawn,
        VirtualOrdersExecuted: VirtualOrdersExecuted,
    }

    #[derive(Serde, Copy, Drop)]
    struct UpdateSaleRateCallbackData {
        owner: ContractAddress,
        order_key: OrderKey,
        id: felt252,
        sale_rate_delta: i129
    }

    #[derive(Serde, Copy, Drop)]
    struct WithdrawProceedsCallbackData {
        owner: ContractAddress,
        order_key: OrderKey,
        id: felt252,
    }

    #[derive(Serde, Copy, Drop)]
    enum LockCallbackData {
        ExecuteVirtualSwapsCallbackData: StateKey,
        UpdateSaleRateCallbackData: UpdateSaleRateCallbackData,
        WithdrawProceedsCallbackData: WithdrawProceedsCallbackData
    }

    #[derive(Serde, Copy, Drop)]
    enum LockCallbackResult {
        Empty: (),
    }

    #[abi(embed_v0)]
    impl TWAMMHasInterface of IHasInterface<ContractState> {
        fn get_primary_interface_id(self: @ContractState) -> felt252 {
            return selector!("ekubo::extensions::twamm::TWAMM");
        }
    }

    #[abi(embed_v0)]
    impl ExtensionImpl of IExtension<ContractState> {
        fn before_initialize_pool(
            ref self: ContractState, caller: ContractAddress, pool_key: PoolKey, initial_tick: i129
        ) -> CallPoints {
            assert(pool_key.tick_spacing == MAX_TICK_SPACING, 'TICK_SPACING');

            CallPoints {
                after_initialize_pool: false,
                before_swap: true,
                after_swap: false,
                before_update_position: true,
                after_update_position: false,
            }
        }

        fn after_initialize_pool(
            ref self: ContractState, caller: ContractAddress, pool_key: PoolKey, initial_tick: i129
        ) {
            assert(false, 'NOT_USED');
        }

        fn before_swap(
            ref self: ContractState,
            caller: ContractAddress,
            pool_key: PoolKey,
            params: SwapParameters
        ) {
            self
                .execute_virtual_orders(
                    StateKey { token0: pool_key.token0, token1: pool_key.token1, fee: pool_key.fee }
                );
        }

        fn after_swap(
            ref self: ContractState,
            caller: ContractAddress,
            pool_key: PoolKey,
            params: SwapParameters,
            delta: Delta
        ) {
            assert(false, 'NOT_USED');
        }

        fn before_update_position(
            ref self: ContractState,
            caller: ContractAddress,
            pool_key: PoolKey,
            params: UpdatePositionParameters
        ) {
            assert(params.bounds == max_bounds(pool_key.tick_spacing), 'BOUNDS');
            self
                .execute_virtual_orders(
                    StateKey { token0: pool_key.token0, token1: pool_key.token1, fee: pool_key.fee }
                );
        }

        fn after_update_position(
            ref self: ContractState,
            caller: ContractAddress,
            pool_key: PoolKey,
            params: UpdatePositionParameters,
            delta: Delta
        ) {
            assert(false, 'NOT_USED');
        }
    }

    #[abi(embed_v0)]
    impl TWAMMImpl of ITWAMM<ContractState> {
        fn get_order_state(
            self: @ContractState, owner: ContractAddress, order_key: OrderKey, id: felt252
        ) -> OrderState {
            self.orders.read((owner, order_key, id))
        }

        fn get_sale_rate(self: @ContractState, key: StateKey) -> (u128, u128) {
            self.sale_rate.read(key.into())
        }

        fn get_reward_rate(self: @ContractState, key: StateKey) -> (felt252, felt252) {
            self.reward_rate.read(key.into())
        }

        fn get_sale_rate_net(self: @ContractState, key: StateKey, time: u64) -> (u128, u128) {
            self.time_sale_rate_net.read((key.into(), time))
        }

        fn get_sale_rate_delta(self: @ContractState, key: StateKey, time: u64) -> (i129, i129) {
            self.time_sale_rate_delta.read((key.into(), time))
        }

        fn get_next_virtual_order_time(
            self: @ContractState, key: StateKey, max_time: u64
        ) -> (u64, u64) {
            let last_virtual_order_time = self.last_virtual_order_time.read(key.into());

            assert(max_time > last_virtual_order_time, 'INVALID_MAX_TIME');

            (
                last_virtual_order_time,
                self.next_initialized_time(key.into(), last_virtual_order_time, max_time)
            )
        }

        fn update_order(
            ref self: ContractState, order_key: OrderKey, id: felt252, sale_rate_delta: i129
        ) {
            match call_core_with_callback::<
                LockCallbackData, LockCallbackResult
            >(
                self.core.read(),
                @LockCallbackData::UpdateSaleRateCallbackData(
                    UpdateSaleRateCallbackData {
                        owner: get_caller_address(), order_key, id, sale_rate_delta
                    }
                )
            ) {
                LockCallbackResult::Empty => {},
            }
        }

        fn collect_proceeds(ref self: ContractState, order_key: OrderKey, id: felt252) {
            match call_core_with_callback::<
                LockCallbackData, LockCallbackResult
            >(
                self.core.read(),
                @LockCallbackData::WithdrawProceedsCallbackData(
                    WithdrawProceedsCallbackData { owner: get_caller_address(), order_key, id }
                )
            ) {
                LockCallbackResult::Empty => {},
            }
        }

        #[inline(always)]
        fn execute_virtual_orders(ref self: ContractState, key: StateKey) {
            match call_core_with_callback::<
                LockCallbackData, LockCallbackResult
            >(self.core.read(), @LockCallbackData::ExecuteVirtualSwapsCallbackData({
                key
            })) {
                LockCallbackResult::Empty => {},
            }
        }
    }

    #[abi(embed_v0)]
    impl LockerImpl of ILocker<ContractState> {
        fn locked(ref self: ContractState, id: u32, data: Span<felt252>) -> Span<felt252> {
            let core = self.core.read();

            let result: LockCallbackResult =
                match consume_callback_data::<LockCallbackData>(core, data) {
                LockCallbackData::ExecuteVirtualSwapsCallbackData(key) => {
                    self.internal_execute_virtual_orders(core, key);
                    LockCallbackResult::Empty
                },
                LockCallbackData::UpdateSaleRateCallbackData(data) => {
                    let owner = data.owner;
                    let order_key = data.order_key;
                    let id = data.id;
                    let sale_rate_delta = data.sale_rate_delta;

                    self.internal_execute_virtual_orders(core, order_key.into());

                    let current_time = get_block_timestamp();
                    assert(order_key.end_time > current_time, 'ORDER_ENDED');

                    let order_state = self.orders.read((owner, order_key, id));

                    let order_started = order_key.start_time <= current_time;

                    if (order_state.is_zero()) {
                        // validate end time if order is being created 
                        validate_time(current_time, order_key.end_time);

                        if (!order_started) {
                            // validate start time if order is starting in the future 
                            validate_time(current_time, order_key.start_time);
                        }
                    }

                    // assert sale rate will not be negative
                    assert(
                        !sale_rate_delta.sign || sale_rate_delta.mag <= order_state.sale_rate,
                        'INVALID_SALE_RATE_DELTA'
                    );

                    self
                        .update_order_sale_rate(
                            owner, order_key, id, order_state, sale_rate_delta, order_started
                        );

                    let amount_delta = calculate_amount_from_sale_rate(
                        sale_rate_delta.mag,
                        max(order_key.start_time, current_time),
                        order_key.end_time,
                    );

                    let token = order_key.sell_token;

                    if (sale_rate_delta.sign) {
                        // if decreasing sale rate, pay fee and withdraw funds

                        core.load(token, 0, amount_delta);

                        let key: StateKey = order_key.into();

                        if (core.get_pool_liquidity(key.into()).is_non_zero()) {
                            let fee_amount = compute_fee(amount_delta, key.fee);

                            let (amount0, amount1) = if (order_key
                                .sell_token > order_key
                                .buy_token) {
                                (0, fee_amount)
                            } else {
                                (fee_amount, 0)
                            };

                            core.accumulate_as_fees(key.into(), amount0, amount1);
                            core.withdraw(token, get_contract_address(), amount_delta - fee_amount);
                        } else {
                            core.withdraw(token, get_contract_address(), amount_delta);
                        }
                    } else {
                        // if increasing sale rate, deposit additional funds
                        IERC20Dispatcher { contract_address: token }
                            .approve(core.contract_address, amount_delta.into());

                        core.pay(token);

                        core
                            .save(
                                SavedBalanceKey {
                                    owner: get_contract_address(), token: token, salt: 0
                                },
                                amount_delta
                            );
                    }

                    LockCallbackResult::Empty
                },
                LockCallbackData::WithdrawProceedsCallbackData(data) => {
                    let owner = data.owner;
                    let order_key = data.order_key;
                    let id = data.id;
                    let current_time = get_block_timestamp();

                    assert(
                        order_key.start_time == 0 || order_key.start_time < current_time,
                        'NOT_STARTED'
                    );

                    self.internal_execute_virtual_orders(core, data.order_key.into());

                    let order_state = self.orders.read((owner, order_key, id));

                    // order has been cancelled
                    assert(order_state.sale_rate > 0, 'ZERO_SALE_RATE');

                    let order_reward_rate = if (order_state.use_snapshot) {
                        order_state.reward_rate
                    } else {
                        self.get_reward_rate_at(order_key, order_key.start_time)
                    };

                    let purchased_amount = if (current_time >= order_key.end_time) {
                        // update order state to reflect that the order has been fully executed
                        self.orders.write((owner, order_key, id), Zero::zero());

                        // reward rate at expiration/full-execution time
                        let total_reward_rate = self
                            .get_reward_rate_at(order_key, order_key.end_time)
                            - order_reward_rate;
                        calculate_reward_amount(total_reward_rate, order_state.sale_rate)
                    } else {
                        let current_reward_rate = self.get_current_reward_rate(order_key);
                        // update order state to reflect that the order has been partially executed
                        self
                            .orders
                            .write(
                                (owner, order_key, id),
                                OrderState {
                                    sale_rate: order_state.sale_rate,
                                    reward_rate: current_reward_rate,
                                    use_snapshot: true,
                                }
                            );

                        calculate_reward_amount(
                            current_reward_rate - order_reward_rate, order_state.sale_rate
                        )
                    };

                    if (purchased_amount.is_non_zero()) {
                        let token = order_key.buy_token;

                        core.load(token, 0, purchased_amount);
                        core.withdraw(token, get_contract_address(), purchased_amount);
                    }

                    self
                        .emit(
                            OrderProceedsWithdrawn {
                                owner, order_key, id, amount: purchased_amount
                            }
                        );
                    LockCallbackResult::Empty
                }
            };

            let mut result_data = ArrayTrait::new();
            Serde::serialize(@result, ref result_data);
            result_data.span()
        }
    }

    #[generate_trait]
    impl Internal of InternalTrait {
        fn update_order_sale_rate(
            ref self: ContractState,
            owner: ContractAddress,
            order_key: OrderKey,
            id: felt252,
            order_state: OrderState,
            sale_rate_delta: i129,
            order_started: bool
        ) {
            let current_time = get_block_timestamp();
            assert(order_key.end_time > current_time, 'ORDER_ENDED');

            let sale_rate_next = order_state.sale_rate.add(sale_rate_delta);

            let (reward_rate, use_snapshot, order_start_time) = if (sale_rate_next.is_zero()) {
                let order_reward_rate = if (order_state.use_snapshot) {
                    order_state.reward_rate
                } else {
                    self.get_reward_rate_at(order_key, order_key.start_time)
                };

                // all proceeds must be withdrawn before order is cancelled
                assert(
                    self.get_current_reward_rate(order_key) == order_reward_rate
                        || order_key.start_time > current_time,
                    'MUST_WITHDRAW_PROCEEDS'
                );

                // zero out the state
                (0, false, order_key.start_time)
            } else if (order_started) {
                let current_reward_rate = self.get_current_reward_rate(order_key);

                let current_order_reward_rate = current_reward_rate - order_state.reward_rate;

                let adjusted_reward_rate = if (current_order_reward_rate == 0) {
                    order_state.reward_rate
                } else {
                    let token_reward_amount = calculate_reward_amount(
                        current_reward_rate, order_state.sale_rate
                    );

                    let adjusted_reward_rate = calculate_reward_rate(
                        token_reward_amount, sale_rate_next
                    );

                    current_order_reward_rate - adjusted_reward_rate
                };

                (adjusted_reward_rate, true, current_time)
            } else {
                (0, false, order_key.start_time)
            };

            self
                .orders
                .write(
                    (owner, order_key, id),
                    OrderState {
                        sale_rate: sale_rate_next,
                        reward_rate: reward_rate,
                        use_snapshot: use_snapshot,
                    }
                );

            self.emit(OrderUpdated { owner, order_key, id, sale_rate_delta: sale_rate_delta });

            if (order_started) {
                self.update_global_sale_rate(order_key, sale_rate_delta);
            } else {
                self.update_time(order_key, order_start_time, sale_rate_delta, true);
            }

            self.update_time(order_key, order_key.end_time, sale_rate_delta, false);
        }

        fn update_time(
            ref self: ContractState,
            order_key: OrderKey,
            time: u64,
            sale_rate_delta: i129,
            is_start_time: bool
        ) {
            let key: StateKey = order_key.into();
            let (token0_sale_rate_delta, token1_sale_rate_delta) = self
                .time_sale_rate_delta
                .read((key, time));

            if (order_key.sell_token > order_key.buy_token) {
                let next_sale_rate_delta = if (is_start_time) {
                    token1_sale_rate_delta + sale_rate_delta
                } else {
                    token1_sale_rate_delta - sale_rate_delta
                };
                self
                    .time_sale_rate_delta
                    .write((key, time), (token0_sale_rate_delta, next_sale_rate_delta));
            } else {
                let next_sale_rate_delta = if (is_start_time) {
                    token0_sale_rate_delta + sale_rate_delta
                } else {
                    token0_sale_rate_delta - sale_rate_delta
                };
                self
                    .time_sale_rate_delta
                    .write((key, time), (next_sale_rate_delta, token1_sale_rate_delta));
            }

            let (token0_sale_rate_net, token1_sale_rate_net) = self
                .time_sale_rate_net
                .read((key, time));

            let (current_sale_rate_net, next_sale_rate_net, other_token_sale_rate_net) =
                if (order_key
                .sell_token > order_key
                .buy_token) {
                let next_sale_rate_net = token1_sale_rate_net.add(sale_rate_delta);
                self
                    .time_sale_rate_net
                    .write((key, time), (token0_sale_rate_net, next_sale_rate_net));
                (token1_sale_rate_net, next_sale_rate_net, token0_sale_rate_net)
            } else {
                let next_sale_rate_net = token0_sale_rate_net.add(sale_rate_delta);
                self
                    .time_sale_rate_net
                    .write((key, time), (next_sale_rate_net, token1_sale_rate_net));
                (token0_sale_rate_net, next_sale_rate_net, token1_sale_rate_net)
            };

            if ((next_sale_rate_net == 0) != (current_sale_rate_net == 0)
                && other_token_sale_rate_net == 0) {
                if (next_sale_rate_net == 0) {
                    self.remove_initialized_time(key, time);
                } else {
                    self.insert_initialized_time(key, time);
                }
            };
        }

        fn update_global_sale_rate(
            ref self: ContractState, order_key: OrderKey, sale_rate_delta: i129
        ) {
            let key: StateKey = order_key.into();
            let (token0_sale_rate, token1_sale_rate) = self.sale_rate.read(key);

            self
                .sale_rate
                .write(
                    key,
                    if (order_key.sell_token > order_key.buy_token) {
                        (token0_sale_rate, token1_sale_rate.add(sale_rate_delta))
                    } else {
                        (token0_sale_rate.add(sale_rate_delta), token1_sale_rate)
                    }
                );
        }

        fn get_current_reward_rate(self: @ContractState, order_key: OrderKey) -> felt252 {
            let key: StateKey = order_key.into();
            let (token0_reward_rate, token1_reward_rate) = self.reward_rate.read(key.into());

            if (order_key.sell_token > order_key.buy_token) {
                token0_reward_rate
            } else {
                token1_reward_rate
            }
        }

        fn get_reward_rate_at(self: @ContractState, order_key: OrderKey, time: u64) -> felt252 {
            let key: StateKey = order_key.into();

            let (token0_reward_rate, token1_reward_rate) = self
                .time_reward_rate
                .read((key.into(), time));

            if (order_key.sell_token > order_key.buy_token) {
                token0_reward_rate
            } else {
                token1_reward_rate
            }
        }

        fn update_reward_rate(
            ref self: ContractState,
            key: StateKey,
            sale_rates: (u128, u128),
            delta: Delta,
            time: u64
        ) -> (felt252, felt252) {
            let (token0_reward_delta, token1_reward_delta) = calculate_reward_rate_deltas(
                sale_rates, delta
            );

            let (current_token0_reward_rate, current_token1_reward_rate) = self
                .reward_rate
                .read(key);

            let reward_rate = (
                current_token0_reward_rate + token0_reward_delta,
                current_token1_reward_rate + token1_reward_delta
            );

            self.reward_rate.write(key, reward_rate);

            let (token0_reward_rate, token1_reward_rate) = reward_rate;

            self.time_reward_rate.write((key, time), (token0_reward_rate, token1_reward_rate));

            reward_rate
        }

        fn update_token_sale_rate_and_rewards(
            ref self: ContractState, key: StateKey, sale_rates: (u128, u128), time: u64
        ) {
            let (token0_sale_rate, token1_sale_rate) = sale_rates;

            let (token0_sale_rate_delta, token1_sale_rate_delta) = self
                .time_sale_rate_delta
                .read((key, time));

            if (token0_sale_rate_delta.mag > 0 || token1_sale_rate_delta.mag > 0) {
                self
                    .sale_rate
                    .write(
                        key,
                        (
                            (i129 { mag: token0_sale_rate, sign: false } + token0_sale_rate_delta)
                                .mag,
                            (i129 { mag: token1_sale_rate, sign: false } + token1_sale_rate_delta)
                                .mag
                        )
                    );

                let (token0_reward_rate, token1_reward_rate) = self.reward_rate.read(key);

                self.time_reward_rate.write((key, time), (token0_reward_rate, token1_reward_rate));
            }
        }

        fn remove_initialized_time(ref self: ContractState, key: StateKey, time: u64) {
            let (word_index, bit_index) = time_to_word_and_bit_index(time);

            let bitmap = self.time_sale_rate_bitmaps.read((key, word_index));

            // it is assumed that bitmap already contains the set bit exp2(bit_index)
            self.time_sale_rate_bitmaps.write((key, word_index), bitmap.unset_bit(bit_index));
        }

        fn insert_initialized_time(ref self: ContractState, key: StateKey, time: u64) {
            let (word_index, bit_index) = time_to_word_and_bit_index(time);

            let bitmap = self.time_sale_rate_bitmaps.read((key, word_index));

            self.time_sale_rate_bitmaps.write((key, word_index), bitmap.set_bit(bit_index));
        }

        fn next_initialized_time(
            self: @ContractState, key: StateKey, from: u64, max_time: u64
        ) -> u64 {
            self
                .prefix_next_initialized_time(
                    LegacyHash::hash(selector!("time_sale_rate_bitmaps"), key), from, max_time
                )
        }

        fn prefix_next_initialized_time(
            self: @ContractState, prefix: felt252, from: u64, max_time: u64
        ) -> u64 {
            let (word_index, bit_index) = time_to_word_and_bit_index(
                from + constants::BITMAP_SPACING
            );

            let bitmap: Bitmap = Store::read(
                0, storage_base_address_from_felt252(LegacyHash::hash(prefix, word_index))
            )
                .expect('BITMAP_READ_FAILED');

            match bitmap.next_set_bit(bit_index) {
                Option::Some(next_bit) => { word_and_bit_index_to_time((word_index, next_bit)) },
                Option::None => {
                    let next = word_and_bit_index_to_time((word_index, 0));

                    if (next > max_time) {
                        max_time
                    } else {
                        self.prefix_next_initialized_time(prefix, next, max_time)
                    }
                },
            }
        }

        fn deposit(
            ref self: ContractState, core: ICoreDispatcher, token: ContractAddress, amount: u128
        ) {
            IERC20Dispatcher { contract_address: token }
                .approve(core.contract_address, amount.into());

            core.pay(token);

            core
                .save(
                    SavedBalanceKey { owner: get_contract_address(), token: token, salt: 0 }, amount
                );
        }

        fn internal_execute_virtual_orders(
            ref self: ContractState, core: ICoreDispatcher, key: StateKey
        ) {
            let pool_key: PoolKey = key.into();
            let key: StateKey = key.into();

            // since virtual orders are executed at the same time for both tokens,
            // last_virtual_order_time is the same for both tokens.
            let mut last_virtual_order_time = self.last_virtual_order_time.read(key.into());

            let current_time = get_block_timestamp();

            let self_snap = @self;

            if (last_virtual_order_time == 0) {
                // we haven't executed any virtual orders yet, and no orders have been placed
                self.last_virtual_order_time.write(key, current_time);
            } else if (last_virtual_order_time != current_time) {
                let mut total_delta = Zero::<Delta>::zero();
                let mut token_reward_rate = (0, 0);

                loop {
                    let mut delta = Zero::zero();

                    // find next time with a sale rate delta
                    let next_initialized_time = self_snap
                        .next_initialized_time(key, last_virtual_order_time, current_time);

                    let next_virtual_order_time = min(current_time, next_initialized_time);

                    let (token0_sale_rate, token1_sale_rate) = self.sale_rate.read(key);

                    if (token0_sale_rate > 0 || token1_sale_rate > 0) {
                        let price = core.get_pool_price(pool_key);

                        if price.sqrt_ratio != 0 {
                            let time_elapsed = next_virtual_order_time - last_virtual_order_time;

                            let token0_amount = (token0_sale_rate * time_elapsed.into())
                                / constants::X32_u128;
                            let token1_amount = (token1_sale_rate * time_elapsed.into())
                                / constants::X32_u128;

                            if (token0_amount != 0 && token1_amount != 0) {
                                let sqrt_ratio_limit = calculate_next_sqrt_ratio(
                                    price.sqrt_ratio,
                                    core.get_pool_liquidity(pool_key),
                                    token0_sale_rate,
                                    token1_sale_rate,
                                    time_elapsed
                                );

                                let is_token1 = price.sqrt_ratio < sqrt_ratio_limit;

                                // swap up/down to sqrt_ratio_limit
                                delta = core
                                    .swap(
                                        pool_key,
                                        SwapParameters {
                                            amount: i129 {
                                                mag: 0xffffffffffffffffffffffffffffffff, sign: false
                                            },
                                            is_token1: is_token1,
                                            sqrt_ratio_limit,
                                            skip_ahead: 0
                                        }
                                    );

                                // update reward rate
                                token_reward_rate = self
                                    .update_reward_rate(
                                        key,
                                        (token0_sale_rate, token1_sale_rate),
                                        delta
                                            + Delta {
                                                amount0: i129 { mag: token0_amount, sign: true },
                                                amount1: i129 { mag: token1_amount, sign: true }
                                            },
                                        next_virtual_order_time
                                    );
                            } else {
                                let (amount, is_token1, sqrt_ratio_limit) = if token0_amount > 0 {
                                    (token0_amount, false, min_sqrt_ratio())
                                } else {
                                    (token1_amount, true, max_sqrt_ratio())
                                };

                                delta = core
                                    .swap(
                                        pool_key,
                                        SwapParameters {
                                            amount: i129 { mag: amount, sign: false },
                                            is_token1,
                                            sqrt_ratio_limit,
                                            skip_ahead: 0
                                        }
                                    );

                                // update reward rate
                                token_reward_rate = self
                                    .update_reward_rate(
                                        key,
                                        (token0_sale_rate, token1_sale_rate),
                                        delta,
                                        next_virtual_order_time
                                    );
                            }

                            // accumulate deltas
                            total_delta += delta;

                            let (token0_reward_rate, token1_reward_rate) = token_reward_rate;

                            self
                                .emit(
                                    VirtualOrdersExecuted {
                                        last_virtual_order_time,
                                        next_virtual_order_time,
                                        token0_sale_rate: token0_sale_rate,
                                        token1_sale_rate: token1_sale_rate,
                                        token0_reward_rate: token0_reward_rate,
                                        token1_reward_rate: token1_reward_rate
                                    }
                                );
                        }
                    }

                    let (token0_sale_rate_net, token1_sale_rate_net) = self
                        .time_sale_rate_net
                        .read((key, next_virtual_order_time));

                    // update ending sale rates 
                    if (token0_sale_rate_net != 0 || token1_sale_rate_net != 0) {
                        self
                            .update_token_sale_rate_and_rewards(
                                key, (token0_sale_rate, token1_sale_rate), next_virtual_order_time
                            );
                    }

                    // update last_virtual_order_time to next_virtual_order_time
                    last_virtual_order_time = next_virtual_order_time;

                    // virtual orders were executed up to current time
                    if next_virtual_order_time == current_time {
                        break;
                    }
                };

                self.last_virtual_order_time.write(key, last_virtual_order_time);

                // zero out deltas
                if (total_delta.amount0.mag > 0) {
                    if (total_delta.amount0.sign) {
                        core
                            .save(
                                SavedBalanceKey {
                                    owner: get_contract_address(), token: pool_key.token0, salt: 0
                                },
                                total_delta.amount0.mag
                            );
                    } else {
                        core.load(pool_key.token0, 0, total_delta.amount0.mag);
                    }
                }
                if (total_delta.amount1.mag > 0) {
                    if (total_delta.amount1.sign) {
                        core
                            .save(
                                SavedBalanceKey {
                                    owner: get_contract_address(), token: pool_key.token1, salt: 0
                                },
                                total_delta.amount1.mag
                            );
                    } else {
                        core.load(pool_key.token1, 0, total_delta.amount1.mag);
                    }
                }
            }
        }
    }

    pub fn time_to_word_and_bit_index(time: u64) -> (u128, u8) {
        (
            (time / (constants::BITMAP_SPACING * 251)).into(),
            250_u8 - ((time / constants::BITMAP_SPACING) % 251).try_into().unwrap()
        )
    }

    pub fn word_and_bit_index_to_time(word_and_bit_index: (u128, u8)) -> u64 {
        let (word, bit) = word_and_bit_index;
        ((word * 251 * constants::BITMAP_SPACING.into())
            + ((250 - bit).into() * constants::BITMAP_SPACING.into()))
            .try_into()
            .unwrap()
    }

    impl OrderKeyIntoStateKey of Into<OrderKey, StateKey> {
        fn into(self: OrderKey) -> StateKey {
            let (token0, token1) = if (self.sell_token > self.buy_token) {
                (self.buy_token, self.sell_token)
            } else {
                (self.sell_token, self.buy_token)
            };

            StateKey { token0, token1, fee: self.fee, }
        }
    }

    impl StateKeyIntoPoolKey of Into<StateKey, PoolKey> {
        fn into(self: StateKey) -> PoolKey {
            PoolKey {
                token0: self.token0,
                token1: self.token1,
                fee: self.fee,
                tick_spacing: MAX_TICK_SPACING,
                extension: get_contract_address()
            }
        }
    }
}
