use starknet::{ContractAddress};

#[derive(Drop, Copy, Serde, storage_access::StorageAccess)]
struct ExtensionCalled {
    call_point: u32,
    token0: ContractAddress,
    token1: ContractAddress,
    fee: u128,
    tick_spacing: u128,
}

#[starknet::interface]
trait IMockExtension<TStorage> {
    fn get_num_calls(self: @TStorage) -> u32;
    fn get_call(self: @TStorage, call_id: u32) -> ExtensionCalled;
}

#[starknet::contract]
mod MockExtension {
    use super::{IMockExtension, ExtensionCalled, ContractAddress};
    use ekubo::interfaces::core::{IExtension, ICoreDispatcher, ICoreDispatcherTrait};
    use ekubo::types::keys::{PoolKey};
    use ekubo::types::i129::i129;
    use ekubo::types::delta::{Delta};
    use ekubo::interfaces::core::{SwapParameters, UpdatePositionParameters};
    use starknet::{get_caller_address};
    use zeroable::Zeroable;
    use ekubo::types::call_points::{CallPoints, all_call_points};
    use traits::{Into};
    use debug::PrintTrait;

    #[storage]
    struct Storage {
        core: ContractAddress,
        core_locker: ContractAddress,
        num_calls: u32,
        calls: LegacyMap<u32, ExtensionCalled>,
        call_points: CallPoints
    }

    #[generate_trait]
    impl InternalMethods of InternalTrait {
        fn check_caller_is_core(self: @ContractState) {
            assert(get_caller_address() == self.core.read(), 'CORE_ONLY');
        }

        fn insert_call(ref self: ContractState, call_point: u32, pool_key: PoolKey) {
            let num_calls = self.num_calls.read();
            self
                .calls
                .write(
                    num_calls,
                    ExtensionCalled {
                        call_point: call_point,
                        token0: pool_key.token0,
                        token1: pool_key.token1,
                        fee: pool_key.fee,
                        tick_spacing: pool_key.tick_spacing,
                    }
                );
            self.num_calls.write(num_calls + 1);
        }
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        _core: ContractAddress,
        _core_locker: ContractAddress,
        _call_points_u8: u8
    ) {
        self.core.write(_core);
        self.core_locker.write(_core_locker);
        self.call_points.write(_call_points_u8.into());
    }

    #[external(v0)]
    impl ExtensionImpl of IExtension<ContractState> {
        fn before_initialize_pool(
            ref self: ContractState, pool_key: PoolKey, initial_tick: i129
        ) -> CallPoints {
            self.check_caller_is_core();

            let pool = ICoreDispatcher {
                contract_address: get_caller_address()
            }.get_pool(pool_key);

            assert(pool.sqrt_ratio.is_zero(), 'pool is not init');

            self.insert_call(0, pool_key);

            self.call_points.read()
        }
        fn after_initialize_pool(ref self: ContractState, pool_key: PoolKey, initial_tick: i129) {
            self.check_caller_is_core();
            self.insert_call(1, pool_key);

            let pool = ICoreDispatcher {
                contract_address: get_caller_address()
            }.get_pool(pool_key);

            assert(pool.sqrt_ratio.is_non_zero(), 'pool is init');
        }

        fn before_swap(ref self: ContractState, pool_key: PoolKey, params: SwapParameters) {
            self.check_caller_is_core();
            self.insert_call(2, pool_key);
        }
        fn after_swap(
            ref self: ContractState, pool_key: PoolKey, params: SwapParameters, delta: Delta
        ) {
            self.check_caller_is_core();
            self.insert_call(3, pool_key);
        }

        fn before_update_position(
            ref self: ContractState, pool_key: PoolKey, params: UpdatePositionParameters
        ) {
            self.check_caller_is_core();
            self.insert_call(4, pool_key);
        }
        fn after_update_position(
            ref self: ContractState,
            pool_key: PoolKey,
            params: UpdatePositionParameters,
            delta: Delta
        ) {
            self.check_caller_is_core();
            self.insert_call(5, pool_key);
        }
    }

    #[external(v0)]
    impl MockExtensionImpl of IMockExtension<ContractState> {
        fn get_num_calls(self: @ContractState) -> u32 {
            self.num_calls.read()
        }

        fn get_call(self: @ContractState, call_id: u32) -> ExtensionCalled {
            self.calls.read(call_id)
        }
    }
}
