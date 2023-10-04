use ekubo::types::i129::{i129};
use starknet::{ContractAddress};
use traits::{Into};

#[derive(Drop, Copy, Serde, Hash)]
struct OrderKey {
    sell_token: ContractAddress,
    buy_token: ContractAddress,
    tick: i129,
}

// State of a particular order, defined by the key
#[derive(Drop, Copy, Serde, starknet::Store)]
struct OrderState {
    ticks_crossed_last: u64,
    liquidity: u128,
}

// The state of the pool as it was last seen
#[derive(Drop, Copy, Serde, starknet::Store)]
struct PoolState {
    // the number of initialized ticks that has been crossed
    ticks_crossed: u64,
    last_tick: i129,
}

#[starknet::interface]
trait ILimitOrders<TContractState> {
    // Return the NFT contract address that this contract uses to represent limit orders
    fn get_nft_address(self: @TContractState) -> ContractAddress;

    // Returns the stored order state
    fn get_order_state(self: @TContractState, order_key: OrderKey, id: u64) -> OrderState;

    // Creates a new limit order, selling the given `sell_token` for the given `buy_token` at the specified tick
    // The size of the new order is determined by the current balance of the sell token
    fn place_order(ref self: TContractState, order_key: OrderKey) -> u64;

    // Closes an order with the given token ID, returning the amount of token0 and token1 to the recipient
    fn close_order(
        ref self: TContractState, order_key: OrderKey, id: u64, recipient: ContractAddress
    ) -> (u128, u128);

    // Clear the token balance held by this contract
    // This contract is non-custodial, i.e. never holds a balance on behalf of a user
    fn clear(ref self: TContractState, token: ContractAddress) -> u256;
}

#[starknet::contract]
mod LimitOrders {
    use array::{ArrayTrait};
    use ekubo::enumerable_owned_nft::{
        EnumerableOwnedNFT, IEnumerableOwnedNFTDispatcher, IEnumerableOwnedNFTDispatcherTrait
    };
    use ekubo::interfaces::core::{
        IExtension, SwapParameters, UpdatePositionParameters, Delta, ILocker, ICoreDispatcher,
        ICoreDispatcherTrait
    };
    use ekubo::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use ekubo::math::contract_address::{ContractAddressOrder};
    use ekubo::math::max_liquidity::{max_liquidity_for_token0, max_liquidity_for_token1};
    use ekubo::math::swap::{is_price_increasing};
    use ekubo::math::ticks::{tick_to_sqrt_ratio};
    use ekubo::shared_locker::{call_core_with_callback};
    use ekubo::types::bounds::{Bounds};
    use ekubo::types::call_points::{CallPoints};
    use ekubo::types::keys::{PoolKey, PositionKey};
    use option::{OptionTrait};
    use starknet::{get_contract_address, get_caller_address, ClassHash};
    use super::{ILimitOrders, i129, ContractAddress, OrderKey, OrderState, PoolState};
    use traits::{TryInto, Into};
    use zeroable::{Zeroable};

    #[storage]
    struct Storage {
        core: ICoreDispatcher,
        nft: IEnumerableOwnedNFTDispatcher,
        pools: LegacyMap<PoolKey, PoolState>,
        orders: LegacyMap<(OrderKey, u64), OrderState>,
        tick_last_cross_epoch: LegacyMap<(PoolKey, i129), u64>,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        core: ICoreDispatcher,
        nft_class_hash: ClassHash,
        token_uri_base: felt252,
    ) {
        self.core.write(core);

        self
            .nft
            .write(
                EnumerableOwnedNFT::deploy(
                    nft_class_hash: nft_class_hash,
                    controller: get_contract_address(),
                    name: 'Ekubo Limit Order',
                    symbol: 'eLO',
                    token_uri_base: token_uri_base,
                    salt: 0
                )
            );
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

    #[external(v0)]
    impl ExtensionImpl of IExtension<ContractState> {
        fn before_initialize_pool(
            ref self: ContractState, caller: ContractAddress, pool_key: PoolKey, initial_tick: i129
        ) -> CallPoints {
            assert(pool_key.fee.is_zero(), 'ZERO_FEE_ONLY');
            assert(pool_key.tick_spacing == 1, 'TICK_SPACING_ONE_ONLY');

            // we choose 1 as starting epoch so we can always tell if a pool is initialized by reading only the local state
            self.pools.write(pool_key, PoolState { ticks_crossed: 1, last_tick: initial_tick });

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
            let core = self.core.read();

            call_core_with_callback::<
                LockCallbackData, ()
            >(
                core,
                @LockCallbackData::HandleAfterSwapCallbackData(
                    HandleAfterSwapCallbackData { pool_key, skip_ahead: params.skip_ahead }
                )
            );
        }

        fn before_update_position(
            ref self: ContractState,
            caller: ContractAddress,
            pool_key: PoolKey,
            params: UpdatePositionParameters
        ) {
            // only this contract can create positions, and the extension will not be called in that case
            assert(false, 'ONLY_LIMIT_ORDERS');
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

            match callback_data {
                LockCallbackData::PlaceOrderCallbackData(place_order) => {
                    let delta = core
                        .update_position(
                            pool_key: place_order.pool_key,
                            params: UpdatePositionParameters {
                                salt: 0,
                                bounds: Bounds {
                                    lower: place_order.tick,
                                    upper: place_order.tick + i129 { mag: 1, sign: false },
                                }, // TODO: compute it from the balance of this contract
                                liquidity_delta: i129 { mag: place_order.liquidity, sign: false }
                            }
                        );

                    let (pay_token, pay_amount) = if place_order.is_token1 {
                        (place_order.pool_key.token1, delta.amount1.mag)
                    } else {
                        (place_order.pool_key.token0, delta.amount0.mag)
                    };

                    IERC20Dispatcher { contract_address: pay_token }
                        .transfer(core.contract_address, pay_amount.into());
                    core.deposit(pay_token);
                },
                LockCallbackData::HandleAfterSwapCallbackData(after_swap) => {
                    let price_after_swap = core.get_pool_price(after_swap.pool_key);
                    let state = self.pools.read(after_swap.pool_key);
                    let mut ticks_crossed = state.ticks_crossed;

                    if (price_after_swap.tick != state.last_tick) {
                        let price_increasing = price_after_swap.tick > state.last_tick;

                        loop {
                            let (next_tick, is_initialized) = if price_increasing {
                                core
                                    .next_initialized_tick(
                                        after_swap.pool_key, state.last_tick, after_swap.skip_ahead
                                    )
                            } else {
                                core
                                    .prev_initialized_tick(
                                        after_swap.pool_key, state.last_tick, after_swap.skip_ahead
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
                                            salt: 0,
                                            owner: get_contract_address(),
                                            bounds: Bounds {
                                                lower: next_tick,
                                                upper: next_tick + i129 { mag: 1, sign: false },
                                            }
                                        }
                                    );

                                core
                                    .update_position(
                                        after_swap.pool_key,
                                        UpdatePositionParameters {
                                            salt: 0,
                                            bounds: Bounds {
                                                lower: next_tick,
                                                upper: next_tick + i129 { mag: 1, sign: false },
                                            },
                                            liquidity_delta: i129 {
                                                mag: position_data.liquidity, sign: true
                                            }
                                        }
                                    );

                                ticks_crossed += 1;
                                self
                                    .tick_last_cross_epoch
                                    .write((after_swap.pool_key, next_tick), ticks_crossed);
                            };
                        };

                        self
                            .pools
                            .write(
                                after_swap.pool_key,
                                PoolState {
                                    ticks_crossed: ticks_crossed, last_tick: price_after_swap.tick
                                }
                            );
                    }
                }
            };

            ArrayTrait::new()
        }
    }

    #[external(v0)]
    impl LimitOrderImpl of ILimitOrders<ContractState> {
        fn get_nft_address(self: @ContractState) -> ContractAddress {
            self.nft.read().contract_address
        }


        fn get_order_state(self: @ContractState, order_key: OrderKey, id: u64) -> OrderState {
            self.orders.read((order_key, id))
        }

        fn place_order(ref self: ContractState, order_key: OrderKey) -> u64 {
            // orders can only be placed on even ticks
            // this means we know even ticks are always the specified price
            // this allows us to optimize iterating through ticks, by only considering even ticks
            assert(order_key.tick.mag % 2 == 0, 'EVEN_TICKS_ONLY');

            let id = self.nft.read().mint(get_caller_address());

            let (token0, token1, is_token1) = if (order_key.sell_token < order_key.buy_token) {
                (order_key.sell_token, order_key.buy_token, false)
            } else {
                (order_key.buy_token, order_key.sell_token, true)
            };

            let pool_key = PoolKey {
                token0, token1, fee: 0, tick_spacing: 1, extension: get_contract_address()
            };

            // validate the pool key is initialized
            let core = self.core.read();
            let price = core.get_pool_price(pool_key);

            assert(price.sqrt_ratio.is_non_zero(), 'POOL_NOT_INITIALIZED');

            assert(
                price.tick != order_key.tick, 'PRICE_AT_TICK'
            ); // cannot place an order at the current tick

            assert(
                if is_token1 {
                    order_key.tick < price.tick
                } else {
                    order_key.tick > price.tick
                },
                'TICK_WRONG_SIDE'
            );

            let sqrt_ratio_lower = tick_to_sqrt_ratio(order_key.tick);
            let sqrt_ratio_upper = tick_to_sqrt_ratio(
                order_key.tick + i129 { mag: 1, sign: false }
            );
            let amount: u128 = IERC20Dispatcher { contract_address: order_key.sell_token }
                .balanceOf(get_contract_address())
                .try_into()
                .expect('SELL_BALANCE_TOO_LARGE');
            let liquidity = if is_token1 {
                max_liquidity_for_token1(sqrt_ratio_lower, sqrt_ratio_upper, amount)
            } else {
                max_liquidity_for_token0(sqrt_ratio_lower, sqrt_ratio_upper, amount)
            };

            assert(liquidity > 0, 'SELL_AMOUNT_TOO_SMALL');

            self
                .orders
                .write(
                    (order_key, id),
                    OrderState {
                        ticks_crossed_last: self.pools.read(pool_key).ticks_crossed, liquidity
                    }
                );

            call_core_with_callback::<
                LockCallbackData, ()
            >(
                core,
                @LockCallbackData::PlaceOrderCallbackData(
                    PlaceOrderCallbackData { pool_key, tick: order_key.tick, is_token1, liquidity }
                )
            );

            id
        }

        fn close_order(
            ref self: ContractState, order_key: OrderKey, id: u64, recipient: ContractAddress
        ) -> (u128, u128) {
            let nft = self.nft.read();
            assert(nft.is_account_authorized(id, get_caller_address()), 'UNAUTHORIZED');
            nft.burn(id);

            let order = self.orders.read((order_key, id));
            assert(order.liquidity.is_non_zero(), 'INVALID_ORDER');

            (0, 0)
        }

        fn clear(ref self: ContractState, token: ContractAddress) -> u256 {
            let dispatcher = IERC20Dispatcher { contract_address: token };
            let balance = dispatcher.balanceOf(get_contract_address());
            if (balance.is_non_zero()) {
                dispatcher.transfer(get_caller_address(), balance);
            }
            balance
        }
    }
}
