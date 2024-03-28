use ekubo::types::keys::{PoolKey};
use starknet::{ContractAddress};

#[derive(Drop, Copy, Serde, starknet::Store)]
pub struct ExtensionCalled {
    pub caller: ContractAddress,
    pub call_point: u32,
    pub token0: ContractAddress,
    pub token1: ContractAddress,
    pub fee: u128,
    pub tick_spacing: u128,
}

#[starknet::interface]
pub trait IMockExtension<TStorage> {
    fn get_num_calls(self: @TStorage) -> u32;
    fn get_call(self: @TStorage, call_id: u32) -> ExtensionCalled;

    fn call_into_pool(self: @TStorage, pool_key: PoolKey);
}

#[starknet::contract]
pub mod MockExtension {
    use core::array::{ArrayTrait};
    use core::num::traits::{Zero};
    use core::option::{OptionTrait};
    use core::traits::{Into, TryInto};
    use ekubo::components::shared_locker::{call_core_with_callback, consume_callback_data};
    use ekubo::interfaces::core::{IExtension, ILocker, ICoreDispatcher, ICoreDispatcherTrait};
    use ekubo::interfaces::core::{SwapParameters, UpdatePositionParameters};
    use ekubo::math::ticks::{min_sqrt_ratio, max_sqrt_ratio};
    use ekubo::types::bounds::{Bounds, max_bounds};
    use ekubo::types::call_points::{CallPoints, all_call_points};
    use ekubo::types::delta::{Delta};
    use ekubo::types::i129::i129;
    use ekubo::types::keys::{PoolKey};
    use starknet::{get_caller_address};
    use super::{IMockExtension, ExtensionCalled, ContractAddress};

    #[storage]
    struct Storage {
        core: ICoreDispatcher,
        num_calls: u32,
        calls: LegacyMap<u32, ExtensionCalled>,
        call_points: u8
    }

    #[generate_trait]
    impl InternalMethods of InternalTrait {
        fn get_call_points(self: @ContractState) -> CallPoints {
            TryInto::<u8, CallPoints>::try_into(self.call_points.read()).unwrap()
        }

        fn check_caller_is_core(self: @ContractState) -> ICoreDispatcher {
            let core = self.core.read();
            assert(get_caller_address() == core.contract_address, 'CORE_ONLY');
            core
        }

        fn insert_call(
            ref self: ContractState, caller: ContractAddress, call_point: u32, pool_key: PoolKey
        ) {
            let num_calls = self.num_calls.read();
            self
                .calls
                .write(
                    num_calls,
                    ExtensionCalled {
                        caller: caller,
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
    fn constructor(ref self: ContractState, core: ICoreDispatcher, call_points: CallPoints) {
        self.core.write(core);
        self.call_points.write(call_points.into());
    }

    #[abi(embed_v0)]
    impl ExtensionImpl of IExtension<ContractState> {
        fn before_initialize_pool(
            ref self: ContractState, caller: ContractAddress, pool_key: PoolKey, initial_tick: i129
        ) -> CallPoints {
            let core = self.check_caller_is_core();
            let price = core.get_pool_price(pool_key);
            assert(price.sqrt_ratio.is_zero(), 'pool is not init');

            self.insert_call(caller, 0, pool_key);
            self.get_call_points()
        }
        fn after_initialize_pool(
            ref self: ContractState, caller: ContractAddress, pool_key: PoolKey, initial_tick: i129
        ) {
            let core = self.check_caller_is_core();
            self.insert_call(caller, 1, pool_key);

            let price = core.get_pool_price(pool_key);

            assert(price.sqrt_ratio.is_non_zero(), 'pool is init');
        }

        fn before_swap(
            ref self: ContractState,
            caller: ContractAddress,
            pool_key: PoolKey,
            params: SwapParameters
        ) {
            self.check_caller_is_core();
            self.insert_call(caller, 2, pool_key);
        }
        fn after_swap(
            ref self: ContractState,
            caller: ContractAddress,
            pool_key: PoolKey,
            params: SwapParameters,
            delta: Delta
        ) {
            self.check_caller_is_core();
            self.insert_call(caller, 3, pool_key);
        }

        fn before_update_position(
            ref self: ContractState,
            caller: ContractAddress,
            pool_key: PoolKey,
            params: UpdatePositionParameters
        ) {
            self.check_caller_is_core();
            self.insert_call(caller, 4, pool_key);
        }
        fn after_update_position(
            ref self: ContractState,
            caller: ContractAddress,
            pool_key: PoolKey,
            params: UpdatePositionParameters,
            delta: Delta
        ) {
            self.check_caller_is_core();
            self.insert_call(caller, 5, pool_key);
        }

        fn before_collect_fees(
            ref self: ContractState,
            caller: ContractAddress,
            pool_key: PoolKey,
            salt: felt252,
            bounds: Bounds
        ) {
            self.check_caller_is_core();
            self.insert_call(caller, 6, pool_key);
        }
        fn after_collect_fees(
            ref self: ContractState,
            caller: ContractAddress,
            pool_key: PoolKey,
            salt: felt252,
            bounds: Bounds,
            delta: Delta
        ) {
            self.check_caller_is_core();
            self.insert_call(caller, 7, pool_key);
        }
    }

    #[abi(embed_v0)]
    impl ExtensionLocked of ILocker<ContractState> {
        fn locked(ref self: ContractState, id: u32, data: Span<felt252>) -> Span<felt252> {
            let core = self.core.read();
            let data = consume_callback_data::<CallbackData>(core, data);

            let mut delta: Delta = Zero::zero();

            delta += core
                .swap(
                    data.pool_key,
                    SwapParameters {
                        amount: Zero::zero(),
                        is_token1: false,
                        sqrt_ratio_limit: min_sqrt_ratio(),
                        skip_ahead: 0
                    }
                );

            delta += core
                .update_position(
                    data.pool_key,
                    UpdatePositionParameters {
                        salt: Zero::zero(),
                        bounds: max_bounds(data.pool_key.tick_spacing),
                        liquidity_delta: Zero::zero()
                    }
                );

            delta += core
                .collect_fees(
                    data.pool_key,
                    salt: Zero::zero(),
                    bounds: max_bounds(data.pool_key.tick_spacing)
                );

            assert(delta.is_zero(), 'delta is zero');

            ArrayTrait::new().span()
        }
    }

    #[derive(Serde, Copy, Drop)]
    struct CallbackData {
        pool_key: PoolKey
    }

    #[abi(embed_v0)]
    impl MockExtensionImpl of IMockExtension<ContractState> {
        fn call_into_pool(self: @ContractState, pool_key: PoolKey) {
            call_core_with_callback::<
                CallbackData, ()
            >(self.core.read(), @CallbackData { pool_key });
        }
        fn get_num_calls(self: @ContractState) -> u32 {
            self.num_calls.read()
        }

        fn get_call(self: @ContractState, call_id: u32) -> ExtensionCalled {
            self.calls.read(call_id)
        }
    }
}
