pub mod math;
#[cfg(test)]
pub(crate) mod math_test;

#[cfg(test)]
pub(crate) mod twamm_test;

#[starknet::contract]
pub mod TWAMM {
    use core::cmp::{max};
    use core::hash::{LegacyHash};
    use core::num::traits::{Zero};
    use core::option::{OptionTrait};
    use core::traits::{Into, TryInto};
    use ekubo::components::owned::{Owned as owned_component};
    use ekubo::components::shared_locker::{
        call_core_with_callback, consume_callback_data, check_caller_is_core
    };
    use ekubo::components::upgradeable::{Upgradeable as upgradeable_component, IHasInterface};
    use ekubo::extensions::interfaces::twamm::{
        ITWAMM, StateKey, OrderKey, OrderInfo, SaleRateState
    };
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
        ContractAddress, Store, get_contract_address, get_caller_address, get_block_timestamp,
        ClassHash, storage_access::{storage_base_address_from_felt252}
    };
    use super::math::{
        calculate_reward_amount, time::{validate_time, to_duration, TIME_SPACING_SIZE},
        calculate_next_sqrt_ratio, calculate_amount_from_sale_rate, calculate_reward_rate
    };

    #[derive(Drop, Copy, Serde)]
    struct OrderState {
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

    impl SaleRateStorePacking of starknet::storage_access::StorePacking<
        SaleRateState, (felt252, felt252)
    > {
        fn pack(value: SaleRateState) -> (felt252, felt252) {
            (
                u256 { low: value.token0_sale_rate, high: value.last_virtual_order_time.into() }
                    .try_into()
                    .unwrap(),
                value.token1_sale_rate.into()
            )
        }
        fn unpack(value: (felt252, felt252)) -> SaleRateState {
            let (token0_sale_rate_and_last_virtual_order_time, token1_sale_rate_felt252) = value;
            let token0_sale_rate_and_last_virtual_order_time_u256: u256 =
                token0_sale_rate_and_last_virtual_order_time
                .into();
            let last_virtual_order_time: u64 = token0_sale_rate_and_last_virtual_order_time_u256
                .high
                .try_into()
                .unwrap();

            SaleRateState {
                token0_sale_rate: token0_sale_rate_and_last_virtual_order_time_u256.low,
                token1_sale_rate: token1_sale_rate_felt252.try_into().unwrap(),
                last_virtual_order_time
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
        sale_rate_and_last_virtual_order_time: LegacyMap<StorageKey, SaleRateState>,
        time_sale_rate_delta: LegacyMap<(StorageKey, u64), (i129, i129)>,
        time_sale_rate_net: LegacyMap<(StorageKey, u64), u128>,
        time_sale_rate_bitmaps: LegacyMap<(StorageKey, u128), Bitmap>,
        reward_rate: LegacyMap<StorageKey, (felt252, felt252)>,
        time_reward_rate: LegacyMap<(StorageKey, u64), (felt252, felt252)>,
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
        pub key: StateKey,
        pub token0_sale_rate: u128,
        pub token1_sale_rate: u128,
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
    enum LockCallbackData {
        ExecuteVirtualSwapsCallbackData: StateKey,
        // owner, salt, order_key, sale_rate_delta
        UpdateSaleRateCallbackData: (ContractAddress, felt252, OrderKey, i129),
        // owner, salt, order_key
        CollectProceedsCallbackData: (ContractAddress, felt252, OrderKey)
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
            check_caller_is_core(self.core.read());
            assert(pool_key.tick_spacing == MAX_TICK_SPACING, 'TICK_SPACING');

            self
                .sale_rate_and_last_virtual_order_time
                .write(
                    StateKey { token0: pool_key.token0, token1: pool_key.token1, fee: pool_key.fee }
                        .into(),
                    SaleRateState {
                        token0_sale_rate: 0,
                        token1_sale_rate: 0,
                        last_virtual_order_time: get_block_timestamp()
                    }
                );

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
        fn get_order_info(
            self: @ContractState, owner: ContractAddress, salt: felt252, order_key: OrderKey
        ) -> OrderInfo {
            let current_time = get_block_timestamp();
            let order_state = self.orders.read((owner, salt, order_key));

            let order_reward_rate = if (order_state.use_snapshot) {
                order_state.reward_rate
            } else {
                self.get_reward_rate_at(order_key, order_key.start_time)
            };

            let (remaining_sell_amount, purchased_amount) = if current_time < order_key.start_time {
                (
                    calculate_amount_from_sale_rate(
                        sale_rate: order_state.sale_rate,
                        duration: to_duration(start: order_key.start_time, end: order_key.end_time),
                        round_up: false
                    ),
                    0
                )
            } else if (current_time < order_key.end_time) {
                let current_reward_rate = self.get_current_reward_rate(order_key);

                (
                    calculate_amount_from_sale_rate(
                        sale_rate: order_state.sale_rate,
                        duration: to_duration(start: current_time, end: order_key.end_time),
                        round_up: false
                    ),
                    calculate_reward_amount(
                        current_reward_rate - order_reward_rate, order_state.sale_rate
                    )
                )
            } else {
                let interval_reward_rate = self.get_reward_rate_at(order_key, order_key.end_time)
                    - order_reward_rate;
                (0, calculate_reward_amount(interval_reward_rate, order_state.sale_rate))
            };

            OrderInfo { sale_rate: order_state.sale_rate, remaining_sell_amount, purchased_amount }
        }

        fn get_sale_rate_and_last_virtual_order_time(
            self: @ContractState, key: StateKey
        ) -> SaleRateState {
            self.sale_rate_and_last_virtual_order_time.read(key.into())
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
                    LegacyHash::hash(selector!("time_sale_rate_bitmaps"), storage_key),
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
                    (get_caller_address(), salt, order_key, sale_rate_delta)
                )
            )
        }

        fn collect_proceeds(ref self: ContractState, salt: felt252, order_key: OrderKey) {
            call_core_with_callback(
                self.core.read(),
                @LockCallbackData::CollectProceedsCallbackData(
                    (get_caller_address(), salt, order_key)
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
                LockCallbackData::UpdateSaleRateCallbackData((
                    owner, salt, order_key, sale_rate_delta
                )) => {
                    let current_time = get_block_timestamp();
                    // there is no reason to adjust the sale rate of an order that has already ended
                    assert(current_time < order_key.end_time, 'ORDER_ENDED');

                    self.internal_execute_virtual_orders(core, order_key.into());

                    let order_info = self.get_order_info(owner, salt, order_key);

                    validate_time(now: current_time, time: order_key.end_time);
                    validate_time(now: current_time, time: order_key.start_time);

                    let sale_rate_next = order_info.sale_rate.add(sale_rate_delta);

                    let (reward_rate, use_snapshot) = if (sale_rate_next.is_zero()) {
                        // all proceeds must be withdrawn before order is cancelled
                        assert(order_info.purchased_amount.is_zero(), 'MUST_WITHDRAW_PROCEEDS');

                        // zero out the state
                        (0, false)
                    } else {
                        (
                            self.get_current_reward_rate(order_key)
                                - calculate_reward_rate(
                                    order_info.purchased_amount, sale_rate_next
                                ),
                            true
                        )
                    };

                    self
                        .orders
                        .write(
                            (owner, salt, order_key),
                            OrderState { sale_rate: sale_rate_next, reward_rate, use_snapshot }
                        );

                    self.emit(OrderUpdated { owner, salt, order_key, sale_rate_delta });

                    let key: StateKey = order_key.into();

                    if (order_key.start_time <= current_time) {
                        // order already started, update the current sale rate
                        let storage_key: StorageKey = key.into();

                        let sale_rate_storage_address = storage_base_address_from_felt252(
                            LegacyHash::hash(
                                selector!("sale_rate_and_last_virtual_order_time"), storage_key
                            )
                        );

                        let sale_rate_state: SaleRateState = Store::read(
                            0, sale_rate_storage_address
                        )
                            .expect('FAILED_TO_READ_SALE_RATE');

                        Store::write(
                            0,
                            sale_rate_storage_address,
                            if (order_key.sell_token > order_key.buy_token) {
                                SaleRateState {
                                    token0_sale_rate: sale_rate_state.token0_sale_rate,
                                    token1_sale_rate: sale_rate_state
                                        .token1_sale_rate
                                        .add(sale_rate_delta),
                                    last_virtual_order_time: sale_rate_state.last_virtual_order_time
                                }
                            } else {
                                SaleRateState {
                                    token0_sale_rate: sale_rate_state
                                        .token0_sale_rate
                                        .add(sale_rate_delta),
                                    token1_sale_rate: sale_rate_state.token1_sale_rate,
                                    last_virtual_order_time: sale_rate_state.last_virtual_order_time
                                }
                            }
                        )
                            .expect('FAILED_TO_WRITE_SALE_RATE');
                    } else {
                        // order starts in the future, update start time
                        self.update_time(order_key, order_key.start_time, sale_rate_delta, true);
                    }

                    // always update end time because this point is only reached if the order is active or hasn't started
                    self.update_time(order_key, order_key.end_time, sale_rate_delta, false);

                    // must round down if decreasing (withdrawing) and round up if increasing (depositing) sale rate to remain solvent
                    let amount_delta = calculate_amount_from_sale_rate(
                        sale_rate: sale_rate_delta.mag,
                        duration: to_duration(
                            start: max(order_key.start_time, current_time), end: order_key.end_time
                        ),
                        round_up: !sale_rate_delta.sign
                    );

                    let token = order_key.sell_token;

                    if (sale_rate_delta.sign) {
                        // if decreasing sale rate, pay fee and withdraw funds

                        let pool_key: PoolKey = key.into();

                        core.load(token: token, salt: 0, amount: amount_delta);

                        if (core.get_pool_liquidity(pool_key).is_non_zero()) {
                            let fee_amount = compute_fee(amount_delta, key.fee);

                            let (amount0, amount1) = if (order_key
                                .sell_token > order_key
                                .buy_token) {
                                (0, fee_amount)
                            } else {
                                (fee_amount, 0)
                            };

                            core.accumulate_as_fees(pool_key, amount0, amount1);
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
                LockCallbackData::CollectProceedsCallbackData((
                    owner, salt, order_key
                )) => {
                    self.internal_execute_virtual_orders(core, order_key.into());

                    let order_info = self.get_order_info(owner, salt, order_key);

                    // snapshot the reward rate so we know the proceeds of the order have been withdrawn at this current time
                    self
                        .orders
                        .write(
                            (owner, salt, order_key),
                            OrderState {
                                sale_rate: order_info.sale_rate,
                                reward_rate: self.get_current_reward_rate(order_key),
                                use_snapshot: true,
                            }
                        );

                    if (order_info.purchased_amount.is_non_zero()) {
                        let token = order_key.buy_token;

                        core.load(token, 0, order_info.purchased_amount);
                        core.withdraw(token, get_contract_address(), order_info.purchased_amount);
                    }

                    self
                        .emit(
                            OrderProceedsWithdrawn {
                                owner, salt, order_key, amount: order_info.purchased_amount
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

            let time_sale_rate_delta_storage_address = storage_base_address_from_felt252(
                LegacyHash::hash(
                    LegacyHash::hash(selector!("time_sale_rate_delta"), storage_key), time
                )
            );

            let (token0_sale_rate_delta, token1_sale_rate_delta): (i129, i129) = Store::read(
                0, time_sale_rate_delta_storage_address
            )
                .expect('FAILED_TO_READ_TSALE_RATE_DELTA');

            if (order_key.sell_token > order_key.buy_token) {
                let next_sale_rate_delta = if (is_start_time) {
                    token1_sale_rate_delta + sale_rate_delta
                } else {
                    token1_sale_rate_delta - sale_rate_delta
                };

                Store::write(
                    0,
                    time_sale_rate_delta_storage_address,
                    (token0_sale_rate_delta, next_sale_rate_delta)
                )
                    .expect('FAILED_WRITE_TSALE_RATE_DELTA');
            } else {
                let next_sale_rate_delta = if (is_start_time) {
                    token0_sale_rate_delta + sale_rate_delta
                } else {
                    token0_sale_rate_delta - sale_rate_delta
                };

                Store::write(
                    0,
                    time_sale_rate_delta_storage_address,
                    (next_sale_rate_delta, token1_sale_rate_delta)
                )
                    .expect('FAILED_WRITE_TSALE_RATE_DELTA');
            }

            let sale_rate_net_storage_address = storage_base_address_from_felt252(
                LegacyHash::hash(
                    LegacyHash::hash(selector!("time_sale_rate_net"), storage_key), time
                )
            );

            let sale_rate_net: u128 = Store::read(0, sale_rate_net_storage_address)
                .expect('FAILED_TO_SALE_RATE_NET');

            let next_sale_rate_net = sale_rate_net.add(sale_rate_delta);

            Store::write(0, sale_rate_net_storage_address, next_sale_rate_net)
                .expect('FAILED_TO_WRITE_SALE_RATE_NET');

            if sale_rate_net.is_zero() & next_sale_rate_net.is_non_zero() {
                self.insert_initialized_time(storage_key, time);
            } else if sale_rate_net.is_non_zero() & next_sale_rate_net.is_zero() {
                self.remove_initialized_time(storage_key, time);
            };
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
            let (word_index, bit_index) = time_to_word_and_bit_index(from + TIME_SPACING_SIZE);

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
            let current_time = get_block_timestamp();
            let self_snap = @self;

            let sale_rate_storage_address = storage_base_address_from_felt252(
                LegacyHash::hash(selector!("sale_rate_and_last_virtual_order_time"), storage_key)
            );

            let sale_rate_state: SaleRateState = Store::read(0, sale_rate_storage_address)
                .expect('FAILED_TO_READ_SALE_RATE');

            let mut token0_sale_rate = sale_rate_state.token0_sale_rate;
            let mut token1_sale_rate = sale_rate_state.token1_sale_rate;
            // all virtual orders are executed at the same time 
            // last_virtual_order_time is the same for both tokens
            let mut last_virtual_order_time = sale_rate_state.last_virtual_order_time;

            if (last_virtual_order_time != current_time) {
                let starting_sqrt_ratio = core.get_pool_price(pool_key).sqrt_ratio;
                assert(starting_sqrt_ratio.is_non_zero(), 'POOL_NOT_INITIALIZED');

                let mut next_sqrt_ratio = Option::Some(starting_sqrt_ratio);
                let mut total_delta = Zero::zero();

                let reward_rate_storage_address = storage_base_address_from_felt252(
                    LegacyHash::hash(selector!("reward_rate"), storage_key)
                );

                let (mut token0_reward_rate, mut token1_reward_rate): (felt252, felt252) =
                    Store::read(
                    0, reward_rate_storage_address
                )
                    .expect('FAILED_TO_READ_REWARD_RATE');

                let time_bitmap_storage_prefix = LegacyHash::hash(
                    selector!("time_sale_rate_bitmaps"), storage_key
                );

                let time_sale_rate_delta_storage_prefix = LegacyHash::hash(
                    selector!("time_sale_rate_delta"), storage_key
                );

                let time_reward_rate_storage_prefix = LegacyHash::hash(
                    selector!("time_reward_rate"), storage_key
                );

                loop {
                    let mut delta = Zero::zero();

                    // we must trade up to the earliest initialzed time because sale rate changes
                    let (next_virtual_order_time, is_initialized) = self_snap
                        .prefix_next_initialized_time(
                            time_bitmap_storage_prefix, last_virtual_order_time, current_time
                        );

                    if (token0_sale_rate.is_non_zero() || token1_sale_rate.is_non_zero()) {
                        let mut sqrt_ratio = match next_sqrt_ratio {
                            Option::Some(sqrt_ratio) => { sqrt_ratio },
                            Option::None => {
                                let price = core.get_pool_price(pool_key);
                                price.sqrt_ratio
                            }
                        };

                        let time_elapsed = to_duration(
                            start: last_virtual_order_time, end: next_virtual_order_time
                        );

                        let token0_amount: u128 = calculate_amount_from_sale_rate(
                            sale_rate: token0_sale_rate, duration: time_elapsed, round_up: false
                        );
                        let token1_amount: u128 = calculate_amount_from_sale_rate(
                            sale_rate: token1_sale_rate, duration: time_elapsed, round_up: false
                        );

                        let twamm_delta = if (token0_amount.is_non_zero()
                            && token1_amount.is_non_zero()) {
                            next_sqrt_ratio =
                                Option::Some(
                                    calculate_next_sqrt_ratio(
                                        sqrt_ratio,
                                        core.get_pool_liquidity(pool_key),
                                        token0_sale_rate,
                                        token1_sale_rate,
                                        time_elapsed
                                    )
                                );

                            delta = core
                                .swap(
                                    pool_key,
                                    SwapParameters {
                                        amount: i129 {
                                            mag: 0xffffffffffffffffffffffffffffffff, sign: false
                                        },
                                        is_token1: sqrt_ratio < next_sqrt_ratio.unwrap(),
                                        sqrt_ratio_limit: next_sqrt_ratio.unwrap(),
                                        skip_ahead: 0
                                    }
                                );

                            // both sides are swapping, twamm delta is the swap amounts needed to reach
                            // the target price minus amounts in the twamm
                            delta
                                - Delta {
                                    amount0: i129 { mag: token0_amount, sign: false },
                                    amount1: i129 { mag: token1_amount, sign: false }
                                }
                        } else {
                            let (amount, is_token1, sqrt_ratio_limit) = if token0_amount
                                .is_non_zero() {
                                (token0_amount, false, min_sqrt_ratio())
                            } else {
                                (token1_amount, true, max_sqrt_ratio())
                            };

                            if sqrt_ratio_limit != sqrt_ratio {
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
                            }

                            // must fetch price from core after a single sided swap
                            next_sqrt_ratio = Option::None;

                            // only one side is swapping, twamm delta is the same as amounts swapped
                            delta
                        };

                        // must accumulate swap deltas to zero out at the end
                        total_delta += delta;

                        if (twamm_delta.amount0.is_non_zero() && twamm_delta.amount0.sign) {
                            token0_reward_rate +=
                                calculate_reward_rate(twamm_delta.amount0.mag, token1_sale_rate);
                        }

                        if (twamm_delta.amount1.is_non_zero() && twamm_delta.amount1.sign) {
                            token1_reward_rate +=
                                calculate_reward_rate(twamm_delta.amount1.mag, token0_sale_rate);
                        }
                    }

                    if (is_initialized) {
                        let (token0_sale_rate_delta, token1_sale_rate_delta): (i129, i129) =
                            Store::read(
                            0,
                            storage_base_address_from_felt252(
                                LegacyHash::hash(
                                    time_sale_rate_delta_storage_prefix, next_virtual_order_time
                                )
                            )
                        )
                            .expect('FAILED_TO_READ_TSALE_RATE_DELTA');

                        if (token0_sale_rate_delta.is_non_zero()) {
                            token0_sale_rate = token0_sale_rate.add(token0_sale_rate_delta);
                        }

                        if (token1_sale_rate_delta.is_non_zero()) {
                            token1_sale_rate = token1_sale_rate.add(token1_sale_rate_delta);
                        }

                        Store::write(
                            0,
                            storage_base_address_from_felt252(
                                LegacyHash::hash(
                                    time_reward_rate_storage_prefix, next_virtual_order_time
                                )
                            ),
                            (token0_reward_rate, token1_reward_rate)
                        )
                            .expect('FAILED_TO_WRITE_TREWARD_RATE');
                    }

                    last_virtual_order_time = next_virtual_order_time;

                    // virtual orders were executed up to current time
                    if next_virtual_order_time == current_time {
                        break;
                    }
                };

                self
                    .emit(
                        VirtualOrdersExecuted {
                            key,
                            token0_sale_rate,
                            token1_sale_rate
                        }
                    );

                Store::write(
                    0,
                    sale_rate_storage_address,
                    SaleRateState { token0_sale_rate, token1_sale_rate, last_virtual_order_time }
                )
                    .expect('FAILED_TO_WRITE_SALE_RATE');

                Store::write(
                    0, reward_rate_storage_address, (token0_reward_rate, token1_reward_rate)
                )
                    .expect('FAILED_TO_WRITE_REWARD_RATE');

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
            (time / (TIME_SPACING_SIZE * 251)).into(),
            250_u8 - ((time / TIME_SPACING_SIZE) % 251).try_into().unwrap()
        )
    }

    pub(crate) fn word_and_bit_index_to_time(word_and_bit_index: (u128, u8)) -> u64 {
        let (word, bit) = word_and_bit_index;
        ((word * 251 * TIME_SPACING_SIZE.into()) + ((250 - bit).into() * TIME_SPACING_SIZE.into()))
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
