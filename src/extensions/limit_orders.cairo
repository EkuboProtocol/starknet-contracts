use ekubo::types::i129::{i129, i129Trait};
use integer::{u256_safe_divmod, u256_as_non_zero};
use starknet::{ContractAddress, StorePacking};
use traits::{Into, TryInto};

#[derive(Drop, Copy, Serde, Hash)]
struct OrderKey {
    token0: ContractAddress,
    token1: ContractAddress,
    tick: i129,
}

// State of a particular order, defined by the key
#[derive(Drop, Copy, Serde, PartialEq)]
struct OrderState {
    // the number of ticks crossed when this order was created
    ticks_crossed_at_create: u64,
    // how much liquidity was deposited for this order
    liquidity: u128,
}

impl OrderStateStorePacking of StorePacking<OrderState, felt252> {
    fn pack(value: OrderState) -> felt252 {
        u256 { low: value.liquidity, high: value.ticks_crossed_at_create.into() }
            .try_into()
            .unwrap()
    }
    fn unpack(value: felt252) -> OrderState {
        let x: u256 = value.into();

        OrderState { ticks_crossed_at_create: x.high.try_into().unwrap(), liquidity: x.low }
    }
}

// The state of the pool as it was last seen
#[derive(Drop, Copy, Serde, PartialEq)]
struct PoolState {
    // the number of initialized ticks that have been crossed, minus 1
    ticks_crossed: u64,
    // the last tick that was seen for the pool
    last_tick: i129,
}

impl PoolStateStorePacking of StorePacking<PoolState, felt252> {
    fn pack(value: PoolState) -> felt252 {
        u256 {
            low: value.last_tick.mag,
            high: if value.last_tick.is_negative() {
                value.ticks_crossed.into() + 0x10000000000000000
            } else {
                value.ticks_crossed.into()
            }
        }
            .try_into()
            .unwrap()
    }
    fn unpack(value: felt252) -> PoolState {
        let x: u256 = value.into();

        if (x.high >= 0x10000000000000000) {
            PoolState {
                last_tick: i129 { mag: x.low, sign: true },
                ticks_crossed: (x.high - 0x10000000000000000).try_into().unwrap()
            }
        } else {
            PoolState {
                last_tick: i129 { mag: x.low, sign: false },
                ticks_crossed: x.high.try_into().unwrap()
            }
        }
    }
}

#[derive(Drop, Copy, Serde)]
struct GetOrderInfoRequest {
    order_key: OrderKey,
    id: u64
}

#[derive(Drop, Copy, Serde)]
struct GetOrderInfoResult {
    state: OrderState,
    executed: bool,
    amount0: u128,
    amount1: u128,
}

#[starknet::interface]
trait ILimitOrders<TContractState> {
    // Return the NFT contract address that this contract uses to represent limit orders
    fn get_nft_address(self: @TContractState) -> ContractAddress;

    // Returns the stored order state
    fn get_order_state(self: @TContractState, order_key: OrderKey, id: u64) -> OrderState;

    // Return information on each of the given orders
    fn get_order_info(
        self: @TContractState, requests: Span<GetOrderInfoRequest>
    ) -> Array<GetOrderInfoResult>;

    // Creates a new limit order, selling the given `sell_token` for the given `buy_token` at the specified tick
    // The size of the new order is determined by the current balance of the sell token
    fn place_order(ref self: TContractState, order_key: OrderKey, amount: u128) -> u64;

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
        ICoreDispatcherTrait, SavedBalanceKey
    };
    use ekubo::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use ekubo::interfaces::upgradeable::{IUpgradeable};
    use ekubo::math::delta::{amount0_delta, amount1_delta};
    use ekubo::math::liquidity::{liquidity_delta_to_amount_delta};
    use ekubo::math::max_liquidity::{max_liquidity_for_token0, max_liquidity_for_token1};
    use ekubo::math::ticks::{tick_to_sqrt_ratio};
    use ekubo::owner::{check_owner_only};
    use ekubo::shared_locker::{call_core_with_callback, consume_callback_data};
    use ekubo::types::bounds::{Bounds};
    use ekubo::types::call_points::{CallPoints};
    use ekubo::types::keys::{PoolKey, PositionKey};
    use option::{OptionTrait};
    use starknet::{get_contract_address, get_caller_address, replace_class_syscall, ClassHash};
    use super::{
        ILimitOrders, i129, i129Trait, ContractAddress, OrderKey, OrderState, PoolState,
        GetOrderInfoRequest, GetOrderInfoResult
    };
    use traits::{TryInto, Into};
    use zeroable::{Zeroable};

    #[storage]
    struct Storage {
        core: ICoreDispatcher,
        nft: IEnumerableOwnedNFTDispatcher,
        pools: LegacyMap<PoolKey, PoolState>,
        orders: LegacyMap<(OrderKey, u64), OrderState>,
        ticks_crossed_last_crossing: LegacyMap<(PoolKey, i129), u64>,
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
        is_selling_token1: bool,
        tick: i129,
        liquidity: u128,
    }

    #[derive(Serde, Copy, Drop)]
    struct HandleAfterSwapCallbackData {
        pool_key: PoolKey,
        skip_ahead: u128,
    }

    #[derive(Serde, Copy, Drop)]
    struct WithdrawExecutedOrderBalance {
        token: ContractAddress,
        amount: u128,
        recipient: ContractAddress,
    }

    #[derive(Serde, Copy, Drop)]
    struct WithdrawUnexecutedOrderBalance {
        pool_key: PoolKey,
        tick: i129,
        liquidity: u128,
        recipient: ContractAddress,
    }

    #[derive(Serde, Copy, Drop)]
    enum LockCallbackData {
        PlaceOrderCallbackData: PlaceOrderCallbackData,
        HandleAfterSwapCallbackData: HandleAfterSwapCallbackData,
        WithdrawExecutedOrderBalance: WithdrawExecutedOrderBalance,
        WithdrawUnexecutedOrderBalance: WithdrawUnexecutedOrderBalance,
    }

    #[derive(Serde, Copy, Drop)]
    enum LockCallbackResult {
        Empty: (),
        Delta: Delta,
    }

    #[derive(starknet::Event, Drop)]
    struct OrderPlaced {
        id: u64,
        order_key: OrderKey,
        amount: u128,
        liquidity: u128,
    }

    #[derive(starknet::Event, Drop)]
    struct OrderClosed {
        id: u64,
        amount0: u128,
        amount1: u128,
    }


    #[derive(starknet::Event, Drop)]
    struct ClassHashReplaced {
        new_class_hash: ClassHash,
    }

    #[derive(starknet::Event, Drop)]
    #[event]
    enum Event {
        ClassHashReplaced: ClassHashReplaced,
        OrderPlaced: OrderPlaced,
        OrderClosed: OrderClosed,
    }

    #[external(v0)]
    impl Upgradeable of IUpgradeable<ContractState> {
        fn replace_class_hash(ref self: ContractState, class_hash: ClassHash) {
            check_owner_only();
            replace_class_syscall(class_hash);
            self.emit(ClassHashReplaced { new_class_hash: class_hash });
        }
    }

    #[external(v0)]
    impl ExtensionImpl of IExtension<ContractState> {
        fn before_initialize_pool(
            ref self: ContractState, caller: ContractAddress, pool_key: PoolKey, initial_tick: i129
        ) -> CallPoints {
            assert(caller == get_contract_address(), 'ONLY_FROM_PLACE_ORDER');

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
            // only this contract can create positions, and the extension will not be called in that case, so always revert
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

            let result: LockCallbackResult =
                match consume_callback_data::<LockCallbackData>(core, data) {
                LockCallbackData::PlaceOrderCallbackData(place_order) => {
                    let delta = core
                        .update_position(
                            pool_key: place_order.pool_key,
                            params: UpdatePositionParameters {
                                // all the positions have the same salt
                                salt: 0,
                                bounds: Bounds {
                                    lower: place_order.tick,
                                    upper: place_order.tick + i129 { mag: 1, sign: false },
                                },
                                liquidity_delta: i129 { mag: place_order.liquidity, sign: false }
                            }
                        );

                    let (pay_token, pay_amount, other_is_zero) = if place_order.is_selling_token1 {
                        (place_order.pool_key.token1, delta.amount1.mag, delta.amount0.is_zero())
                    } else {
                        (place_order.pool_key.token0, delta.amount0.mag, delta.amount1.is_zero())
                    };

                    assert(other_is_zero, 'TICK_WRONG_SIDE');

                    IERC20Dispatcher { contract_address: pay_token }
                        .transfer(core.contract_address, pay_amount.into());
                    let paid_amount = core.deposit(pay_token);
                    if (paid_amount > pay_amount) {
                        core.withdraw(pay_token, get_contract_address(), paid_amount - pay_amount);
                    }

                    LockCallbackResult::Empty
                },
                LockCallbackData::HandleAfterSwapCallbackData(after_swap) => {
                    let price_after_swap = core.get_pool_price(after_swap.pool_key);
                    let state = self.pools.read(after_swap.pool_key);
                    let mut ticks_crossed = state.ticks_crossed;

                    if (price_after_swap.tick != state.last_tick) {
                        let price_increasing = price_after_swap.tick > state.last_tick;
                        let mut tick_current = state.last_tick;
                        let mut save_amount: u128 = 0;

                        loop {
                            let (next_tick, is_initialized) = if price_increasing {
                                core
                                    .next_initialized_tick(
                                        after_swap.pool_key, tick_current, after_swap.skip_ahead
                                    )
                            } else {
                                core
                                    .prev_initialized_tick(
                                        after_swap.pool_key, tick_current, after_swap.skip_ahead
                                    )
                            };

                            if ((next_tick > price_after_swap.tick) == price_increasing) {
                                break ();
                            };

                            if (is_initialized & (next_tick.mag % 2 == 1)) {
                                let bounds = if price_increasing {
                                    Bounds {
                                        lower: next_tick - i129 { mag: 1, sign: false },
                                        upper: next_tick,
                                    }
                                } else {
                                    Bounds {
                                        lower: next_tick,
                                        upper: next_tick + i129 { mag: 1, sign: false },
                                    }
                                };

                                let position_data = core
                                    .get_position(
                                        after_swap.pool_key,
                                        PositionKey {
                                            salt: 0, owner: get_contract_address(), bounds
                                        }
                                    );

                                let delta = core
                                    .update_position(
                                        after_swap.pool_key,
                                        UpdatePositionParameters {
                                            salt: 0,
                                            bounds,
                                            liquidity_delta: i129 {
                                                mag: position_data.liquidity, sign: true
                                            }
                                        }
                                    );

                                save_amount +=
                                    if price_increasing {
                                        delta.amount1.mag
                                    } else {
                                        delta.amount0.mag
                                    };
                                ticks_crossed += 1;
                                self
                                    .ticks_crossed_last_crossing
                                    .write((after_swap.pool_key, next_tick), ticks_crossed);
                            };

                            tick_current =
                                if price_increasing {
                                    next_tick
                                } else {
                                    next_tick - i129 { mag: 1, sign: false }
                                };
                        };

                        if (save_amount.is_non_zero()) {
                            core
                                .save(
                                    SavedBalanceKey {
                                        owner: get_contract_address(),
                                        token: if price_increasing {
                                            after_swap.pool_key.token1
                                        } else {
                                            after_swap.pool_key.token0
                                        },
                                        salt: 0,
                                    },
                                    save_amount
                                );
                        }

                        self
                            .pools
                            .write(
                                after_swap.pool_key,
                                PoolState { ticks_crossed, last_tick: price_after_swap.tick }
                            );
                    }

                    LockCallbackResult::Empty
                },
                LockCallbackData::WithdrawExecutedOrderBalance(withdraw) => {
                    core.load(token: withdraw.token, salt: 0, amount: withdraw.amount);
                    core
                        .withdraw(
                            token_address: withdraw.token,
                            recipient: withdraw.recipient,
                            amount: withdraw.amount
                        );
                    LockCallbackResult::Empty
                },
                LockCallbackData::WithdrawUnexecutedOrderBalance(withdraw) => {
                    let delta = core
                        .update_position(
                            pool_key: withdraw.pool_key,
                            params: UpdatePositionParameters {
                                // all the positions have the same salt
                                salt: 0,
                                bounds: Bounds {
                                    lower: withdraw.tick,
                                    upper: withdraw.tick + i129 { mag: 1, sign: false },
                                },
                                liquidity_delta: i129 { mag: withdraw.liquidity, sign: true }
                            }
                        );

                    if (delta.amount0.is_non_zero()) {
                        core
                            .withdraw(
                                token_address: withdraw.pool_key.token0,
                                recipient: withdraw.recipient,
                                amount: delta.amount0.mag
                            );
                    }

                    if (delta.amount1.is_non_zero()) {
                        core
                            .withdraw(
                                token_address: withdraw.pool_key.token1,
                                recipient: withdraw.recipient,
                                amount: delta.amount1.mag
                            );
                    }

                    LockCallbackResult::Delta(delta)
                }
            };

            let mut result_data = ArrayTrait::new();
            Serde::serialize(@result, ref result_data);
            result_data
        }
    }

    fn to_pool_key(order_key: OrderKey) -> PoolKey {
        PoolKey {
            token0: order_key.token0,
            token1: order_key.token1,
            fee: 0,
            tick_spacing: 1,
            extension: get_contract_address()
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

        fn place_order(ref self: ContractState, order_key: OrderKey, amount: u128) -> u64 {
            let id = self.nft.read().mint(get_caller_address());

            let pool_key = to_pool_key(order_key);
            let is_selling_token1 = (order_key.tick.mag % 2) == 1;

            let core = self.core.read();

            // check the price is on the right side of the order tick
            {
                let price = core.get_pool_price(pool_key);

                // the first order initializes the pool just next to where the order is placed
                if (price.sqrt_ratio.is_zero()) {
                    let initial_tick = if is_selling_token1 {
                        order_key.tick + i129 { mag: 1, sign: false }
                    } else {
                        order_key.tick
                    };

                    self
                        .pools
                        .write(pool_key, PoolState { ticks_crossed: 1, last_tick: initial_tick });
                    core.initialize_pool(pool_key, initial_tick);
                }
            }

            let sqrt_ratio_lower = tick_to_sqrt_ratio(order_key.tick);
            let sqrt_ratio_upper = tick_to_sqrt_ratio(
                order_key.tick + i129 { mag: 1, sign: false }
            );
            let liquidity = if is_selling_token1 {
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
                        ticks_crossed_at_create: self.pools.read(pool_key).ticks_crossed, liquidity
                    }
                );

            call_core_with_callback::<
                LockCallbackData, ()
            >(
                core,
                @LockCallbackData::PlaceOrderCallbackData(
                    PlaceOrderCallbackData {
                        pool_key, tick: order_key.tick, is_selling_token1, liquidity
                    }
                )
            );

            self.emit(OrderPlaced { id, order_key, amount, liquidity });

            id
        }

        fn close_order(
            ref self: ContractState, order_key: OrderKey, id: u64, recipient: ContractAddress
        ) -> (u128, u128) {
            let nft = self.nft.read();
            assert(nft.is_account_authorized(id, get_caller_address()), 'UNAUTHORIZED');

            let order = self.orders.read((order_key, id));
            assert(order.liquidity.is_non_zero(), 'INVALID_ORDER_KEY');

            // burn the NFT and clear the order state so it cannot be withdrawn twice
            nft.burn(id);
            self
                .orders
                .write((order_key, id), OrderState { liquidity: 0, ticks_crossed_at_create: 0 });

            let pool_key = to_pool_key(order_key);

            let core = self.core.read();

            let is_selling_token1 = order_key.tick.mag % 2 == 1;

            let ticks_crossed_at_order_tick = self
                .ticks_crossed_last_crossing
                .read(
                    (
                        pool_key,
                        if is_selling_token1 {
                            order_key.tick
                        } else {
                            order_key.tick + i129 { mag: 1, sign: false }
                        }
                    )
                );

            // the order is fully executed, just withdraw the saved balance
            let (amount0, amount1) = if (ticks_crossed_at_order_tick > order
                .ticks_crossed_at_create) {
                let sqrt_ratio_a = tick_to_sqrt_ratio(order_key.tick);
                let sqrt_ratio_b = tick_to_sqrt_ratio(
                    order_key.tick + i129 { mag: 1, sign: false }
                );

                let (amount0, amount1) = if is_selling_token1 {
                    (
                        amount0_delta(
                            sqrt_ratio_a, sqrt_ratio_b, liquidity: order.liquidity, round_up: false
                        ),
                        0_u128
                    )
                } else {
                    (
                        0_u128,
                        amount1_delta(
                            sqrt_ratio_a, sqrt_ratio_b, liquidity: order.liquidity, round_up: false
                        )
                    )
                };

                call_core_with_callback::<
                    LockCallbackData, ()
                >(
                    core,
                    @LockCallbackData::WithdrawExecutedOrderBalance(
                        if is_selling_token1 {
                            WithdrawExecutedOrderBalance {
                                token: order_key.token0, amount: amount0, recipient,
                            }
                        } else {
                            WithdrawExecutedOrderBalance {
                                token: order_key.token1, amount: amount1, recipient,
                            }
                        }
                    )
                );

                (amount0, amount1)
            } else {
                match call_core_with_callback::<
                    LockCallbackData, LockCallbackResult
                >(
                    core,
                    @LockCallbackData::WithdrawUnexecutedOrderBalance(
                        WithdrawUnexecutedOrderBalance {
                            pool_key, tick: order_key.tick, liquidity: order.liquidity, recipient
                        }
                    )
                ) {
                    LockCallbackResult::Empty => {
                        assert(false, 'EMPTY_RESULT');
                        (0, 0)
                    },
                    LockCallbackResult::Delta(delta) => { (delta.amount0.mag, delta.amount1.mag) }
                }
            };

            self.emit(OrderClosed { id, amount0, amount1 });

            (amount0, amount1)
        }

        fn get_order_info(
            self: @ContractState, mut requests: Span<GetOrderInfoRequest>
        ) -> Array<GetOrderInfoResult> {
            let mut result: Array<GetOrderInfoResult> = ArrayTrait::new();

            let core = self.core.read();

            loop {
                match requests.pop_front() {
                    Option::Some(request) => {
                        let is_selling_token1 = *request.order_key.tick.mag % 2 == 1;
                        let pool_key = to_pool_key(*request.order_key);
                        let price = core.get_pool_price(pool_key);

                        assert(price.sqrt_ratio.is_non_zero(), 'INVALID_ORDER_KEY');

                        let ticks_crossed_at_order_tick = self
                            .ticks_crossed_last_crossing
                            .read(
                                (
                                    pool_key,
                                    if is_selling_token1 {
                                        *request.order_key.tick
                                    } else {
                                        *request.order_key.tick + i129 { mag: 1, sign: false }
                                    }
                                )
                            );

                        let order = self.orders.read((*request.order_key, *request.id));

                        // the order is fully executed, just withdraw the saved balance
                        if (ticks_crossed_at_order_tick > order.ticks_crossed_at_create) {
                            let sqrt_ratio_a = tick_to_sqrt_ratio(*request.order_key.tick);
                            let sqrt_ratio_b = tick_to_sqrt_ratio(
                                *request.order_key.tick + i129 { mag: 1, sign: false }
                            );

                            let (amount0, amount1) = if is_selling_token1 {
                                (
                                    amount0_delta(
                                        sqrt_ratio_a,
                                        sqrt_ratio_b,
                                        liquidity: order.liquidity,
                                        round_up: false
                                    ),
                                    0
                                )
                            } else {
                                (
                                    0,
                                    amount1_delta(
                                        sqrt_ratio_a,
                                        sqrt_ratio_b,
                                        liquidity: order.liquidity,
                                        round_up: false
                                    )
                                )
                            };

                            result
                                .append(
                                    GetOrderInfoResult {
                                        state: order, executed: true, amount0, amount1
                                    }
                                );
                        } else {
                            let delta = liquidity_delta_to_amount_delta(
                                sqrt_ratio: price.sqrt_ratio,
                                liquidity_delta: i129 { mag: order.liquidity, sign: true },
                                sqrt_ratio_lower: tick_to_sqrt_ratio(*request.order_key.tick),
                                sqrt_ratio_upper: tick_to_sqrt_ratio(
                                    *request.order_key.tick + i129 { mag: 1, sign: false }
                                )
                            );

                            result
                                .append(
                                    GetOrderInfoResult {
                                        state: order,
                                        executed: false,
                                        amount0: delta.amount0.mag,
                                        amount1: delta.amount1.mag
                                    }
                                );
                        }
                    },
                    Option::None => { break (); }
                };
            };

            result
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
