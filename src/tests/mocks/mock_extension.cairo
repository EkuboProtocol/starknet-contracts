#[starknet::contract]
mod MockExtension {
    use ekubo::interfaces::core::{IExtension};
    use starknet::{get_caller_address};
    #[storage]
    struct Storage {
        core: ContractAddress, 
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn check_caller_is_core() {
            assert(get_caller_address() == self.core.read(), 'CORE_ONLY');
        }
    }

    #[constructor]
    fn constructor(_core: ContractAddress) {
        self.core.write(_core);
    }

    #[external(v0)]
    impl MockExtensionImpl of IExtension<ContractState> {
        fn before_initialize_pool(ref self: ContractState, pool_key: PoolKey, initial_tick: i129) {
            self.check_caller_is_core();
        }
        fn after_initialize_pool(ref self: ContractState, pool_key: PoolKey, initial_tick: i129) {
            self.check_caller_is_core();
        }

        fn before_swap(ref self: ContractState, pool_key: PoolKey, params: SwapParameters) {
            self.check_caller_is_core();
        }
        fn after_swap(
            ref self: ContractState, pool_key: PoolKey, params: SwapParameters, delta: Delta
        ) {
            self.check_caller_is_core();
        }

        fn before_update_position(
            ref self: ContractState, pool_key: PoolKey, params: UpdatePositionParameters
        ) {
            self.check_caller_is_core();
        }
        fn after_update_position(
            ref self: ContractState,
            pool_key: PoolKey,
            params: UpdatePositionParameters,
            delta: Delta
        ) {
            self.check_caller_is_core();
        }
    }
}
