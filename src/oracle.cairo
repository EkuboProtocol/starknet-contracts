use ekubo::types::i129::{i129};
use starknet::{ContractAddress};

#[starknet::interface]
pub trait IOracle<TContractState> {
    // Returns the timestamp of the earliest observation for a given pair, or Option::None if the
    // pair has no observations
    fn get_earliest_observation_time(
        self: @TContractState, token_a: ContractAddress, token_b: ContractAddress
    ) -> Option<u64>;

    // Returns the time weighted average tick between the given start and end time
    fn get_average_tick_over_period(
        self: @TContractState,
        base_token: ContractAddress,
        quote_token: ContractAddress,
        start_time: u64,
        end_time: u64
    ) -> i129;

    // Returns the time weighted average tick between the given start and end time
    fn get_average_tick_over_periods(
        self: @TContractState,
        base_token: ContractAddress,
        quote_token: ContractAddress,
        start_and_end_times: Span<(u64, u64)>
    ) -> Span<i129>;

    // Returns the time weighted average tick over the last `period` seconds
    fn get_average_tick_over_last(
        self: @TContractState,
        base_token: ContractAddress,
        quote_token: ContractAddress,
        period: u64
    ) -> i129;

    // Returns the a list of ticks representing the TWAP history from `end_time - (num_intervals *
    // interval_seconds)` to `end_time`
    fn get_average_tick_history(
        self: @TContractState,
        base_token: ContractAddress,
        quote_token: ContractAddress,
        end_time: u64,
        num_intervals: u32,
        interval_seconds: u32,
    ) -> Span<i129>;

    // Returns the realized volatility over the period in ticks, extrapolated to the given number of
    // seconds.
    // E.g.: to get the 7 day realized volatility using hourly observations, call with the following
    //  parameters:
    //      end_time = now, num_intervals = 168, interval_seconds = 3600, extrapolated_to = 604800
    // E.g.: to get the annualized realized volatility using half-hourly observations for the last
    //  day, call with the following parameters:
    //      end_time = now, num_intervals = 48, interval_seconds = 1800, extrapolated_to = 31557600
    fn get_realized_volatility_over_period(
        self: @TContractState,
        token_a: ContractAddress,
        token_b: ContractAddress,
        end_time: u64,
        num_intervals: u32,
        interval_seconds: u32,
        extrapolated_to: u32
    ) -> u64;

    // Returns the geomean average price of a token as a 128.128 between the given start and end
    // time
    fn get_price_x128_over_period(
        self: @TContractState,
        base_token: ContractAddress,
        quote_token: ContractAddress,
        start_time: u64,
        end_time: u64
    ) -> u256;

    // Returns the geomean average price of a token as a 128.128 over the last `period` seconds
    fn get_price_x128_over_last(
        self: @TContractState,
        base_token: ContractAddress,
        quote_token: ContractAddress,
        period: u64
    ) -> u256;


    // Returns the a list of prices representing the TWAP history from `end_time - (num_intervals *
    // interval_seconds)` to `end_time`
    fn get_average_price_x128_history(
        self: @TContractState,
        base_token: ContractAddress,
        quote_token: ContractAddress,
        end_time: u64,
        num_intervals: u32,
        interval_seconds: u32,
    ) -> Span<u256>;

    // Updates the call points for the latest version of this extension, or simply registers it on
    // the first call
    fn set_call_points(ref self: TContractState);

    // Returns the set oracle token
    fn get_oracle_token(self: @TContractState) -> ContractAddress;
}

#[starknet::contract]
pub mod Oracle {
    use core::cmp::{max};
    use core::num::traits::{Zero, Sqrt, WideMul};
    use core::traits::{Into};
    use ekubo::components::owned::{Owned as owned_component};
    use ekubo::components::shared_locker::{check_caller_is_core};
    use ekubo::components::upgradeable::{Upgradeable as upgradeable_component, IHasInterface};
    use ekubo::interfaces::core::{
        ICoreDispatcher, ICoreDispatcherTrait, IExtension, SwapParameters, UpdatePositionParameters
    };
    use ekubo::math::ticks::{tick_to_sqrt_ratio};
    use ekubo::types::bounds::{Bounds};
    use ekubo::types::call_points::{CallPoints};
    use ekubo::types::delta::{Delta};
    use ekubo::types::i129::{i129};
    use ekubo::types::keys::{PoolKey};
    use ekubo::types::snapshot::{Snapshot};
    use starknet::storage::{
        Map, StoragePointerWriteAccess, StorageMapReadAccess, StoragePointerReadAccess, StoragePath,
        StoragePathEntry, StorageMapWriteAccess
    };

    use starknet::{get_block_timestamp, get_contract_address};

    use super::{IOracle, ContractAddress};

    // Converts a tick to the price as a 128.128 number
    pub fn tick_to_price_x128(tick: i129) -> u256 {
        let sqrt_ratio = tick_to_sqrt_ratio(tick);
        // this is a 128.256 number, i.e. limb3 is always 0. we can shift it right 128 bits by
        // just taking limb2 and limb1 and get a 128.128 number
        let ratio = WideMul::wide_mul(sqrt_ratio, sqrt_ratio);

        u256 { high: ratio.limb2, low: ratio.limb1 }
    }

    // Given an amount0 and a tick corresponding to the average price in terms of amount1/amount0,
    // return the quoted amount at that pri
    pub fn quote_amount_from_tick(amount0: u128, tick: i129) -> u256 {
        let result_x128 = WideMul::wide_mul(tick_to_price_x128(tick), amount0.into());

        u256 { high: result_x128.limb2, low: result_x128.limb1 }
    }

    component!(path: owned_component, storage: owned, event: OwnedEvent);
    #[abi(embed_v0)]
    impl Owned = owned_component::OwnedImpl<ContractState>;
    impl OwnableImpl = owned_component::OwnableImpl<ContractState>;

    component!(path: upgradeable_component, storage: upgradeable, event: UpgradeableEvent);
    #[abi(embed_v0)]
    impl Upgradeable = upgradeable_component::UpgradeableImpl<ContractState>;

    #[starknet::storage_node]
    struct PoolState {
        count: u64,
        snapshots: Map<u64, Snapshot>,
    }

    #[storage]
    struct Storage {
        pub core: ICoreDispatcher,
        pub pool_state: Map<(ContractAddress, ContractAddress), PoolState>,
        pub oracle_token: ContractAddress,
        #[substorage(v0)]
        upgradeable: upgradeable_component::Storage,
        #[substorage(v0)]
        owned: owned_component::Storage,
    }

    #[derive(starknet::Event, Drop)]
    struct SnapshotEvent {
        token0: ContractAddress,
        token1: ContractAddress,
        index: u64,
        snapshot: Snapshot,
    }

    #[derive(starknet::Event, Drop)]
    #[event]
    enum Event {
        UpgradeableEvent: upgradeable_component::Event,
        OwnedEvent: owned_component::Event,
        SnapshotEvent: SnapshotEvent
    }

    #[abi(embed_v0)]
    impl HasInterfaceImpl of IHasInterface<ContractState> {
        fn get_primary_interface_id(self: @ContractState) -> felt252 {
            return selector!("ekubo_oracle_extension::oracle::Oracle");
        }
    }

    #[generate_trait]
    impl PoolKeyToPairImpl of PoolKeyToPairTrait {
        fn to_pair_key(self: PoolKey) -> (ContractAddress, ContractAddress) {
            assert(self.fee.is_zero(), 'Fee must be 0');
            assert(self.tick_spacing == MAX_TICK_SPACING, 'Tick spacing must be max');
            (self.token0, self.token1)
        }

        fn to_pool_key(self: (ContractAddress, ContractAddress)) -> PoolKey {
            let (token0, token1) = self;

            PoolKey {
                token0,
                token1,
                fee: 0,
                tick_spacing: MAX_TICK_SPACING,
                extension: get_contract_address()
            }
        }
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner: ContractAddress,
        core: ICoreDispatcher,
        oracle_token: ContractAddress
    ) {
        self.initialize_owned(owner);
        self.core.write(core);
        self.set_call_points();
        self.oracle_token.write(oracle_token);
    }

    #[generate_trait]
    impl Internal of InternalTrait {
        fn check_caller_is_core(self: @ContractState) -> ICoreDispatcher {
            let core = self.core.read();
            check_caller_is_core(core);
            core
        }

        // Returns the cumulative tick at the given time. The time must be in between the
        // initialization time of the pool and the current block timestamp.
        fn get_tick_cumulative_at(
            self: @ContractState,
            entry: StoragePath<PoolState>,
            count: u64,
            current_tick: i129,
            time: u64
        ) -> i129 {
            let mut l = 0_u64;
            let mut r = count;
            let (index, snapshot) = loop {
                let mid = (l + r) / 2;
                let snap = entry.snapshots.read(mid);
                if snap.block_timestamp == time {
                    break (mid, snap);
                } else if snap.block_timestamp > time {
                    assert(mid.is_non_zero(), 'Time before first snapshot');
                    r = mid;
                } else {
                    let next = mid + 1;
                    // this is the last snapshot, and it's before the specified time
                    if (next >= count) {
                        break (mid, snap);
                    } else {
                        let next_snap = entry.snapshots.read(next);
                        if next_snap.block_timestamp > time {
                            break (mid, snap);
                        } else {
                            l = next;
                        }
                    }
                }
            };

            if snapshot.block_timestamp == time {
                snapshot.tick_cumulative
            } else {
                let tick = if index == count - 1 {
                    current_tick
                } else {
                    let next = entry.snapshots.read(index + 1);
                    (next.tick_cumulative - snapshot.tick_cumulative)
                        / i129 {
                            mag: (next.block_timestamp - snapshot.block_timestamp).into(),
                            sign: false
                        }
                };
                snapshot.tick_cumulative
                    + tick * i129 { mag: (time - snapshot.block_timestamp).into(), sign: false }
            }
        }
    }

    #[abi(embed_v0)]
    impl OracleImpl of IOracle<ContractState> {
        fn get_earliest_observation_time(
            self: @ContractState, token_a: ContractAddress, token_b: ContractAddress
        ) -> Option<u64> {
            let oracle_token = self.oracle_token.read();

            if token_a == oracle_token || token_b == oracle_token {
                let (token0, token1) = if token_a < token_b {
                    (token_a, token_b)
                } else {
                    (token_b, token_a)
                };
                let entry = self.pool_state.entry((token0, token1));
                let count = entry.count.read();
                if count.is_zero() {
                    Option::None
                } else {
                    let first = entry.snapshots.entry(0).read();
                    Option::Some(first.block_timestamp)
                }
            } else {
                if let Option::Some(time_a) = self
                    .get_earliest_observation_time(oracle_token, token_a) {
                    if let Option::Some(time_b) = self
                        .get_earliest_observation_time(oracle_token, token_b) {
                        Option::Some(max(time_a, time_b))
                    } else {
                        Option::None
                    }
                } else {
                    Option::None
                }
            }
        }

        fn get_average_tick_over_period(
            self: @ContractState,
            base_token: ContractAddress,
            quote_token: ContractAddress,
            start_time: u64,
            end_time: u64
        ) -> i129 {
            let times: Span<(u64, u64)> = array![(start_time, end_time)].span();
            let mut result: Span<i129> = self
                .get_average_tick_over_periods(base_token, quote_token, times);
            *result.pop_front().unwrap()
        }

        fn get_average_tick_over_periods(
            self: @ContractState,
            base_token: ContractAddress,
            quote_token: ContractAddress,
            mut start_and_end_times: Span<(u64, u64)>
        ) -> Span<i129> {
            let current_time = get_block_timestamp();

            let mut results: Array<i129> = array![];

            let oracle_token = self.oracle_token.read();

            if base_token == oracle_token || quote_token == oracle_token {
                let (token0, token1, flipped) = if base_token < quote_token {
                    (base_token, quote_token, false)
                } else {
                    (quote_token, base_token, true)
                };

                let key = (token0, token1);
                let entry = self.pool_state.entry(key);

                let count = entry.count.read();
                assert(count.is_non_zero(), 'Pool not initialized');

                let current_tick = self.core.read().get_pool_price(key.to_pool_key()).tick;

                while let Option::Some((start_time, end_time)) = start_and_end_times.pop_front() {
                    assert(end_time > start_time, 'Period must be > 0 seconds long');
                    assert(*end_time <= current_time, 'Time in future');
                    let start_cumulative = self
                        .get_tick_cumulative_at(entry, count, current_tick, *start_time);
                    let end_cumulative = self
                        .get_tick_cumulative_at(entry, count, current_tick, *end_time);
                    let difference = end_cumulative - start_cumulative;
                    results
                        .append(
                            difference
                                / i129 { mag: (*end_time - *start_time).into(), sign: flipped }
                        );
                };
            } else {
                // use the oracle token to get the quote price and base price, then combine them

                // price is quote_token / oracle_token
                let mut t_quotes = self
                    .get_average_tick_over_periods(oracle_token, quote_token, start_and_end_times);

                // price is oracle_token / base_token
                let mut t_bases = self
                    .get_average_tick_over_periods(base_token, oracle_token, start_and_end_times);

                while let Option::Some(t_quote) = t_quotes.pop_front() {
                    results.append(*t_quote + *t_bases.pop_front().unwrap());
                };
            };

            results.span()
        }

        fn get_average_tick_over_last(
            self: @ContractState,
            base_token: ContractAddress,
            quote_token: ContractAddress,
            period: u64
        ) -> i129 {
            let now = get_block_timestamp();
            self.get_average_tick_over_period(base_token, quote_token, now - period, now)
        }

        fn get_average_tick_history(
            self: @ContractState,
            base_token: ContractAddress,
            quote_token: ContractAddress,
            end_time: u64,
            num_intervals: u32,
            interval_seconds: u32,
        ) -> Span<i129> {
            let mut periods: Array<(u64, u64)> = array![];

            let mut start_time = (end_time - (num_intervals * interval_seconds).into());
            while start_time < end_time {
                periods.append((start_time, start_time + interval_seconds.into()));

                start_time += interval_seconds.into();
            };

            self.get_average_tick_over_periods(base_token, quote_token, periods.span())
        }

        fn get_realized_volatility_over_period(
            self: @ContractState,
            token_a: ContractAddress,
            token_b: ContractAddress,
            end_time: u64,
            num_intervals: u32,
            interval_seconds: u32,
            extrapolated_to: u32
        ) -> u64 {
            assert(num_intervals > 1, 'num_intervals must be g.t. 1');
            let mut history = self
                .get_average_tick_history(
                    token_a, token_b, end_time, num_intervals, interval_seconds
                );

            let mut previous: Option<i129> = Option::None;
            let mut sum: u128 = 0;
            while let Option::Some(next) = history.pop_front() {
                if let Option::Some(prev) = previous {
                    let delta_mag = (*next - prev).mag;
                    sum += delta_mag * delta_mag;
                }
                previous = Option::Some(*next);
            };

            let extrapolated = sum * extrapolated_to.into();

            (extrapolated / (Into::<u32, u128>::into(num_intervals - 1) * interval_seconds.into()))
                .sqrt()
        }

        fn get_price_x128_over_period(
            self: @ContractState,
            base_token: ContractAddress,
            quote_token: ContractAddress,
            start_time: u64,
            end_time: u64,
        ) -> u256 {
            tick_to_price_x128(
                self.get_average_tick_over_period(base_token, quote_token, start_time, end_time)
            )
        }

        fn get_price_x128_over_last(
            self: @ContractState,
            base_token: ContractAddress,
            quote_token: ContractAddress,
            period: u64
        ) -> u256 {
            let now = get_block_timestamp();
            self.get_price_x128_over_period(base_token, quote_token, now - period, now)
        }

        fn get_average_price_x128_history(
            self: @ContractState,
            base_token: ContractAddress,
            quote_token: ContractAddress,
            end_time: u64,
            num_intervals: u32,
            interval_seconds: u32,
        ) -> Span<u256> {
            let mut ticks = self
                .get_average_tick_history(
                    base_token, quote_token, end_time, num_intervals, interval_seconds
                );

            let mut converted: Array<u256> = array![];

            while let Option::Some(next) = ticks.pop_front() {
                converted.append(tick_to_price_x128(*next));
            };

            converted.span()
        }

        fn set_call_points(ref self: ContractState) {
            self
                .core
                .read()
                .set_call_points(
                    CallPoints {
                        // to record the starting timestamp
                        before_initialize_pool: true,
                        after_initialize_pool: false,
                        // in order to record the price at the end of the last block
                        before_swap: true,
                        after_swap: false,
                        // in order to limit position creation to max bounds positions
                        before_update_position: true,
                        after_update_position: false,
                        before_collect_fees: false,
                        after_collect_fees: false,
                    }
                );
        }

        fn get_oracle_token(self: @ContractState) -> ContractAddress {
            self.oracle_token.read()
        }
    }

    pub(crate) const MAX_TICK_SPACING: u128 = 354892;

    #[abi(embed_v0)]
    impl OracleExtension of IExtension<ContractState> {
        fn before_initialize_pool(
            ref self: ContractState, caller: ContractAddress, pool_key: PoolKey, initial_tick: i129
        ) {
            self.check_caller_is_core();

            let oracle_token = self.oracle_token.read();
            assert(
                pool_key.token0 == oracle_token || pool_key.token1 == oracle_token,
                'Must use oracle token'
            );

            let key = pool_key.to_pair_key();

            let state = self.pool_state.entry(key);

            let snapshot = Snapshot {
                block_timestamp: get_block_timestamp(), tick_cumulative: Zero::zero(),
            };
            state.count.write(1);
            state.snapshots.write(0, snapshot);
            self
                .emit(
                    SnapshotEvent {
                        token0: pool_key.token0, token1: pool_key.token1, index: 0, snapshot
                    }
                )
        }

        fn after_initialize_pool(
            ref self: ContractState, caller: ContractAddress, pool_key: PoolKey, initial_tick: i129
        ) {
            assert(false, 'Call point not used');
        }

        fn before_swap(
            ref self: ContractState,
            caller: ContractAddress,
            pool_key: PoolKey,
            params: SwapParameters
        ) {
            let core = self.check_caller_is_core();
            let key = pool_key.to_pair_key();
            let state = self.pool_state.entry(key);

            // we know if core is calling this, the pool is initialized i.e. count is greater tha 0
            let count = state.count.read();
            let last_snapshot = state.snapshots.read(count - 1);

            let time = get_block_timestamp();
            let time_passed = time - last_snapshot.block_timestamp;

            if (time_passed.is_zero()) {
                return;
            }

            let tick = core.get_pool_price(pool_key).tick;

            let snapshot = Snapshot {
                block_timestamp: time,
                tick_cumulative: last_snapshot.tick_cumulative
                    + (tick * i129 { mag: time_passed.into(), sign: false }),
            };
            state.count.write(count + 1);
            state.snapshots.write(count, snapshot);
            self
                .emit(
                    SnapshotEvent {
                        token0: pool_key.token0, token1: pool_key.token1, index: count, snapshot
                    }
                );
        }

        fn after_swap(
            ref self: ContractState,
            caller: ContractAddress,
            pool_key: PoolKey,
            params: SwapParameters,
            delta: Delta
        ) {
            assert(false, 'Call point not used');
        }

        fn before_update_position(
            ref self: ContractState,
            caller: ContractAddress,
            pool_key: PoolKey,
            params: UpdatePositionParameters
        ) {
            assert(
                params
                    .bounds == Bounds {
                        lower: i129 { mag: 88368108, sign: true },
                        upper: i129 { mag: 88368108, sign: false },
                    },
                'Position must be full range'
            );

            let oracle_token = self.oracle_token.read();

            // must be using the oracle token in the pool, or withdrawing liquidity
            assert(
                pool_key.token0 == oracle_token
                    || pool_key.token1 == oracle_token
                    || params.liquidity_delta.is_zero()
                    || params.liquidity_delta.sign,
                'Must use oracle token'
            );
        }

        fn after_update_position(
            ref self: ContractState,
            caller: ContractAddress,
            pool_key: PoolKey,
            params: UpdatePositionParameters,
            delta: Delta
        ) {
            assert(false, 'Call point not used');
        }

        fn before_collect_fees(
            ref self: ContractState,
            caller: ContractAddress,
            pool_key: PoolKey,
            salt: felt252,
            bounds: Bounds
        ) {
            assert(false, 'Call point not used');
        }

        fn after_collect_fees(
            ref self: ContractState,
            caller: ContractAddress,
            pool_key: PoolKey,
            salt: felt252,
            bounds: Bounds,
            delta: Delta
        ) {
            assert(false, 'Call point not used');
        }
    }
}
