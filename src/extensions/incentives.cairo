use ekubo::interfaces::core::ICoreDispatcherTrait;
use ekubo::types::keys::{PoolKey, PositionKey};
use ekubo::types::i129::{i129};
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
    // todo: pack timestamp and tick last
    tick_last: i129,
    block_timestamp_last: u64,
    seconds_per_liquidity_global: SecondsPerLiquidity,
}

#[starknet::interface]
trait IIncentives<TStorage> {
    // Returns the number of seconds that the position has held the full liquidity of the pool, as a fixed point number with 128 bits after the radix
    fn get_liquidity_seconds(self: @TStorage, pool_key: PoolKey, position_key: PositionKey) -> u256;
}

// This extension can be used with pools to track the liquidity-seconds per liquidity over time. This measure can be used to incentive positions in this pool.
#[starknet::contract]
mod Incentives {
    use super::{IIncentives, PoolKey, PositionKey, PoolState, SecondsPerLiquidity};
    use ekubo::types::call_points::{CallPoints};
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
        position_snapshots: LegacyMap<(PoolKey, PositionKey), SecondsPerLiquidity>,
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

        fn update_seconds_per_liquidity_global(
            ref self: ContractState, core: ICoreDispatcher, pool_key: PoolKey
        ) {
            let state = self.pool_state.read(pool_key);

            let time = get_block_timestamp();

            if (state.block_timestamp_last == time) {
                return ();
            }

            let pool = core.get_pool(pool_key);

            if (pool.liquidity.is_non_zero()) {
                let seconds_per_liquidity_global_next = SecondsPerLiquidity {
                    inner: state.seconds_per_liquidity_global.inner
                        + (u256 {
                            low: 0, high: (time - state.block_timestamp_last).into()
                            } / u256 {
                            low: pool.liquidity, high: 0
                        })
                };

                self
                    .pool_state
                    .write(
                        pool_key,
                        PoolState {
                            tick_last: state.tick_last,
                            block_timestamp_last: time,
                            seconds_per_liquidity_global: seconds_per_liquidity_global_next,
                        }
                    );
            } else {
                self
                    .pool_state
                    .write(
                        pool_key,
                        PoolState {
                            tick_last: state.tick_last,
                            block_timestamp_last: time,
                            // we don't increment it at all with 0 liquidity,
                            // which makes it seem like time stopped from a rewards perspective
                            seconds_per_liquidity_global: state.seconds_per_liquidity_global,
                        }
                    );
            }
        }
    }

    #[external(v0)]
    impl IncentivesImpl of IIncentives<ContractState> {
        // Returns the number of seconds that the position has held the full liquidity of the pool, as a fixed point number with 128 bits after the radix
        fn get_liquidity_seconds(
            self: @ContractState, pool_key: PoolKey, position_key: PositionKey
        ) -> u256 {
            let time = get_block_timestamp();
            let pool = self.core.read().get_pool(pool_key);

            // subtract the lower and upper tick of the bounds based on the price
            let seconds_per_liquiidty_inside = if (pool.tick < position_key.bounds.lower) {
                let lower = self.tick_state.read((pool_key, position_key.bounds.lower));
                let upper = self.tick_state.read((pool_key, position_key.bounds.upper));

                unsafe_sub(upper.inner, lower.inner)
            } else if (pool.tick < position_key.bounds.upper) {
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

                let lower = self.tick_state.read((pool_key, position_key.bounds.lower));
                let upper = self.tick_state.read((pool_key, position_key.bounds.upper));

                unsafe_sub(unsafe_sub(seconds_per_liquidity_global, lower.inner), upper.inner)
            } else {
                let lower = self.tick_state.read((pool_key, position_key.bounds.lower));
                let upper = self.tick_state.read((pool_key, position_key.bounds.upper));
                unsafe_sub(upper.inner, lower.inner)
            };

            let snapshot = self.position_snapshots.read((pool_key, position_key));

            unsafe_sub(snapshot.inner, seconds_per_liquiidty_inside)
        }
    }

    #[external(v0)]
    impl IncentivesExtension of IExtension<ContractState> {
        fn before_initialize_pool(
            ref self: ContractState, caller: ContractAddress, pool_key: PoolKey, initial_tick: i129
        ) -> CallPoints {
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
            self.update_seconds_per_liquidity_global(core, pool_key);
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

            loop {
                if (tick == pool.tick) {
                    break ();
                }

                let next_initialized = if (tick < pool.tick) {
                    core.next_initialized_tick(pool_key, tick, params.skip_ahead)
                } else {
                    core.prev_initialized_tick(pool_key, tick, params.skip_ahead)
                };
            };

            self
                .pool_state
                .write(
                    pool_key,
                    PoolState {
                        tick_last: pool.tick,
                        block_timestamp_last: state.block_timestamp_last,
                        seconds_per_liquidity_global: state.seconds_per_liquidity_global
                    }
                );
        }

        fn before_update_position(
            ref self: ContractState,
            caller: ContractAddress,
            pool_key: PoolKey,
            params: UpdatePositionParameters
        ) {
            let core = self.check_caller_is_core();
            self.update_seconds_per_liquidity_global(core, pool_key);
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
