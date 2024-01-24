use core::integer::{u256_safe_divmod, u256_as_non_zero};
use core::traits::{Into, TryInto};
use ekubo::types::i129::{i129, i129Trait};
use ekubo::types::keys::{PoolKey};
use starknet::{ContractAddress, ClassHash, StorePacking};

#[derive(Drop, Copy, Serde, Hash)]
struct TWAMMPoolKey {
    token0: ContractAddress,
    token1: ContractAddress,
    // pool fee
    fee: u128,
}

#[derive(Drop, Copy, Serde, Hash)]
struct OrderKey {
    twamm_pool_key: TWAMMPoolKey,
    is_sell_token1: bool,
    start_time: u64,
    end_time: u64
}

// state of a particular order, defined by the key
#[derive(Drop, Copy, Serde, PartialEq, starknet::Store)]
struct OrderState {
    sale_rate: u128,
    reward_rate_start_time: u64
}

#[starknet::interface]
trait ITWAMM<TContractState> {
    // Return the NFT contract address that this contract uses to represent limit orders
    fn get_nft_address(self: @TContractState) -> ContractAddress;

    // Upgrade the NFT contract to a new version
    fn upgrade_nft(ref self: TContractState, class_hash: ClassHash);

    // Return the stored order state
    fn get_order_state(self: @TContractState, order_key: OrderKey, id: u64) -> OrderState;

    // Returns the current sale rate 
    fn get_sale_rate(self: @TContractState, twamm_pool_key: TWAMMPoolKey) -> (u128, u128);

    // Return the current reward rate
    fn get_reward_rate(self: @TContractState, twamm_pool_key: TWAMMPoolKey) -> (felt252, felt252);

    // Creates a new twamm order
    fn place_order(ref self: TContractState, order_key: OrderKey, amount: u128) -> u64;

    // Cancels a twamm order
    fn cancel_order(ref self: TContractState, order_key: OrderKey, id: u64);

    // Withdraws proceeds from a twamm order
    fn withdraw_from_order(ref self: TContractState, order_key: OrderKey, id: u64);

    // Execute virtual orders
    fn execute_virtual_orders(ref self: TContractState, pool_key: PoolKey);
}

#[starknet::contract]
mod TWAMM {
    use core::cmp::{min};
    use core::integer::{downcast, upcast, u256_sqrt, u128_sqrt};
    use core::num::traits::{Zero};
    use core::option::{OptionTrait};
    use core::traits::{TryInto, Into};
    use ekubo::components::owned::{Owned as owned_component};
    use ekubo::components::shared_locker::{call_core_with_callback, consume_callback_data};
    use ekubo::components::upgradeable::{Upgradeable as upgradeable_component, IHasInterface};
    use ekubo::extensions::twamm::math::{
        constants, calculate_sale_rate, calculate_reward_rate_deltas, calculate_reward_amount,
        validate_time, calculate_next_sqrt_ratio, BitmapIsSetTraitImpl
    };
    use ekubo::interfaces::core::{
        IExtension, SwapParameters, UpdatePositionParameters, Delta, ILocker, ICoreDispatcher,
        ICoreDispatcherTrait, SavedBalanceKey
    };
    use ekubo::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use ekubo::interfaces::upgradeable::{
        IUpgradeable, IUpgradeableDispatcher, IUpgradeableDispatcherTrait
    };
    use ekubo::math::bitmap::{Bitmap, BitmapTrait};
    use ekubo::math::bits::{msb};
    use ekubo::math::delta::{amount0_delta, amount1_delta};
    use ekubo::math::exp2::{exp2};
    use ekubo::math::liquidity::{liquidity_delta_to_amount_delta};
    use ekubo::math::ticks::constants::{MAX_TICK_SPACING};
    use ekubo::math::ticks::{min_tick, max_tick, min_sqrt_ratio, max_sqrt_ratio};
    use ekubo::math::ticks::{tick_to_sqrt_ratio};
    use ekubo::owned_nft::{OwnedNFT, IOwnedNFTDispatcher, IOwnedNFTDispatcherTrait};
    use ekubo::types::bounds::{Bounds, max_bounds};
    use ekubo::types::call_points::{CallPoints};
    use ekubo::types::i129::{i129, i129Trait};
    use ekubo::types::keys::{PoolKey, PoolKeyTrait};
    use starknet::{
        get_contract_address, get_caller_address, replace_class_syscall, get_block_timestamp,
        ClassHash
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
        nft: IOwnedNFTDispatcher,
        orders: LegacyMap<(OrderKey, u64), OrderState>,
        // current rate at which tokens are sold
        sale_rate: LegacyMap<TWAMMPoolKey, (u128, u128)>,
        // sale rate deltas
        sale_rate_delta: LegacyMap<(TWAMMPoolKey, u64), (i129, i129)>,
        // used to find next timestamp at which sale rate changes
        sale_rate_time_bitmaps: LegacyMap<(TWAMMPoolKey, u128), Bitmap>,
        // current reward rates
        reward_rate: LegacyMap<TWAMMPoolKey, (felt252, felt252)>,
        // reward rates 
        reward_rate_at_time: LegacyMap<(TWAMMPoolKey, u64), (felt252, felt252)>,
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
        core: ICoreDispatcher,
        nft_class_hash: ClassHash,
        token_uri_base: felt252
    ) {
        self.initialize_owned(owner);
        self.core.write(core);

        self
            .nft
            .write(
                OwnedNFT::deploy(
                    nft_class_hash: nft_class_hash,
                    owner: get_contract_address(),
                    name: 'Ekubo TWAMM',
                    symbol: 'eTWAMM',
                    token_uri_base: token_uri_base,
                    salt: 0
                )
            );
    }

    #[derive(starknet::Event, Drop)]
    struct OrderPlaced {
        id: u64,
        order_key: OrderKey,
        amount: u128,
        sale_rate: u128
    }

    #[derive(starknet::Event, Drop)]
    struct OrderCancelled {
        id: u64,
        order_key: OrderKey,
    }

    #[derive(starknet::Event, Drop)]
    struct OrderWithdrawn {
        id: u64,
        order_key: OrderKey,
        amount: u128
    }

    #[derive(starknet::Event, Drop)]
    struct VirtualOrdersExecuted {
        last_virtual_order_time: u64,
        next_virtual_order_time: u64,
        token0_sale_rate: u128,
        token1_sale_rate: u128,
        token0_reward_rate: felt252,
        token1_reward_rate: felt252
    }

    #[derive(starknet::Event, Drop)]
    #[event]
    enum Event {
        #[flat]
        UpgradeableEvent: upgradeable_component::Event,
        OwnedEvent: owned_component::Event,
        OrderPlaced: OrderPlaced,
        OrderCancelled: OrderCancelled,
        OrderWithdrawn: OrderWithdrawn,
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
        token: ContractAddress,
        recipient: ContractAddress,
        amount: u128
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
        fn get_nft_address(self: @ContractState) -> ContractAddress {
            self.nft.read().contract_address
        }

        fn upgrade_nft(ref self: ContractState, class_hash: ClassHash) {
            self.require_owner();
            IUpgradeableDispatcher { contract_address: self.nft.read().contract_address }
                .replace_class_hash(class_hash);
        }

        fn get_order_state(self: @ContractState, order_key: OrderKey, id: u64) -> OrderState {
            self.orders.read((order_key, id))
        }

        fn get_sale_rate(self: @ContractState, twamm_pool_key: TWAMMPoolKey) -> (u128, u128) {
            self.sale_rate.read(twamm_pool_key)
        }

        fn get_reward_rate(
            self: @ContractState, twamm_pool_key: TWAMMPoolKey
        ) -> (felt252, felt252) {
            self.reward_rate.read(twamm_pool_key)
        }

        fn place_order(ref self: ContractState, order_key: OrderKey, amount: u128) -> u64 {
            let current_time = get_block_timestamp();

            // validate order starts now or in the future
            assert(
                order_key.start_time == 0 || order_key.start_time > current_time,
                'INVALID_START_TIME'
            );

            let order_start_time = if (order_key.start_time == 0) {
                current_time
            } else {
                validate_time(current_time, order_key.start_time);
                order_key.start_time
            };
            validate_time(order_start_time, order_key.end_time);

            // execute virtual orders up to current time
            self.internal_execute_virtual_orders(to_pool_key(order_key));

            // mint TWAMM NFT
            let id = self.nft.read().mint(get_caller_address());

            // calculate and store order sale rate
            let sale_rate = calculate_sale_rate(amount, order_key.end_time, order_start_time);

            // store order state
            self
                .orders
                .write(
                    (order_key, id),
                    OrderState { sale_rate, reward_rate_start_time: order_start_time }
                );

            if (order_key.start_time.is_zero()) {
                // increase global sale rate
                self.update_global_sale_rate(order_key, sale_rate, true);
            } else {
                // add sale rate to sale rate delta
                self
                    .update_sale_rate_delta(
                        order_key, order_key.start_time, i129 { mag: sale_rate, sign: false }
                    );
            }

            // update sale rate delta at end time
            let (token0_sale_rate_delta, token1_sale_rate_delta) = self
                .update_sale_rate_delta(
                    order_key, order_key.end_time, i129 { mag: sale_rate, sign: true }
                );

            self.emit(OrderPlaced { id, order_key, amount, sale_rate });

            // deposit token amount to core contract
            self
                .deposit(
                    if (order_key.is_sell_token1) {
                        order_key.twamm_pool_key.token1
                    } else {
                        order_key.twamm_pool_key.token0
                    },
                    amount
                );

            id
        }

        fn cancel_order(ref self: ContractState, order_key: OrderKey, id: u64) {
            let caller = get_caller_address();
            self.validate_caller(id, caller);

            self.internal_execute_virtual_orders(to_pool_key(order_key));

            let order_state = self.orders.read((order_key, id));
            let current_time = get_block_timestamp();

            // validate that the order has not expired
            assert(order_key.end_time > current_time, 'ORDER_EXPIRED');

            // calculate amount that was not sold
            let remaining_amount = self.get_order_remaining_amount(order_key, order_state);

            // decrease global rates
            self.update_global_sale_rate(order_key, order_state.sale_rate, false);

            // update sale rate delta at end time (zero out the delta)
            let (token0_sale_rate_delta, token1_sale_rate_delta) = self
                .update_sale_rate_delta(
                    order_key, order_key.end_time, i129 { mag: order_state.sale_rate, sign: false }
                );

            // remove the initialized time if this is the last order 
            if (token0_sale_rate_delta.mag == 0 && token1_sale_rate_delta.mag == 0) {
                self.remove_initialized_time(order_key.twamm_pool_key, order_key.end_time);
            }

            // update order state to reflect that the order has been cancelled
            self
                .orders
                .write((order_key, id), OrderState { sale_rate: 0, reward_rate_start_time: 0 });

            // burn the NFT
            self.nft.read().burn(id);

            if (order_key.start_time <= current_time) {
                // calculate amount that was purchased
                let reward_rate = (self.get_current_reward_rate(order_key)
                    - self.get_reward_rate_at(order_key, order_key.start_time));
                let purchased_amount = calculate_reward_amount(reward_rate, order_state.sale_rate);

                // transfer remaining amount
                if (remaining_amount.is_non_zero()) {
                    self.withdraw(order_key.twamm_pool_key.token0, caller, remaining_amount);
                }

                // transfer purchased amount 
                if (purchased_amount.is_non_zero()) {
                    self.withdraw(order_key.twamm_pool_key.token1, caller, purchased_amount)
                }
            }

            self.emit(OrderCancelled { id, order_key });
        }

        fn withdraw_from_order(ref self: ContractState, order_key: OrderKey, id: u64) {
            let caller = get_caller_address();
            self.validate_caller(id, caller);

            self.internal_execute_virtual_orders(to_pool_key(order_key));

            let order_state = self.orders.read((order_key, id));

            // order has been fully withdrawn
            assert(order_state.sale_rate > 0, 'ZERO_SALE_RATE');

            let current_time = get_block_timestamp();

            let start_time_reward = self
                .get_reward_rate_at(order_key, order_state.reward_rate_start_time);

            let total_reward_rate = if current_time >= order_key.end_time {
                // TODO: Should we burn the NFT? Probably not.
                // update order state to reflect that the order has been fully executed
                self
                    .orders
                    .write((order_key, id), OrderState { sale_rate: 0, reward_rate_start_time: 0 });

                // reward rate at expiration/full-execution time
                self.get_reward_rate_at(order_key, order_key.end_time) - start_time_reward
            } else {
                // update order state to reflect that the order has been partially executed
                let reward_rate = self.get_current_reward_rate(order_key);

                self
                    .orders
                    .write(
                        (order_key, id),
                        OrderState {
                            sale_rate: order_state.sale_rate, reward_rate_start_time: current_time
                        }
                    );

                reward_rate - start_time_reward
            };

            let purchased_amount = calculate_reward_amount(
                total_reward_rate, order_state.sale_rate
            );

            // transfer purchased amount 
            if (purchased_amount.is_non_zero()) {
                self
                    .withdraw(
                        if (order_key.is_sell_token1) {
                            order_key.twamm_pool_key.token0
                        } else {
                            order_key.twamm_pool_key.token1
                        },
                        caller,
                        purchased_amount
                    );
            }

            self.emit(OrderWithdrawn { id, order_key, amount: purchased_amount });
        }

        fn execute_virtual_orders(ref self: ContractState, pool_key: PoolKey) {
            self.internal_execute_virtual_orders(pool_key);
        }
    }

    #[abi(embed_v0)]
    impl LockerImpl of ILocker<ContractState> {
        fn locked(ref self: ContractState, id: u32, data: Array<felt252>) -> Array<felt252> {
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
                            let mut delta = Zero::<Delta>::zero();

                            // find next time with sale rate delta
                            let next_initialized_time = self_snap
                                .next_initialized_time(
                                    twamm_pool_key, last_virtual_order_time, current_time
                                );

                            let next_virtual_order_time = min(next_initialized_time, current_time);

                            let (token0_sale_rate, token1_sale_rate) = self
                                .sale_rate
                                .read(twamm_pool_key);

                            if (token0_sale_rate > 0 || token1_sale_rate > 0) {
                                let price = core.get_pool_price(data.pool_key);

                                if price.sqrt_ratio != 0 {
                                    let virtual_order_time_window = next_virtual_order_time
                                        - last_virtual_order_time;
                                    let token0_amount = (token0_sale_rate
                                        * virtual_order_time_window.into())
                                        / constants::X32_u128;
                                    let token1_amount = (token1_sale_rate
                                        * virtual_order_time_window.into())
                                        / constants::X32_u128;

                                    if (token0_amount != 0 && token1_amount != 0) {
                                        let sqrt_ratio_limit = calculate_next_sqrt_ratio(
                                            price.sqrt_ratio,
                                            core.get_pool_liquidity(data.pool_key),
                                            token0_sale_rate,
                                            token1_sale_rate,
                                            virtual_order_time_window
                                        );

                                        let is_token1 = price.sqrt_ratio < sqrt_ratio_limit;

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

                            // update ending sale rates 
                            self
                                .update_sale_rate(
                                    twamm_pool_key,
                                    (token0_sale_rate, token1_sale_rate),
                                    next_virtual_order_time
                                );

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

                    core.withdraw(data.token, data.recipient, data.amount);

                    LockCallbackResult::Empty
                }
            };

            let mut result_data = ArrayTrait::new();
            Serde::serialize(@result, ref result_data);
            result_data
        }
    }

    #[generate_trait]
    impl Internal of InternalTrait {
        fn validate_caller(self: @ContractState, id: u64, caller: ContractAddress) {
            assert(self.nft.read().is_account_authorized(id, caller), 'UNAUTHORIZED');
        }

        // update the sale rate deltas at a time, and returns the updated value
        fn update_sale_rate_delta(
            ref self: ContractState, order_key: OrderKey, time: u64, sale_rate: i129,
        ) -> (i129, i129) {
            let (token0_sale_rate_delta, token1_sale_rate_delta) = self
                .sale_rate_delta
                .read((order_key.twamm_pool_key, time));

            let sale_rate_delta = if (order_key.is_sell_token1) {
                (token0_sale_rate_delta, token1_sale_rate_delta + sale_rate)
            } else {
                (token0_sale_rate_delta + sale_rate, token1_sale_rate_delta)
            };

            self.sale_rate_delta.write((order_key.twamm_pool_key, time), sale_rate_delta);

            // TODO: figure out if we can avoid retrieving the bitmap
            self.insert_initialized_time(order_key.twamm_pool_key, time);

            sale_rate_delta
        }

        // update the global sale rate, and return the updated value
        fn update_global_sale_rate(
            ref self: ContractState, order_key: OrderKey, sale_rate: u128, increase: bool
        ) -> (u128, u128) {
            let (token0_sale_rate, token1_sale_rate) = self
                .sale_rate
                .read(order_key.twamm_pool_key);

            let sale_rate = if (increase) {
                if (order_key.is_sell_token1) {
                    (token0_sale_rate, token1_sale_rate + sale_rate)
                } else {
                    (token0_sale_rate + sale_rate, token1_sale_rate)
                }
            } else {
                if (order_key.is_sell_token1) {
                    (token0_sale_rate, token1_sale_rate - sale_rate)
                } else {
                    (token0_sale_rate - sale_rate, token1_sale_rate)
                }
            };

            self.sale_rate.write(order_key.twamm_pool_key, sale_rate);

            sale_rate
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
                .reward_rate_at_time
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
                .reward_rate_at_time
                .write((twamm_pool_key, time), (token0_reward_rate, token1_reward_rate));

            reward_rate
        }

        fn update_sale_rate(
            ref self: ContractState,
            twamm_pool_key: TWAMMPoolKey,
            sale_rates: (u128, u128),
            time: u64
        ) {
            let (token0_sale_rate, token1_sale_rate) = sale_rates;

            let (token0_sale_rate_delta, token1_sale_rate_delta) = self
                .sale_rate_delta
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
                    .reward_rate_at_time
                    .write((twamm_pool_key, time), (token0_reward_rate, token1_reward_rate));
            }
        }

        // returns the amount that has not been sold based on the order sale_rate
        fn get_order_remaining_amount(
            ref self: ContractState, order_key: OrderKey, order_state: OrderState
        ) -> u128 {
            (order_state.sale_rate
                * (order_key.end_time - self.last_virtual_order_time.read(order_key.twamm_pool_key))
                    .into())
                / constants::X32_u128
        }

        // remove the initialized time for the order
        fn remove_initialized_time(
            ref self: ContractState, twamm_pool_key: TWAMMPoolKey, time: u64
        ) {
            let (word_index, bit_index) = time_to_word_and_bit_index(time);

            let bitmap = self.sale_rate_time_bitmaps.read((twamm_pool_key, word_index));

            // it is assumed that bitmap already contains the set bit exp2(bit_index)
            self
                .sale_rate_time_bitmaps
                .write((twamm_pool_key, word_index), bitmap.unset_bit(bit_index));
        }

        // insert the initialized time for the order
        fn insert_initialized_time(
            ref self: ContractState, twamm_pool_key: TWAMMPoolKey, time: u64
        ) {
            let (word_index, bit_index) = time_to_word_and_bit_index(time);

            let bitmap = self.sale_rate_time_bitmaps.read((twamm_pool_key, word_index));

            if (!bitmap.is_set(bit_index)) {
                // only initialize the time if it is not already initialized
                self
                    .sale_rate_time_bitmaps
                    .write((twamm_pool_key, word_index), bitmap.set_bit(bit_index));
            }
        }

        // return the next initialized time
        fn next_initialized_time(
            self: @ContractState, twamm_pool_key: TWAMMPoolKey, from: u64, max_time: u64
        ) -> u64 {
            let (word_index, bit_index) = time_to_word_and_bit_index(
                from + constants::BITMAP_SPACING
            );

            let bitmap: Bitmap = self.sale_rate_time_bitmaps.read((twamm_pool_key, word_index));

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
            token: ContractAddress,
            recipient: ContractAddress,
            amount: u128
        ) {
            match call_core_with_callback::<
                LockCallbackData, LockCallbackResult
            >(
                self.core.read(),
                @LockCallbackData::WithdrawBalanceCallbackData(
                    WithdrawBalanceCallbackData { token, recipient, amount }
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

    fn to_pool_key(order_key: OrderKey) -> PoolKey {
        PoolKey {
            token0: order_key.twamm_pool_key.token0,
            token1: order_key.twamm_pool_key.token1,
            fee: order_key.twamm_pool_key.fee,
            tick_spacing: MAX_TICK_SPACING,
            extension: get_contract_address()
        }
    }

    fn time_to_word_and_bit_index(time: u64) -> (u128, u8) {
        (
            (time / (constants::BITMAP_SPACING * 251)).into(),
            250_u8 - downcast((time / constants::BITMAP_SPACING) % 251).unwrap()
        )
    }

    fn word_and_bit_index_to_time(word_and_bit_index: (u128, u8)) -> u64 {
        let (word, bit) = word_and_bit_index;
        ((word * 251 * constants::BITMAP_SPACING.into())
            + (upcast(250 - bit) * constants::BITMAP_SPACING.into()))
            .try_into()
            .unwrap()
    }
}
