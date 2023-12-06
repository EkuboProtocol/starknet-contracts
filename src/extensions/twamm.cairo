use ekubo::types::i129::{i129, i129Trait};
use ekubo::types::keys::{PoolKey};
use integer::{u256_safe_divmod, u256_as_non_zero};
use starknet::{ContractAddress, StorePacking};
use traits::{Into, TryInto};

#[derive(Drop, Copy, Serde, Hash)]
struct OrderKey {
    token0: ContractAddress,
    token1: ContractAddress,
    fee: u128,
    expiry_time: u64
}

// State of a particular order, defined by the key
#[derive(Drop, Copy, Serde, PartialEq, starknet::Store)]
struct OrderState {
    // the rate at which the order is selling token0 for token1
    sale_rate: u128,
    // reward factor for token0
    reward_factor: u128,
}

#[derive(Drop, Copy, Serde, Hash)]
struct TWAMMPoolKey {
    token0: ContractAddress,
    token1: ContractAddress,
    // pool fee
    fee: u128,
}

#[starknet::interface]
trait ITWAMM<TContractState> {
    // Return the NFT contract address that this contract uses to represent limit orders
    fn get_nft_address(self: @TContractState) -> ContractAddress;

    // Return the stored order state
    fn get_order_state(self: @TContractState, order_key: OrderKey, id: u64) -> OrderState;

    // Returns the current sale rate for a token key
    fn get_sale_rate(self: @TContractState, twamm_pool_key: TWAMMPoolKey) -> u128;

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
    use array::{ArrayTrait};
    use cmp::{min};
    use debug::PrintTrait;
    use ekubo::interfaces::core::{
        IExtension, SwapParameters, UpdatePositionParameters, Delta, ILocker, ICoreDispatcher,
        ICoreDispatcherTrait, SavedBalanceKey
    };
    use ekubo::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use ekubo::interfaces::upgradeable::{IUpgradeable};
    use ekubo::math::bitmap::{Bitmap, BitmapTrait};
    use ekubo::math::bits::{msb};
    use ekubo::math::contract_address::{ContractAddressOrder};
    use ekubo::math::delta::{amount0_delta, amount1_delta};
    use ekubo::math::exp2::{exp2};
    use ekubo::math::liquidity::{liquidity_delta_to_amount_delta};
    use ekubo::math::max_liquidity::{max_liquidity_for_token0, max_liquidity_for_token1};
    use ekubo::math::ticks::constants::{MAX_TICK_SPACING};
    use ekubo::math::ticks::{min_tick, max_tick, min_sqrt_ratio, max_sqrt_ratio};
    use ekubo::math::ticks::{tick_to_sqrt_ratio};
    use ekubo::owned_nft::{OwnedNFT, IOwnedNFTDispatcher, IOwnedNFTDispatcherTrait};
    use ekubo::shared_locker::{call_core_with_callback, consume_callback_data};
    use ekubo::types::bounds::{Bounds, max_bounds};
    use ekubo::types::call_points::{CallPoints};
    use ekubo::types::keys::{PoolKey, PoolKeyTrait};
    use ekubo::upgradeable::{Upgradeable as upgradeable_component};
    use integer::{downcast, upcast, u256_sqrt, u128_sqrt};
    use option::{OptionTrait};
    use starknet::{
        get_contract_address, get_caller_address, replace_class_syscall, ClassHash,
        get_block_timestamp,
    };
    use super::{ITWAMM, i129, i129Trait, ContractAddress, OrderKey, OrderState, TWAMMPoolKey};
    use traits::{TryInto, Into};
    use zeroable::{Zeroable};

    const LOG_SCALE_FACTOR: u8 = 4;
    const BIT_MAP_SPACING: u64 = 16;

    component!(path: upgradeable_component, storage: upgradeable, event: ClassHashReplaced);

    #[abi(embed_v0)]
    impl Upgradeable = upgradeable_component::UpgradeableImpl<ContractState>;

    #[abi(embed_v0)]
    impl Clear = ekubo::clear::ClearImpl<ContractState>;

    #[storage]
    struct Storage {
        core: ICoreDispatcher,
        nft: IOwnedNFTDispatcher,
        orders: LegacyMap<(OrderKey, u64), OrderState>,
        // current rate at which token0 is being sold for token1
        sale_rate: LegacyMap<TWAMMPoolKey, u128>,
        // cumulative sale rate for token0 ending at a particular timestamp
        sale_rate_ending: LegacyMap<(TWAMMPoolKey, u64), u128>,
        // used to find next timestamp at which orders expire
        expiry_time_bitmaps: LegacyMap<(TWAMMPoolKey, u128), Bitmap>,
        // current reward factor for token key
        reward_factor: LegacyMap<TWAMMPoolKey, u128>,
        // reward factor for token key at a particular timestamp
        reward_factor_at_time: LegacyMap<(TWAMMPoolKey, u64), u128>,
        // last timestamp at which virtual order was executed
        last_virtual_order_time: LegacyMap<TWAMMPoolKey, u64>,
        // upgradable component storage (empty)
        #[substorage(v0)]
        upgradeable: upgradeable_component::Storage
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        core: ICoreDispatcher,
        nft_class_hash: ClassHash,
        token_uri_base: felt252
    ) {
        self.core.write(core);

        self
            .nft
            .write(
                OwnedNFT::deploy(
                    nft_class_hash: nft_class_hash,
                    controller: get_contract_address(),
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
        expiry_time: u64,
        sale_rate: u128,
        global_sale_rate: u128,
        sale_rate_ending: u128
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
    }

    #[derive(starknet::Event, Drop)]
    struct VirtualOrdersExecuted {
        last_virtual_order_time: u64,
        next_virtual_order_time: u64,
        token0_sale_rate: u128,
        token1_sale_rate: u128
    }

    #[derive(starknet::Event, Drop)]
    #[event]
    enum Event {
        #[flat]
        ClassHashReplaced: upgradeable_component::Event,
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


    #[external(v0)]
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

    #[external(v0)]
    impl TWAMMImpl of ITWAMM<ContractState> {
        fn get_nft_address(self: @ContractState) -> ContractAddress {
            self.nft.read().contract_address
        }

        fn get_order_state(self: @ContractState, order_key: OrderKey, id: u64) -> OrderState {
            self.orders.read((order_key, id))
        }

        fn get_sale_rate(self: @ContractState, twamm_pool_key: TWAMMPoolKey) -> u128 {
            self.sale_rate.read(twamm_pool_key)
        }

        fn place_order(ref self: ContractState, order_key: OrderKey, amount: u128) -> u64 {
            let current_time = get_block_timestamp();

            // validate that the order has a valid expiry time
            validate_expiry_time(current_time, order_key.expiry_time);

            // execute virtual orders up to current time
            self.internal_execute_virtual_orders(to_pool_key(order_key));

            // mint TWAMM NFT
            let id = self.nft.read().mint(get_caller_address());

            // calculate and store order sale rate
            let sale_rate = (amount * 0x100000000) / (order_key.expiry_time - current_time).into();

            let twamm_pool_key = to_token_key(order_key);

            self
                .orders
                .write(
                    (order_key, id),
                    OrderState {
                        sale_rate: sale_rate, reward_factor: self.reward_factor.read(twamm_pool_key)
                    }
                );

            // update global sale rate
            let global_sale_rate = self.sale_rate.read(twamm_pool_key) + sale_rate;
            self.sale_rate.write(twamm_pool_key, global_sale_rate);

            // update sale rate ending at expiry time
            let sale_rate_ending = self
                .sale_rate_ending
                .read((twamm_pool_key, order_key.expiry_time))
                + sale_rate;
            self.sale_rate_ending.write((twamm_pool_key, order_key.expiry_time), sale_rate_ending);

            // first order at this expiry time, insert the initialized expiry time
            if (sale_rate_ending == sale_rate) {
                self.insert_initialized_expiry(twamm_pool_key, order_key.expiry_time);
            }

            self
                .emit(
                    OrderPlaced {
                        id,
                        order_key,
                        amount,
                        expiry_time: order_key.expiry_time,
                        sale_rate,
                        global_sale_rate,
                        sale_rate_ending
                    }
                );

            self.deposit(twamm_pool_key.token0, amount);

            id
        }

        fn cancel_order(ref self: ContractState, order_key: OrderKey, id: u64) {
            let caller = get_caller_address();
            self.validate_caller(id, caller);

            self.internal_execute_virtual_orders(to_pool_key(order_key));

            let twamm_pool_key = to_token_key(order_key);

            let order_state = self.orders.read((order_key, id));
            let current_time = get_block_timestamp();

            // validate that the order has not expired
            assert(order_key.expiry_time > current_time, 'ORDER_EXPIRED');

            // calculate token0 amount that was not sold
            let remaining_amount = self.get_order_remaining_amount(order_key, order_state);

            // calculate token1 amount that was purchased
            let purchased_amount = ((self.reward_factor.read(twamm_pool_key)
                - order_state.reward_factor)
                * order_state.sale_rate)
                / 0x100000000;

            // update global rates
            let sale_rate = self.sale_rate.read(twamm_pool_key) - order_state.sale_rate;
            self.sale_rate.write(twamm_pool_key, sale_rate);
            self
                .sale_rate_ending
                .write(
                    (twamm_pool_key, order_key.expiry_time),
                    self.sale_rate_ending.read((twamm_pool_key, order_key.expiry_time))
                        - order_state.sale_rate
                );

            // update order state to reflect that the order has been cancelled
            self.orders.write((order_key, id), OrderState { sale_rate: 0, reward_factor: 0 });
            // burn the NFT
            self.nft.read().burn(id);

            // transfer remaining token0
            if (remaining_amount.is_non_zero()) {
                self.withdraw(twamm_pool_key.token0, caller, remaining_amount);
            }

            // transfer purchased token1 
            if (purchased_amount.is_non_zero()) {
                self.withdraw(twamm_pool_key.token1, caller, purchased_amount)
            }

            self.emit(OrderCancelled { id, order_key });
        }

        fn withdraw_from_order(ref self: ContractState, order_key: OrderKey, id: u64) {
            let caller = get_caller_address();
            self.validate_caller(id, caller);

            self.internal_execute_virtual_orders(to_pool_key(order_key));

            let twamm_pool_key = to_token_key(order_key);

            let order_state = self.orders.read((order_key, id));

            assert(order_state.sale_rate > 0, 'ZERO_SALE_RATE');

            let current_time = get_block_timestamp();

            let total_reward_factor = if current_time > order_key.expiry_time {
                // TODO: Should we burn the NFT? Probably not.
                // order has been fully executed
                // update order state to reflect that the order has been fully executed
                self.orders.write((order_key, id), OrderState { sale_rate: 0, reward_factor: 0 });

                // reward factor at expiration/full-execution time
                self.reward_factor_at_time.read((twamm_pool_key, order_key.expiry_time))
                    - order_state.reward_factor
            } else {
                // update order state to reflect that the order has been partially executed
                self
                    .orders
                    .write(
                        (order_key, id),
                        OrderState {
                            sale_rate: order_state.sale_rate,
                            // use current rewards factor
                            reward_factor: self.reward_factor.read(twamm_pool_key)
                        }
                    );

                self.reward_factor.read(twamm_pool_key) - order_state.reward_factor
            };

            let total_reward = (total_reward_factor * order_state.sale_rate) / 0x100000000;

            // transfer purchased token1 
            if (total_reward.is_non_zero()) {
                self.withdraw(twamm_pool_key.token1, caller, total_reward);
            }

            self.emit(OrderWithdrawn { id, order_key });
        }

        // TODO: figure out if we want to add a skip_ahead parameter
        fn execute_virtual_orders(ref self: ContractState, pool_key: PoolKey) {
            self.internal_execute_virtual_orders(pool_key);
        }
    }

    #[external(v0)]
    impl LockerImpl of ILocker<ContractState> {
        fn locked(ref self: ContractState, id: u32, data: Array<felt252>) -> Array<felt252> {
            let core = self.core.read();

            let result: LockCallbackResult =
                match consume_callback_data::<LockCallbackData>(core, data) {
                LockCallbackData::ExecuteVirtualSwapsCallbackData(data) => {
                    let (token0_key, token1_key) = (
                        TWAMMPoolKey {
                            token0: data.pool_key.token0,
                            token1: data.pool_key.token1,
                            fee: data.pool_key.fee
                        },
                        TWAMMPoolKey {
                            token0: data.pool_key.token1,
                            token1: data.pool_key.token0,
                            fee: data.pool_key.fee
                        }
                    );

                    // since virtual orders are executed at the same time for both tokens,
                    // last_virtual_order_time is the same for both tokens.
                    let shared_token_key = if (token0_key.token0 < token0_key.token1) {
                        token0_key
                    } else {
                        token1_key
                    };

                    let current_time = get_block_timestamp();

                    let mut last_virtual_order_time = self
                        .last_virtual_order_time
                        .read(shared_token_key);

                    let self_snap = @self;

                    // TODO: double check sale rates are 0? that should never happen.
                    if (last_virtual_order_time != 0 && last_virtual_order_time != current_time) {
                        let mut delta = Zeroable::<Delta>::zero();

                        loop {
                            // find next expiry time on the token0 bitmap
                            let token0_next_expiry_time = self_snap
                                .next_initialized_expiry(
                                    token0_key, last_virtual_order_time, current_time
                                );

                            // find next expiry time on the token1 bitmap
                            let token1_next_expiry_time = self_snap
                                .next_initialized_expiry(
                                    token1_key, last_virtual_order_time, current_time
                                );

                            let next_virtual_order_time = min(
                                min(token0_next_expiry_time, token1_next_expiry_time), current_time
                            );

                            let price = core.get_pool_price(data.pool_key);

                            if price.sqrt_ratio != 0 {
                                let virtual_order_time_window = (next_virtual_order_time
                                    - last_virtual_order_time)
                                    .into();
                                let token0_sale_rate = self.sale_rate.read(token0_key);
                                let token1_sale_rate = self.sale_rate.read(token1_key);
                                let token0_amount = (token0_sale_rate * virtual_order_time_window)
                                    / 0x100000000;
                                let token1_amount = (token1_sale_rate * virtual_order_time_window)
                                    / 0x100000000;

                                // TODO: Execute swap and accumulate all deltas.
                                // TODO: Zero out deltas, and update rewards factor at expiry.
                                // sqrt_ratio_limit should be set to max on the direction of the swap.
                                // skip_ahead should be 0
                                // add up delta += swap

                                if (token0_amount != 0
                                    && token1_amount != 0) {} else if (token0_amount > 0) {
                                        // swap token0 for token1
                                        delta += core
                                            .swap(
                                                data.pool_key,
                                                SwapParameters {
                                                    amount: i129 {
                                                        mag: token0_amount, sign: false
                                                    },
                                                    is_token1: false,
                                                    sqrt_ratio_limit: min_sqrt_ratio(),
                                                    skip_ahead: 0
                                                }
                                            );
                                    } else if (token1_amount > 0) {
                                        // swap token1 for token0
                                        delta += core
                                            .swap(
                                                data.pool_key,
                                                SwapParameters {
                                                    amount: i129 {
                                                        mag: token1_amount, sign: false
                                                    },
                                                    is_token1: true,
                                                    sqrt_ratio_limit: max_sqrt_ratio(),
                                                    skip_ahead: 0
                                                }
                                            );
                                    }

                                self
                                    .emit(
                                        // TODO: Add values from swaps
                                        VirtualOrdersExecuted {
                                            last_virtual_order_time,
                                            next_virtual_order_time,
                                            token0_sale_rate,
                                            token1_sale_rate
                                        }
                                    );

                                // update token0 sale rate with expiring rates 
                                if next_virtual_order_time == token0_next_expiry_time {
                                    self
                                        .sale_rate
                                        .write(
                                            token0_key,
                                            token0_sale_rate
                                                - self
                                                    .sale_rate_ending
                                                    .read((token0_key, next_virtual_order_time))
                                        );
                                }

                                // update token1 sale rate with expiring rates 
                                if next_virtual_order_time == token1_next_expiry_time {
                                    self
                                        .sale_rate
                                        .write(
                                            token1_key,
                                            token1_sale_rate
                                                - self
                                                    .sale_rate_ending
                                                    .read((token1_key, next_virtual_order_time))
                                        );
                                }
                            // TODO: update rewards factor.
                            }

                            // update last_virtual_order_time to next_virtual_order_time
                            last_virtual_order_time = next_virtual_order_time;

                            // virtual orders were executed up to current time
                            if next_virtual_order_time == current_time {
                                break;
                            }
                        };

                        // zero out deltas
                        if (delta.amount0.mag > 0) {
                            if (delta.amount0.sign) {
                                core
                                    .save(
                                        SavedBalanceKey {
                                            owner: get_contract_address(),
                                            token: token0_key.token0,
                                            salt: 0
                                        },
                                        delta.amount0.mag
                                    );
                            } else {
                                core.load(token0_key.token0, 0, delta.amount0.mag);
                            }
                        }
                        if (delta.amount1.mag > 0) {
                            if (delta.amount1.sign) {
                                core
                                    .save(
                                        SavedBalanceKey {
                                            owner: get_contract_address(),
                                            token: token0_key.token1,
                                            salt: 0
                                        },
                                        delta.amount1.mag
                                    );
                            } else {
                                core.load(token0_key.token1, 0, delta.amount1.mag);
                            }
                        }

                        self
                            .last_virtual_order_time
                            .write(shared_token_key, last_virtual_order_time);
                    } else if (last_virtual_order_time == 0) {
                        // we haven't executed any virtual orders yet, and no orders have been placed
                        self.last_virtual_order_time.write(shared_token_key, current_time);
                    }

                    LockCallbackResult::Empty
                },
                LockCallbackData::DepositBalanceCallbackData(data) => {
                    IERC20Dispatcher { contract_address: data.token }
                        .transfer(recipient: core.contract_address, amount: data.amount.into());

                    let deposited_amount = core.deposit(data.token);

                    assert(deposited_amount == data.amount, 'DEPOSIT_AMOUNT_NE_AMOUNT');

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


        // insert the initialized expiry time for the order
        fn insert_initialized_expiry(
            ref self: ContractState, twamm_pool_key: TWAMMPoolKey, expiry: u64
        ) {
            let (word_index, bit_index) = expiry_to_word_and_bit_index(expiry);
            let bitmap = self.expiry_time_bitmaps.read((twamm_pool_key, word_index));
            // it is assumed that bitmap does not contain the set bit exp2(bit_index) already
            self.expiry_time_bitmaps.write((twamm_pool_key, word_index), bitmap.set_bit(bit_index));
        }

        fn next_initialized_expiry(
            self: @ContractState, twamm_pool_key: TWAMMPoolKey, from: u64, max_time: u64
        ) -> u64 {
            let (word_index, bit_index) = expiry_to_word_and_bit_index(from + BIT_MAP_SPACING);

            let bitmap: Bitmap = self.expiry_time_bitmaps.read((twamm_pool_key, word_index));

            match bitmap.next_set_bit(bit_index) {
                Option::Some(next_bit) => { word_and_bit_index_to_expiry((word_index, next_bit)) },
                Option::None => {
                    let next = word_and_bit_index_to_expiry((word_index, 0));

                    if (next > max_time) {
                        max_time
                    } else {
                        self.next_initialized_expiry(twamm_pool_key, next, BIT_MAP_SPACING)
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

        // returns the amount of token0 that has not been sold
        fn get_order_remaining_amount(
            ref self: ContractState, order_key: OrderKey, order_state: OrderState
        ) -> u128 {
            let shared_token_key = if (order_key.token0 < order_key.token1) {
                to_token_key(order_key)
            } else {
                to_token_key(
                    OrderKey {
                        token0: order_key.token1,
                        token1: order_key.token0,
                        fee: order_key.fee,
                        expiry_time: order_key.expiry_time
                    }
                )
            };

            (order_state.sale_rate
                * (order_key.expiry_time - self.last_virtual_order_time.read(shared_token_key))
                    .into())
                / 0x100000000
        }
    }

    fn validate_expiry_time(order_time: u64, expiry_time: u64) {
        assert(expiry_time > order_time, 'INVALID_EXPIRY_TIME');

        // calculate the closest timestamp at which an order can expire
        // based on the step of the interval that the order expires in using
        // an approximation of
        // = 16**(floor(log_16(expiry_time-order_time)))
        // = 2**(4 * (floor(log_2(expiry_time-order_time)) / 4))
        let step = exp2(
            LOG_SCALE_FACTOR * (msb((expiry_time - order_time).into()) / LOG_SCALE_FACTOR)
        );
        assert(step >= BIT_MAP_SPACING.into(), 'INVALID_SPACING');
        assert(expiry_time.into() % step == 0, 'INVALID_EXPIRY_TIME');
    }

    fn to_token_key(order_key: OrderKey) -> TWAMMPoolKey {
        TWAMMPoolKey { token0: order_key.token0, token1: order_key.token1, fee: order_key.fee }
    }

    fn to_pool_key(order_key: OrderKey) -> PoolKey {
        let (token0, token1) = if (order_key.token0 < order_key.token1) {
            (order_key.token0, order_key.token1)
        } else {
            (order_key.token1, order_key.token0)
        };

        PoolKey {
            token0: token0,
            token1: token1,
            fee: order_key.fee,
            tick_spacing: MAX_TICK_SPACING,
            extension: get_contract_address()
        }
    }

    fn expiry_to_word_and_bit_index(expiry: u64) -> (u128, u8) {
        (
            (expiry / (BIT_MAP_SPACING * 251)).into(),
            250_u8 - downcast((expiry / BIT_MAP_SPACING) % 251).unwrap()
        )
    }

    fn word_and_bit_index_to_expiry(word_and_bit_index: (u128, u8)) -> u64 {
        let (word, bit) = word_and_bit_index;
        ((word * 251 * BIT_MAP_SPACING.into()) + (upcast(250 - bit) * BIT_MAP_SPACING.into()))
            .try_into()
            .unwrap()
    }

    fn calculate_virtual_order_outputs(
        sqrt_ratio: u256,
        liquidity: u128,
        token0_sale_ratio: u128,
        token1_sale_ratio: u128,
        token0_amount: u128,
        token1_amount: u128
    ) -> (u128, u128, u128) {
        // sell ratio
        let sell_ratio = (u256 { high: token1_sale_ratio, low: 0 } / token0_sale_ratio.into());
        // c
        let (c, sign) = c(sqrt_ratio, sell_ratio);

        // x_out
        // TODO: exponentiate it should be e^mult
        // let mult = ((2 / liquidity) * u128_sqrt(token0_amount * token1_amount).into());
        // let x_amm_start = liquidity / sqrt_ratio;
        // let x_amm_end = liquidity
        //     * u128_sqrt(token0_amount / token1_amount).into()
        //     * (mult + c / mult - c);
        // let x_out = (liquidity / sqrt_ratio) + token0_amount - x_amm_end;

        // // y_out
        // let y_amm_start = liquidity * sqrt_ratio;
        // let y_out = y_amm_start + token1_amount - ((token0_amount * y_amm_start) / x_amm_end);

        // // sqrt_ratio_next
        // let next_sqrt_ratio = (y_amm_start - y_out) / (x_amm_start - x_out);

        // (x_out, y_out, next_sqrt_ratio)
        (0, 0, 0)
    }

    fn c(sqrt_ratio: u256, sell_ratio: u256) -> (u256, bool) {
        let sqrt_sell_ratio: u256 = u256_sqrt(sell_ratio).into();

        let (num, sign) = if (sqrt_ratio > sqrt_sell_ratio) {
            (sqrt_ratio - sqrt_sell_ratio, true)
        } else {
            (sqrt_sell_ratio - sqrt_ratio, false)
        };

        (num / (sqrt_sell_ratio + sqrt_ratio), sign)
    }
}
