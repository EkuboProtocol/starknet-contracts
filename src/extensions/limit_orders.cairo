#[starknet::contract]
pub mod LimitOrders {
    use core::array::ArrayTrait;
    use core::num::traits::Zero;
    use core::traits::{Into, TryInto};
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePathEntry,
        StoragePointerReadAccess, StoragePointerWriteAccess,
    };
    use starknet::storage_access::StorePacking;
    use starknet::{ContractAddress, get_contract_address};
    use crate::components::clear::ClearImpl;
    use crate::components::owned::Owned as owned_component;
    use crate::components::upgradeable::{IHasInterface, Upgradeable as upgradeable_component};
    use crate::components::util::{call_core_with_callback, consume_callback_data, serialize};
    use crate::interfaces::core::{
        ICoreDispatcher, ICoreDispatcherTrait, IExtension, IForwardee, ILocker, SwapParameters,
        UpdatePositionParameters,
    };
    use crate::interfaces::extensions::limit_orders::{
        CloseOrderForwardCallbackData, CloseOrderForwardCallbackResult, ForwardCallbackData,
        GetOrderInfoRequest, GetOrderInfoResult, ILimitOrders, OrderKey, OrderState,
        PlaceOrderForwardCallbackData, PlaceOrderForwardCallbackResult, PoolState,
    };
    use crate::math::delta::{amount0_delta, amount1_delta};
    use crate::math::liquidity::liquidity_delta_to_amount_delta;
    use crate::math::ticks::tick_to_sqrt_ratio;
    use crate::types::bounds::Bounds;
    use crate::types::call_points::CallPoints;
    use crate::types::delta::Delta;
    use crate::types::i129::{i129, i129Trait};
    use crate::types::keys::{PoolKey, PositionKey, SavedBalanceKey};

    impl OrderStateStorePacking of StorePacking<OrderState, felt252> {
        fn pack(value: OrderState) -> felt252 {
            u256 { low: value.liquidity, high: value.initialized_ticks_crossed_snapshot.into() }
                .try_into()
                .unwrap()
        }
        fn unpack(value: felt252) -> OrderState {
            let x: u256 = value.into();

            OrderState {
                initialized_ticks_crossed_snapshot: x.high.try_into().unwrap(), liquidity: x.low,
            }
        }
    }


    impl PoolStateStorePacking of StorePacking<PoolState, felt252> {
        fn pack(value: PoolState) -> felt252 {
            u256 {
                low: value.last_tick.mag,
                high: if value.last_tick.is_negative() {
                    value.initialized_ticks_crossed.into() + 0x10000000000000000
                } else {
                    value.initialized_ticks_crossed.into()
                },
            }
                .try_into()
                .unwrap()
        }
        fn unpack(value: felt252) -> PoolState {
            let x: u256 = value.into();

            if (x.high >= 0x10000000000000000) {
                PoolState {
                    last_tick: i129 { mag: x.low, sign: true },
                    initialized_ticks_crossed: (x.high - 0x10000000000000000).try_into().unwrap(),
                }
            } else {
                PoolState {
                    last_tick: i129 { mag: x.low, sign: false },
                    initialized_ticks_crossed: x.high.try_into().unwrap(),
                }
            }
        }
    }


    pub const LIMIT_ORDER_TICK_SPACING: u128 = 128;
    pub const DOUBLE_LIMIT_ORDER_TICK_SPACING: u128 = 256;

    #[abi(embed_v0)]
    impl Clear = crate::components::clear::ClearImpl<ContractState>;

    component!(path: owned_component, storage: owned, event: OwnedEvent);
    #[abi(embed_v0)]
    impl Owned = owned_component::OwnedImpl<ContractState>;
    impl OwnableImpl = owned_component::OwnableImpl<ContractState>;

    component!(path: upgradeable_component, storage: upgradeable, event: UpgradeableEvent);
    #[abi(embed_v0)]
    impl Upgradeable = upgradeable_component::UpgradeableImpl<ContractState>;

    #[storage]
    struct Storage {
        core: ICoreDispatcher,
        pools: Map<(ContractAddress, ContractAddress), PoolState>,
        initialized_ticks_crossed_last_crossing: Map<
            (ContractAddress, ContractAddress), Map<i129, u64>,
        >,
        orders: Map<(ContractAddress, felt252, OrderKey), OrderState>,
        #[substorage(v0)]
        upgradeable: upgradeable_component::Storage,
        #[substorage(v0)]
        owned: owned_component::Storage,
    }

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress, core: ICoreDispatcher) {
        self.initialize_owned(owner);
        self.core.write(core);
        core
            .set_call_points(
                CallPoints {
                    before_initialize_pool: true,
                    after_initialize_pool: false,
                    before_swap: false,
                    after_swap: true,
                    before_update_position: true,
                    after_update_position: false,
                    before_collect_fees: false,
                    after_collect_fees: false,
                },
            );
    }

    #[derive(Drop, starknet::Event)]
    pub struct OrderPlaced {
        pub owner: ContractAddress,
        pub salt: felt252,
        pub order_key: OrderKey,
        pub liquidity: u128,
        pub amount: u128,
    }

    #[derive(Drop, starknet::Event)]
    pub struct OrderClosed {
        pub owner: ContractAddress,
        pub salt: felt252,
        pub order_key: OrderKey,
        pub amount0: u128,
        pub amount1: u128,
    }

    #[derive(starknet::Event, Drop)]
    #[event]
    enum Event {
        OrderPlaced: OrderPlaced,
        OrderClosed: OrderClosed,
        #[flat]
        UpgradeableEvent: upgradeable_component::Event,
        OwnedEvent: owned_component::Event,
    }

    #[abi(embed_v0)]
    impl LimitOrdersHasInterface of IHasInterface<ContractState> {
        fn get_primary_interface_id(self: @ContractState) -> felt252 {
            return selector!("crate::extensions::limit_orders::LimitOrders");
        }
    }

    #[abi(embed_v0)]
    impl ExtensionImpl of IExtension<ContractState> {
        fn before_initialize_pool(
            ref self: ContractState, caller: ContractAddress, pool_key: PoolKey, initial_tick: i129,
        ) {
            // This entrypoint is not called if the limit order extension initializes the pool. Only
            // the limit order extension can create pools using this extension.
            panic!("Only from place_order");
        }

        fn after_initialize_pool(
            ref self: ContractState, caller: ContractAddress, pool_key: PoolKey, initial_tick: i129,
        ) {
            panic!("Not used");
        }

        fn before_swap(
            ref self: ContractState,
            caller: ContractAddress,
            pool_key: PoolKey,
            params: SwapParameters,
        ) {
            panic!("Not used");
        }

        fn after_swap(
            ref self: ContractState,
            caller: ContractAddress,
            pool_key: PoolKey,
            params: SwapParameters,
            delta: Delta,
        ) {
            let core = self.core.read();

            call_core_with_callback::<(PoolKey, u128), ()>(core, @(pool_key, params.skip_ahead));
        }

        fn before_update_position(
            ref self: ContractState,
            caller: ContractAddress,
            pool_key: PoolKey,
            params: UpdatePositionParameters,
        ) {
            // pools with this extension may only contain limit orders, to simplify routing
            panic!("Only limit orders");
        }

        fn after_update_position(
            ref self: ContractState,
            caller: ContractAddress,
            pool_key: PoolKey,
            params: UpdatePositionParameters,
            delta: Delta,
        ) {
            panic!("Not used");
        }

        fn before_collect_fees(
            ref self: ContractState,
            caller: ContractAddress,
            pool_key: PoolKey,
            salt: felt252,
            bounds: Bounds,
        ) {
            panic!("Not used");
        }
        fn after_collect_fees(
            ref self: ContractState,
            caller: ContractAddress,
            pool_key: PoolKey,
            salt: felt252,
            bounds: Bounds,
            delta: Delta,
        ) {
            panic!("Not used");
        }
    }

    #[generate_trait]
    impl OrderKeyTraitImpl of OrderKeyTrait {
        // Returns the pool key of the pool on which the order's liquidity will be placed
        fn get_pool_key(self: OrderKey) -> PoolKey {
            PoolKey {
                token0: self.token0,
                token1: self.token1,
                fee: 0,
                tick_spacing: LIMIT_ORDER_TICK_SPACING,
                extension: get_contract_address(),
            }
        }
        // Returns the bounds for the position that is used to implement the order
        fn get_bounds(self: OrderKey) -> Bounds {
            Bounds {
                lower: self.tick,
                upper: self.tick + i129 { mag: LIMIT_ORDER_TICK_SPACING, sign: false },
            }
        }
    }

    #[generate_trait]
    impl InternalMethods of InternalMethodsTrait {
        fn _get_order_info(
            self: @ContractState, core: ICoreDispatcher, request: GetOrderInfoRequest,
        ) -> GetOrderInfoResult {
            let price = core.get_pool_price(request.order_key.get_pool_key());
            assert(price.sqrt_ratio.is_non_zero(), 'Pool not initialized');

            let order = self.orders.read((request.owner, request.salt, request.order_key));

            if order.liquidity.is_zero() {
                GetOrderInfoResult { state: order, executed: false, amount0: 0, amount1: 0 }
            } else {
                let is_selling_token1 = (request
                    .order_key
                    .tick
                    .mag % DOUBLE_LIMIT_ORDER_TICK_SPACING)
                    .is_non_zero();

                let initialized_ticks_crossed_at_order_tick = self
                    .initialized_ticks_crossed_last_crossing
                    .entry((request.order_key.token0, request.order_key.token1))
                    .read(
                        if is_selling_token1 {
                            request.order_key.tick
                        } else {
                            request.order_key.tick
                                + i129 { mag: LIMIT_ORDER_TICK_SPACING, sign: false }
                        },
                    );

                // the order is fully executed, just withdraw the saved balance
                if (initialized_ticks_crossed_at_order_tick > order
                    .initialized_ticks_crossed_snapshot) {
                    let sqrt_ratio_a = tick_to_sqrt_ratio(request.order_key.tick);
                    let sqrt_ratio_b = tick_to_sqrt_ratio(
                        request.order_key.tick
                            + i129 { mag: LIMIT_ORDER_TICK_SPACING, sign: false },
                    );

                    let (amount0, amount1) = if is_selling_token1 {
                        (
                            amount0_delta(
                                sqrt_ratio_a,
                                sqrt_ratio_b,
                                liquidity: order.liquidity,
                                round_up: false,
                            ),
                            0,
                        )
                    } else {
                        (
                            0,
                            amount1_delta(
                                sqrt_ratio_a,
                                sqrt_ratio_b,
                                liquidity: order.liquidity,
                                round_up: false,
                            ),
                        )
                    };

                    GetOrderInfoResult { state: order, executed: true, amount0, amount1 }
                } else {
                    let delta = liquidity_delta_to_amount_delta(
                        sqrt_ratio: price.sqrt_ratio,
                        liquidity_delta: i129 { mag: order.liquidity, sign: true },
                        sqrt_ratio_lower: tick_to_sqrt_ratio(request.order_key.tick),
                        sqrt_ratio_upper: tick_to_sqrt_ratio(
                            request.order_key.tick
                                + i129 { mag: LIMIT_ORDER_TICK_SPACING, sign: false },
                        ),
                    );

                    GetOrderInfoResult {
                        state: order,
                        executed: false,
                        amount0: delta.amount0.mag,
                        amount1: delta.amount1.mag,
                    }
                }
            }
        }
    }

    #[abi(embed_v0)]
    impl LockedImpl of ILocker<ContractState> {
        fn locked(ref self: ContractState, id: u32, data: Span<felt252>) -> Span<felt252> {
            let core = self.core.read();
            let (pool_key, skip_ahead) = consume_callback_data::<(PoolKey, u128)>(core, data);

            let tick_after_swap = core.get_pool_price(pool_key).tick;
            let state_entry = self.pools.entry((pool_key.token0, pool_key.token1));
            let state = state_entry.read();
            let mut initialized_ticks_crossed = state.initialized_ticks_crossed;

            let pool_initialized_ticks_crossed_entry = self
                .initialized_ticks_crossed_last_crossing
                .entry((pool_key.token0, pool_key.token1));

            if (tick_after_swap != state.last_tick) {
                let this_address = get_contract_address();
                let price_increasing = tick_after_swap > state.last_tick;
                let mut tick_current = state.last_tick;
                let mut save_amount: u128 = 0;

                loop {
                    let (next_tick, is_initialized) = if price_increasing {
                        core.next_initialized_tick(pool_key, tick_current, skip_ahead)
                    } else {
                        core.prev_initialized_tick(pool_key, tick_current, skip_ahead)
                    };

                    if ((next_tick > tick_after_swap) == price_increasing) {
                        break ();
                    }

                    if (is_initialized
                        & ((next_tick.mag % DOUBLE_LIMIT_ORDER_TICK_SPACING).is_non_zero())) {
                        let bounds = if price_increasing {
                            Bounds {
                                lower: next_tick
                                    - i129 { mag: LIMIT_ORDER_TICK_SPACING, sign: false },
                                upper: next_tick,
                            }
                        } else {
                            Bounds {
                                lower: next_tick,
                                upper: next_tick
                                    + i129 { mag: LIMIT_ORDER_TICK_SPACING, sign: false },
                            }
                        };

                        let position_data = core
                            .get_position(
                                pool_key, PositionKey { salt: 0, owner: this_address, bounds },
                            );

                        let delta = core
                            .update_position(
                                pool_key,
                                UpdatePositionParameters {
                                    salt: 0,
                                    bounds,
                                    liquidity_delta: i129 {
                                        mag: position_data.liquidity, sign: true,
                                    },
                                },
                            );

                        save_amount +=
                            if price_increasing {
                                delta.amount1.mag
                            } else {
                                delta.amount0.mag
                            };
                        initialized_ticks_crossed += 1;
                        pool_initialized_ticks_crossed_entry
                            .write(next_tick, initialized_ticks_crossed);
                    }

                    tick_current =
                        if price_increasing {
                            next_tick
                        } else {
                            next_tick - i129 { mag: LIMIT_ORDER_TICK_SPACING, sign: false }
                        };
                }

                if (save_amount.is_non_zero()) {
                    core
                        .save(
                            SavedBalanceKey {
                                owner: this_address,
                                token: if price_increasing {
                                    pool_key.token1
                                } else {
                                    pool_key.token0
                                },
                                salt: 0,
                            },
                            save_amount,
                        );
                }

                state_entry
                    .write(PoolState { initialized_ticks_crossed, last_tick: tick_after_swap });
            }

            array![].span()
        }
    }

    #[abi(embed_v0)]
    impl ForwardeeImpl of IForwardee<ContractState> {
        fn forwarded(
            ref self: ContractState, original_locker: ContractAddress, id: u32, data: Span<felt252>,
        ) -> Span<felt252> {
            let core = self.core.read();

            match consume_callback_data::<ForwardCallbackData>(core, data) {
                ForwardCallbackData::PlaceOrder(params) => {
                    let PlaceOrderForwardCallbackData { salt, order_key, liquidity } = params;

                    assert(liquidity > 0, 'Liquidity must be non-zero');

                    let is_selling_token1 = (order_key.tick.mag % DOUBLE_LIMIT_ORDER_TICK_SPACING)
                        .is_non_zero();

                    let state_entry = self.pools.entry((order_key.token0, order_key.token1));
                    let order_entry = self.orders.entry((original_locker, salt, order_key));

                    assert(order_entry.read().liquidity.is_zero(), 'Order already exists');

                    let mut pool_state = state_entry.read();

                    // the ticks crossed is zero IFF the pool is not initialized
                    if (pool_state.initialized_ticks_crossed.is_zero()) {
                        let initial_tick = if is_selling_token1 {
                            order_key.tick + i129 { mag: LIMIT_ORDER_TICK_SPACING, sign: false }
                        } else {
                            order_key.tick
                        };

                        pool_state =
                            PoolState { initialized_ticks_crossed: 1, last_tick: initial_tick };

                        state_entry.write(pool_state);
                        core.initialize_pool(order_key.get_pool_key(), initial_tick);
                    }

                    order_entry
                        .write(
                            OrderState {
                                initialized_ticks_crossed_snapshot: pool_state
                                    .initialized_ticks_crossed,
                                liquidity,
                            },
                        );

                    let delta = core
                        .update_position(
                            pool_key: order_key.get_pool_key(),
                            params: UpdatePositionParameters {
                                // all the positions have the same salt
                                salt: 0,
                                bounds: order_key.get_bounds(),
                                liquidity_delta: i129 { mag: liquidity, sign: false },
                            },
                        );

                    let amount = if is_selling_token1 {
                        assert(delta.amount0.is_zero(), 'Tick wrong side selling token1');
                        delta.amount1.mag
                    } else {
                        assert(delta.amount1.is_zero(), 'Tick wrong side selling token0');
                        delta.amount0.mag
                    };

                    self
                        .emit(
                            OrderPlaced {
                                owner: original_locker, salt, order_key, liquidity, amount,
                            },
                        );

                    let result: PlaceOrderForwardCallbackResult = amount;

                    serialize(@result).span()
                },
                ForwardCallbackData::CloseOrder(params) => {
                    let CloseOrderForwardCallbackData { salt, order_key } = params;

                    let order_info = self
                        ._get_order_info(
                            core, GetOrderInfoRequest { owner: original_locker, salt, order_key },
                        );
                    assert(order_info.state.liquidity.is_non_zero(), 'Order does not exist');

                    // clear the order state
                    self
                        .orders
                        .write(
                            (original_locker, salt, order_key),
                            OrderState { liquidity: 0, initialized_ticks_crossed_snapshot: 0 },
                        );

                    if order_info.executed {
                        if order_info.amount0.is_non_zero() {
                            core.load(token: order_key.token0, salt: 0, amount: order_info.amount0);
                        } else if order_info.amount1.is_non_zero() {
                            core.load(token: order_key.token1, salt: 0, amount: order_info.amount1);
                        }
                    } else {
                        // withdraw the liquidity position since it's not executed
                        let delta = core
                            .update_position(
                                pool_key: order_key.get_pool_key(),
                                params: UpdatePositionParameters {
                                    // all the positions have the same salt
                                    salt: 0,
                                    bounds: order_key.get_bounds(),
                                    liquidity_delta: i129 {
                                        mag: order_info.state.liquidity, sign: true,
                                    },
                                },
                            );
                        // safety check that the result of _get_order_info matches up with the
                        // amount we get from withdrawing
                        assert(delta.amount0.mag == order_info.amount0, 'amount0 mismatch');
                        assert(delta.amount1.mag == order_info.amount1, 'amount1 mismatch');
                    }

                    self
                        .emit(
                            OrderClosed {
                                owner: original_locker,
                                salt,
                                order_key,
                                amount0: order_info.amount0,
                                amount1: order_info.amount1,
                            },
                        );

                    let result: CloseOrderForwardCallbackResult = (
                        order_info.amount0, order_info.amount1,
                    );

                    serialize(@result).span()
                },
            }
        }
    }

    #[abi(embed_v0)]
    impl LimitOrderImpl of ILimitOrders<ContractState> {
        fn get_order_info(
            self: @ContractState, request: GetOrderInfoRequest,
        ) -> GetOrderInfoResult {
            self._get_order_info(self.core.read(), request)
        }

        fn get_order_infos(
            self: @ContractState, mut requests: Span<GetOrderInfoRequest>,
        ) -> Span<GetOrderInfoResult> {
            let core = self.core.read();
            let mut result: Array<GetOrderInfoResult> = array![];

            while let Option::Some(request) = requests.pop_front() {
                result.append(self._get_order_info(core, *request));
            }

            result.span()
        }
    }
}
