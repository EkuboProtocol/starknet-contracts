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

#[derive(Serde, Drop, Copy)]
pub struct StateKey {
    pub token0: ContractAddress,
    pub token1: ContractAddress,
    pub fee: u128,
}

#[starknet::interface]
pub trait ITWAMM<TContractState> {
    fn get_last_virtual_order_time(self: @TContractState, key: StateKey) -> u64;

    // Return the stored order state
    fn get_order_state(
        self: @TContractState, owner: ContractAddress, salt: felt252, order_key: OrderKey
    ) -> OrderState;

    // Returns the current sale rate 
    fn get_sale_rate(self: @TContractState, key: StateKey) -> (u128, u128);

    // Return the current reward rate
    fn get_reward_rate(self: @TContractState, key: StateKey) -> (felt252, felt252);

    // Return the sale rate net for a specific time
    fn get_sale_rate_net(self: @TContractState, key: StateKey, time: u64) -> u128;

    // Return the sale rate delta for a specific time
    fn get_sale_rate_delta(self: @TContractState, key: StateKey, time: u64) -> (i129, i129);

    // Return the next initialized time
    fn next_initialized_time(
        self: @TContractState, key: StateKey, from: u64, max_time: u64
    ) -> (u64, bool);

    // Update an existing twamm order
    fn update_order(
        ref self: TContractState, salt: felt252, order_key: OrderKey, sale_rate_delta: i129
    );

    // Collect proceeds from a twamm order
    fn collect_proceeds(ref self: TContractState, salt: felt252, order_key: OrderKey);

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

    #[derive(Drop, Copy, Hash)]
    struct StorageKey {
        value: felt252,
    }

    #[storage]
    struct Storage {
        core: ICoreDispatcher,
        orders: LegacyMap<(ContractAddress, felt252, OrderKey), OrderState>,
        sale_rate: LegacyMap<StorageKey, (u128, u128)>,
        time_sale_rate_delta: LegacyMap<(StorageKey, u64), (i129, i129)>,
        time_sale_rate_net: LegacyMap<(StorageKey, u64), u128>,
        time_sale_rate_bitmaps: LegacyMap<(StorageKey, u128), Bitmap>,
        reward_rate: LegacyMap<StorageKey, (felt252, felt252)>,
        time_reward_rate: LegacyMap<(StorageKey, u64), (felt252, felt252)>,
        last_virtual_order_time: LegacyMap<StorageKey, u64>,
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
        pub salt: felt252,
        pub order_key: OrderKey,
        pub sale_rate_delta: i129
    }

    #[derive(starknet::Event, Drop)]
    pub struct OrderProceedsWithdrawn {
        pub owner: ContractAddress,
        pub salt: felt252,
        pub order_key: OrderKey,
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
        salt: felt252,
        order_key: OrderKey,
        sale_rate_delta: i129
    }

    #[derive(Serde, Copy, Drop)]
    struct WithdrawProceedsCallbackData {
        owner: ContractAddress,
        salt: felt252,
        order_key: OrderKey,
    }

    #[derive(Serde, Copy, Drop)]
    enum LockCallbackData {
        ExecuteVirtualSwapsCallbackData: StateKey,
        UpdateSaleRateCallbackData: UpdateSaleRateCallbackData,
        WithdrawProceedsCallbackData: WithdrawProceedsCallbackData
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
        fn get_last_virtual_order_time(self: @ContractState, key: StateKey) -> u64 {
            self.last_virtual_order_time.read(key.into())
        }

        fn get_order_state(
            self: @ContractState, owner: ContractAddress, salt: felt252, order_key: OrderKey
        ) -> OrderState {
            self.orders.read((owner, salt, order_key))
        }

        fn get_sale_rate(self: @ContractState, key: StateKey) -> (u128, u128) {
            self.sale_rate.read(key.into())
        }

        fn get_reward_rate(self: @ContractState, key: StateKey) -> (felt252, felt252) {
            self.reward_rate.read(key.into())
        }

        fn get_sale_rate_net(self: @ContractState, key: StateKey, time: u64) -> u128 {
            self.time_sale_rate_net.read((key.into(), time))
        }

        fn get_sale_rate_delta(self: @ContractState, key: StateKey, time: u64) -> (i129, i129) {
            self.time_sale_rate_delta.read((key.into(), time))
        }

        fn next_initialized_time(
            self: @ContractState, key: StateKey, from: u64, max_time: u64
        ) -> (u64, bool) {
            let storage_key: StorageKey = key.into();

            self
                .prefix_next_initialized_time(
                    LegacyHash::hash(selector!("time_sale_rate_bitmaps"), storage_key.value),
                    from,
                    max_time
                )
        }

        fn update_order(
            ref self: ContractState, salt: felt252, order_key: OrderKey, sale_rate_delta: i129
        ) {
            call_core_with_callback(
                self.core.read(),
                @LockCallbackData::UpdateSaleRateCallbackData(
                    UpdateSaleRateCallbackData {
                        owner: get_caller_address(), salt, order_key, sale_rate_delta
                    }
                )
            )
        }

        fn collect_proceeds(ref self: ContractState, salt: felt252, order_key: OrderKey) {
            call_core_with_callback(
                self.core.read(),
                @LockCallbackData::WithdrawProceedsCallbackData(
                    WithdrawProceedsCallbackData { owner: get_caller_address(), salt, order_key }
                )
            )
        }

        #[inline(always)]
        fn execute_virtual_orders(ref self: ContractState, key: StateKey) {
            call_core_with_callback(
                self.core.read(), @LockCallbackData::ExecuteVirtualSwapsCallbackData({
                    key
                })
            )
        }
    }

    #[abi(embed_v0)]
    impl LockerImpl of ILocker<ContractState> {
        fn locked(ref self: ContractState, id: u32, data: Span<felt252>) -> Span<felt252> {
            let core = self.core.read();

            match consume_callback_data::<LockCallbackData>(core, data) {
                LockCallbackData::ExecuteVirtualSwapsCallbackData(key) => {
                    self.internal_execute_virtual_orders(core, key);
                },
                LockCallbackData::UpdateSaleRateCallbackData(data) => {
                    let owner = data.owner;
                    let order_key = data.order_key;
                    let salt = data.salt;
                    let sale_rate_delta = data.sale_rate_delta;

                    self.internal_execute_virtual_orders(core, order_key.into());

                    let current_time = get_block_timestamp();
                    assert(order_key.end_time > current_time, 'ORDER_ENDED');

                    let order_state = self.orders.read((owner, salt, order_key));

                    let order_started = order_key.start_time <= current_time;

                    validate_time(current_time, order_key.end_time);
                    validate_time(current_time, order_key.start_time);

                    let sale_rate_next = order_state.sale_rate.add(sale_rate_delta);

                    let (reward_rate, use_snapshot, order_start_time) = if (sale_rate_next
                        .is_zero()) {
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

                        let current_order_reward_rate = current_reward_rate
                            - order_state.reward_rate;

                        let adjusted_reward_rate = if (current_order_reward_rate.is_zero()) {
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
                            (owner, salt, order_key),
                            OrderState { sale_rate: sale_rate_next, reward_rate, use_snapshot, }
                        );

                    self.emit(OrderUpdated { owner, salt, order_key, sale_rate_delta });

                    if (order_started) {
                        self.update_global_sale_rate(order_key, sale_rate_delta);
                    } else {
                        self.update_time(order_key, order_start_time, sale_rate_delta, true);
                    }

                    self.update_time(order_key, order_key.end_time, sale_rate_delta, false);

                    let amount_delta = calculate_amount_from_sale_rate(
                        sale_rate_delta.mag,
                        max(order_key.start_time, current_time),
                        order_key.end_time
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
                },
                LockCallbackData::WithdrawProceedsCallbackData(data) => {
                    let owner = data.owner;
                    let order_key = data.order_key;
                    let salt = data.salt;
                    let current_time = get_block_timestamp();

                    assert(
                        order_key.start_time.is_zero() || order_key.start_time < current_time,
                        'NOT_STARTED'
                    );

                    self.internal_execute_virtual_orders(core, data.order_key.into());

                    let order_state = self.orders.read((owner, salt, order_key));

                    // order has been cancelled
                    assert(order_state.sale_rate > 0, 'ZERO_SALE_RATE');

                    let order_reward_rate = if (order_state.use_snapshot) {
                        order_state.reward_rate
                    } else {
                        self.get_reward_rate_at(order_key, order_key.start_time)
                    };

                    let purchased_amount = if (current_time >= order_key.end_time) {
                        // update order state to reflect that the order has been fully executed
                        self.orders.write((owner, salt, order_key), Zero::zero());

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
                                (owner, salt, order_key),
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
                                owner, salt, order_key, amount: purchased_amount
                            }
                        );
                }
            }

            array![].span()
        }
    }

    #[generate_trait]
    impl Internal of InternalTrait {
        fn update_time(
            ref self: ContractState,
            order_key: OrderKey,
            time: u64,
            sale_rate_delta: i129,
            is_start_time: bool
        ) {
            let key: StateKey = order_key.into();
            let storage_key: StorageKey = key.into();
            let (token0_sale_rate_delta, token1_sale_rate_delta) = self
                .time_sale_rate_delta
                .read((storage_key, time));

            if (order_key.sell_token > order_key.buy_token) {
                let next_sale_rate_delta = if (is_start_time) {
                    token1_sale_rate_delta + sale_rate_delta
                } else {
                    token1_sale_rate_delta - sale_rate_delta
                };
                self
                    .time_sale_rate_delta
                    .write((storage_key, time), (token0_sale_rate_delta, next_sale_rate_delta));
            } else {
                let next_sale_rate_delta = if (is_start_time) {
                    token0_sale_rate_delta + sale_rate_delta
                } else {
                    token0_sale_rate_delta - sale_rate_delta
                };
                self
                    .time_sale_rate_delta
                    .write((storage_key, time), (next_sale_rate_delta, token1_sale_rate_delta));
            }

            let sale_rate_net = self.time_sale_rate_net.read((storage_key, time));
            let next_sale_rate_net = sale_rate_net.add(sale_rate_delta);
            self.time_sale_rate_net.write((storage_key, time), next_sale_rate_net);

            if sale_rate_net.is_zero() & next_sale_rate_net.is_non_zero() {
                self.insert_initialized_time(storage_key, time);
            } else if sale_rate_net.is_non_zero() & next_sale_rate_net.is_zero() {
                self.remove_initialized_time(storage_key, time);
            };
        }

        fn update_global_sale_rate(
            ref self: ContractState, order_key: OrderKey, sale_rate_delta: i129
        ) {
            let key: StateKey = order_key.into();
            let storage_key: StorageKey = key.into();
            let (token0_sale_rate, token1_sale_rate) = self.sale_rate.read(storage_key);

            self
                .sale_rate
                .write(
                    storage_key,
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
            storage_key: StorageKey,
            sale_rates: (u128, u128),
            delta: Delta,
            time: u64
        ) -> (felt252, felt252) {
            let (token0_reward_delta, token1_reward_delta) = calculate_reward_rate_deltas(
                sale_rates, delta
            );

            let (current_token0_reward_rate, current_token1_reward_rate) = self
                .reward_rate
                .read(storage_key);

            let reward_rate = (
                current_token0_reward_rate + token0_reward_delta,
                current_token1_reward_rate + token1_reward_delta
            );

            self.reward_rate.write(storage_key, reward_rate);

            let (token0_reward_rate, token1_reward_rate) = reward_rate;

            self
                .time_reward_rate
                .write((storage_key, time), (token0_reward_rate, token1_reward_rate));

            reward_rate
        }

        fn update_token_sale_rate_and_rewards(
            ref self: ContractState,
            storage_key: StorageKey,
            sale_rates: (u128, u128),
            reward_rates: (felt252, felt252),
            time: u64
        ) {
            let (token0_sale_rate, token1_sale_rate) = sale_rates;

            let (token0_sale_rate_delta, token1_sale_rate_delta) = self
                .time_sale_rate_delta
                .read((storage_key, time));

            if (token0_sale_rate_delta.mag > 0 || token1_sale_rate_delta.mag > 0) {
                self
                    .sale_rate
                    .write(
                        storage_key,
                        (
                            (i129 { mag: token0_sale_rate, sign: false } + token0_sale_rate_delta)
                                .mag,
                            (i129 { mag: token1_sale_rate, sign: false } + token1_sale_rate_delta)
                                .mag
                        )
                    );

                let (token0_reward_rate, token1_reward_rate) = reward_rates;

                self
                    .time_reward_rate
                    .write((storage_key, time), (token0_reward_rate, token1_reward_rate));
            }
        }

        fn remove_initialized_time(ref self: ContractState, storage_key: StorageKey, time: u64) {
            let (word_index, bit_index) = time_to_word_and_bit_index(time);

            let bitmap = self.time_sale_rate_bitmaps.read((storage_key, word_index));

            // it is assumed that bitmap already contains the set bit exp2(bit_index)
            self
                .time_sale_rate_bitmaps
                .write((storage_key, word_index), bitmap.unset_bit(bit_index));
        }

        fn insert_initialized_time(ref self: ContractState, storage_key: StorageKey, time: u64) {
            let (word_index, bit_index) = time_to_word_and_bit_index(time);

            let bitmap = self.time_sale_rate_bitmaps.read((storage_key, word_index));

            self.time_sale_rate_bitmaps.write((storage_key, word_index), bitmap.set_bit(bit_index));
        }

        fn prefix_next_initialized_time(
            self: @ContractState, prefix: felt252, from: u64, max_time: u64
        ) -> (u64, bool) {
            let (word_index, bit_index) = time_to_word_and_bit_index(
                from + constants::BITMAP_SPACING
            );

            let bitmap: Bitmap = Store::read(
                0, storage_base_address_from_felt252(LegacyHash::hash(prefix, word_index))
            )
                .expect('BITMAP_READ_FAILED');

            match bitmap.next_set_bit(bit_index) {
                Option::Some(next_bit) => {
                    let next_time = word_and_bit_index_to_time((word_index, next_bit));
                    if next_time > max_time {
                        (max_time, false)
                    } else {
                        (next_time, true)
                    }
                },
                Option::None => {
                    let next = word_and_bit_index_to_time((word_index, 0));

                    if (next > max_time) {
                        (max_time, false)
                    } else {
                        self.prefix_next_initialized_time(prefix, next, max_time)
                    }
                },
            }
        }

        fn internal_execute_virtual_orders(
            ref self: ContractState, core: ICoreDispatcher, key: StateKey
        ) {
            let pool_key: PoolKey = key.into();
            let storage_key: StorageKey = key.into();

            // since virtual orders are executed at the same time for both tokens,
            // last_virtual_order_time is the same for both tokens.
            let mut last_virtual_order_time = self.last_virtual_order_time.read(key.into());

            let current_time = get_block_timestamp();

            let self_snap = @self;

            if (last_virtual_order_time != current_time) {
                let time_bitmap_storage_prefix = LegacyHash::hash(
                    selector!("time_sale_rate_bitmaps"), storage_key.value
                );
                // todo: don't use 0 to mean not initialized, instead use Option<u256>
                let mut next_sqrt_ratio = 0;
                let mut total_delta = Zero::<Delta>::zero();

                loop {
                    let mut delta = Zero::zero();

                    // we must trade up to the earliest initialzed time because sale rate changes
                    let (next_virtual_order_time, is_initialized) = self_snap
                        .prefix_next_initialized_time(
                            time_bitmap_storage_prefix, last_virtual_order_time, current_time
                        );

                    let (token0_sale_rate, token1_sale_rate) = self.sale_rate.read(storage_key);

                    let (token0_reward_rate, token1_reward_rate) = if (token0_sale_rate > 0
                        || token1_sale_rate > 0) {
                        let mut sqrt_ratio = if (next_sqrt_ratio.is_zero()) {
                            let price = core.get_pool_price(pool_key);
                            price.sqrt_ratio
                        } else {
                            next_sqrt_ratio
                        };

                        if sqrt_ratio.is_non_zero() {
                            let time_elapsed = next_virtual_order_time - last_virtual_order_time;

                            let token0_amount = (token0_sale_rate * time_elapsed.into())
                                / constants::X32_u128;
                            let token1_amount = (token1_sale_rate * time_elapsed.into())
                                / constants::X32_u128;

                            let twamm_delta = if (token0_amount.is_non_zero()
                                && token1_amount.is_non_zero()) {
                                next_sqrt_ratio =
                                    calculate_next_sqrt_ratio(
                                        sqrt_ratio,
                                        core.get_pool_liquidity(pool_key),
                                        token0_sale_rate,
                                        token1_sale_rate,
                                        time_elapsed
                                    );

                                delta = core
                                    .swap(
                                        pool_key,
                                        SwapParameters {
                                            amount: i129 {
                                                mag: 0xffffffffffffffffffffffffffffffff, sign: false
                                            },
                                            is_token1: sqrt_ratio < next_sqrt_ratio,
                                            sqrt_ratio_limit: next_sqrt_ratio,
                                            skip_ahead: 0
                                        }
                                    );

                                // both sides are swapping, twamm delta is the amounts swapped to reach
                                // target price minus amounts in the twamm
                                delta
                                    - Delta {
                                        amount0: i129 { mag: token0_amount, sign: false },
                                        amount1: i129 { mag: token1_amount, sign: false }
                                    }
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

                                // must fetch price from core after a single sided swap
                                next_sqrt_ratio = 0;

                                // only one side is swapping, twamm delta is the same as amounts swapped
                                delta
                            };

                            let (token0_reward_rate, token1_reward_rate) = self
                                .update_reward_rate(
                                    storage_key,
                                    (token0_sale_rate, token1_sale_rate),
                                    twamm_delta,
                                    next_virtual_order_time
                                );

                            // must accumulate swap deltas to zero out at the end
                            total_delta += delta;

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

                            (token0_reward_rate, token1_reward_rate)
                        } else {
                            // no tokens swapped, no rewards change
                            (0, 0)
                        }
                    } else {
                        // no tokens swapped, no rewards change
                        (0, 0)
                    };

                    if (is_initialized) {
                        self
                            .update_token_sale_rate_and_rewards(
                                storage_key,
                                (token0_sale_rate, token1_sale_rate),
                                (token0_reward_rate, token1_reward_rate),
                                next_virtual_order_time
                            );
                    }

                    // update last_virtual_order_time to next_virtual_order_time
                    last_virtual_order_time = next_virtual_order_time;

                    // virtual orders were executed up to current time
                    if next_virtual_order_time == current_time {
                        break;
                    }
                };

                self.last_virtual_order_time.write(storage_key, last_virtual_order_time);

                self
                    .handle_delta_with_saved_balances(
                        core, get_contract_address(), pool_key.token0, total_delta.amount0
                    );

                self
                    .handle_delta_with_saved_balances(
                        core, get_contract_address(), pool_key.token1, total_delta.amount1
                    );
            }
        }

        fn handle_delta_with_saved_balances(
            ref self: ContractState,
            core: ICoreDispatcher,
            owner: ContractAddress,
            token: ContractAddress,
            delta: i129
        ) {
            if delta.is_non_zero() {
                if (delta.sign) {
                    core.save(key: SavedBalanceKey { owner, token, salt: 0 }, amount: delta.mag);
                } else {
                    core.load(token: token, salt: 0, amount: delta.mag);
                }
            }
        }
    }

    pub(crate) fn time_to_word_and_bit_index(time: u64) -> (u128, u8) {
        (
            (time / (constants::BITMAP_SPACING * 251)).into(),
            250_u8 - ((time / constants::BITMAP_SPACING) % 251).try_into().unwrap()
        )
    }

    pub(crate) fn word_and_bit_index_to_time(word_and_bit_index: (u128, u8)) -> u64 {
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

    impl StateKeyIntoStorageKey of Into<StateKey, StorageKey> {
        fn into(self: StateKey) -> StorageKey {
            StorageKey {
                value: core::pedersen::pedersen(
                    core::pedersen::pedersen(self.token0.into(), self.token1.into()),
                    self.fee.into()
                )
            }
        }
    }
}
