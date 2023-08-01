use ekubo::types::i129::{i129};
use starknet::{ContractAddress};

trait ILimitOrder<TContractState> {
    fn place_order(
        ref self: TContractState,
        sell_token: ContractAddress,
        quote_token: ContractAddress,
        tick: i129
    );
}

#[starknet::contract]
mod LimitOrderExtension {
    use super::{ILimitOrder, i129, ContractAddress};
    use ekubo::interfaces::core::{
        IExtension, SwapParameters, UpdatePositionParameters, Delta, ILocker, ICoreDispatcher,
        ICoreDispatcherTrait
    };
    use ekubo::types::keys::{PoolKey, PositionKey};
    use ekubo::types::bounds::{Bounds};
    use ekubo::types::call_points::{CallPoints};
    use zeroable::{Zeroable};
    use starknet::{get_contract_address, get_caller_address};
    use ekubo::math::utils::{ContractAddressOrder};
    use ekubo::shared_locker::{call_core_with_callback};
    use array::{ArrayTrait};
    use option::{OptionTrait};
    use ekubo::math::swap::{is_price_increasing};


    #[storage]
    struct Storage {
        core: ICoreDispatcher,
        last_seen_pool_key_tick: LegacyMap<PoolKey, i129>,
    }

    #[constructor]
    fn constructor(ref self: ContractState, core: ICoreDispatcher) {
        self.core.write(core);
    }

    #[external(v0)]
    impl ExtensionImpl of IExtension<ContractState> {
        fn before_initialize_pool(
            ref self: ContractState, caller: ContractAddress, pool_key: PoolKey, initial_tick: i129
        ) -> CallPoints {
            assert(pool_key.fee.is_zero(), 'ZERO_FEE');
            assert(pool_key.tick_spacing == 1, 'TICK_SPACING_ONE');

            self.last_seen_pool_key_tick.write(pool_key, initial_tick);

            CallPoints {
                after_initialize_pool: false,
                before_swap: false,
                after_swap: true,
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
            assert(false, 'NOT_USED');
        }


        fn after_swap(
            ref self: ContractState,
            caller: ContractAddress,
            pool_key: PoolKey,
            params: SwapParameters,
            delta: Delta
        ) {
            // implement this
            let core = self.core.read();

            let price = core.get_pool_price(pool_key);

            let mut last_seen_tick = self.last_seen_pool_key_tick.read(pool_key);

            let price_increasing = is_price_increasing(params.amount.sign, params.is_token1);

            loop {
                let (next_tick, is_initialized) = if price_increasing {
                    core.next_initialized_tick(pool_key, last_seen_tick, params.skip_ahead)
                } else {
                    core.prev_initialized_tick(pool_key, last_seen_tick, params.skip_ahead)
                };

                if ((last_seen_tick >= price.tick) == price_increasing) {
                    break ();
                };
            };

            self.last_seen_pool_key_tick.write(pool_key, price.tick);
        }

        fn before_update_position(
            ref self: ContractState,
            caller: ContractAddress,
            pool_key: PoolKey,
            params: UpdatePositionParameters
        ) {
            assert(caller == get_contract_address(), 'ONLY_LIMIT_ORDERS');
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


    #[derive(Serde, Copy, Drop)]
    struct PlaceOrderCallbackData {
        pool_key: PoolKey,
        tick: i129,
        sell_token: ContractAddress
    }

    #[derive(Serde, Copy, Drop)]
    struct PullLimitOrderCallbackData {
        pool_key: PoolKey,
        tick: i129,
    }

    #[derive(Serde, Copy, Drop)]
    enum LockCallbackData {
        PlaceOrderCallbackData: PlaceOrderCallbackData,
        PullLimitOrderCallbackData: PullLimitOrderCallbackData,
    }

    #[derive(Serde, Copy, Drop)]
    struct LockCallbackResult {}

    #[external(v0)]
    impl LockerImpl of ILocker<ContractState> {
        fn locked(ref self: ContractState, id: u32, data: Array<felt252>) -> Array<felt252> {
            let core = self.core.read();
            assert(core.contract_address == get_caller_address(), 'CALLER_IS_CORE');

            let mut data_span = data.span();

            let callback_data = Serde::<LockCallbackData>::deserialize(ref data_span).unwrap();

            let result = match callback_data {
                LockCallbackData::PlaceOrderCallbackData(place_order) => {
                    let delta = core
                        .update_position(
                            pool_key: place_order.pool_key,
                            params: UpdatePositionParameters {
                                salt: 0, bounds: Bounds {
                                    lower: place_order.tick, upper: place_order.tick + i129 {
                                        mag: 1, sign: false
                                    },
                                    }, // TODO: compute it from the balance of this contract
                                    liquidity_delta: i129 {
                                    mag: 1, sign: false
                                }
                            }
                        );

                    // IERC20Dispatcher { contract_address: callback_data.sell_token }
                    //  .transfer(core.contract_address, delta.amount0 | delta.amount1);
                    core.deposit(place_order.sell_token);

                    LockCallbackResult {}
                },
                LockCallbackData::PullLimitOrderCallbackData(pull_data) => {
                    // get the position data
                    let position_data = core
                        .get_position(
                            pull_data.pool_key,
                            PositionKey {
                                salt: 0, owner: get_contract_address(), bounds: Bounds {
                                    lower: pull_data.tick, upper: pull_data.tick + i129 {
                                        mag: 1, sign: false
                                    },
                                }
                            }
                        );

                    let delta = core
                        .update_position(
                            pool_key: pull_data.pool_key,
                            params: UpdatePositionParameters {
                                salt: 0, bounds: Bounds {
                                    lower: pull_data.tick, upper: pull_data.tick + i129 {
                                        mag: 1, sign: false
                                    },
                                    }, liquidity_delta: i129 {
                                    mag: position_data.liquidity, sign: true
                                }
                            }
                        );
                    LockCallbackResult {}
                }
            };

            let mut result_data = ArrayTrait::<felt252>::new();

            Serde::serialize(@result, ref result_data);

            result_data
        }
    }

    #[external(v0)]
    impl LimitOrderImpl of ILimitOrder<ContractState> {
        fn place_order(
            ref self: ContractState,
            sell_token: ContractAddress,
            quote_token: ContractAddress,
            tick: i129
        ) {
            let (token0, token1) = if (sell_token < quote_token) {
                (sell_token, quote_token)
            } else {
                (quote_token, sell_token)
            };

            let pool_key = PoolKey {
                token0, token1, fee: 0, tick_spacing: 1, extension: get_contract_address()
            };

            // validate the pool key is initialized

            let core = self.core.read();
            let price = core.get_pool_price(pool_key);

            assert(price.tick == tick, 'TICK_ON_PRICE');

            let callback_data = PlaceOrderCallbackData { pool_key, tick, sell_token };
            let result: LockCallbackResult = call_core_with_callback(core, @callback_data);
        }
    }
}
