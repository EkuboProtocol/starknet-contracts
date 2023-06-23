use ekubo::interfaces::core::ICoreDispatcherTrait;
use ekubo::types::keys::{PoolKey, PositionKey};
use ekubo::types::i129::{i129};
use ekubo::types::bounds::{Bounds};
use traits::{TryInto, Into};
use option::{Option, OptionTrait};
use starknet::{StorageAccess, SyscallResult, StorageBaseAddress};

// Constraints to 192 bits, used for seconds per liquidity
#[derive(Copy, Drop)]
struct SecondsPerLiquidity {
    inner: u256, 
}

impl SecondsPerLiquidityStorageAccess of StorageAccess<SecondsPerLiquidity> {
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<SecondsPerLiquidity> {
        StorageAccess::<SecondsPerLiquidity>::read_at_offset_internal(address_domain, base, 0_u8)
    }
    fn write(
        address_domain: u32, base: StorageBaseAddress, value: SecondsPerLiquidity
    ) -> SyscallResult<()> {
        StorageAccess::<SecondsPerLiquidity>::write_at_offset_internal(
            address_domain, base, 0_u8, value
        )
    }
    fn read_at_offset_internal(
        address_domain: u32, base: StorageBaseAddress, offset: u8
    ) -> SyscallResult<SecondsPerLiquidity> {
        let x: felt252 = StorageAccess::read_at_offset_internal(address_domain, base, offset)?;

        SyscallResult::Ok(SecondsPerLiquidity { inner: x.into() })
    }
    fn write_at_offset_internal(
        address_domain: u32, base: StorageBaseAddress, offset: u8, value: SecondsPerLiquidity
    ) -> SyscallResult<()> {
        let maybe_felt: Option<felt252> = value.inner.try_into();

        match maybe_felt {
            Option::Some(value) => {
                StorageAccess::<felt252>::write_at_offset_internal(
                    address_domain, base, offset, value
                )
            },
            Option::None(_) => {
                assert(false, 'OVERFLOW_FELT252');
                SyscallResult::Ok(())
            },
        }
    }
    fn size_internal(value: SecondsPerLiquidity) -> u8 {
        1
    }
}

#[derive(Copy, Drop, storage_access::StorageAccess)]
struct PoolState {
    block_timestamp_last: u64,
    tick_cumulative_last: i129,
    tick_last: i129,
    seconds_per_liquidity_global: SecondsPerLiquidity,
}

#[starknet::interface]
trait IIncentives<TStorage> {
    // Returns the seconds per liquidity within the given bounds. Must be used only as a snapshot
    // You cannot rely on this snapshot to be consistent across positions
    fn get_seconds_per_liquidity_inside(self: @TStorage, pool_key: PoolKey, bounds: Bounds) -> u256;

    // Returns the cumulative tick value for a given pool, useful for computing a geomean oracle for the duration of a position
    fn get_tick_cumulative(self: @TStorage, pool_key: PoolKey) -> i129;
}

// This extension can be used with pools to track the liquidity-seconds per liquidity over time. This measure can be used to incentive positions in this pool.
#[starknet::contract]
mod Incentives {
    use super::{IIncentives, PoolKey, PositionKey, PoolState, SecondsPerLiquidity};
    use ekubo::types::call_points::{CallPoints};
    use ekubo::types::bounds::{Bounds};
    use ekubo::types::i129::{i129};
    use ekubo::math::utils::{unsafe_sub};
    use ekubo::interfaces::core::{
        ICoreDispatcher, ICoreDispatcherTrait, IExtension, SwapParameters, UpdatePositionParameters,
        Delta
    };

    use starknet::{ContractAddress, get_block_timestamp, get_caller_address};
    use zeroable::Zeroable;
    use traits::{Into};

    #[storage]
    struct Storage {
        core: ICoreDispatcher,
        pool_state: LegacyMap<PoolKey, PoolState>,
        tick_state: LegacyMap<(PoolKey, i129), SecondsPerLiquidity>,
    }

    #[constructor]
    fn constructor(ref self: ContractState, core: ICoreDispatcher) {
        self.core.write(core);
    }

    #[generate_trait]
    impl Internal of InternalTrait {
        fn check_caller_is_core(self: @ContractState) -> ICoreDispatcher {
            let core = self.core.read();
            assert(core.contract_address == get_caller_address(), 'CALLER_NOT_CORE');
            core
        }

        fn update_pool(ref self: ContractState, core: ICoreDispatcher, pool_key: PoolKey) {
            let state = self.pool_state.read(pool_key);

            let time = get_block_timestamp();
            let time_passed: u128 = (time - state.block_timestamp_last).into();

            if (time_passed.is_zero()) {
                return ();
            }

            let pool = core.get_pool(pool_key);

            let seconds_per_liquidity_global_next = if (pool.liquidity.is_non_zero()) {
                SecondsPerLiquidity {
                    inner: state.seconds_per_liquidity_global.inner
                        + (u256 {
                            low: 0, high: time_passed
                            } / u256 {
                            low: pool.liquidity, high: 0
                        })
                }
            } else {
                state.seconds_per_liquidity_global
            };

            let tick_cumulative_next = state.tick_cumulative_last
                + (pool.tick * i129 { mag: time_passed, sign: false });

            self
                .pool_state
                .write(
                    pool_key,
                    PoolState {
                        block_timestamp_last: time,
                        tick_cumulative_last: tick_cumulative_next,
                        tick_last: state.tick_last,
                        seconds_per_liquidity_global: seconds_per_liquidity_global_next,
                    }
                );
        }
    }

    #[external(v0)]
    impl IncentivesImpl of IIncentives<ContractState> {
        // Returns the number of seconds that the position has held the full liquidity of the pool, as a fixed point number with 128 bits after the radix
        fn get_seconds_per_liquidity_inside(
            self: @ContractState, pool_key: PoolKey, bounds: Bounds
        ) -> u256 {
            let time = get_block_timestamp();
            let pool = self.core.read().get_pool(pool_key);

            // subtract the lower and upper tick of the bounds based on the price
            let lower = self.tick_state.read((pool_key, bounds.lower)).inner;
            let upper = self.tick_state.read((pool_key, bounds.upper)).inner;

            if (pool.tick < bounds.lower) {
                unsafe_sub(upper, lower)
            } else if (pool.tick < bounds.upper) {
                // get the global seconds per liquidity
                let state = self.pool_state.read(pool_key);
                let seconds_per_liquidity_global = if (time == state.block_timestamp_last) {
                    state.seconds_per_liquidity_global.inner
                } else {
                    if (pool.liquidity == 0) {
                        state.seconds_per_liquidity_global.inner
                    } else {
                        state.seconds_per_liquidity_global.inner
                            + (u256 {
                                low: 0, high: (time - state.block_timestamp_last).into()
                                } / u256 {
                                low: pool.liquidity, high: 0
                            })
                    }
                };

                unsafe_sub(unsafe_sub(seconds_per_liquidity_global, lower), upper)
            } else {
                unsafe_sub(upper, lower)
            }
        }

        fn get_tick_cumulative(self: @ContractState, pool_key: PoolKey) -> i129 {
            let time = get_block_timestamp();
            let state = self.pool_state.read(pool_key);

            if (time == state.block_timestamp_last) {
                state.tick_cumulative_last
            } else {
                let pool = self.core.read().get_pool(pool_key);
                state.tick_cumulative_last
                    + (pool.tick * i129 {
                        mag: (time - state.block_timestamp_last).into(), sign: false
                    })
            }
        }
    }

    #[external(v0)]
    impl IncentivesExtension of IExtension<ContractState> {
        fn before_initialize_pool(
            ref self: ContractState, caller: ContractAddress, pool_key: PoolKey, initial_tick: i129
        ) -> CallPoints {
            self.check_caller_is_core();

            self
                .pool_state
                .write(
                    pool_key,
                    PoolState {
                        block_timestamp_last: get_block_timestamp(), tick_cumulative_last: i129 {
                            mag: 0, sign: false
                            },
                            tick_last: initial_tick,
                            seconds_per_liquidity_global: SecondsPerLiquidity {
                            inner: 0
                        },
                    }
                );

            CallPoints {
                after_initialize_pool: false,
                // in order to record the seconds that have passed / liquidity
                before_swap: true,
                // to update the per-tick seconds per liquiidty
                after_swap: true,
                // the same as above
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
            // update seconds per liquidity
            let core = self.check_caller_is_core();
            self.update_pool(core, pool_key);
        }

        fn after_swap(
            ref self: ContractState,
            caller: ContractAddress,
            pool_key: PoolKey,
            params: SwapParameters,
            delta: Delta
        ) {
            let core = self.check_caller_is_core();

            let pool = core.get_pool(pool_key);
            let state = self.pool_state.read(pool_key);

            let mut tick = state.tick_last;

            // update all the ticks between the last updated tick to the starting tick
            loop {
                if (tick == pool.tick) {
                    break ();
                }

                let increasing = tick < pool.tick;

                let (next, initialized) = if (increasing) {
                    core.next_initialized_tick(pool_key, tick, params.skip_ahead)
                } else {
                    core.prev_initialized_tick(pool_key, tick, params.skip_ahead)
                };

                if (initialized) {
                    let current = self.tick_state.read((pool_key, tick));

                    self
                        .tick_state
                        .write(
                            (pool_key, tick),
                            SecondsPerLiquidity {
                                inner: unsafe_sub(
                                    state.seconds_per_liquidity_global.inner, current.inner
                                )
                            }
                        );
                }

                tick = if (increasing) {
                    next
                } else {
                    next - i129 { mag: 1, sign: false }
                };
            };

            if (state.tick_last != pool.tick) {
                // we are just updating tick last to indicate we processed all the ticks that were crossed in the swap
                self
                    .pool_state
                    .write(
                        pool_key,
                        PoolState {
                            block_timestamp_last: state.block_timestamp_last,
                            tick_cumulative_last: state.tick_cumulative_last,
                            tick_last: pool.tick,
                            seconds_per_liquidity_global: state.seconds_per_liquidity_global
                        }
                    );
            }
        }

        fn before_update_position(
            ref self: ContractState,
            caller: ContractAddress,
            pool_key: PoolKey,
            params: UpdatePositionParameters
        ) {
            let core = self.check_caller_is_core();
            self.update_pool(core, pool_key);
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
}
