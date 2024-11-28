pub mod math;
#[cfg(test)]
pub(crate) mod math_test;

#[cfg(test)]
pub(crate) mod twamm_test;

#[starknet::contract]
pub mod TWAMM {
    use core::cmp::{max, min};
    use core::num::traits::{Zero};
    use core::option::{OptionTrait};
    use core::traits::{Into, TryInto};
    use ekubo::components::owned::{Owned as owned_component};
    use ekubo::components::shared_locker::{
        call_core_with_callback, consume_callback_data, check_caller_is_core
    };
    use ekubo::components::upgradeable::{Upgradeable as upgradeable_component, IHasInterface};
    use ekubo::components::util::{serialize};
    use ekubo::interfaces::extensions::twamm::{
        ITWAMM, StateKey, OrderKey, OrderInfo, SaleRateState, ForwardCallbackData
    };
    use ekubo::interfaces::core::{
        IExtension, SwapParameters, UpdatePositionParameters, IForwardee, ILocker, ICoreDispatcher,
        ICoreDispatcherTrait
    };
    use ekubo::math::bitmap::{Bitmap, BitmapTrait};
    use ekubo::math::fee::{compute_fee};
    use ekubo::math::ticks::constants::{MAX_TICK_SPACING};
    use ekubo::math::ticks::{max_sqrt_ratio, min_sqrt_ratio};
    use ekubo::types::bounds::{max_bounds, Bounds};
    use ekubo::types::call_points::{CallPoints};
    use ekubo::types::delta::{Delta};
    use ekubo::types::fees_per_liquidity::{FeesPerLiquidity, to_fees_per_liquidity};
    use ekubo::types::i129::{i129, AddDeltaTrait};
    use ekubo::types::keys::{PoolKey, SavedBalanceKey};
    use starknet::storage::{
        StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess, Map
    };
    use starknet::storage::{StoragePathEntry, StoragePath};
    use starknet::{
        ContractAddress, get_contract_address, get_block_timestamp, storage_access::{StorePacking}
    };
    use super::math::{
        calculate_reward_amount, time::{validate_time, to_duration, TIME_SPACING_SIZE},
        calculate_next_sqrt_ratio, calculate_amount_from_sale_rate,
        constants::{MAX_USABLE_TICK_MAGNITUDE, MAX_BOUNDS_MIN_SQRT_RATIO, MAX_BOUNDS_MAX_SQRT_RATIO}
    };

    #[derive(Drop, Copy, Serde, starknet::Store)]
    struct OrderState {
        sale_rate: u128,
        reward_rate_snapshot: felt252,
    }

    impl SaleRateStorePacking of StorePacking<SaleRateState, (felt252, felt252)> {
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
        orders: Map<(ContractAddress, felt252, OrderKey), OrderState>,
        sale_rate_and_last_virtual_order_time: Map<StorageKey, SaleRateState>,
        time_sale_rate_delta: Map<StorageKey, Map<u64, (i129, i129)>>,
        time_sale_rate_net: Map<StorageKey, Map<u64, u128>>,
        time_sale_rate_bitmaps: Map<StorageKey, Map<u128, Bitmap>>,
        reward_rate: Map<StorageKey, FeesPerLiquidity>,
        time_reward_rate_before: Map<StorageKey, Map<u64, FeesPerLiquidity>>,
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
        pub amount: u128,
    }

    #[derive(starknet::Event, Drop)]
    pub struct VirtualOrdersExecuted {
        pub key: StateKey,
        pub token0_sale_rate: u128,
        pub token1_sale_rate: u128,
        pub twamm_delta: Delta
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


    #[abi(embed_v0)]
    impl TWAMMHasInterface of IHasInterface<ContractState> {
        fn get_primary_interface_id(self: @ContractState) -> felt252 {
            return selector!("ekubo::extensions::twamm::TWAMM");
        }
    }

    fn twamm_call_points() -> CallPoints {
        CallPoints {
            before_initialize_pool: true,
            after_initialize_pool: true,
            before_swap: true,
            after_swap: false,
            before_update_position: true,
            after_update_position: false,
            before_collect_fees: true,
            after_collect_fees: false,
        }
    }

    #[abi(embed_v0)]
    impl ExtensionImpl of IExtension<ContractState> {
        fn before_initialize_pool(
            ref self: ContractState, caller: ContractAddress, pool_key: PoolKey, initial_tick: i129
        ) {
            check_caller_is_core(self.core.read());
            assert(pool_key.tick_spacing == MAX_TICK_SPACING, 'TICK_SPACING');
        }

        fn after_initialize_pool(
            ref self: ContractState, caller: ContractAddress, pool_key: PoolKey, initial_tick: i129
        ) {
            check_caller_is_core(self.core.read());

            let key = StateKey {
                token0: pool_key.token0, token1: pool_key.token1, fee: pool_key.fee
            };
            self
                .sale_rate_and_last_virtual_order_time
                .write(
                    key.into(),
                    SaleRateState {
                        token0_sale_rate: 0,
                        token1_sale_rate: 0,
                        last_virtual_order_time: get_block_timestamp()
                    }
                );

            self
                .emit(
                    VirtualOrdersExecuted {
                        key,
                        token0_sale_rate: Zero::zero(),
                        token1_sale_rate: Zero::zero(),
                        twamm_delta: Zero::zero()
                    }
                );
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

        fn before_collect_fees(
            ref self: ContractState,
            caller: ContractAddress,
            pool_key: PoolKey,
            salt: felt252,
            bounds: Bounds
        ) {
            self
                .execute_virtual_orders(
                    StateKey { token0: pool_key.token0, token1: pool_key.token1, fee: pool_key.fee }
                );
        }

        fn after_collect_fees(
            ref self: ContractState,
            caller: ContractAddress,
            pool_key: PoolKey,
            salt: felt252,
            bounds: Bounds,
            delta: Delta
        ) {
            assert(false, 'NOT_USED');
        }
    }

    #[abi(embed_v0)]
    impl TWAMMImpl of ITWAMM<ContractState> {
        fn execute_virtual_orders(ref self: ContractState, key: StateKey) {
            call_core_with_callback::<StateKey, ()>(self.core.read(), @key)
        }

        fn get_order_info(
            self: @ContractState, owner: ContractAddress, salt: felt252, order_key: OrderKey
        ) -> OrderInfo {
            // we have to do this to return the correct order information, even though this is a
            // view function
            call_core_with_callback::<
                StateKey, ()
            >(self.core.read(), @Into::<OrderKey, StateKey>::into(order_key));
            let (order_info, _) = self.internal_get_order_info(owner, salt, order_key);
            order_info
        }

        fn get_sale_rate_and_last_virtual_order_time(
            self: @ContractState, key: StateKey
        ) -> SaleRateState {
            self.sale_rate_and_last_virtual_order_time.read(key.into())
        }

        fn get_reward_rate(self: @ContractState, key: StateKey) -> FeesPerLiquidity {
            self.reward_rate.read(key.into())
        }

        fn get_time_reward_rate_before(
            self: @ContractState, key: StateKey, time: u64
        ) -> FeesPerLiquidity {
            self.time_reward_rate_before.entry(key.into()).read(time)
        }

        fn get_sale_rate_net(self: @ContractState, key: StateKey, time: u64) -> u128 {
            self.time_sale_rate_net.entry(key.into()).read(time)
        }

        fn get_sale_rate_delta(self: @ContractState, key: StateKey, time: u64) -> (i129, i129) {
            self.time_sale_rate_delta.entry(key.into()).read(time)
        }

        fn next_initialized_time(
            self: @ContractState, key: StateKey, from: u64, max_time: u64
        ) -> (u64, bool) {
            let storage_key: StorageKey = key.into();

            self
                .prefix_next_initialized_time(
                    self.time_sale_rate_bitmaps.entry(storage_key), from, max_time
                )
        }

        fn update_call_points(ref self: ContractState) {
            self.core.read().set_call_points(twamm_call_points());
        }
    }

    #[abi(embed_v0)]
    impl LockerImpl of ILocker<ContractState> {
        fn locked(ref self: ContractState, id: u32, data: Span<felt252>) -> Span<felt252> {
            let core = self.core.read();
            let key = consume_callback_data::<StateKey>(core, data);
            self.internal_execute_virtual_orders(core, key);
            array![].span()
        }
    }

    #[abi(embed_v0)]
    impl ForwardeeImpl of IForwardee<ContractState> {
        fn forwarded(
            ref self: ContractState, original_locker: ContractAddress, id: u32, data: Span<felt252>
        ) -> Span<felt252> {
            let core = self.core.read();

            let owner = original_locker;

            match consume_callback_data::<ForwardCallbackData>(core, data) {
                ForwardCallbackData::UpdateSaleRate(data) => {
                    let current_time = get_block_timestamp();

                    // there is no reason to update an order's sale rate after it has ended, because
                    // it is effectively no-op and only incurs additional l1 data cost this should
                    // be prevented at the periphery contract level
                    assert(current_time < data.order_key.end_time, 'ORDER_ENDED');

                    validate_time(now: current_time, time: data.order_key.end_time);
                    validate_time(now: current_time, time: data.order_key.start_time);

                    let state_key: StateKey = data.order_key.into();

                    self.internal_execute_virtual_orders(core, state_key);

                    let (order_info, reward_rate_snapshot) = self
                        .internal_get_order_info(owner, data.salt, data.order_key);
                    let sale_rate_next = order_info.sale_rate.add(data.sale_rate_delta);

                    let reward_rate_snapshot_adjusted = if sale_rate_next.is_zero() {
                        assert(order_info.purchased_amount.is_zero(), 'MUST_WITHDRAW_PROCEEDS');
                        0
                    } else {
                        // we compute the snapshot here and adjust by the purchased amount divided
                        // by sale rate delta so that the computed purchased amount does not change
                        // after updating the sale rate, except for rounding down by up to 1 wei
                        reward_rate_snapshot
                            - to_fees_per_liquidity(order_info.purchased_amount, sale_rate_next)
                    };

                    self
                        .orders
                        .write(
                            (owner, data.salt, data.order_key),
                            OrderState {
                                sale_rate: sale_rate_next,
                                reward_rate_snapshot: reward_rate_snapshot_adjusted
                            }
                        );

                    self
                        .emit(
                            OrderUpdated {
                                owner,
                                salt: data.salt,
                                order_key: data.order_key,
                                sale_rate_delta: data.sale_rate_delta
                            }
                        );

                    // this part updates the pool state only if the order is active or will be
                    // active
                    if current_time < data.order_key.start_time {
                        // order starts in the future, update both start and end time
                        self
                            .update_time(
                                data.order_key,
                                data.order_key.start_time,
                                data.sale_rate_delta,
                                true
                            );
                        self
                            .update_time(
                                data.order_key, data.order_key.end_time, data.sale_rate_delta, false
                            );
                    } else {
                        // we know current_time < order_key.end_time because we assert it above
                        let storage_key: StorageKey = state_key.into();

                        let sale_rate_storage_address = self
                            .sale_rate_and_last_virtual_order_time
                            .entry(storage_key);

                        let sale_rate_state = sale_rate_storage_address.read();

                        sale_rate_storage_address
                            .write(
                                if (data.order_key.sell_token > data.order_key.buy_token) {
                                    SaleRateState {
                                        token0_sale_rate: sale_rate_state.token0_sale_rate,
                                        token1_sale_rate: sale_rate_state
                                            .token1_sale_rate
                                            .add(data.sale_rate_delta),
                                        last_virtual_order_time: sale_rate_state
                                            .last_virtual_order_time
                                    }
                                } else {
                                    SaleRateState {
                                        token0_sale_rate: sale_rate_state
                                            .token0_sale_rate
                                            .add(data.sale_rate_delta),
                                        token1_sale_rate: sale_rate_state.token1_sale_rate,
                                        last_virtual_order_time: sale_rate_state
                                            .last_virtual_order_time
                                    }
                                }
                            );

                        // we only need to update the end time, because start time has been crossed
                        // and will never be crossed again
                        self
                            .update_time(
                                data.order_key, data.order_key.end_time, data.sale_rate_delta, false
                            );
                    }

                    // must round down if decreasing (withdrawing) and round up if increasing
                    // (depositing) sale rate to remain solvent
                    let mut amount_delta = calculate_amount_from_sale_rate(
                        sale_rate: data.sale_rate_delta.mag,
                        duration: to_duration(
                            start: max(data.order_key.start_time, current_time),
                            end: data.order_key.end_time
                        ),
                        round_up: !data.sale_rate_delta.sign
                    );

                    let token = data.order_key.sell_token;

                    if (data.sale_rate_delta.sign) {
                        // if decreasing sale rate, pay fee and withdraw funds
                        let pool_key: PoolKey = state_key.into();

                        core.load(token: token, salt: 0, amount: amount_delta);

                        if (core.get_pool_liquidity(pool_key).is_non_zero()) {
                            let fee_amount = compute_fee(amount_delta, state_key.fee);

                            let (amount0, amount1) = if (data
                                .order_key
                                .sell_token > data
                                .order_key
                                .buy_token) {
                                (0, fee_amount)
                            } else {
                                (fee_amount, 0)
                            };

                            core.accumulate_as_fees(pool_key, amount0, amount1);

                            amount_delta -= fee_amount;
                        }
                    } else {
                        core
                            .save(
                                SavedBalanceKey {
                                    owner: get_contract_address(), token: token, salt: 0
                                },
                                amount_delta
                            );
                    }

                    serialize(@i129 { mag: amount_delta, sign: data.sale_rate_delta.sign }).span()
                },
                ForwardCallbackData::CollectProceeds(data) => {
                    self.internal_execute_virtual_orders(core, data.order_key.into());

                    let (order_info, reward_rate_snapshot) = self
                        .internal_get_order_info(owner, data.salt, data.order_key);

                    // snapshot the reward rate so we know the proceeds of the order have been
                    // withdrawn at this current time
                    self
                        .orders
                        .write(
                            (owner, data.salt, data.order_key),
                            OrderState { sale_rate: order_info.sale_rate, reward_rate_snapshot, }
                        );

                    if (order_info.purchased_amount.is_non_zero()) {
                        let token = data.order_key.buy_token;

                        core.load(token, 0, order_info.purchased_amount);
                    }

                    self
                        .emit(
                            OrderProceedsWithdrawn {
                                owner,
                                salt: data.salt,
                                order_key: data.order_key,
                                amount: order_info.purchased_amount,
                            }
                        );

                    serialize(@order_info.purchased_amount).span()
                }
            }
        }
    }

    #[generate_trait]
    impl Internal of InternalTrait {
        fn get_reward_rate_snapshot_inside(
            self: @ContractState, storage_key: StorageKey, now: u64, start_time: u64, end_time: u64
        ) -> FeesPerLiquidity {
            if now < start_time {
                Zero::zero()
            } else {
                let time_reward_rate_before_entry = self.time_reward_rate_before.entry(storage_key);
                if now < end_time {
                    self.reward_rate.read(storage_key)
                        - time_reward_rate_before_entry.read(start_time)
                } else {
                    time_reward_rate_before_entry.read(end_time)
                        - time_reward_rate_before_entry.read(start_time)
                }
            }
        }

        fn update_time(
            ref self: ContractState,
            order_key: OrderKey,
            time: u64,
            sale_rate_delta: i129,
            is_start_time: bool
        ) {
            let key: StateKey = order_key.into();
            let storage_key: StorageKey = key.into();

            let time_sale_rate_delta_storage_address = self
                .time_sale_rate_delta
                .entry(storage_key)
                .entry(time);

            let (token0_sale_rate_delta, token1_sale_rate_delta) =
                time_sale_rate_delta_storage_address
                .read();

            if (order_key.sell_token > order_key.buy_token) {
                let next_sale_rate_delta = if (is_start_time) {
                    token1_sale_rate_delta + sale_rate_delta
                } else {
                    token1_sale_rate_delta - sale_rate_delta
                };

                time_sale_rate_delta_storage_address
                    .write((token0_sale_rate_delta, next_sale_rate_delta));
            } else {
                let next_sale_rate_delta = if (is_start_time) {
                    token0_sale_rate_delta + sale_rate_delta
                } else {
                    token0_sale_rate_delta - sale_rate_delta
                };

                time_sale_rate_delta_storage_address
                    .write((next_sale_rate_delta, token1_sale_rate_delta));
            }

            let sale_rate_net_storage_address = self
                .time_sale_rate_net
                .entry(storage_key)
                .entry(time);

            let sale_rate_net = sale_rate_net_storage_address.read();

            let next_sale_rate_net = sale_rate_net.add(sale_rate_delta);

            sale_rate_net_storage_address.write(next_sale_rate_net);

            if sale_rate_net.is_zero() & next_sale_rate_net.is_non_zero() {
                self.insert_initialized_time(storage_key, time);
            } else if sale_rate_net.is_non_zero() & next_sale_rate_net.is_zero() {
                self.remove_initialized_time(storage_key, time);
            };
        }

        fn remove_initialized_time(ref self: ContractState, storage_key: StorageKey, time: u64) {
            let (word_index, bit_index) = time_to_word_and_bit_index(time);

            let bitmap_entry = self.time_sale_rate_bitmaps.entry(storage_key).entry(word_index);
            let bitmap = bitmap_entry.read();

            // it is assumed that bitmap already contains the set bit exp2(bit_index)
            bitmap_entry.write(bitmap.unset_bit(bit_index));
        }

        fn insert_initialized_time(ref self: ContractState, storage_key: StorageKey, time: u64) {
            let (word_index, bit_index) = time_to_word_and_bit_index(time);

            let bitmap_entry = self.time_sale_rate_bitmaps.entry(storage_key).entry(word_index);
            let bitmap = bitmap_entry.read();

            bitmap_entry.write(bitmap.set_bit(bit_index));
        }

        fn prefix_next_initialized_time(
            self: @ContractState, prefix: StoragePath<Map<u128, Bitmap>>, from: u64, max_time: u64
        ) -> (u64, bool) {
            let (word_index, bit_index) = time_to_word_and_bit_index(from + TIME_SPACING_SIZE);

            let bitmap = prefix.read(word_index);

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

            let sale_rate_storage_address = self
                .sale_rate_and_last_virtual_order_time
                .entry(storage_key);

            let sale_rate_state = sale_rate_storage_address.read();

            let mut token0_sale_rate = sale_rate_state.token0_sale_rate;
            let mut token1_sale_rate = sale_rate_state.token1_sale_rate;
            // all virtual orders are executed at the same time
            // last_virtual_order_time is the same for both tokens
            let mut last_virtual_order_time = sale_rate_state.last_virtual_order_time;

            if (last_virtual_order_time != current_time) {
                let starting_sqrt_ratio = core.get_pool_price(pool_key).sqrt_ratio;
                assert(starting_sqrt_ratio.is_non_zero(), 'POOL_NOT_INITIALIZED');

                let mut total_delta: Delta = Zero::zero();
                let mut total_twamm_delta = Zero::zero();

                let reward_rate_storage_address = self.reward_rate.entry(storage_key);

                let mut reward_rate = reward_rate_storage_address.read();

                let time_bitmap_storage_prefix: StoragePath<Map<u128, Bitmap>> = self
                    .time_sale_rate_bitmaps
                    .entry(storage_key)
                    .into();

                let time_sale_rate_delta_storage_prefix = self
                    .time_sale_rate_delta
                    .entry(storage_key);

                let time_reward_rate_storage_prefix = self
                    .time_reward_rate_before
                    .entry(storage_key);

                while last_virtual_order_time != current_time {
                    let mut delta = Zero::zero();

                    // must trade up to the earliest initialzed time because sale rate changes
                    let (next_virtual_order_time, is_initialized) = self
                        .prefix_next_initialized_time(
                            time_bitmap_storage_prefix, last_virtual_order_time, current_time
                        );

                    if (token0_sale_rate.is_non_zero() || token1_sale_rate.is_non_zero()) {
                        let current_sqrt_ratio = core.get_pool_price(pool_key).sqrt_ratio;

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
                            // must use sqrt_ratio and liquidity at the closest usable tick, since
                            // swaps on this pool could push the price out of range and liquidity to
                            // zero
                            let sqrt_ratio = max(
                                MAX_BOUNDS_MIN_SQRT_RATIO,
                                min(MAX_BOUNDS_MAX_SQRT_RATIO, current_sqrt_ratio)
                            );

                            let liquidity = core
                                .get_pool_tick_liquidity_net(
                                    pool_key, i129 { mag: MAX_USABLE_TICK_MAGNITUDE, sign: true }
                                );

                            let next_sqrt_ratio = calculate_next_sqrt_ratio(
                                sqrt_ratio,
                                liquidity,
                                token0_sale_rate,
                                token1_sale_rate,
                                time_elapsed,
                                key.fee,
                            );

                            let (is_token1, swap_amount) = if current_sqrt_ratio < next_sqrt_ratio {
                                (true, token1_amount)
                            } else {
                                (false, token0_amount)
                            };

                            delta = core
                                .swap(
                                    pool_key,
                                    SwapParameters {
                                        amount: i129 { mag: swap_amount, sign: false },
                                        is_token1,
                                        sqrt_ratio_limit: next_sqrt_ratio,
                                        skip_ahead: 0
                                    }
                                );

                            // both sides are swapping, twamm delta is the swap amounts needed to
                            // reach the target price minus amounts in the twamm
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

                            if sqrt_ratio_limit != current_sqrt_ratio {
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

                            // only one side is swapping, twamm delta is the same as amounts swapped
                            delta
                        };

                        // must accumulate swap deltas to zero out at the end
                        total_delta += delta;

                        // must accumulate twamm delta to twamm calculate volume
                        total_twamm_delta += twamm_delta;

                        if (twamm_delta.amount0.is_non_zero() && twamm_delta.amount0.sign) {
                            reward_rate
                                .value0 +=
                                    to_fees_per_liquidity(
                                        twamm_delta.amount0.mag, token1_sale_rate
                                    );
                        }

                        if (twamm_delta.amount1.is_non_zero() && twamm_delta.amount1.sign) {
                            reward_rate
                                .value1 +=
                                    to_fees_per_liquidity(
                                        twamm_delta.amount1.mag, token0_sale_rate
                                    );
                        }
                    }

                    if (is_initialized) {
                        let (token0_sale_rate_delta, token1_sale_rate_delta) =
                            time_sale_rate_delta_storage_prefix
                            .read(next_virtual_order_time);

                        if (token0_sale_rate_delta.is_non_zero()) {
                            token0_sale_rate = token0_sale_rate.add(token0_sale_rate_delta);
                        }

                        if (token1_sale_rate_delta.is_non_zero()) {
                            token1_sale_rate = token1_sale_rate.add(token1_sale_rate_delta);
                        }

                        time_reward_rate_storage_prefix.write(next_virtual_order_time, reward_rate);
                    }

                    last_virtual_order_time = next_virtual_order_time;
                };

                self
                    .emit(
                        VirtualOrdersExecuted {
                            key, token0_sale_rate, token1_sale_rate, twamm_delta: total_twamm_delta
                        }
                    );

                sale_rate_storage_address
                    .write(
                        SaleRateState {
                            token0_sale_rate, token1_sale_rate, last_virtual_order_time
                        }
                    );
                reward_rate_storage_address.write(reward_rate);

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

        // Gets an order info and the latest reward rate snapshot
        // The pool must be executed up to the current time for an accurate response
        fn internal_get_order_info(
            self: @ContractState, owner: ContractAddress, salt: felt252, order_key: OrderKey
        ) -> (OrderInfo, felt252) {
            let current_time = get_block_timestamp();
            let order_state = self.orders.read((owner, salt, order_key));

            let state_key: StateKey = order_key.into();

            let reward_rate_inside = self
                .get_reward_rate_snapshot_inside(
                    storage_key: state_key.into(),
                    now: current_time,
                    start_time: order_key.start_time,
                    end_time: order_key.end_time
                );

            let reward_rate_snapshot = if order_key.sell_token > order_key.buy_token {
                reward_rate_inside.value0
            } else {
                reward_rate_inside.value1
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
                (
                    calculate_amount_from_sale_rate(
                        sale_rate: order_state.sale_rate,
                        duration: to_duration(start: current_time, end: order_key.end_time),
                        round_up: false
                    ),
                    calculate_reward_amount(
                        reward_rate_snapshot - order_state.reward_rate_snapshot,
                        order_state.sale_rate
                    )
                )
            } else {
                (
                    0,
                    calculate_reward_amount(
                        reward_rate_snapshot - order_state.reward_rate_snapshot,
                        order_state.sale_rate
                    )
                )
            };

            (
                OrderInfo {
                    sale_rate: order_state.sale_rate, remaining_sell_amount, purchased_amount
                },
                reward_rate_snapshot
            )
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
