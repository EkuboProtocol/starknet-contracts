use ekubo::types::keys::{PoolKey};

#[starknet::interface]
trait IIncentives<TStorage> {
    fn create(ref self: TStorage, pool_key: PoolKey);
}

#[starknet::contract]
mod Incentives {
    use super::{IIncentives, PoolKey};
    use ekubo::types::call_points::{CallPoints};
    use ekubo::types::i129::{i129};
    use ekubo::interfaces::core::{IExtension, SwapParameters, UpdatePositionParameters, Delta};
    use starknet::{ContractAddress};

    #[storage]
    struct Storage {
        core: ContractAddress
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
                before_swap: false,
                after_swap: true,
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
