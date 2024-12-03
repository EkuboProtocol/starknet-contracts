#[starknet::contract]
pub mod Core {
    use core::array::{ArrayTrait};
    use core::num::traits::{Zero};
    use core::option::{Option};
    use core::traits::{Into};
    use ekubo::components::owned::{Owned as owned_component};
    use ekubo::components::upgradeable::{IHasInterface, Upgradeable as upgradeable_component};
    use ekubo::interfaces::core::{
        GetPositionWithFeesResult, ICore, IExtensionDispatcher, IExtensionDispatcherTrait,
        IForwardeeDispatcher, IForwardeeDispatcherTrait, ILockerDispatcher, ILockerDispatcherTrait,
        LockerState, SwapParameters, UpdatePositionParameters,
    };
    use ekubo::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use ekubo::math::bitmap::{
        Bitmap, BitmapTrait, tick_to_word_and_bit_index, word_and_bit_index_to_tick,
    };
    use ekubo::math::fee::{accumulate_fee_amount, compute_fee};
    use ekubo::math::liquidity::liquidity_delta_to_amount_delta;
    use ekubo::math::swap::{is_price_increasing, swap_result};
    use ekubo::math::ticks::{
        max_sqrt_ratio, max_tick, min_sqrt_ratio, min_tick, sqrt_ratio_to_tick, tick_to_sqrt_ratio,
    };
    use ekubo::types::bounds::{Bounds, BoundsTrait};
    use ekubo::types::call_points::{CallPoints};
    use ekubo::types::delta::{Delta};
    use ekubo::types::fees_per_liquidity::{
        FeesPerLiquidity, fees_per_liquidity_from_amount0, fees_per_liquidity_from_amount1,
        fees_per_liquidity_new,
    };
    use ekubo::types::i129::{AddDeltaTrait, i129, i129Trait};
    use ekubo::types::keys::{PoolKey, PoolKeyTrait, PositionKey, SavedBalanceKey};
    use ekubo::types::pool_price::{PoolPrice};
    use ekubo::types::position::{Position, PositionTrait};
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::storage::{StoragePath, StoragePathEntry};
    use starknet::{
        ContractAddress, Store, get_caller_address, get_contract_address,
        storage_access::{storage_base_address_from_felt252},
    };

    component!(path: owned_component, storage: owned, event: OwnedEvent);
    #[abi(embed_v0)]
    impl Owned = owned_component::OwnedImpl<ContractState>;
    impl Ownable = owned_component::OwnableImpl<ContractState>;

    component!(path: upgradeable_component, storage: upgradeable, event: UpgradeableEvent);
    #[abi(embed_v0)]
    impl Upgradeable = upgradeable_component::UpgradeableImpl<ContractState>;

    #[storage]
    pub struct Storage {
        // withdrawal fees collected, controlled by the owner
        pub protocol_fees_collected: Map<ContractAddress, u128>,
        // transient state of the lockers, which always starts and ends at zero
        pub lock_count: u32,
        pub locker_token_deltas: Map<(u32, ContractAddress), i129>,
        // the rest of transient state is accessed directly using Store::read and Store::write to
        // save on hashes

        // the persistent state of all the pools is stored in these structs
        pub pool_price: Map<PoolKey, PoolPrice>,
        pub pool_liquidity: Map<PoolKey, u128>,
        pub pool_fees: Map<PoolKey, FeesPerLiquidity>,
        pub tick_liquidity_net: Map<PoolKey, Map<i129, u128>>,
        pub tick_liquidity_delta: Map<PoolKey, Map<i129, i129>>,
        pub tick_fees_outside: Map<PoolKey, Map<i129, FeesPerLiquidity>>,
        pub positions: Map<(PoolKey, PositionKey), Position>,
        pub tick_bitmaps: Map<PoolKey, Map<u128, Bitmap>>,
        // users may save balances in the singleton to avoid transfers, keyed by (owner, token,
        // cache_key)
        pub saved_balances: Map<SavedBalanceKey, u128>,
        // extensions must be registered before they are used in a pool key
        pub extension_call_points: Map<ContractAddress, CallPoints>,
        #[substorage(v0)]
        upgradeable: upgradeable_component::Storage,
        #[substorage(v0)]
        owned: owned_component::Storage,
    }

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress) {
        self.initialize_owned(owner);
    }

    #[derive(starknet::Event, Drop)]
    pub struct ProtocolFeesWithdrawn {
        pub recipient: ContractAddress,
        pub token: ContractAddress,
        pub amount: u128,
    }

    #[derive(starknet::Event, Drop)]
    pub struct ProtocolFeesPaid {
        pub pool_key: PoolKey,
        pub position_key: PositionKey,
        pub delta: Delta,
    }

    #[derive(starknet::Event, Drop)]
    pub struct PoolInitialized {
        pub pool_key: PoolKey,
        pub initial_tick: i129,
        pub sqrt_ratio: u256,
    }

    #[derive(starknet::Event, Drop)]
    pub struct PositionUpdated {
        pub locker: ContractAddress,
        pub pool_key: PoolKey,
        pub params: UpdatePositionParameters,
        pub delta: Delta,
    }

    #[derive(starknet::Event, Drop)]
    pub struct PositionFeesCollected {
        pub pool_key: PoolKey,
        pub position_key: PositionKey,
        pub delta: Delta,
    }

    #[derive(starknet::Event, Drop)]
    pub struct Swapped {
        pub locker: ContractAddress,
        pub pool_key: PoolKey,
        pub params: SwapParameters,
        pub delta: Delta,
        pub sqrt_ratio_after: u256,
        pub tick_after: i129,
        pub liquidity_after: u128,
    }

    #[derive(starknet::Event, Drop)]
    pub struct FeesAccumulated {
        pub pool_key: PoolKey,
        pub amount0: u128,
        pub amount1: u128,
    }

    #[derive(starknet::Event, Drop)]
    pub struct SavedBalance {
        pub key: SavedBalanceKey,
        pub amount: u128,
    }

    #[derive(starknet::Event, Drop)]
    pub struct LoadedBalance {
        pub key: SavedBalanceKey,
        pub amount: u128,
    }

    #[derive(starknet::Event, Drop)]
    #[event]
    enum Event {
        #[flat]
        UpgradeableEvent: upgradeable_component::Event,
        OwnedEvent: owned_component::Event,
        ProtocolFeesPaid: ProtocolFeesPaid,
        ProtocolFeesWithdrawn: ProtocolFeesWithdrawn,
        PoolInitialized: PoolInitialized,
        PositionUpdated: PositionUpdated,
        PositionFeesCollected: PositionFeesCollected,
        Swapped: Swapped,
        SavedBalance: SavedBalance,
        LoadedBalance: LoadedBalance,
        FeesAccumulated: FeesAccumulated,
    }

    #[generate_trait]
    impl Internal of InternalTrait {
        fn get_current_locker_id(self: @ContractState) -> u32 {
            let lock_count = self.lock_count.read();
            assert(lock_count > 0, 'NOT_LOCKED');
            lock_count - 1
        }

        fn get_locker_address(self: @ContractState, id: u32) -> ContractAddress {
            Store::read(0, storage_base_address_from_felt252(id.into()))
                .expect('FAILED_READ_LOCKER_ADDRESS')
        }

        fn set_locker_address(self: @ContractState, id: u32, address: ContractAddress) {
            Store::write(0, storage_base_address_from_felt252(id.into()), address)
                .expect('FAILED_WRITE_LOCKER_ADDRESS');
        }

        fn get_nonzero_delta_count(self: @ContractState, id: u32) -> u32 {
            Store::read(0, storage_base_address_from_felt252(0x100000000 + id.into()))
                .expect('FAILED_READ_NZD_COUNT')
        }

        fn crement_storage_delta_count(self: @ContractState, id: u32, decrease: bool) {
            let delta_count_storage_location = storage_base_address_from_felt252(
                0x100000000 + id.into(),
            );

            let count = Store::read(0, delta_count_storage_location)
                .expect('FAILED_READ_NZD_COUNT');

            Store::write(
                0, delta_count_storage_location, if decrease {
                    count - 1
                } else {
                    count + 1
                },
            )
                .expect('FAILED_WRITE_NZD_COUNT');
        }

        fn get_locker(self: @ContractState) -> (u32, ContractAddress) {
            let id = self.get_current_locker_id();
            let locker = self.get_locker_address(id);
            (id, locker)
        }

        fn require_locker(self: @ContractState) -> (u32, ContractAddress) {
            let (id, locker) = self.get_locker();
            assert(locker == get_caller_address(), 'NOT_LOCKER');
            (id, locker)
        }

        fn account_delta(
            ref self: ContractState, id: u32, token_address: ContractAddress, delta: i129,
        ) {
            let delta_storage_location = self.locker_token_deltas.entry((id, token_address));
            let current = delta_storage_location.read();
            let next = current + delta;
            delta_storage_location.write(next);

            let next_is_zero = next.is_zero();

            if (current.is_zero() != next_is_zero) {
                self.crement_storage_delta_count(id, next_is_zero);
            }
        }

        fn account_pool_delta(ref self: ContractState, id: u32, pool_key: PoolKey, delta: Delta) {
            self.account_delta(id, pool_key.token0, delta.amount0);
            self.account_delta(id, pool_key.token1, delta.amount1);
        }

        // Remove the initialized tick for the given pool
        fn remove_initialized_tick(ref self: ContractState, pool_key: PoolKey, index: i129) {
            let (word_index, bit_index) = tick_to_word_and_bit_index(index, pool_key.tick_spacing);
            let bitmap_entry = self.tick_bitmaps.entry(pool_key).entry(word_index);
            let bitmap = bitmap_entry.read();
            // it is assumed that bitmap already contains the set bit exp2(bit_index)
            bitmap_entry.write(bitmap.unset_bit(bit_index));
        }

        // Insert an initialized tick for the given pool
        fn insert_initialized_tick(ref self: ContractState, pool_key: PoolKey, index: i129) {
            let (word_index, bit_index) = tick_to_word_and_bit_index(index, pool_key.tick_spacing);
            let bitmap_entry = self.tick_bitmaps.entry(pool_key).entry(word_index);
            let bitmap = bitmap_entry.read();
            // it is assumed that bitmap does not contain the set bit exp2(bit_index) already
            bitmap_entry.write(bitmap.set_bit(bit_index));
        }

        fn update_tick(
            ref self: ContractState,
            pool_key: PoolKey,
            index: i129,
            liquidity_delta: i129,
            is_upper: bool,
        ) {
            let liquidity_delta_current = self
                .tick_liquidity_delta
                .entry(pool_key)
                .entry(index)
                .read();

            let liquidity_net_current = self.tick_liquidity_net.entry(pool_key).entry(index).read();
            let next_liquidity_net = liquidity_net_current.add(liquidity_delta);

            self
                .tick_liquidity_delta
                .entry(pool_key)
                .write(
                    index,
                    if is_upper {
                        liquidity_delta_current - liquidity_delta
                    } else {
                        liquidity_delta_current + liquidity_delta
                    },
                );

            self.tick_liquidity_net.entry(pool_key).write(index, next_liquidity_net);

            if ((next_liquidity_net == 0) != (liquidity_net_current == 0)) {
                if (next_liquidity_net == 0) {
                    self.remove_initialized_tick(pool_key, index);
                } else {
                    self.insert_initialized_tick(pool_key, index);
                }
            };
        }


        fn prefix_next_initialized_tick(
            self: @ContractState,
            prefix: StoragePath<Map<u128, Bitmap>>,
            tick_spacing: u128,
            from: i129,
            skip_ahead: u128,
        ) -> (i129, bool) {
            assert(from < max_tick(), 'NEXT_FROM_MAX');

            let (word_index, bit_index) = tick_to_word_and_bit_index(
                from + i129 { mag: tick_spacing, sign: false }, tick_spacing,
            );

            let bitmap = prefix.read(word_index);

            match bitmap.next_set_bit(bit_index) {
                Option::Some(next_bit) => {
                    (word_and_bit_index_to_tick((word_index, next_bit), tick_spacing), true)
                },
                Option::None => {
                    let next = word_and_bit_index_to_tick((word_index, 0), tick_spacing);
                    if (next > max_tick()) {
                        return (max_tick(), false);
                    }
                    if (skip_ahead.is_zero()) {
                        (next, false)
                    } else {
                        self
                            .prefix_next_initialized_tick(
                                prefix, tick_spacing, next, skip_ahead - 1,
                            )
                    }
                },
            }
        }

        fn prefix_prev_initialized_tick(
            self: @ContractState,
            prefix: StoragePath<Map<u128, Bitmap>>,
            tick_spacing: u128,
            from: i129,
            skip_ahead: u128,
        ) -> (i129, bool) {
            assert(from >= min_tick(), 'PREV_FROM_MIN');
            let (word_index, bit_index) = tick_to_word_and_bit_index(from, tick_spacing);

            let bitmap = prefix.read(word_index);

            match bitmap.prev_set_bit(bit_index) {
                Option::Some(prev_bit_index) => {
                    (word_and_bit_index_to_tick((word_index, prev_bit_index), tick_spacing), true)
                },
                Option::None => {
                    // if it's not set, we know there is no set bit in this word
                    let prev = word_and_bit_index_to_tick((word_index, 250), tick_spacing);
                    if (prev < min_tick()) {
                        return (min_tick(), false);
                    }
                    if (skip_ahead == 0) {
                        (prev, false)
                    } else {
                        self
                            .prefix_prev_initialized_tick(
                                prefix,
                                tick_spacing,
                                prev - i129 { mag: 1, sign: false },
                                skip_ahead - 1,
                            )
                    }
                },
            }
        }

        fn get_call_points_for_caller(
            self: @ContractState, pool_key: PoolKey, caller: ContractAddress,
        ) -> CallPoints {
            if pool_key.extension.is_non_zero() {
                if (pool_key.extension != caller) {
                    self.extension_call_points.read(pool_key.extension)
                } else {
                    Default::default()
                }
            } else {
                Default::default()
            }
        }
    }

    #[abi(embed_v0)]
    impl CoreHasInterface of IHasInterface<ContractState> {
        fn get_primary_interface_id(self: @ContractState) -> felt252 {
            return selector!("ekubo::core::Core");
        }
    }

    #[abi(embed_v0)]
    impl Core of ICore<ContractState> {
        fn get_protocol_fees_collected(self: @ContractState, token: ContractAddress) -> u128 {
            self.protocol_fees_collected.read(token)
        }

        fn get_locker_state(self: @ContractState, id: u32) -> LockerState {
            let address = self.get_locker_address(id);
            let nonzero_delta_count = self.get_nonzero_delta_count(id);
            LockerState { address, nonzero_delta_count }
        }


        fn get_locker_delta(self: @ContractState, id: u32, token_address: ContractAddress) -> i129 {
            self.locker_token_deltas.read((id, token_address))
        }

        fn get_pool_price(self: @ContractState, pool_key: PoolKey) -> PoolPrice {
            self.pool_price.read(pool_key)
        }

        fn get_pool_liquidity(self: @ContractState, pool_key: PoolKey) -> u128 {
            self.pool_liquidity.read(pool_key)
        }

        fn get_pool_fees_per_liquidity(
            self: @ContractState, pool_key: PoolKey,
        ) -> FeesPerLiquidity {
            self.pool_fees.read(pool_key)
        }

        fn get_pool_tick_liquidity_delta(
            self: @ContractState, pool_key: PoolKey, index: i129,
        ) -> i129 {
            self.tick_liquidity_delta.entry(pool_key).entry(index).read()
        }

        fn get_pool_tick_liquidity_net(
            self: @ContractState, pool_key: PoolKey, index: i129,
        ) -> u128 {
            self.tick_liquidity_net.entry(pool_key).entry(index).read()
        }

        fn get_pool_tick_fees_outside(
            self: @ContractState, pool_key: PoolKey, index: i129,
        ) -> FeesPerLiquidity {
            self.tick_fees_outside.entry(pool_key).entry(index).read()
        }

        fn get_position(
            self: @ContractState, pool_key: PoolKey, position_key: PositionKey,
        ) -> Position {
            self.positions.read((pool_key, position_key))
        }

        fn get_position_with_fees(
            self: @ContractState, pool_key: PoolKey, position_key: PositionKey,
        ) -> GetPositionWithFeesResult {
            let position = self.get_position(pool_key, position_key);

            let fees_per_liquidity_inside_current = self
                .get_pool_fees_per_liquidity_inside(pool_key, position_key.bounds);

            let (fees0, fees1) = position.fees(fees_per_liquidity_inside_current);

            GetPositionWithFeesResult { position, fees0, fees1, fees_per_liquidity_inside_current }
        }

        fn get_saved_balance(self: @ContractState, key: SavedBalanceKey) -> u128 {
            self.saved_balances.read(key)
        }


        fn next_initialized_tick(
            self: @ContractState, pool_key: PoolKey, from: i129, skip_ahead: u128,
        ) -> (i129, bool) {
            self
                .prefix_next_initialized_tick(
                    self.tick_bitmaps.entry(pool_key), pool_key.tick_spacing, from, skip_ahead,
                )
        }

        fn prev_initialized_tick(
            self: @ContractState, pool_key: PoolKey, from: i129, skip_ahead: u128,
        ) -> (i129, bool) {
            self
                .prefix_prev_initialized_tick(
                    self.tick_bitmaps.entry(pool_key), pool_key.tick_spacing, from, skip_ahead,
                )
        }

        fn withdraw_all_protocol_fees(
            ref self: ContractState, recipient: ContractAddress, token: ContractAddress,
        ) -> u128 {
            let amount_collected = self.get_protocol_fees_collected(token);
            self.withdraw_protocol_fees(recipient, token, amount_collected);
            amount_collected
        }

        fn withdraw_protocol_fees(
            ref self: ContractState,
            recipient: ContractAddress,
            token: ContractAddress,
            amount: u128,
        ) {
            self.require_owner();

            let collected: u128 = self.protocol_fees_collected.read(token);
            self.protocol_fees_collected.write(token, collected - amount);

            assert(
                IERC20Dispatcher { contract_address: token }.transfer(recipient, amount.into()),
                'TOKEN_TRANSFER_FAILED',
            );
            self.emit(ProtocolFeesWithdrawn { recipient, token, amount });
        }

        fn lock(ref self: ContractState, data: Span<felt252>) -> Span<felt252> {
            let id = self.lock_count.read();
            let caller = get_caller_address();

            self.lock_count.write(id + 1);
            self.set_locker_address(id, caller);

            let result = ILockerDispatcher { contract_address: caller }.locked(id, data);

            assert(self.get_nonzero_delta_count(id) == 0, 'NOT_ZEROED');

            self.lock_count.write(id);
            self.set_locker_address(id, Zero::zero());

            result
        }

        fn forward(
            ref self: ContractState, to: IForwardeeDispatcher, data: Span<felt252>,
        ) -> Span<felt252> {
            let (id, locker) = self.require_locker();

            // update this lock's locker to the forwarded address for the duration of the forwarded
            // call, meaning only the forwarded address can update state
            self.set_locker_address(id, to.contract_address);
            let result = to.forwarded(locker, id, data);
            self.set_locker_address(id, locker);

            result
        }

        fn withdraw(
            ref self: ContractState,
            token_address: ContractAddress,
            recipient: ContractAddress,
            amount: u128,
        ) {
            let (id, _) = self.require_locker();

            // tracks the delta for the given token address
            self.account_delta(id, token_address, i129 { mag: amount, sign: false });

            assert(
                IERC20Dispatcher { contract_address: token_address }
                    .transfer(recipient, amount.into()),
                'TOKEN_TRANSFER_FAILED',
            );
        }

        fn save(ref self: ContractState, key: SavedBalanceKey, amount: u128) -> u128 {
            let (id, _) = self.require_locker();

            let saved_balance = self.saved_balances.read(key);
            let balance_next = saved_balance + amount;
            self.saved_balances.write(key, balance_next);

            // tracks the delta for the given token address
            self.account_delta(id, key.token, i129 { mag: amount, sign: false });

            self.emit(SavedBalance { key, amount: amount });

            balance_next
        }

        fn pay(ref self: ContractState, token_address: ContractAddress) {
            let (id, payer) = self.require_locker();

            let token = IERC20Dispatcher { contract_address: token_address };

            let this_address = get_contract_address();
            let allowance = token.allowance(payer, this_address);
            let balance_before = token.balanceOf(this_address);

            assert(
                token.transferFrom(sender: payer, recipient: this_address, amount: allowance),
                'TOKEN_TRANSFERFROM_FAILED',
            );

            let delta = token.balanceOf(this_address) - balance_before;

            assert(delta.high.is_zero(), 'DELTA_TOO_LARGE');
            assert(delta == allowance, 'TRANSFER_FROM_INVARIANT');

            self.account_delta(id, token_address, i129 { mag: delta.low, sign: true });
        }

        fn load(
            ref self: ContractState, token: ContractAddress, salt: felt252, amount: u128,
        ) -> u128 {
            let id = self.get_current_locker_id();

            // the contract calling load does not have to be the locker!
            // this allows for a contract to load a stored balance for another user, e.g.:
            //  wrapping saved balances as an erc1155
            let caller = get_caller_address();
            let key = SavedBalanceKey { owner: caller, token, salt };

            let saved_balance = self.saved_balances.read(key);
            assert(amount <= saved_balance, 'INSUFFICIENT_SAVED_BALANCE');
            let balance_next = saved_balance - amount;
            self.saved_balances.write(key, balance_next);

            self.account_delta(id, token, i129 { mag: amount, sign: true });

            self.emit(LoadedBalance { key, amount });

            balance_next
        }

        fn maybe_initialize_pool(
            ref self: ContractState, pool_key: PoolKey, initial_tick: i129,
        ) -> Option<u256> {
            let price = self.pool_price.read(pool_key);
            if (price.sqrt_ratio.is_zero()) {
                Option::Some(self.initialize_pool(pool_key, initial_tick))
            } else {
                Option::None
            }
        }

        fn initialize_pool(ref self: ContractState, pool_key: PoolKey, initial_tick: i129) -> u256 {
            pool_key.check_valid();

            assert(
                pool_key.extension.is_zero()
                    || (self.extension_call_points.read(pool_key.extension) != Default::default()),
                'EXTENSION_NOT_REGISTERED',
            );

            let call_points = self.get_call_points_for_caller(pool_key, get_caller_address());

            if (call_points.before_initialize_pool) {
                IExtensionDispatcher { contract_address: pool_key.extension }
                    .before_initialize_pool(get_caller_address(), pool_key, initial_tick);
            }

            let price = self.pool_price.read(pool_key);
            assert(price.sqrt_ratio.is_zero(), 'ALREADY_INITIALIZED');

            let sqrt_ratio = tick_to_sqrt_ratio(initial_tick);

            self.pool_price.write(pool_key, PoolPrice { sqrt_ratio, tick: initial_tick });

            self.emit(PoolInitialized { pool_key, initial_tick, sqrt_ratio });

            if (call_points.after_initialize_pool) {
                IExtensionDispatcher { contract_address: pool_key.extension }
                    .after_initialize_pool(get_caller_address(), pool_key, initial_tick);
            }

            sqrt_ratio
        }

        fn get_pool_fees_per_liquidity_inside(
            self: @ContractState, pool_key: PoolKey, bounds: Bounds,
        ) -> FeesPerLiquidity {
            let price = self.pool_price.read(pool_key);
            assert(price.sqrt_ratio.is_non_zero(), 'NOT_INITIALIZED');

            let pool_key_entry = self.tick_fees_outside.entry(pool_key);
            let fees_outside_lower = pool_key_entry.entry(bounds.lower).read();
            let fees_outside_upper = pool_key_entry.entry(bounds.upper).read();

            if (price.tick < bounds.lower) {
                fees_outside_lower - fees_outside_upper
            } else if (price.tick < bounds.upper) {
                let fees = self.pool_fees.read(pool_key);

                fees - fees_outside_lower - fees_outside_upper
            } else {
                fees_outside_upper - fees_outside_lower
            }
        }

        fn update_position(
            ref self: ContractState, pool_key: PoolKey, params: UpdatePositionParameters,
        ) -> Delta {
            let (id, locker) = self.require_locker();

            let call_points = self.get_call_points_for_caller(pool_key, locker);

            if (call_points.before_update_position) {
                IExtensionDispatcher { contract_address: pool_key.extension }
                    .before_update_position(locker, pool_key, params);
            }

            // bounds must be multiple of tick spacing
            params.bounds.check_valid(pool_key.tick_spacing);

            // pool must be initialized
            let mut price = self.pool_price.read(pool_key);
            assert(price.sqrt_ratio.is_non_zero(), 'NOT_INITIALIZED');

            let (sqrt_ratio_lower, sqrt_ratio_upper) = (
                tick_to_sqrt_ratio(params.bounds.lower), tick_to_sqrt_ratio(params.bounds.upper),
            );

            // compute the amount deltas due to the liquidity delta
            let mut delta = liquidity_delta_to_amount_delta(
                price.sqrt_ratio, params.liquidity_delta, sqrt_ratio_lower, sqrt_ratio_upper,
            );

            // here we are accumulating fees owed to the position based on its current liquidity
            let position_key = PositionKey {
                owner: locker, salt: params.salt, bounds: params.bounds,
            };

            // account the withdrawal protocol fee, because it's based on the deltas
            if (params.liquidity_delta.is_negative()) {
                let amount0_fee = compute_fee(delta.amount0.mag, pool_key.fee);
                let amount1_fee = compute_fee(delta.amount1.mag, pool_key.fee);

                let withdrawal_fee_delta = Delta {
                    amount0: i129 { mag: amount0_fee, sign: true },
                    amount1: i129 { mag: amount1_fee, sign: true },
                };

                if (amount0_fee.is_non_zero()) {
                    self
                        .protocol_fees_collected
                        .write(
                            pool_key.token0,
                            accumulate_fee_amount(
                                self.protocol_fees_collected.read(pool_key.token0), amount0_fee,
                            ),
                        );
                }
                if (amount1_fee.is_non_zero()) {
                    self
                        .protocol_fees_collected
                        .write(
                            pool_key.token1,
                            accumulate_fee_amount(
                                self.protocol_fees_collected.read(pool_key.token1), amount1_fee,
                            ),
                        );
                }

                delta -= withdrawal_fee_delta;
                self.emit(ProtocolFeesPaid { pool_key, position_key, delta: withdrawal_fee_delta });
            }

            let get_position_result = self.get_position_with_fees(pool_key, position_key);

            let position_liquidity_next: u128 = get_position_result
                .position
                .liquidity
                .add(params.liquidity_delta);

            // if the user is withdrawing everything, they must have collected all the fees
            if position_liquidity_next.is_non_zero() {
                // fees are implicitly stored in the fees per liquidity inside snapshot variable
                let fees_per_liquidity_inside_last = get_position_result
                    .fees_per_liquidity_inside_current
                    - fees_per_liquidity_new(
                        get_position_result.fees0,
                        get_position_result.fees1,
                        position_liquidity_next,
                    );

                // update the position
                self
                    .positions
                    .write(
                        (pool_key, position_key),
                        Position {
                            liquidity: position_liquidity_next,
                            fees_per_liquidity_inside_last: fees_per_liquidity_inside_last,
                        },
                    );
            } else {
                assert(
                    (get_position_result.fees0.is_zero()) & (get_position_result.fees1.is_zero()),
                    'MUST_COLLECT_FEES',
                );
                // delete the position from storage
                self.positions.write((pool_key, position_key), Zero::zero());
            }

            self.update_tick(pool_key, params.bounds.lower, params.liquidity_delta, false);
            self.update_tick(pool_key, params.bounds.upper, params.liquidity_delta, true);

            // update pool liquidity if it changed
            if ((price.tick >= params.bounds.lower) & (price.tick < params.bounds.upper)) {
                let liquidity = self.pool_liquidity.read(pool_key);
                self.pool_liquidity.write(pool_key, liquidity.add(params.liquidity_delta));
            }

            // and finally account the computed deltas
            self.account_pool_delta(id, pool_key, delta);

            self.emit(PositionUpdated { locker, pool_key, params, delta });

            if (call_points.after_update_position) {
                IExtensionDispatcher { contract_address: pool_key.extension }
                    .after_update_position(locker, pool_key, params, delta);
            }

            delta
        }

        fn collect_fees(
            ref self: ContractState, pool_key: PoolKey, salt: felt252, bounds: Bounds,
        ) -> Delta {
            let (id, locker) = self.require_locker();

            let call_points = self.get_call_points_for_caller(pool_key, locker);

            if (call_points.before_collect_fees) {
                IExtensionDispatcher { contract_address: pool_key.extension }
                    .before_collect_fees(locker, pool_key, salt, bounds);
            }

            let position_key = PositionKey { owner: locker, salt, bounds };
            let result = self.get_position_with_fees(pool_key, position_key);

            // update the position
            self
                .positions
                .write(
                    (pool_key, position_key),
                    Position {
                        liquidity: result.position.liquidity,
                        fees_per_liquidity_inside_last: result.fees_per_liquidity_inside_current,
                    },
                );

            let delta = Delta {
                amount0: i129 { mag: result.fees0, sign: true },
                amount1: i129 { mag: result.fees1, sign: true },
            };

            self.account_pool_delta(id, pool_key, delta);

            self.emit(PositionFeesCollected { pool_key, position_key, delta });

            if (call_points.after_collect_fees) {
                IExtensionDispatcher { contract_address: pool_key.extension }
                    .after_collect_fees(locker, pool_key, salt, bounds, delta);
            }

            delta
        }

        fn swap(ref self: ContractState, pool_key: PoolKey, params: SwapParameters) -> Delta {
            let (id, locker) = self.require_locker();

            let call_points = self.get_call_points_for_caller(pool_key, locker);

            if (call_points.before_swap) {
                IExtensionDispatcher { contract_address: pool_key.extension }
                    .before_swap(locker, pool_key, params);
            }

            let pool_price_entry = self.pool_price.entry(pool_key);

            let mut price: PoolPrice = pool_price_entry.read();

            // pool must be initialized
            assert(price.sqrt_ratio.is_non_zero(), 'NOT_INITIALIZED');

            let increasing = is_price_increasing(params.amount.sign, params.is_token1);

            // check the limit is not in the wrong direction and is within the price bounds
            assert((params.sqrt_ratio_limit > price.sqrt_ratio) == increasing, 'LIMIT_DIRECTION');
            assert(
                (params.sqrt_ratio_limit >= min_sqrt_ratio())
                    & (params.sqrt_ratio_limit <= max_sqrt_ratio()),
                'LIMIT_MAG',
            );

            let mut tick = price.tick;
            let mut amount_remaining = params.amount;
            let mut sqrt_ratio = price.sqrt_ratio;

            let liquidity_storage_address = self.pool_liquidity.entry(pool_key);

            let mut liquidity = liquidity_storage_address.read();
            let mut calculated_amount: u128 = Zero::zero();

            let fees_per_liquidity_storage_address = self.pool_fees.entry(pool_key);

            let mut fees_per_liquidity = fees_per_liquidity_storage_address.read();

            let tick_bitmap_storage_prefix: StoragePath<Map<u128, Bitmap>> = self
                .tick_bitmaps
                .entry(pool_key)
                .into();

            let mut tick_crossing_storage_prefixes: Option<(StoragePath, StoragePath)> =
                Option::None;

            while (amount_remaining.is_non_zero() & (sqrt_ratio != params.sqrt_ratio_limit)) {
                let (next_tick, is_initialized) = if (increasing) {
                    self
                        .prefix_next_initialized_tick(
                            tick_bitmap_storage_prefix,
                            pool_key.tick_spacing,
                            tick,
                            params.skip_ahead,
                        )
                } else {
                    self
                        .prefix_prev_initialized_tick(
                            tick_bitmap_storage_prefix,
                            pool_key.tick_spacing,
                            tick,
                            params.skip_ahead,
                        )
                };

                let next_tick_sqrt_ratio = tick_to_sqrt_ratio(next_tick);

                let step_sqrt_ratio_limit = if (increasing) {
                    if (params.sqrt_ratio_limit < next_tick_sqrt_ratio) {
                        params.sqrt_ratio_limit
                    } else {
                        next_tick_sqrt_ratio
                    }
                } else {
                    if (params.sqrt_ratio_limit > next_tick_sqrt_ratio) {
                        params.sqrt_ratio_limit
                    } else {
                        next_tick_sqrt_ratio
                    }
                };

                let swap_result = swap_result(
                    sqrt_ratio,
                    liquidity,
                    sqrt_ratio_limit: step_sqrt_ratio_limit,
                    amount: amount_remaining,
                    is_token1: params.is_token1,
                    fee: pool_key.fee,
                );

                // we know this only happens when liquidity is non zero
                if (swap_result.fee_amount.is_non_zero()) {
                    fees_per_liquidity = fees_per_liquidity
                        + if increasing {
                            fees_per_liquidity_from_amount1(
                                swap_result.fee_amount, liquidity.into(),
                            )
                        } else {
                            fees_per_liquidity_from_amount0(
                                swap_result.fee_amount, liquidity.into(),
                            )
                        };
                }

                amount_remaining -= swap_result.consumed_amount;
                calculated_amount += swap_result.calculated_amount;

                // we hit the tick boundary, transition to the next tick
                if (swap_result.sqrt_ratio_next == next_tick_sqrt_ratio) {
                    sqrt_ratio = swap_result.sqrt_ratio_next;
                    // we are crossing the tick, so the tick is changed to the next tick
                    tick =
                        if (increasing) {
                            next_tick
                        } else {
                            next_tick - i129 { mag: 1, sign: false }
                        };

                    if (is_initialized) {
                        // only compute the storage prefixes if we haven't already
                        let (liquidity_delta_storage_prefix, fees_per_liquidity_storage_prefix) =
                            if let Option::Some(prefixes) =
                            tick_crossing_storage_prefixes {
                            prefixes
                        } else {
                            let prefixes = (
                                self.tick_liquidity_delta.entry(pool_key),
                                self.tick_fees_outside.entry(pool_key),
                            );
                            tick_crossing_storage_prefixes = Option::Some(prefixes);
                            prefixes
                        };

                        let liquidity_delta = liquidity_delta_storage_prefix.read(next_tick);
                        // update our working liquidity based on the direction we are crossing the
                        // tick
                        if (increasing) {
                            liquidity = liquidity.add(liquidity_delta);
                        } else {
                            liquidity = liquidity.sub(liquidity_delta);
                        }

                        let tick_fpl_storage_address = fees_per_liquidity_storage_prefix
                            .entry(next_tick);
                        tick_fpl_storage_address
                            .write(fees_per_liquidity - tick_fpl_storage_address.read());
                    }
                } else if sqrt_ratio != swap_result.sqrt_ratio_next {
                    // the price moved but it did not cross the next tick
                    // we must only update the tick in case the price moved, otherwise we may
                    // transition the tick incorrectly
                    sqrt_ratio = swap_result.sqrt_ratio_next;
                    tick = sqrt_ratio_to_tick(sqrt_ratio);
                };
            };

            let delta = if (params.is_token1) {
                Delta {
                    amount0: i129 { mag: calculated_amount, sign: !params.amount.sign },
                    amount1: params.amount - amount_remaining,
                }
            } else {
                Delta {
                    amount0: params.amount - amount_remaining,
                    amount1: i129 { mag: calculated_amount, sign: !params.amount.sign },
                }
            };

            pool_price_entry.write(PoolPrice { sqrt_ratio, tick });
            liquidity_storage_address.write(liquidity);
            fees_per_liquidity_storage_address.write(fees_per_liquidity);

            self.account_pool_delta(id, pool_key, delta);

            self
                .emit(
                    Swapped {
                        locker,
                        pool_key,
                        params,
                        delta,
                        sqrt_ratio_after: sqrt_ratio,
                        tick_after: tick,
                        liquidity_after: liquidity,
                    },
                );

            if (call_points.after_swap) {
                IExtensionDispatcher { contract_address: pool_key.extension }
                    .after_swap(locker, pool_key, params, delta);
            }

            delta
        }

        fn accumulate_as_fees(
            ref self: ContractState, pool_key: PoolKey, amount0: u128, amount1: u128,
        ) {
            let (id, locker) = self.require_locker();

            // This method is only allowed for the extension of a pool,
            // because otherwise it complicates extension implementation considerably
            assert(locker == pool_key.extension, 'NOT_EXTENSION');

            self
                .pool_fees
                .write(
                    pool_key,
                    self.pool_fees.read(pool_key)
                        + fees_per_liquidity_new(
                            amount0, amount1, self.pool_liquidity.read(pool_key),
                        ),
                );

            self
                .account_pool_delta(
                    id,
                    pool_key,
                    Delta {
                        amount0: i129 { mag: amount0, sign: false },
                        amount1: i129 { mag: amount1, sign: false },
                    },
                );

            self.emit(FeesAccumulated { pool_key, amount0, amount1 });
        }

        fn set_call_points(ref self: ContractState, call_points: CallPoints) {
            assert(call_points != Default::default(), 'INVALID_CALL_POINTS');
            self.extension_call_points.write(get_caller_address(), call_points);
        }

        // Returns the call points for the given extension.
        fn get_call_points(self: @ContractState, extension: ContractAddress) -> CallPoints {
            self.extension_call_points.read(extension)
        }
    }
}
