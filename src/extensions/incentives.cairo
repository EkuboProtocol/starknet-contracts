use ekubo::types::keys::{PoolKey, PositionKey};
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
    seconds_per_liquidity_global: SecondsPerLiquidity,
}

#[starknet::interface]
trait IIncentives<TStorage> {
    fn create(ref self: TStorage, pool_key: PoolKey);
}

#[starknet::contract]
mod Incentives {
    use super::{IIncentives, PoolKey, PositionKey, PoolState, SecondsPerLiquidity};
    use ekubo::types::call_points::{CallPoints};
    use ekubo::types::i129::{i129};
    use ekubo::interfaces::core::{IExtension, SwapParameters, UpdatePositionParameters, Delta};
    use starknet::{ContractAddress};

    #[storage]
    struct Storage {
        core: ContractAddress,
        pool_state: LegacyMap<PoolKey, PoolState>,
        position_state: LegacyMap<(PoolKey, PositionKey), SecondsPerLiquidity>,
        tick_state: LegacyMap<(PoolKey, PositionKey), SecondsPerLiquidity>,
    }

    #[constructor]
    fn constructor(ref self: ContractState, core: ContractAddress) {
        self.core.write(core);
    }

    #[external(v0)]
    impl IncentivesImpl of IIncentives<ContractState> {
        fn create(ref self: ContractState, pool_key: PoolKey) {}
    }

    #[external(v0)]
    impl IncentivesExtension of IExtension<ContractState> {
        fn before_initialize_pool(
            ref self: ContractState, pool_key: PoolKey, initial_tick: i129
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
            ref self: ContractState, pool_key: PoolKey, initial_tick: i129
        ) { // not called
        }

        fn before_swap(ref self: ContractState, pool_key: PoolKey, params: SwapParameters) {}

        fn after_swap(
            ref self: ContractState, pool_key: PoolKey, params: SwapParameters, delta: Delta
        ) {}

        fn before_update_position(
            ref self: ContractState, pool_key: PoolKey, params: UpdatePositionParameters
        ) {}

        fn after_update_position(
            ref self: ContractState,
            pool_key: PoolKey,
            params: UpdatePositionParameters,
            delta: Delta
        ) {}
    }
}
