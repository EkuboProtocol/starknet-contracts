use ekubo::types::i129::{i129, i129Trait};
use ekubo::types::keys::{PoolKey};
use integer::{u256_safe_divmod, u256_as_non_zero};
use starknet::{ContractAddress, StorePacking};
use traits::{Into, TryInto};

#[derive(Drop, Copy, Serde, Hash)]
struct OrderKey {
    token0: ContractAddress,
    token1: ContractAddress,
    time_intervals: u64,
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
    use ekubo::math::delta::{amount0_delta, amount1_delta};
    use ekubo::math::ticks::constants::{MAX_TICK_SPACING};
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

    component!(path: upgradeable_component, storage: upgradeable, event: ClassHashReplaced);

    #[abi(embed_v0)]
    impl Upgradeable = upgradeable_component::UpgradeableImpl<ContractState>;

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
        // reward factor for token0
        reward_factor: LegacyMap<TokenKey, u128>,
        // token reserves for a token key
        reserves: LegacyMap<TokenKey, u256>,
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
    #[event]
    enum Event {
        #[flat]
        ClassHashReplaced: upgradeable_component::Event,
        OrderPlaced: OrderPlaced,
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
            self.execute_virtual_trades();
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
            self.execute_virtual_trades();

            let id = self.nft.read().mint(get_caller_address());

            // calculate and store order expiry time and sale rate
            let current_time = get_block_timestamp();
            let last_expiry_time = current_time - (current_time % self.order_time_interval.read());
            let expiry_time = last_expiry_time
                + (self.order_time_interval.read() * (order_key.time_intervals + 1));

            let sale_rate = amount / (expiry_time - current_time).into();

            let token_key = to_token_key(order_key);

            self
                .orders
                .write(
                    (order_key, id),
                    OrderState {
                        expiry_time: expiry_time,
                        sale_rate,
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

            // TODO: Update rewards factor.
            self.deposit(token_key, id, amount);

            id
        }

        fn cancel_order(ref self: ContractState, order_key: OrderKey, id: u64) {
            // TODO: Implement
            self.execute_virtual_trades();
        }

        fn withdraw_from_order(ref self: ContractState, order_key: OrderKey, id: u64) {
            // TODO: Implement
            self.execute_virtual_trades();
        }
    }

    fn to_token_key(order_key: OrderKey) -> TokenKey {
        TokenKey { token0: order_key.token0, token1: order_key.token1, }
    }

    #[generate_trait]
    impl Internal of InternalTrait {
        fn deposit(ref self: ContractState, token_key: TokenKey, id: u64, amount: u128) {
            let balance = IERC20Dispatcher { contract_address: token_key.token0 }
                .balanceOf(get_contract_address());

            let reserves = self.reserves.read(token_key);

            assert(balance >= reserves, 'BALANCE_LT_RESERVE');

            let delta = balance - reserves;

            // the delta is limited to u128
            assert(delta.high == 0, 'DELTA_EXCEEDED_MAX');

            // the delta must equal the deposit amount
            assert(delta.low == amount, 'DELTA_LT_AMOUNT');

            // update reserves
            self.reserves.write(token_key, reserves + delta);
        }

        fn execute_virtual_trades(
            ref self: ContractState
        ) { // TODO: execute virtual trades, and update rates based on expirying orders
        // swap tokens on core based on current rates
        }
    }

    // TODO: Move to an embeddable impl
    fn clear(ref self: ContractState, token: ContractAddress) -> u256 {
        let dispatcher = IERC20Dispatcher { contract_address: token };
        let balance = dispatcher.balanceOf(get_contract_address());
        if (balance.is_non_zero()) {
            dispatcher.transfer(get_caller_address(), balance);
        }
        balance
    }
}
