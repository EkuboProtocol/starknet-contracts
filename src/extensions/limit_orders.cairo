use ekubo::types::i129::{i129};
use starknet::{ContractAddress};

#[derive(Drop, Copy, Serde, starknet::Store)]
struct OrderInfo {
    sell_token: ContractAddress,
    buy_token: ContractAddress,
    owner: ContractAddress,
    liquidity: u128,
}

#[starknet::interface]
trait ILimitOrders<TContractState> {
    // Returns the stored order state
    fn get_order_info(self: @TContractState, order_id: u64) -> OrderInfo;

    // Creates a new limit order, selling the given `sell_token` for the given `buy_token` at the specified tick
    // The size of the order is determined by the current balance of the sell token
    fn place_order(
        ref self: TContractState,
        sell_token: ContractAddress,
        buy_token: ContractAddress,
        tick: i129
    ) -> u64;

    // Closes an order with the given token ID, returning the amount of token0 and token1 to the recipient
    fn close_order(
        ref self: TContractState, order_id: u64, recipient: ContractAddress
    ) -> (u128, u128);
}

#[starknet::contract]
mod LimitOrders {
    use super::{ILimitOrders, i129, ContractAddress, OrderInfo};
    use ekubo::interfaces::core::{
        IExtension, SwapParameters, UpdatePositionParameters, Delta, ILocker, ICoreDispatcher,
        ICoreDispatcherTrait
    };
    use ekubo::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use ekubo::types::keys::{PoolKey, PositionKey};
    use ekubo::types::bounds::{Bounds};
    use ekubo::types::call_points::{CallPoints};
    use ekubo::math::ticks::{tick_to_sqrt_ratio};
    use zeroable::{Zeroable};
    use starknet::{get_contract_address, get_caller_address};
    use ekubo::math::utils::{ContractAddressOrder};
    use ekubo::shared_locker::{call_core_with_callback};
    use array::{ArrayTrait};
    use option::{OptionTrait};
    use ekubo::math::swap::{is_price_increasing};
    use ekubo::math::liquidity::{max_liquidity_for_token0, max_liquidity_for_token1};
    use traits::{TryInto, Into};

    #[storage]
    struct Storage {
        core: ICoreDispatcher,
        last_seen_pool_key_tick: LegacyMap<PoolKey, i129>,
        orders: LegacyMap<u64, OrderInfo>,
        next_order_id: u64,
    }

    #[constructor]
    fn constructor(ref self: ContractState, core: ICoreDispatcher) {
        self.core.write(core);
        self.next_order_id.write(1);
    }


    #[derive(Serde, Copy, Drop)]
    struct PlaceOrderCallbackData {
        pool_key: PoolKey,
        is_token1: bool,
        tick: i129,
        liquidity: u128,
    }

    #[derive(Serde, Copy, Drop)]
    struct HandleAfterSwapCallbackData {
        pool_key: PoolKey,
        skip_ahead: u32,
    }

    #[derive(Serde, Copy, Drop)]
    enum LockCallbackData {
        PlaceOrderCallbackData: PlaceOrderCallbackData,
        HandleAfterSwapCallbackData: HandleAfterSwapCallbackData,
    }

    #[derive(Serde, Copy, Drop)]
    struct LockCallbackResult {}

    #[external(v0)]
    impl ExtensionImpl of IExtension<ContractState> {
        fn before_initialize_pool(
            ref self: ContractState, caller: ContractAddress, pool_key: PoolKey, initial_tick: i129
        ) -> CallPoints {
            assert(pool_key.fee.is_zero(), 'ZERO_FEE_ONLY');
            assert(pool_key.tick_spacing == 1, 'TICK_SPACING_ONE_ONLY');

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

            let callback_data = HandleAfterSwapCallbackData {
                pool_key, skip_ahead: params.skip_ahead
            };
            let result: LockCallbackResult = call_core_with_callback(core, @callback_data);
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
    #[external(v0)]
    impl LockerImpl of ILocker<ContractState> {
        fn locked(ref self: ContractState, id: u32, data: Array<felt252>) -> Array<felt252> {
            let core = self.core.read();
            assert(core.contract_address == get_caller_address(), 'CALLER_IS_CORE');

            let mut data_span = data.span();

            let callback_data = Serde::<LockCallbackData>::deserialize(ref data_span)
                .expect('LOCK_CALLBACK_DESERIALIZE');

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
                                    mag: place_order.liquidity, sign: false
                                }
                            }
                        );

                    let (pay_token, pay_amount) = if place_order.is_token1 {
                        (place_order.pool_key.token1, delta.amount1.mag)
                    } else {
                        (place_order.pool_key.token0, delta.amount0.mag)
                    };

                    IERC20Dispatcher {
                        contract_address: pay_token
                    }.transfer(core.contract_address, pay_amount.into());
                    core.deposit(pay_token);

                    LockCallbackResult {}
                },
                LockCallbackData::HandleAfterSwapCallbackData(after_swap) => {
                    let price_after_swap = core.get_pool_price(after_swap.pool_key);
                    let mut last_seen_tick = self.last_seen_pool_key_tick.read(after_swap.pool_key);

                    if (price_after_swap.tick != last_seen_tick) {
                        let price_increasing = price_after_swap.tick > last_seen_tick;

                        loop {
                            let (next_tick, is_initialized) = if price_increasing {
                                core
                                    .next_initialized_tick(
                                        after_swap.pool_key, last_seen_tick, after_swap.skip_ahead
                                    )
                            } else {
                                core
                                    .prev_initialized_tick(
                                        after_swap.pool_key, last_seen_tick, after_swap.skip_ahead
                                    )
                            };

                            if ((next_tick >= price_after_swap.tick) == price_increasing) {
                                break ();
                            };

                            if (is_initialized) {
                                let position_data = core
                                    .get_position(
                                        after_swap.pool_key,
                                        PositionKey {
                                            salt: 0, owner: get_contract_address(), bounds: Bounds {
                                                lower: next_tick, upper: next_tick + i129 {
                                                    mag: 1, sign: false
                                                },
                                            }
                                        }
                                    );

                                core
                                    .update_position(
                                        after_swap.pool_key,
                                        UpdatePositionParameters {
                                            salt: 0, bounds: Bounds {
                                                lower: next_tick, upper: next_tick + i129 {
                                                    mag: 1, sign: false
                                                },
                                                }, liquidity_delta: i129 {
                                                mag: position_data.liquidity, sign: true
                                            }
                                        }
                                    );
                            };
                        };

                        self
                            .last_seen_pool_key_tick
                            .write(after_swap.pool_key, price_after_swap.tick);
                    }

                    LockCallbackResult {}
                }
            };

            let mut result_data = ArrayTrait::<felt252>::new();

            Serde::serialize(@result, ref result_data);

            result_data
        }
    }

    #[external(v0)]
    impl LimitOrderImpl of ILimitOrders<ContractState> {
        fn get_order_info(self: @ContractState, order_id: u64) -> OrderInfo {
            self.orders.read(order_id)
        }

        fn place_order(
            ref self: ContractState,
            sell_token: ContractAddress,
            buy_token: ContractAddress,
            tick: i129,
        ) -> u64 {
            // orders can only be placed on even ticks
            // this means we know even ticks are always the specified price
            // this allows us to optimize iterating through ticks, by only considering even ticks
            assert(tick.mag % 2 == 0, 'EVEN_TICKS_ONLY');

            let order_id = self.next_order_id.read();
            self.next_order_id.write(order_id + 1);
            let (token0, token1, is_token1) = if (sell_token < buy_token) {
                (sell_token, buy_token, false)
            } else {
                (buy_token, sell_token, true)
            };

            let pool_key = PoolKey {
                token0, token1, fee: 0, tick_spacing: 1, extension: get_contract_address()
            };

            // validate the pool key is initialized
            let core = self.core.read();
            let price = core.get_pool_price(pool_key);

            assert(price.sqrt_ratio.is_non_zero(), 'POOL_NOT_INITIALIZED');

            assert(
                price.tick != tick, 'PRICE_AT_TICK'
            ); // cannot place an order at the current tick

            assert(
                if is_token1 {
                    tick < price.tick
                } else {
                    tick > price.tick
                }, 'TICK_WRONG_SIDE'
            );

            let sqrt_ratio_lower = tick_to_sqrt_ratio(tick);
            let sqrt_ratio_upper = tick_to_sqrt_ratio(tick + i129 { mag: 1, sign: false });
            let amount: u128 = IERC20Dispatcher {
                contract_address: sell_token
            }.balanceOf(get_contract_address()).try_into().expect('SELL_BALANCE_TOO_LARGE');
            let liquidity = if is_token1 {
                max_liquidity_for_token1(sqrt_ratio_lower, sqrt_ratio_upper, amount)
            } else {
                max_liquidity_for_token0(sqrt_ratio_lower, sqrt_ratio_upper, amount)
            };

            assert(liquidity > 0, 'SELL_AMOUNT_TOO_SMALL');

            self
                .orders
                .write(
                    order_id,
                    OrderInfo { sell_token, buy_token, owner: get_caller_address(), liquidity }
                );

            let result: LockCallbackResult = call_core_with_callback(
                core,
                @LockCallbackData::PlaceOrderCallbackData(
                    PlaceOrderCallbackData { pool_key, tick, is_token1, liquidity }
                )
            );

            order_id
        }

        fn close_order(
            ref self: ContractState, order_id: u64, recipient: ContractAddress
        ) -> (u128, u128) {
            let order_info = self.orders.read(order_id);
            assert(get_caller_address() == order_info.owner, 'OWNER_ONLY');

            (0, 0)
        }
    }
}
