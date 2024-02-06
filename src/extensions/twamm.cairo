pub mod math;
#[cfg(test)]
pub(crate) mod twamm_math_test;

#[cfg(test)]
pub(crate) mod twamm_test;

use core::num::traits::{Zero};
use core::traits::{Into, TryInto};
use ekubo::types::i129::{i129, i129Trait};
use ekubo::types::keys::{PoolKey};
use starknet::{ContractAddress, ClassHash};

#[derive(Drop, Copy, Serde, Hash)]
pub struct TWAMMPoolKey {
    pub token0: ContractAddress,
    pub token1: ContractAddress,
    // pool fee
    pub fee: u128,
}

#[derive(Drop, Copy, Serde, Hash)]
pub struct OrderKey {
    pub owner: ContractAddress,
    pub salt: felt252,
    pub twamm_pool_key: TWAMMPoolKey,
    pub is_sell_token1: bool,
    pub start_time: u64,
    pub end_time: u64
}

// state of a particular order, defined by the key
#[derive(Drop, Copy, Serde, PartialEq, starknet::Store)]
pub struct OrderState {
    sale_rate: u128,
    // snapshot of adjusted reward rate for order updates (withdrawal/sale-rate)
    reward_rate: felt252,
    use_snapshot: bool
}

pub impl OrderStateZero of Zero<OrderState> {
    #[inline(always)]
    fn zero() -> OrderState {
        OrderState { sale_rate: Zero::zero(), reward_rate: Zero::zero(), use_snapshot: false }
    }

    #[inline(always)]
    fn is_zero(self: @OrderState) -> bool {
        self.sale_rate.is_zero()
    }

    #[inline(always)]
    fn is_non_zero(self: @OrderState) -> bool {
        !self.sale_rate.is_zero()
    }
}

#[starknet::interface]
pub trait ITWAMM<TContractState> {
    // Return the stored order state
    fn get_order_state(self: @TContractState, order_key: OrderKey) -> OrderState;

    // Returns the current sale rate 
    fn get_sale_rate(self: @TContractState, twamm_pool_key: TWAMMPoolKey) -> (u128, u128);

    // Return the current reward rate
    fn get_reward_rate(self: @TContractState, twamm_pool_key: TWAMMPoolKey) -> (felt252, felt252);

    // Return the sale rate delta for a specific time
    fn get_sale_rate_delta(
        self: @TContractState, twamm_pool_key: TWAMMPoolKey, time: u64
    ) -> (i129, i129);

    // Return the sale rate net for a specific time
    fn get_sale_rate_net(
        self: @TContractState, twamm_pool_key: TWAMMPoolKey, time: u64
    ) -> (u128, u128);

    // Update an existing twamm order
    fn update_order(ref self: TContractState, order_key: OrderKey, sale_rate_delta: i129);

    // Withdraws proceeds from a twamm order
    fn withdraw_from_order(
        ref self: TContractState, order_key: OrderKey, recipient: ContractAddress
    );

    // Execute virtual orders
    fn execute_virtual_orders(ref self: TContractState, pool_key: PoolKey);
}

#[starknet::contract]
pub mod TWAMM {
    use core::cmp::{max, min};
    use core::num::traits::{Zero};
    use core::option::{OptionTrait};
    use core::traits::{TryInto, Into};
    use ekubo::components::owned::{Owned as owned_component};
    use ekubo::components::shared_locker::{call_core_with_callback, consume_callback_data};
    use ekubo::components::upgradeable::{Upgradeable as upgradeable_component, IHasInterface};
    use ekubo::interfaces::core::{
        IExtension, SwapParameters, UpdatePositionParameters, ILocker, ICoreDispatcher,
        ICoreDispatcherTrait
    };
    use ekubo::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use ekubo::interfaces::upgradeable::{
        IUpgradeable, IUpgradeableDispatcher, IUpgradeableDispatcherTrait
    };
    use ekubo::math::bitmap::{Bitmap, BitmapTrait};
    use ekubo::math::fee::{compute_fee};
    use ekubo::math::ticks::constants::{MAX_TICK_SPACING};
    use ekubo::math::ticks::{min_sqrt_ratio, max_sqrt_ratio};
    use ekubo::owned_nft::{OwnedNFT, IOwnedNFTDispatcher, IOwnedNFTDispatcherTrait};
    use ekubo::types::bounds::{max_bounds};
    use ekubo::types::call_points::{CallPoints};
    use ekubo::types::delta::{Delta};
    use ekubo::types::i129::{i129, i129Trait, AddDeltaTrait};
    use ekubo::types::keys::{PoolKey, PoolKeyTrait, SavedBalanceKey};
    use starknet::{
        get_contract_address, get_caller_address, syscalls::{replace_class_syscall},
        get_block_timestamp, ClassHash
    };
    use super::math::{
        constants, calculate_sale_rate, calculate_reward_rate_deltas, calculate_reward_amount,
        validate_time, calculate_next_sqrt_ratio, calculate_amount_from_sale_rate,
        calculate_reward_rate
    };
    use super::{ITWAMM, ContractAddress, OrderKey, OrderState, TWAMMPoolKey};

    #[abi(embed_v0)]
    impl Clear = ekubo::components::clear::ClearImpl<ContractState>;

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
        orders: LegacyMap<OrderKey, OrderState>,
        // current rate at which tokens are sold
        sale_rate: LegacyMap<TWAMMPoolKey, (u128, u128)>,
        // sale rate net
        time_sale_rate_net: LegacyMap<(TWAMMPoolKey, u64), (u128, u128)>,
        // sale rate deltas
        time_sale_rate_delta: LegacyMap<(TWAMMPoolKey, u64), (i129, i129)>,
        // used to find next timestamp at which sale rate changes
        time_sale_rate_bitmaps: LegacyMap<(TWAMMPoolKey, u128), Bitmap>,
        // current reward rates
        reward_rate: LegacyMap<TWAMMPoolKey, (felt252, felt252)>,
        // reward rates 
        time_reward_rate: LegacyMap<(TWAMMPoolKey, u64), (felt252, felt252)>,
        // last timestamp at which virtual order was executed
        last_virtual_order_time: LegacyMap<TWAMMPoolKey, u64>,
        #[substorage(v0)]
        upgradeable: upgradeable_component::Storage,
        #[substorage(v0)]
        owned: owned_component::Storage,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner: ContractAddress,
        core: ICoreDispatcher
    ) {
        self.initialize_owned(owner);
        self.core.write(core);
    }

    #[derive(starknet::Event, Drop)]
    pub struct OrderUpdated {
        pub order_key: OrderKey,
        pub sale_rate_delta: i129
    }

    #[derive(starknet::Event, Drop)]
    pub struct OrderProceedsWithdrawn {
        pub order_key: OrderKey,
        pub amount: u128
    }

    #[derive(starknet::Event, Drop)]
    pub struct VirtualOrdersExecuted {
        pub last_virtual_order_time: u64,
        pub next_virtual_order_time: u64,
        pub token0_sale_rate: u128,
        pub token1_sale_rate: u128,
        pub token0_reward_rate: felt252,
        pub token1_reward_rate: felt252
    }

    #[derive(starknet::Event, Drop)]
    #[event]
    enum Event {
        #[flat]
        UpgradeableEvent: upgradeable_component::Event,
        OwnedEvent: owned_component::Event,
        OrderUpdated: OrderUpdated,
        OrderProceedsWithdrawn: OrderProceedsWithdrawn,
        VirtualOrdersExecuted: VirtualOrdersExecuted,
    }

    #[derive(Serde, Copy, Drop)]
    struct WithdrawUnexecutedOrderBalance {
        pool_key: PoolKey,
        tick: i129,
        liquidity: u128,
        recipient: ContractAddress,
    }

    #[derive(Serde, Copy, Drop)]
    struct ExecuteVirtualSwapsCallbackData {
        pool_key: PoolKey
    }

    #[derive(Serde, Copy, Drop)]
    struct DepositBalanceCallbackData {
        token: ContractAddress,
        amount: u128
    }

    #[derive(Serde, Copy, Drop)]
    struct WithdrawBalanceCallbackData {
        order_key: OrderKey,
        token: ContractAddress,
        recipient: ContractAddress,
        amount: u128,
        fee: u128
    }

    #[derive(Serde, Copy, Drop)]
    enum LockCallbackData {
        ExecuteVirtualSwapsCallbackData: ExecuteVirtualSwapsCallbackData,
        DepositBalanceCallbackData: DepositBalanceCallbackData,
        WithdrawBalanceCallbackData: WithdrawBalanceCallbackData
    }

    #[derive(Serde, Copy, Drop)]
    enum LockCallbackResult {
        Empty: (),
    }

    #[abi(embed_v0)]
    impl TWAMMHasInterface of IHasInterface<ContractState> {
        fn get_primary_interface_id(self: @ContractState) -> felt252 {
            return selector!("ekubo::extensions::twamm::twamm::TWAMM");
        }
    }

    #[abi(embed_v0)]
    impl ExtensionImpl of IExtension<ContractState> {
        fn before_initialize_pool(
            ref self: ContractState, caller: ContractAddress, pool_key: PoolKey, initial_tick: i129
        ) -> CallPoints {
            assert(pool_key.tick_spacing == MAX_TICK_SPACING, 'TICK_SPACING');

            CallPoints {
                after_initialize_pool: false,
                before_swap: true,
                after_swap: false,
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
            self.internal_execute_virtual_orders(pool_key);
        }

        fn after_swap(
            ref self: ContractState,
            caller: ContractAddress,
            pool_key: PoolKey,
            params: SwapParameters,
            delta: Delta
        ) {
            assert(false, 'NOT_USED');
        }

        fn before_update_position(
            ref self: ContractState,
            caller: ContractAddress,
            pool_key: PoolKey,
            params: UpdatePositionParameters
        ) {
            assert(params.bounds == max_bounds(pool_key.tick_spacing), 'BOUNDS');
            self.internal_execute_virtual_orders(pool_key);
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

    #[abi(embed_v0)]
    impl TWAMMImpl of ITWAMM<ContractState> {
        fn get_order_state(self: @ContractState, order_key: OrderKey) -> OrderState {
            self.orders.read(order_key)
        }

        fn get_sale_rate(self: @ContractState, twamm_pool_key: TWAMMPoolKey) -> (u128, u128) {
            self.sale_rate.read(twamm_pool_key)
        }

        fn get_reward_rate(
            self: @ContractState, twamm_pool_key: TWAMMPoolKey
        ) -> (felt252, felt252) {
            self.reward_rate.read(twamm_pool_key)
        }

        fn get_sale_rate_net(
            self: @ContractState, twamm_pool_key: TWAMMPoolKey, time: u64
        ) -> (u128, u128) {
            self.time_sale_rate_net.read((twamm_pool_key, time))
        }

        fn get_sale_rate_delta(
            self: @ContractState, twamm_pool_key: TWAMMPoolKey, time: u64
        ) -> (i129, i129) {
            self.time_sale_rate_delta.read((twamm_pool_key, time))
        }

        fn update_order(ref self: ContractState, order_key: OrderKey, sale_rate_delta: i129) {
            assert(order_key.owner == get_caller_address(), 'UNAUTHORIZED');

            // execute virtual orders up to current time
            self.internal_execute_virtual_orders(order_key.into());

            let current_time = get_block_timestamp();
            assert(order_key.end_time > current_time, 'ORDER_ENDED');

            let order_state = self.orders.read(order_key);

            let order_started = order_key.start_time <= current_time;

            if (order_state.is_zero()) {
                // order is being created, validate end time
                validate_time(current_time, order_key.end_time);

                if (!order_started) {
                    // order is starting in the future, validate start time
                    validate_time(current_time, order_key.start_time);
                }
            }

            // assert sale rate will not be negative
            assert(
                !sale_rate_delta.sign || sale_rate_delta.mag <= order_state.sale_rate,
                'INVALID_SALE_RATE_DELTA'
            );

            self.update_order_sale_rate(order_key, order_state, sale_rate_delta, order_started);

            let amount_delta = calculate_amount_from_sale_rate(
                sale_rate_delta.mag, order_key.end_time, max(order_key.start_time, current_time)
            );

            if (sale_rate_delta.sign) {
                self
                    .withdraw(
                        order_key,
                        if (order_key.is_sell_token1) {
                            order_key.twamm_pool_key.token1
                        } else {
                            order_key.twamm_pool_key.token0
                        },
                        get_caller_address(),
                        amount_delta,
                        compute_fee(amount_delta, order_key.twamm_pool_key.fee)
                    );
            } else {
                self
                    .deposit(
                        if (order_key.is_sell_token1) {
                            order_key.twamm_pool_key.token1
                        } else {
                            order_key.twamm_pool_key.token0
                        },
                        amount_delta
                    );
            }
        }

        fn withdraw_from_order(
            ref self: ContractState, order_key: OrderKey, recipient: ContractAddress
        ) {
            assert(order_key.owner == get_caller_address(), 'UNAUTHORIZED');

            let current_time = get_block_timestamp();

            assert(order_key.start_time == 0 || order_key.start_time < current_time, 'NOT_STARTED');

            // execute virtual orders up to current time
            self.internal_execute_virtual_orders(order_key.into());

            let order_state = self.orders.read(order_key);

            // order has been fully withdrawn
            assert(order_state.sale_rate > 0, 'ZERO_SALE_RATE');

            let order_reward_rate = if (order_state.use_snapshot) {
                order_state.reward_rate
            } else {
                self.get_reward_rate_at(order_key, order_key.start_time)
            };

            let purchased_amount = if (current_time >= order_key.end_time) {
                // update order state to reflect that the order has been fully executed
                self.orders.write(order_key, Zero::zero());

                // reward rate at expiration/full-execution time
                let total_reward_rate = self.get_reward_rate_at(order_key, order_key.end_time)
                    - order_reward_rate;
                calculate_reward_amount(total_reward_rate, order_state.sale_rate)
            } else {
                let current_reward_rate = self.get_current_reward_rate(order_key);
                // update order state to reflect that the order has been partially executed
                self
                    .orders
                    .write(
                        order_key,
                        OrderState {
                            sale_rate: order_state.sale_rate,
                            reward_rate: current_reward_rate,
                            use_snapshot: true,
                        }
                    );

                calculate_reward_amount(
                    current_reward_rate - order_reward_rate, order_state.sale_rate
                )
            };

            // transfer purchased amount 
            if (purchased_amount.is_non_zero()) {
                self
                    .withdraw(
                        order_key,
                        if (order_key.is_sell_token1) {
                            order_key.twamm_pool_key.token0
                        } else {
                            order_key.twamm_pool_key.token1
                        },
                        recipient,
                        purchased_amount,
                        0
                    );
            }

            self.emit(OrderProceedsWithdrawn { order_key, amount: purchased_amount });
        }

        fn execute_virtual_orders(ref self: ContractState, pool_key: PoolKey) {
            // execute virtual orders up to current time
            self.internal_execute_virtual_orders(pool_key);
        }
    }

    #[abi(embed_v0)]
    impl LockerImpl of ILocker<ContractState> {
        fn locked(ref self: ContractState, id: u32, data: Span<felt252>) -> Span<felt252> {
            let core = self.core.read();

            let result: LockCallbackResult =
                match consume_callback_data::<LockCallbackData>(core, data) {
                LockCallbackData::ExecuteVirtualSwapsCallbackData(data) => {
                    let twamm_pool_key = TWAMMPoolKey {
                        token0: data.pool_key.token0,
                        token1: data.pool_key.token1,
                        fee: data.pool_key.fee
                    };

                    // since virtual orders are executed at the same time for both tokens,
                    // last_virtual_order_time is the same for both tokens.
                    let mut last_virtual_order_time = self
                        .last_virtual_order_time
                        .read(twamm_pool_key);

                    let current_time = get_block_timestamp();

                    let self_snap = @self;

                    if (last_virtual_order_time == 0) {
                        // we haven't executed any virtual orders yet, and no orders have been placed
                        self.last_virtual_order_time.write(twamm_pool_key, current_time);
                    } else if (last_virtual_order_time != current_time) {
                        let mut total_delta = Zero::<Delta>::zero();
                        let mut token_reward_rate = (0, 0);

                        loop {
                            let mut delta = Zero::zero();

                            // find next time with a sale rate delta
                            let next_initialized_time = self_snap
                                .next_initialized_time(
                                    twamm_pool_key, last_virtual_order_time, current_time
                                );

                            let next_virtual_order_time = min(current_time, next_initialized_time);

                            let (token0_sale_rate, token1_sale_rate) = self
                                .sale_rate
                                .read(twamm_pool_key);

                            if (token0_sale_rate > 0 || token1_sale_rate > 0) {
                                let price = core.get_pool_price(data.pool_key);

                                if price.sqrt_ratio != 0 {
                                    let time_elapsed = next_virtual_order_time
                                        - last_virtual_order_time;

                                    let token0_amount = (token0_sale_rate * time_elapsed.into())
                                        / constants::X32_u128;
                                    let token1_amount = (token1_sale_rate * time_elapsed.into())
                                        / constants::X32_u128;

                                    if (token0_amount != 0 && token1_amount != 0) {
                                        let sqrt_ratio_limit = calculate_next_sqrt_ratio(
                                            price.sqrt_ratio,
                                            core.get_pool_liquidity(data.pool_key),
                                            token0_sale_rate,
                                            token1_sale_rate,
                                            time_elapsed
                                        );

                                        let is_token1 = price.sqrt_ratio < sqrt_ratio_limit;

                                        // swap up/down to sqrt_ratio_limit
                                        delta = core
                                            .swap(
                                                data.pool_key,
                                                SwapParameters {
                                                    amount: i129 {
                                                        mag: 0xffffffffffffffffffffffffffffffff,
                                                        sign: false
                                                    },
                                                    is_token1: is_token1,
                                                    sqrt_ratio_limit,
                                                    skip_ahead: 0
                                                }
                                            );

                                        // update reward rate
                                        token_reward_rate = self
                                            .update_reward_rate(
                                                twamm_pool_key,
                                                (token0_sale_rate, token1_sale_rate),
                                                delta
                                                    + Delta {
                                                        amount0: i129 {
                                                            mag: token0_amount, sign: true
                                                        },
                                                        amount1: i129 {
                                                            mag: token1_amount, sign: true
                                                        }
                                                    },
                                                next_virtual_order_time
                                            );
                                    } else {
                                        let (amount, is_token1, sqrt_ratio_limit) =
                                            if token0_amount > 0 {
                                            (token0_amount, false, min_sqrt_ratio())
                                        } else {
                                            (token1_amount, true, max_sqrt_ratio())
                                        };

                                        delta = core
                                            .swap(
                                                data.pool_key,
                                                SwapParameters {
                                                    amount: i129 { mag: amount, sign: false },
                                                    is_token1,
                                                    sqrt_ratio_limit,
                                                    skip_ahead: 0
                                                }
                                            );

                                        // update reward rate
                                        token_reward_rate = self
                                            .update_reward_rate(
                                                twamm_pool_key,
                                                (token0_sale_rate, token1_sale_rate),
                                                delta,
                                                next_virtual_order_time
                                            );
                                    }

                                    // accumulate deltas
                                    total_delta += delta;

                                    let (token0_reward_rate, token1_reward_rate) =
                                        token_reward_rate;

                                    self
                                        .emit(
                                            VirtualOrdersExecuted {
                                                last_virtual_order_time,
                                                next_virtual_order_time,
                                                token0_sale_rate: token0_sale_rate,
                                                token1_sale_rate: token1_sale_rate,
                                                token0_reward_rate: token0_reward_rate,
                                                token1_reward_rate: token1_reward_rate
                                            }
                                        );
                                }
                            }

                            let (token0_sale_rate_net, token1_sale_rate_net) = self
                                .time_sale_rate_net
                                .read((twamm_pool_key, next_virtual_order_time));

                            // update ending sale rates 
                            if (token0_sale_rate_net != 0 || token1_sale_rate_net != 0) {
                                self
                                    .update_token_sale_rate_and_rewards(
                                        twamm_pool_key,
                                        (token0_sale_rate, token1_sale_rate),
                                        next_virtual_order_time
                                    );
                            } else {}

                            // update last_virtual_order_time to next_virtual_order_time
                            last_virtual_order_time = next_virtual_order_time;

                            // virtual orders were executed up to current time
                            if next_virtual_order_time == current_time {
                                break;
                            }
                        };

                        self.last_virtual_order_time.write(twamm_pool_key, last_virtual_order_time);

                        // zero out deltas
                        if (total_delta.amount0.mag > 0) {
                            if (total_delta.amount0.sign) {
                                core
                                    .save(
                                        SavedBalanceKey {
                                            owner: get_contract_address(),
                                            token: twamm_pool_key.token0,
                                            salt: 0
                                        },
                                        total_delta.amount0.mag
                                    );
                            } else {
                                core.load(twamm_pool_key.token0, 0, total_delta.amount0.mag);
                            }
                        }
                        if (total_delta.amount1.mag > 0) {
                            if (total_delta.amount1.sign) {
                                core
                                    .save(
                                        SavedBalanceKey {
                                            owner: get_contract_address(),
                                            token: twamm_pool_key.token1,
                                            salt: 0
                                        },
                                        total_delta.amount1.mag
                                    );
                            } else {
                                core.load(twamm_pool_key.token1, 0, total_delta.amount1.mag);
                            }
                        }
                    }

                    LockCallbackResult::Empty
                },
                LockCallbackData::DepositBalanceCallbackData(data) => {
                    IERC20Dispatcher { contract_address: data.token }
                        .approve(core.contract_address, data.amount.into());
                    core.pay(data.token);

                    core
                        .save(
                            SavedBalanceKey {
                                owner: get_contract_address(), token: data.token, salt: 0
                            },
                            data.amount
                        );

                    LockCallbackResult::Empty
                },
                LockCallbackData::WithdrawBalanceCallbackData(data) => {
                    core.load(data.token, 0, data.amount);

                    let order_key = data.order_key;
                    let pool_key: PoolKey = order_key.into();

                    if (data.fee > 0) {
                        if (core.get_pool_liquidity(pool_key).is_non_zero()) {
                            let (amount0, amount1) = if (order_key.is_sell_token1) {
                                (0, data.fee)
                            } else {
                                (data.fee, 0)
                            };
                            core.accumulate_as_fees(pool_key, amount0, amount1);
                        } else { // TODO: sell token
                        }
                        core.withdraw(data.token, data.recipient, data.amount - data.fee);
                    } else {
                        core.withdraw(data.token, data.recipient, data.amount);
                    }

                    LockCallbackResult::Empty
                }
            };

            let mut result_data = ArrayTrait::new();
            Serde::serialize(@result, ref result_data);
            result_data.span()
        }
    }

    #[generate_trait]
    impl Internal of InternalTrait {
        // assume order has not ended
        fn update_order_sale_rate(
            ref self: ContractState,
            order_key: OrderKey,
            order_state: OrderState,
            sale_rate_delta: i129,
            order_started: bool
        ) {
            let current_time = get_block_timestamp();
            assert(order_key.end_time > current_time, 'ORDER_ENDED');

            // underflow error if delta is negative and larger than the current sale rate
            let sale_rate_next = order_state.sale_rate.add(sale_rate_delta);

            let (reward_rate, use_snapshot, order_start_time) = if (sale_rate_next.is_zero()) {
                // Cancel order
                let order_reward_rate = if (order_state.use_snapshot) {
                    order_state.reward_rate
                } else {
                    self.get_reward_rate_at(order_key, order_key.start_time)
                };

                // all proceeds withdrawn or order has not started
                assert(
                    self.get_current_reward_rate(order_key) == order_reward_rate
                        || order_key.start_time > current_time,
                    'MUST_WITHDRAW_PROCEEDS'
                );

                // zero out the state
                (0, false, order_key.start_time)
            } else if (order_started) {
                let current_reward_rate = self.get_current_reward_rate(order_key);

                let current_order_reward_rate = current_reward_rate - order_state.reward_rate;

                let adjusted_reward_rate = if (current_order_reward_rate == 0) {
                    order_state.reward_rate
                } else {
                    let token_reward_amount = calculate_reward_amount(
                        current_reward_rate, order_state.sale_rate
                    );

                    let adjusted_reward_rate = calculate_reward_rate(
                        token_reward_amount, sale_rate_next
                    );

                    current_order_reward_rate - adjusted_reward_rate
                };

                (adjusted_reward_rate, true, current_time)
            } else {
                (0, false, order_key.start_time)
            };

            // store order state
            self
                .orders
                .write(
                    order_key,
                    OrderState {
                        sale_rate: sale_rate_next,
                        reward_rate: reward_rate,
                        use_snapshot: use_snapshot,
                    }
                );

            self.emit(OrderUpdated { order_key, sale_rate_delta: sale_rate_delta });

            // add sale rate delta 
            if (order_started) {
                self.update_global_sale_rate(order_key, sale_rate_delta);
            } else {
                self.update_time(order_key, order_start_time, sale_rate_delta, true);
            }

            // add sale rate delta at end time
            self.update_time(order_key, order_key.end_time, sale_rate_delta, false);
        }

        // update the sale rate deltas and net
        fn update_time(
            ref self: ContractState,
            order_key: OrderKey,
            time: u64,
            sale_rate_delta: i129,
            is_start_time: bool
        ) {
            // update sale rate delta
            let (token0_sale_rate_delta, token1_sale_rate_delta) = self
                .time_sale_rate_delta
                .read((order_key.twamm_pool_key, time));

            if (order_key.is_sell_token1) {
                let next_sale_rate_delta = if (is_start_time) {
                    token1_sale_rate_delta + sale_rate_delta
                } else {
                    token1_sale_rate_delta - sale_rate_delta
                };
                self
                    .time_sale_rate_delta
                    .write(
                        (order_key.twamm_pool_key, time),
                        (token0_sale_rate_delta, next_sale_rate_delta)
                    );
            } else {
                let next_sale_rate_delta = if (is_start_time) {
                    token0_sale_rate_delta + sale_rate_delta
                } else {
                    token0_sale_rate_delta - sale_rate_delta
                };
                self
                    .time_sale_rate_delta
                    .write(
                        (order_key.twamm_pool_key, time),
                        (next_sale_rate_delta, token1_sale_rate_delta)
                    );
            }

            // update sale rate net
            let (token0_sale_rate_net, token1_sale_rate_net) = self
                .time_sale_rate_net
                .read((order_key.twamm_pool_key, time));

            let (current_sale_rate_net, next_sale_rate_net, other_token_sale_rate_net) =
                if (order_key
                .is_sell_token1) {
                let next_sale_rate_net = token1_sale_rate_net.add(sale_rate_delta);
                self
                    .time_sale_rate_net
                    .write(
                        (order_key.twamm_pool_key, time), (token0_sale_rate_net, next_sale_rate_net)
                    );
                (token1_sale_rate_net, next_sale_rate_net, token0_sale_rate_net)
            } else {
                let next_sale_rate_net = token0_sale_rate_net.add(sale_rate_delta);
                self
                    .time_sale_rate_net
                    .write(
                        (order_key.twamm_pool_key, time), (next_sale_rate_net, token1_sale_rate_net)
                    );
                (token0_sale_rate_net, next_sale_rate_net, token1_sale_rate_net)
            };

            if ((next_sale_rate_net == 0) != (current_sale_rate_net == 0)
                && other_token_sale_rate_net == 0) {
                if (next_sale_rate_net == 0) {
                    self.remove_initialized_time(order_key.twamm_pool_key, time);
                } else {
                    self.insert_initialized_time(order_key.twamm_pool_key, time);
                }
            };
        }

        fn update_global_sale_rate(
            ref self: ContractState, order_key: OrderKey, sale_rate_delta: i129
        ) {
            let (token0_sale_rate, token1_sale_rate) = self
                .sale_rate
                .read(order_key.twamm_pool_key);

            self
                .sale_rate
                .write(
                    order_key.twamm_pool_key,
                    if (order_key.is_sell_token1) {
                        (token0_sale_rate, token1_sale_rate.add(sale_rate_delta))
                    } else {
                        (token0_sale_rate.add(sale_rate_delta), token1_sale_rate)
                    }
                );
        }

        fn get_current_reward_rate(self: @ContractState, order_key: OrderKey) -> felt252 {
            let (token0_reward_rate, token1_reward_rate) = self
                .reward_rate
                .read(order_key.twamm_pool_key);

            if (order_key.is_sell_token1) {
                token0_reward_rate
            } else {
                token1_reward_rate
            }
        }

        fn get_reward_rate_at(self: @ContractState, order_key: OrderKey, time: u64) -> felt252 {
            let (token0_reward_rate, token1_reward_rate) = self
                .time_reward_rate
                .read((order_key.twamm_pool_key, time));

            if (order_key.is_sell_token1) {
                token0_reward_rate
            } else {
                token1_reward_rate
            }
        }

        fn update_reward_rate(
            ref self: ContractState,
            twamm_pool_key: TWAMMPoolKey,
            sale_rates: (u128, u128),
            delta: Delta,
            time: u64
        ) -> (felt252, felt252) {
            let (token0_reward_delta, token1_reward_delta) = calculate_reward_rate_deltas(
                sale_rates, delta
            );

            let (current_token0_reward_rate, current_token1_reward_rate) = self
                .reward_rate
                .read(twamm_pool_key);

            let reward_rate = (
                current_token0_reward_rate + token0_reward_delta,
                current_token1_reward_rate + token1_reward_delta
            );

            self.reward_rate.write(twamm_pool_key, reward_rate);

            let (token0_reward_rate, token1_reward_rate) = self.reward_rate.read(twamm_pool_key);

            self
                .time_reward_rate
                .write((twamm_pool_key, time), (token0_reward_rate, token1_reward_rate));

            reward_rate
        }

        fn update_token_sale_rate_and_rewards(
            ref self: ContractState,
            twamm_pool_key: TWAMMPoolKey,
            sale_rates: (u128, u128),
            time: u64
        ) {
            let (token0_sale_rate, token1_sale_rate) = sale_rates;

            let (token0_sale_rate_delta, token1_sale_rate_delta) = self
                .time_sale_rate_delta
                .read((twamm_pool_key, time));

            if (token0_sale_rate_delta.mag > 0 || token1_sale_rate_delta.mag > 0) {
                self
                    .sale_rate
                    .write(
                        twamm_pool_key,
                        (
                            (i129 { mag: token0_sale_rate, sign: false } + token0_sale_rate_delta)
                                .mag,
                            (i129 { mag: token1_sale_rate, sign: false } + token1_sale_rate_delta)
                                .mag
                        )
                    );

                let (token0_reward_rate, token1_reward_rate) = self
                    .reward_rate
                    .read(twamm_pool_key);

                self
                    .time_reward_rate
                    .write((twamm_pool_key, time), (token0_reward_rate, token1_reward_rate));
            }
        }

        // remove the initialized time for the order
        fn remove_initialized_time(
            ref self: ContractState, twamm_pool_key: TWAMMPoolKey, time: u64
        ) {
            let (word_index, bit_index) = time_to_word_and_bit_index(time);

            let bitmap = self.time_sale_rate_bitmaps.read((twamm_pool_key, word_index));

            // it is assumed that bitmap already contains the set bit exp2(bit_index)
            self
                .time_sale_rate_bitmaps
                .write((twamm_pool_key, word_index), bitmap.unset_bit(bit_index));
        }

        // insert the initialized time for the order
        fn insert_initialized_time(
            ref self: ContractState, twamm_pool_key: TWAMMPoolKey, time: u64
        ) {
            let (word_index, bit_index) = time_to_word_and_bit_index(time);

            let bitmap = self.time_sale_rate_bitmaps.read((twamm_pool_key, word_index));

            self
                .time_sale_rate_bitmaps
                .write((twamm_pool_key, word_index), bitmap.set_bit(bit_index));
        }

        // return the next initialized time
        fn next_initialized_time(
            self: @ContractState, twamm_pool_key: TWAMMPoolKey, from: u64, max_time: u64
        ) -> u64 {
            let (word_index, bit_index) = time_to_word_and_bit_index(
                from + constants::BITMAP_SPACING
            );

            let bitmap: Bitmap = self.time_sale_rate_bitmaps.read((twamm_pool_key, word_index));

            match bitmap.next_set_bit(bit_index) {
                Option::Some(next_bit) => { word_and_bit_index_to_time((word_index, next_bit)) },
                Option::None => {
                    let next = word_and_bit_index_to_time((word_index, 0));

                    if (next > max_time) {
                        max_time
                    } else {
                        self.next_initialized_time(twamm_pool_key, next, max_time)
                    }
                },
            }
        }

        fn deposit(ref self: ContractState, token: ContractAddress, amount: u128) {
            match call_core_with_callback::<
                LockCallbackData, LockCallbackResult
            >(
                self.core.read(),
                @LockCallbackData::DepositBalanceCallbackData(
                    DepositBalanceCallbackData { token: token, amount: amount }
                )
            ) {
                LockCallbackResult::Empty => {},
            }
        }

        fn withdraw(
            ref self: ContractState,
            order_key: OrderKey,
            token: ContractAddress,
            recipient: ContractAddress,
            amount: u128,
            fee: u128
        ) {
            match call_core_with_callback::<
                LockCallbackData, LockCallbackResult
            >(
                self.core.read(),
                @LockCallbackData::WithdrawBalanceCallbackData(
                    WithdrawBalanceCallbackData { order_key, token, recipient, amount, fee }
                )
            ) {
                LockCallbackResult::Empty => {},
            }
        }

        fn internal_execute_virtual_orders(ref self: ContractState, pool_key: PoolKey) {
            pool_key.check_valid();

            match call_core_with_callback::<
                LockCallbackData, LockCallbackResult
            >(
                self.core.read(),
                @LockCallbackData::ExecuteVirtualSwapsCallbackData(
                    ExecuteVirtualSwapsCallbackData { pool_key: pool_key }
                )
            ) {
                LockCallbackResult::Empty => {},
            }
        }
    }

    pub fn time_to_word_and_bit_index(time: u64) -> (u128, u8) {
        (
            (time / (constants::BITMAP_SPACING * 251)).into(),
            250_u8 - ((time / constants::BITMAP_SPACING) % 251).try_into().unwrap()
        )
    }

    pub fn word_and_bit_index_to_time(word_and_bit_index: (u128, u8)) -> u64 {
        let (word, bit) = word_and_bit_index;
        ((word * 251 * constants::BITMAP_SPACING.into())
            + ((250 - bit).into() * constants::BITMAP_SPACING.into()))
            .try_into()
            .unwrap()
    }

    impl OrderKeyIntoPoolKey of Into<OrderKey, PoolKey> {
        fn into(self: OrderKey) -> PoolKey {
            PoolKey {
                token0: self.twamm_pool_key.token0,
                token1: self.twamm_pool_key.token1,
                fee: self.twamm_pool_key.fee,
                tick_spacing: MAX_TICK_SPACING,
                extension: get_contract_address()
            }
        }
    }
}
