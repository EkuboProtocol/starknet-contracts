#[starknet::interface]
trait IMockExtension<TStorage> {}

#[starknet::contract]
mod MockExtension {
    use super::IMockExtension;
    use ekubo::interfaces::core::{IExtension};
    use ekubo::types::keys::{PoolKey};
    use ekubo::types::i129::i129;
    use ekubo::types::delta::{Delta};
    use ekubo::interfaces::core::{SwapParameters, UpdatePositionParameters};
    use starknet::{get_caller_address, ContractAddress};


    #[storage]
    struct Storage {
        core: ContractAddress,
        core_locker: ContractAddress,
    }

    #[generate_trait]
    impl InternalMethods of InternalTrait {
        fn check_caller_is_core(self: @ContractState) {
            assert(get_caller_address() == self.core.read(), 'CORE_ONLY');
        }
    }

    #[constructor]
    fn constructor(ref self: ContractState, _core: ContractAddress, _core_locker: ContractAddress) {
        self.core.write(_core);
        self.core_locker.write(_core_locker);
    }

    #[external(v0)]
    impl ExtensionImpl of IExtension<ContractState> {
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

    #[external(v0)]
    impl MockExtensionImpl of IMockExtension<ContractState> {}
}
