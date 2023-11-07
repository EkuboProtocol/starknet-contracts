use ekubo::types::i129::{i129, i129Trait};
use integer::{u256_safe_divmod, u256_as_non_zero};
use starknet::{ContractAddress, StorePacking};
use traits::{Into, TryInto};

#[derive(Drop, Copy, Serde, Hash)]
struct OrderKey {
    token0: ContractAddress,
    token1: ContractAddress,
    time_intervals: u128,
}

// State of a particular order, defined by the key
#[derive(Drop, Copy, Serde, PartialEq, starknet::Store)]
struct OrderState {
    // the timestamp at which the order expires
    expiration_timestamp: u64,
    // the rate at which the order is selling token0 for token1
    sale_rate: u128,
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
trait ITWAMM<TContractState> {
    // Return the NFT contract address that this contract uses to represent limit orders
    fn get_nft_address(self: @TContractState) -> ContractAddress;

    // Returns the stored order state
    fn get_order_state(self: @TContractState, order_key: OrderKey, id: u64) -> OrderState;

    // Creates a new twamm order
    fn place_order(ref self: TContractState, order_key: OrderKey, amount: u128) -> u64;
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
        get_block_timestamp
    };
    use super::{
        ITWAMM, i129, i129Trait, ContractAddress, OrderKey, OrderState, GetOrderInfoRequest,
        GetOrderInfoResult
    };
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
    #[event]
    enum Event {
        #[flat]
        ClassHashReplaced: upgradeable_component::Event,
    }

    #[external(v0)]
    impl ExtensionImpl of IExtension<ContractState> {
        fn before_initialize_pool(
            ref self: ContractState, caller: ContractAddress, pool_key: PoolKey, initial_tick: i129
        ) -> CallPoints {
            assert(pool_key.tick_spacing == MAX_TICK_SPACING, 'TICK_SPACING');

            // TODO: update to correct call points
            CallPoints {
                after_initialize_pool: false,
                before_swap: false,
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
            assert(false, 'NOT_USED');
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
    impl LockerImpl of ILocker<ContractState> {
        fn locked(ref self: ContractState, id: u32, data: Array<felt252>) -> Array<felt252> {
            let core = self.core.read();

            // let result: LockCallbackResult =
            //     match consume_callback_data::<LockCallbackData>(core, data) {
            //     LockCallbackData::PlaceOrderCallbackData(place_order) => {
            //         LockCallbackResult::Empty
            //     },
            //     LockCallbackData::HandleAfterSwapCallbackData(after_swap) => {
            //         LockCallbackResult::Empty
            //     },
            //     LockCallbackData::WithdrawExecutedOrderBalance(withdraw) => {
            //         LockCallbackResult::Empty
            //     },
            //     LockCallbackData::WithdrawUnexecutedOrderBalance(withdraw) => {
            //         LockCallbackResult::Empty
            //     }
            // };

            let mut result_data = ArrayTrait::new();
            // Serde::serialize(@result, ref result_data);
            result_data
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

        fn place_order(ref self: ContractState, order_key: OrderKey, amount: u128) -> u64 {
            let id = self.nft.read().mint(get_caller_address());

            // TODO: Calculate expiration block, rate, and update global rate.

            // self.emit(OrderPlaced { id, order_key, amount, liquidity });

            id
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
