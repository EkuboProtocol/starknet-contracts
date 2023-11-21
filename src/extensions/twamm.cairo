use ekubo::types::i129::{i129, i129Trait};
use ekubo::types::keys::{PoolKey};
use integer::{u256_safe_divmod, u256_as_non_zero};
use starknet::{ContractAddress, StorePacking};
use traits::{Into, TryInto};

#[derive(Drop, Copy, Serde, Hash)]
struct OrderKey {
    token0: ContractAddress,
    token1: ContractAddress,
    expiry_time: u64,
}

// State of a particular order, defined by the key
#[derive(Drop, Copy, Serde, PartialEq, starknet::Store)]
struct OrderState {
    // the timestamp at which the order expires
    expiry_time: u64,
    // the rate at which the order is selling token0 for token1
    sale_rate: u128,
    // reward factor for token0
    reward_factor: u128,
}

#[derive(Drop, Copy, Serde, Hash)]
struct TokenKey {
    token0: ContractAddress,
    token1: ContractAddress,
}

#[starknet::interface]
trait ITWAMM<TContractState> {
    // Return the NFT contract address that this contract uses to represent limit orders
    fn get_nft_address(self: @TContractState) -> ContractAddress;

    // Return the stored order state
    fn get_order_state(self: @TContractState, order_key: OrderKey, id: u64) -> OrderState;

    // Returns the current sale rate for a token key
    fn get_sale_rate(self: @TContractState, token_key: TokenKey,) -> u128;

    // Creates a new twamm order
    fn place_order(ref self: TContractState, order_key: OrderKey, amount: u128) -> u64;

    // Cancels a twamm order
    fn cancel_order(ref self: TContractState, order_key: OrderKey, id: u64);

    // Withdraws proceeds from a twamm order
    fn withdraw_from_order(ref self: TContractState, order_key: OrderKey, id: u64);
}

#[starknet::contract]
mod TWAMM {
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
    use ekubo::math::bits::{msb};
    use ekubo::math::contract_address::{ContractAddressOrder};
    use ekubo::math::delta::{amount0_delta, amount1_delta};
    use ekubo::math::exp2::{exp2};
    use ekubo::math::ticks::constants::{MAX_TICK_SPACING, TICKS_IN_ONE_PERCENT};
    use ekubo::math::ticks::{constants as tick_constants, min_tick, max_tick};
    use ekubo::math::liquidity::{liquidity_delta_to_amount_delta};
    use ekubo::math::max_liquidity::{max_liquidity_for_token0, max_liquidity_for_token1};
    use ekubo::math::ticks::{tick_to_sqrt_ratio};
    use ekubo::shared_locker::{call_core_with_callback, consume_callback_data};
    use ekubo::types::bounds::{Bounds, max_bounds};
    use ekubo::types::call_points::{CallPoints};
    use ekubo::types::keys::{PoolKey, PositionKey};
    use option::{OptionTrait};
    use starknet::{
        get_contract_address, get_caller_address, replace_class_syscall, ClassHash,
        get_block_timestamp,
    };
    use super::{ITWAMM, i129, i129Trait, ContractAddress, OrderKey, OrderState, TokenKey};
    use traits::{TryInto, Into};
    use zeroable::{Zeroable};
    use ekubo::upgradeable::{Upgradeable as upgradeable_component};
    use ekubo::clear::{ClearImpl};

    component!(path: upgradeable_component, storage: upgradeable, event: ClassHashReplaced);

    #[abi(embed_v0)]
    impl Upgradeable = upgradeable_component::UpgradeableImpl<ContractState>;
    impl Clear = ClearImpl<ContractState>;

    #[storage]
    struct Storage {
        core: ICoreDispatcher,
        nft: IEnumerableOwnedNFTDispatcher,
        orders: LegacyMap<(OrderKey, u64), OrderState>,
        // interval between timestamps where orders can expire
        order_time_interval: u64,
        // current rate at which token0 is being sold for token1
        sale_rate: LegacyMap<TokenKey, u128>,
        // cumulative sale rate for token0 ending at a particular timestamp
        sale_rate_ending: LegacyMap<(TokenKey, u64), u128>,
        // current reward factor for token key
        reward_factor: LegacyMap<TokenKey, u128>,
        // reward factor for token key at a particular timestamp
        reward_factor_at_time: LegacyMap<(TokenKey, u64), u128>,
        // last timestamp at which virtual order was executed
        last_virtual_order_time: LegacyMap<TokenKey, u64>,
        // upgradable component storage (empty)
        #[substorage(v0)]
        upgradeable: upgradeable_component::Storage
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        core: ICoreDispatcher,
        nft_class_hash: ClassHash,
        token_uri_base: felt252,
        order_time_interval: u64
    ) {
        self.core.write(core);

        self
            .nft
            .write(
                EnumerableOwnedNFT::deploy(
                    nft_class_hash: nft_class_hash,
                    controller: get_contract_address(),
                    name: 'Ekubo TWAMM',
                    symbol: 'eTWAMM',
                    token_uri_base: token_uri_base,
                    salt: 0
                )
            );

        self.order_time_interval.write(order_time_interval);
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
    #[event]
    enum Event {
        #[flat]
        ClassHashReplaced: upgradeable_component::Event,
        OrderPlaced: OrderPlaced,
        OrderCancelled: OrderCancelled,
        OrderWithdrawn: OrderWithdrawn,
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
            let token_key = if params.is_token1 {
                TokenKey { token0: pool_key.token1, token1: pool_key.token0 }
            } else {
                TokenKey { token0: pool_key.token0, token1: pool_key.token1 }
            };

            self.execute_virtual_trades(token_key);
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

        fn get_sale_rate(self: @ContractState, token_key: TokenKey) -> u128 {
            self.sale_rate.read(token_key)
        }

        fn place_order(ref self: ContractState, order_key: OrderKey, amount: u128) -> u64 {
            let token_key = to_token_key(order_key);
            self.execute_virtual_trades(token_key);

            let id = self.nft.read().mint(get_caller_address());

            let expiry_time = self.validate_expiry_time(order_key.expiry_time);

            // calculate and store order sale rate
            let sale_rate = self.scale_up(amount) / (expiry_time - get_block_timestamp()).into();

            self
                .orders
                .write(
                    (order_key, id),
                    OrderState {
                        expiry_time: expiry_time,
                        sale_rate: sale_rate,
                        reward_factor: self.reward_factor.read(token_key)
                    }
                );

            // update global sale rate
            let global_sale_rate = self.sale_rate.read(token_key) + sale_rate;
            self.sale_rate.write(token_key, global_sale_rate);

            // update sale rate ending at expiry time
            let sale_rate_ending = self.sale_rate_ending.read((token_key, expiry_time)) + sale_rate;
            self.sale_rate_ending.write((token_key, expiry_time), sale_rate_ending);

            self
                .emit(
                    OrderPlaced {
                        id,
                        order_key,
                        amount,
                        expiry_time,
                        sale_rate,
                        global_sale_rate,
                        sale_rate_ending
                    }
                );

            self.deposit(token_key.token0, amount);

            id
        }

        fn cancel_order(ref self: ContractState, order_key: OrderKey, id: u64) {
            let caller = get_caller_address();
            self.validate_caller(id, caller);

            let token_key = to_token_key(order_key);
            self.execute_virtual_trades(token_key);

            let order_state = self.orders.read((order_key, id));
            let current_time = get_block_timestamp();

            // validate that the order has not expired
            assert(order_state.expiry_time > current_time, 'ORDER_EXPIRED');

            // calculate token0 amount that was not sold
            let remaining_amount = self.get_order_remaining_amount(token_key, order_state);

            // calculate token1 amount that was purchased
            let purchased_amount = self
                .scale_down(
                    (self.reward_factor.read(token_key) - order_state.reward_factor)
                        * order_state.sale_rate
                );

            // update global rates
            let sale_rate = self.sale_rate.read(token_key) - order_state.sale_rate;
            self.sale_rate.write(token_key, sale_rate);
            self
                .sale_rate_ending
                .write(
                    (token_key, order_state.expiry_time),
                    self.sale_rate_ending.read((token_key, order_state.expiry_time))
                        - order_state.sale_rate
                );

            // update order state to reflect that the order has been cancelled
            self
                .orders
                .write(
                    (order_key, id), OrderState { expiry_time: 0, sale_rate: 0, reward_factor: 0 }
                );
            // burn the NFT
            self.nft.read().burn(id);

            // transfer remaining token0
            if (remaining_amount.is_non_zero()) {
                self.withdraw(token_key.token0, caller, remaining_amount);
            }

            // transfer purchased token1 
            if (purchased_amount.is_non_zero()) {
                self.withdraw(token_key.token1, caller, purchased_amount)
            }

            self.emit(OrderCancelled { id, order_key });
        }

        fn withdraw_from_order(ref self: ContractState, order_key: OrderKey, id: u64) {
            let caller = get_caller_address();
            self.validate_caller(id, caller);

            let token_key = TokenKey { token0: order_key.token0, token1: order_key.token1 };
            self.execute_virtual_trades(token_key);

            let order_state = self.orders.read((order_key, id));

            assert(order_state.sale_rate > 0, 'ZERO_SALE_RATE');

            let current_time = get_block_timestamp();

            let total_reward_factor = if current_time > order_state.expiry_time {
                // TODO: Should we burn the NFT? Probably not.
                // order has been fully executed
                // update order state to reflect that the order has been fully executed
                self
                    .orders
                    .write(
                        (order_key, id),
                        OrderState { expiry_time: 0, sale_rate: 0, reward_factor: 0 }
                    );

                // reward factor at expiration/full-execution time
                self.reward_factor_at_time.read((token_key, order_state.expiry_time))
                    - order_state.reward_factor
            } else {
                // update order state to reflect that the order has been partially executed
                self
                    .orders
                    .write(
                        (order_key, id),
                        OrderState {
                            expiry_time: order_state.expiry_time,
                            sale_rate: order_state.sale_rate,
                            reward_factor: self.reward_factor.read(token_key)
                        }
                    );

                self.reward_factor.read(token_key) - order_state.reward_factor
            };

            let total_reward = self.scale_down(total_reward_factor * order_state.sale_rate);

            // transfer purchased token1 
            if (total_reward.is_non_zero()) {
                self.withdraw(token_key.token1, caller, total_reward);
            }

            self.emit(OrderWithdrawn { id, order_key });
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
                        TokenKey { token0: data.pool_key.token0, token1: data.pool_key.token1 },
                        TokenKey { token0: data.pool_key.token1, token1: data.pool_key.token0 }
                    );

                    // since trades are executed at the same time for both tokens,
                    // last_virtual_order_time is the same for both tokens.
                    let shared_token_key = self
                        .get_sorted_token_key(data.pool_key.token0, data.pool_key.token1);

                    let current_time = get_block_timestamp();
                    let order_time_interval = self.order_time_interval.read();

                    // if no trades have been executed, round down to closest trade execution time.
                    // since placing orders executes trades before placing them, there won't be
                    // any orders place before the first virtual trade.
                    let mut last_virtual_order_time = if self
                        .last_virtual_order_time
                        .read(shared_token_key) == 0 {
                        current_time - (current_time % order_time_interval)
                    } else {
                        self.last_virtual_order_time.read(shared_token_key)
                    };

                    let mut next_expiry_time = last_virtual_order_time
                        - (last_virtual_order_time % order_time_interval)
                        + order_time_interval;

                    let mut price = core.get_pool_price(data.pool_key);
                    let mut delta = Default::<Delta>::default();

                    loop {
                        if next_expiry_time > current_time {
                            break;
                        }

                        if price.sqrt_ratio != 0 {
                            // TODO: Execute swap and accumulate all deltas.
                            // sqrt_ratio_limit should be set to max on the direction of the trade.
                            // skip_ahead should be 0
                            // add up delta += swap
                            let time_passed = (next_expiry_time - last_virtual_order_time).into();
                            let token0_amount = self.sale_rate.read(token0_key) * time_passed;
                            let token1_amount = self.sale_rate.read(token1_key) * time_passed;

                            // TODO: Zero out deltas, and update rewards factor.

                            // TODO: Expire orders and update rates
                            if (token0_amount != 0
                                && token1_amount != 0) {} else if (token0_amount > 0) {} else if (token1_amount > 0) {}
                        }

                        // last timestamp at which virtual trades were executed
                        last_virtual_order_time = next_expiry_time;

                        // update price
                        price = core.get_pool_price(data.pool_key);

                        // update next expiry time
                        next_expiry_time += order_time_interval;
                    };

                    self.last_virtual_order_time.write(shared_token_key, last_virtual_order_time);

                    LockCallbackResult::Empty
                },
                LockCallbackData::DepositBalanceCallbackData(data) => {
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

    fn to_token_key(order_key: OrderKey) -> TokenKey {
        TokenKey { token0: order_key.token0, token1: order_key.token1 }
    }

    #[generate_trait]
    impl Internal of InternalTrait {
        fn validate_caller(self: @ContractState, id: u64, caller: ContractAddress) {
            assert(self.nft.read().is_account_authorized(id, caller), 'UNAUTHORIZED');
        }

        fn validate_expiry_time(self: @ContractState, expiry_time: u64) -> u64 {
            let current_time = get_block_timestamp();

            assert(expiry_time > current_time, 'INVALID_EXPIRY_TIME');

            // calculate the closest timestamp at which an order can expire
            // based on the step of the interval that the order expires in using
            // an approximation of
            // = 16**(floor(log_16(expiry_time-current_time)))
            // = 2**(4 * (floor(log_2(expiry_time-current_time)) / 4))
            let step = exp2(4 * (msb((expiry_time - current_time).into()) / 4));

            let rem = expiry_time % step.try_into().unwrap();
            if (rem == 0) {
                expiry_time
            } else {
                expiry_time - rem
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

        fn execute_virtual_trades(ref self: ContractState, token_key: TokenKey) {
            // TODO: Figure out how to properly get pool key
            let pool_key = PoolKey {
                token0: token_key.token0,
                token1: token_key.token1,
                tick_spacing: MAX_TICK_SPACING,
                fee: 0,
                extension: get_contract_address()
            };

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
            ref self: ContractState, token_key: TokenKey, order_state: OrderState
        ) -> u128 {
            let shared_token_key = self.get_sorted_token_key(token_key.token0, token_key.token1);

            self
                .scale_down(
                    order_state.sale_rate
                        * (order_state.expiry_time
                            - self.last_virtual_order_time.read(shared_token_key))
                            .into()
                )
        }

        fn get_sorted_token_key(
            self: @ContractState, token0: ContractAddress, token1: ContractAddress
        ) -> TokenKey {
            if (token0 < token1) {
                TokenKey { token0, token1 }
            } else {
                TokenKey { token0: token1, token1: token0 }
            }
        }

        fn scale_up(ref self: ContractState, amount: u128) -> u128 {
            // scale up by 2**32
            let scaled_amount = amount * 0x100000000;
            // TODO: Include allowable precision loss?
            // assert(scaled_amount / 0x100000000 == amount, 'SCALE_UP_OVERFLOW');
            scaled_amount
        }

        fn scale_down(ref self: ContractState, amount: u128) -> u128 {
            // scale down by 2**32
            let scaled_amount = amount / 0x100000000;
            // TODO: Include allowable precision loss?
            // assert(scaled_amount * 0x100000000 == amount, 'SCALE_DOWN_OVERFLOW');
            scaled_amount
        }
    }
}
