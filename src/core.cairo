#[starknet::contract]
mod Core {
    use array::{ArrayTrait, SpanTrait};
    use ekubo::interfaces::core::{
        SwapParameters, UpdatePositionParameters, ILockerDispatcher, ILockerDispatcherTrait,
        LockerState, ICore, IExtensionDispatcher, IExtensionDispatcherTrait,
        GetPositionWithFeesResult
    };
    use ekubo::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use ekubo::interfaces::upgradeable::{IUpgradeable};
    use ekubo::math::bitmap::{
        Bitmap, BitmapTrait, tick_to_word_and_bit_index, word_and_bit_index_to_tick
    };
    use ekubo::math::bits::{msb, lsb};
    use ekubo::math::contract_address::{ContractAddressOrder};
    use ekubo::math::exp2::{exp2};
    use ekubo::math::fee::{compute_fee, accumulate_fee_amount};
    use ekubo::math::liquidity::liquidity_delta_to_amount_delta;
    use ekubo::math::mask::{mask};
    use ekubo::math::swap::{swap_result, is_price_increasing};
    use ekubo::math::ticks::{
        tick_to_sqrt_ratio, sqrt_ratio_to_tick, min_tick, max_tick, min_sqrt_ratio, max_sqrt_ratio,
        constants as tick_constants
    };
    use ekubo::owner::{check_owner_only};
    use ekubo::types::bounds::{Bounds, BoundsTrait};
    use ekubo::types::call_points::{CallPoints};
    use ekubo::types::delta::{Delta};
    use ekubo::types::fees_per_liquidity::{
        FeesPerLiquidity, fees_per_liquidity_new, fees_per_liquidity_from_amount0,
        fees_per_liquidity_from_amount1
    };
    use ekubo::types::i129::{i129, i129Trait, AddDeltaTrait};
    use ekubo::types::keys::{PositionKey, PoolKey, PoolKeyTrait, SavedBalanceKey};
    use ekubo::types::pool_price::{PoolPrice};
    use ekubo::types::position::{Position, PositionTrait};
    use ekubo::upgradeable::{Upgradeable as upgradeable_component};
    use hash::{LegacyHash};
    use option::{Option, OptionTrait};
    use starknet::{
        Store, ContractAddress, ClassHash, contract_address_const, get_caller_address,
        get_contract_address, replace_class_syscall, storage_base_address_from_felt252
    };
    use traits::{Into};
    use zeroable::{Zeroable};

    component!(path: upgradeable_component, storage: upgradeable, event: UpgradeableEvent);

    #[abi(embed_v0)]
    impl Upgradeable = upgradeable_component::UpgradeableImpl<ContractState>;

    #[storage]
    struct Storage {
        // withdrawal fees collected, controlled by the owner
        protocol_fees_collected: LegacyMap<ContractAddress, u128>,
        // the last recorded balance of each token, used for checking payment
        reserves: LegacyMap<ContractAddress, u256>,
        // transient state of the lockers, which always starts and ends at zero
        lock_count: u32,
        // the rest of transient state is accessed directly using Store::read and Store::write to save on hashes

        // the persistent state of all the pools is stored in these structs
        pool_price: LegacyMap<PoolKey, PoolPrice>,
        pool_liquidity: LegacyMap<PoolKey, u128>,
        pool_fees: LegacyMap<PoolKey, FeesPerLiquidity>,
        tick_liquidity_net: LegacyMap<(PoolKey, i129), u128>,
        tick_liquidity_delta: LegacyMap<(PoolKey, i129), i129>,
        tick_fees_outside: LegacyMap<(PoolKey, i129), FeesPerLiquidity>,
        positions: LegacyMap<(PoolKey, PositionKey), Position>,
        tick_bitmaps: LegacyMap<(PoolKey, u128), Bitmap>,
        // users may save balances in the singleton to avoid transfers, keyed by (owner, token, cache_key)
        saved_balances: LegacyMap<SavedBalanceKey, u128>,
        // upgradable component storage (empty)
        #[substorage(v0)]
        upgradeable: upgradeable_component::Storage
    }

    #[derive(starknet::Event, Drop)]
    struct ProtocolFeesWithdrawn {
        recipient: ContractAddress,
        token: ContractAddress,
        amount: u128,
    }

    #[derive(starknet::Event, Drop)]
    struct ProtocolFeesPaid {
        pool_key: PoolKey,
        position_key: PositionKey,
        delta: Delta,
    }

    #[derive(starknet::Event, Drop)]
    struct PoolInitialized {
        pool_key: PoolKey,
        initial_tick: i129,
        sqrt_ratio: u256,
        call_points: u8,
    }

    #[derive(starknet::Event, Drop)]
    struct PositionUpdated {
        locker: ContractAddress,
        pool_key: PoolKey,
        params: UpdatePositionParameters,
        delta: Delta,
    }

    #[derive(starknet::Event, Drop)]
    struct PositionFeesCollected {
        pool_key: PoolKey,
        position_key: PositionKey,
        delta: Delta,
    }

    #[derive(starknet::Event, Drop)]
    struct Swapped {
        locker: ContractAddress,
        pool_key: PoolKey,
        params: SwapParameters,
        delta: Delta,
        sqrt_ratio_after: u256,
        tick_after: i129,
        liquidity_after: u128,
    }

    #[derive(starknet::Event, Drop)]
    struct FeesAccumulated {
        pool_key: PoolKey,
        amount0: u128,
        amount1: u128,
    }

    #[derive(starknet::Event, Drop)]
    struct SavedBalance {
        key: SavedBalanceKey,
        amount: u128,
    }

    #[derive(starknet::Event, Drop)]
    struct LoadedBalance {
        key: SavedBalanceKey,
        amount: u128,
    }


    #[derive(starknet::Event, Drop)]
    #[event]
    enum Event {
        #[flat]
        UpgradeableEvent: upgradeable_component::Event,
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
        #[inline(always)]
        fn get_current_locker_id(self: @ContractState) -> u32 {
            let lock_count = self.lock_count.read();
            assert(lock_count > 0, 'NOT_LOCKED');
            lock_count - 1
        }

        #[inline(always)]
        fn get_locker_address(self: @ContractState, id: u32) -> ContractAddress {
            Store::read(0, storage_base_address_from_felt252(id.into()))
                .expect('FAILED_READ_LOCKER_ADDRESS')
        }

        #[inline(always)]
        fn set_locker_address(self: @ContractState, id: u32, address: ContractAddress) {
            Store::write(0, storage_base_address_from_felt252(id.into()), address)
                .expect('FAILED_WRITE_LOCKER_ADDRESS');
        }

        #[inline(always)]
        fn get_nonzero_delta_count(self: @ContractState, id: u32) -> u32 {
            Store::read(0, storage_base_address_from_felt252(0x100000000 + id.into()))
                .expect('FAILED_READ_NZD_COUNT')
        }

        #[inline(always)]
        fn set_nonzero_delta_count(self: @ContractState, id: u32, count: u32) {
            Store::write(0, storage_base_address_from_felt252(0x100000000 + id.into()), count)
                .expect('FAILED_WRITE_NZD_COUNT');
        }

        #[inline(always)]
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
            ref self: ContractState, id: u32, token_address: ContractAddress, delta: i129
        ) {
            let delta_storage_location = storage_base_address_from_felt252(
                pedersen::pedersen(id.into(), token_address.into())
            );
            let current: i129 = Store::read(0, delta_storage_location).expect('FAILED_READ_DELTA');
            let next = current + delta;
            Store::write(0, delta_storage_location, next).expect('FAILED_WRITE_DELTA');
            if (current.is_zero() & next.is_non_zero()) {
                self.set_nonzero_delta_count(id, self.get_nonzero_delta_count(id) + 1);
            } else if (current.is_non_zero() & next.is_zero()) {
                self.set_nonzero_delta_count(id, self.get_nonzero_delta_count(id) - 1);
            }
        }

        #[inline(always)]
        fn account_pool_delta(ref self: ContractState, id: u32, pool_key: PoolKey, delta: Delta) {
            self.account_delta(id, pool_key.token0, delta.amount0);
            self.account_delta(id, pool_key.token1, delta.amount1);
        }

        // Remove the initialized tick for the given pool
        fn remove_initialized_tick(ref self: ContractState, pool_key: PoolKey, index: i129) {
            let (word_index, bit_index) = tick_to_word_and_bit_index(index, pool_key.tick_spacing);
            let bitmap = self.tick_bitmaps.read((pool_key, word_index));
            // it is assumed that bitmap already contains the set bit exp2(bit_index)
            self.tick_bitmaps.write((pool_key, word_index), bitmap.unset_bit(bit_index));
        }

        // Insert an initialized tick for the given pool
        fn insert_initialized_tick(ref self: ContractState, pool_key: PoolKey, index: i129) {
            let (word_index, bit_index) = tick_to_word_and_bit_index(index, pool_key.tick_spacing);
            let bitmap = self.tick_bitmaps.read((pool_key, word_index));
            // it is assumed that bitmap does not contain the set bit exp2(bit_index) already
            self.tick_bitmaps.write((pool_key, word_index), bitmap.set_bit(bit_index));
        }

        fn update_tick(
            ref self: ContractState,
            pool_key: PoolKey,
            index: i129,
            liquidity_delta: i129,
            is_upper: bool
        ) {
            let key = (pool_key, index);
            let liquidity_delta_current = self.tick_liquidity_delta.read(key);

            let liquidity_net_current = self.tick_liquidity_net.read(key);
            let next_liquidity_net = liquidity_net_current.add(liquidity_delta);

            self
                .tick_liquidity_delta
                .write(
                    key,
                    if is_upper {
                        liquidity_delta_current - liquidity_delta
                    } else {
                        liquidity_delta_current + liquidity_delta
                    }
                );

            self.tick_liquidity_net.write(key, next_liquidity_net);

            if ((next_liquidity_net == 0) != (liquidity_net_current == 0)) {
                if (next_liquidity_net == 0) {
                    self.remove_initialized_tick(pool_key, index);
                } else {
                    self.insert_initialized_tick(pool_key, index);
                }
            };
        }


        fn prefix_next_initialized_tick(
            self: @ContractState, prefix: felt252, tick_spacing: u128, from: i129, skip_ahead: u128
        ) -> (i129, bool) {
            assert(from < max_tick(), 'NEXT_FROM_MAX');

            let (word_index, bit_index) = tick_to_word_and_bit_index(
                from + i129 { mag: tick_spacing, sign: false }, tick_spacing
            );

            let bitmap: Bitmap = Store::read(
                0, storage_base_address_from_felt252(LegacyHash::hash(prefix, word_index))
            )
                .expect('BITMAP_READ_FAILED');

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
                                prefix, tick_spacing, next, skip_ahead - 1
                            )
                    }
                },
            }
        }

        fn prefix_prev_initialized_tick(
            self: @ContractState, prefix: felt252, tick_spacing: u128, from: i129, skip_ahead: u128
        ) -> (i129, bool) {
            assert(from >= min_tick(), 'PREV_FROM_MIN');
            let (word_index, bit_index) = tick_to_word_and_bit_index(from, tick_spacing);

            let bitmap: Bitmap = Store::read(
                0, storage_base_address_from_felt252(LegacyHash::hash(prefix, word_index))
            )
                .expect('BITMAP_READ_FAILED');

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
                                skip_ahead - 1
                            )
                    }
                }
            }
        }
    }

    #[external(v0)]
    impl Core of ICore<ContractState> {
        fn get_protocol_fees_collected(self: @ContractState, token: ContractAddress) -> u128 {
            self.protocol_fees_collected.read(token)
        }

        fn get_locker_state(self: @ContractState, id: u32) -> LockerState {
            let address = self.get_locker_address(id);
            let nonzero_delta_count = self.get_nonzero_delta_count(id);
            LockerState { address, nonzero_delta_count }
        }

        fn get_pool_price(self: @ContractState, pool_key: PoolKey) -> PoolPrice {
            self.pool_price.read(pool_key)
        }

        fn get_pool_liquidity(self: @ContractState, pool_key: PoolKey) -> u128 {
            self.pool_liquidity.read(pool_key)
        }

        fn get_pool_fees_per_liquidity(
            self: @ContractState, pool_key: PoolKey
        ) -> FeesPerLiquidity {
            self.pool_fees.read(pool_key)
        }

        fn get_reserves(self: @ContractState, token: ContractAddress) -> u256 {
            self.reserves.read(token)
        }

        fn get_pool_tick_liquidity_delta(
            self: @ContractState, pool_key: PoolKey, index: i129
        ) -> i129 {
            self.tick_liquidity_delta.read((pool_key, index))
        }

        fn get_pool_tick_liquidity_net(
            self: @ContractState, pool_key: PoolKey, index: i129
        ) -> u128 {
            self.tick_liquidity_net.read((pool_key, index))
        }

        fn get_pool_tick_fees_outside(
            self: @ContractState, pool_key: PoolKey, index: i129
        ) -> FeesPerLiquidity {
            self.tick_fees_outside.read((pool_key, index))
        }

        fn get_position(
            self: @ContractState, pool_key: PoolKey, position_key: PositionKey
        ) -> Position {
            self.positions.read((pool_key, position_key))
        }

        fn get_position_with_fees(
            self: @ContractState, pool_key: PoolKey, position_key: PositionKey
        ) -> GetPositionWithFeesResult {
            let position = self.get_position(pool_key, position_key);

            let fees_per_liquidity_inside_current = self
                .get_pool_fees_per_liquidity_inside(pool_key, position_key.bounds);

            let (fees0, fees1) = position.fees(fees_per_liquidity_inside_current);

            GetPositionWithFeesResult { position, fees0, fees1, fees_per_liquidity_inside_current, }
        }

        fn get_saved_balance(self: @ContractState, key: SavedBalanceKey) -> u128 {
            self.saved_balances.read(key)
        }


        fn next_initialized_tick(
            self: @ContractState, pool_key: PoolKey, from: i129, skip_ahead: u128
        ) -> (i129, bool) {
            self
                .prefix_next_initialized_tick(
                    LegacyHash::hash(selector!("tick_bitmaps"), pool_key),
                    pool_key.tick_spacing,
                    from,
                    skip_ahead
                )
        }

        fn prev_initialized_tick(
            self: @ContractState, pool_key: PoolKey, from: i129, skip_ahead: u128
        ) -> (i129, bool) {
            self
                .prefix_prev_initialized_tick(
                    LegacyHash::hash(selector!("tick_bitmaps"), pool_key),
                    pool_key.tick_spacing,
                    from,
                    skip_ahead
                )
        }

        fn withdraw_protocol_fees(
            ref self: ContractState,
            recipient: ContractAddress,
            token: ContractAddress,
            amount: u128
        ) {
            check_owner_only();

            let collected: u128 = self.protocol_fees_collected.read(token);
            self.protocol_fees_collected.write(token, collected - amount);
            self.reserves.write(token, self.reserves.read(token) - amount.into());

            IERC20Dispatcher { contract_address: token }.transfer(recipient, amount.into());
            self.emit(ProtocolFeesWithdrawn { recipient, token, amount });
        }

        fn lock(ref self: ContractState, data: Array<felt252>) -> Array<felt252> {
            let id = self.lock_count.read();
            let caller = get_caller_address();

            self.lock_count.write(id + 1);
            self.set_locker_address(id, caller);

            let result = ILockerDispatcher { contract_address: caller }.locked(id, data);

            assert(self.get_nonzero_delta_count(id) == 0, 'NOT_ZEROED');

            self.lock_count.write(id);
            self.set_locker_address(id, Zeroable::zero());

            result
        }

        fn withdraw(
            ref self: ContractState,
            token_address: ContractAddress,
            recipient: ContractAddress,
            amount: u128
        ) {
            let (id, _) = self.require_locker();

            let res = self.reserves.read(token_address);
            let amount_large: u256 = amount.into();
            assert(res >= amount_large, 'INSUFFICIENT_RESERVES');
            self.reserves.write(token_address, res - amount_large);

            // tracks the delta for the given token address
            self.account_delta(id, token_address, i129 { mag: amount, sign: false });

            IERC20Dispatcher { contract_address: token_address }.transfer(recipient, amount_large);
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

        fn deposit(ref self: ContractState, token_address: ContractAddress) -> u128 {
            let (id, _) = self.require_locker();

            let balance = IERC20Dispatcher { contract_address: token_address }
                .balanceOf(get_contract_address());

            let reserve = self.reserves.read(token_address);
            // should never happen, assuming token is well-behaving, e.g. not rebasing or collecting fees on transfers from sender
            assert(balance >= reserve, 'BALANCE_LT_RESERVE');
            let delta = balance - reserve;
            // the delta is limited to u128
            assert(delta.high == 0, 'DELTA_EXCEEDED_MAX');

            self.account_delta(id, token_address, i129 { mag: delta.low, sign: true });
            self.reserves.write(token_address, balance);

            delta.low
        }

        fn load(ref self: ContractState, token: ContractAddress, salt: u64, amount: u128) -> u128 {
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
            ref self: ContractState, pool_key: PoolKey, initial_tick: i129
        ) -> Option<u256> {
            let price = self.pool_price.read(pool_key);
            if (price.sqrt_ratio.is_zero()) {
                Option::Some(self.initialize_pool(pool_key, initial_tick))
            } else {
                Option::None(())
            }
        }

        fn initialize_pool(ref self: ContractState, pool_key: PoolKey, initial_tick: i129) -> u256 {
            pool_key.check_valid();

            let price = self.pool_price.read(pool_key);
            assert(price.sqrt_ratio.is_zero(), 'ALREADY_INITIALIZED');

            let call_points = if (pool_key.extension.is_non_zero()) {
                IExtensionDispatcher { contract_address: pool_key.extension }
                    .before_initialize_pool(get_caller_address(), pool_key, initial_tick)
            } else {
                Default::<CallPoints>::default()
            };

            let sqrt_ratio = tick_to_sqrt_ratio(initial_tick);

            self
                .pool_price
                .write(pool_key, PoolPrice { sqrt_ratio, tick: initial_tick, call_points });

            self
                .emit(
                    PoolInitialized {
                        pool_key, initial_tick, sqrt_ratio, call_points: call_points.into()
                    }
                );

            if (call_points.after_initialize_pool) {
                IExtensionDispatcher { contract_address: pool_key.extension }
                    .after_initialize_pool(get_caller_address(), pool_key, initial_tick);
            }

            sqrt_ratio
        }

        fn get_pool_fees_per_liquidity_inside(
            self: @ContractState, pool_key: PoolKey, bounds: Bounds
        ) -> FeesPerLiquidity {
            let price = self.pool_price.read(pool_key);
            assert(price.sqrt_ratio.is_non_zero(), 'NOT_INITIALIZED');

            let fees_outside_lower = self.tick_fees_outside.read((pool_key, bounds.lower));
            let fees_outside_upper = self.tick_fees_outside.read((pool_key, bounds.upper));

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
            ref self: ContractState, pool_key: PoolKey, params: UpdatePositionParameters
        ) -> Delta {
            let (id, locker) = self.require_locker();

            let price = self.pool_price.read(pool_key);

            if (price.call_points.before_update_position) {
                if (pool_key.extension != locker) {
                    IExtensionDispatcher { contract_address: pool_key.extension }
                        .before_update_position(locker, pool_key, params);
                }
            }

            params.bounds.check_valid(pool_key.tick_spacing);

            // pool must be initialized
            assert(price.sqrt_ratio.is_non_zero(), 'NOT_INITIALIZED');

            let (sqrt_ratio_lower, sqrt_ratio_upper) = (
                tick_to_sqrt_ratio(params.bounds.lower), tick_to_sqrt_ratio(params.bounds.upper)
            );

            // compute the amount deltas due to the liquidity delta
            let mut delta = liquidity_delta_to_amount_delta(
                price.sqrt_ratio, params.liquidity_delta, sqrt_ratio_lower, sqrt_ratio_upper
            );

            // here we are accumulating fees owed to the position based on its current liquidity
            let position_key = PositionKey {
                owner: locker, salt: params.salt, bounds: params.bounds
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
                                self.protocol_fees_collected.read(pool_key.token0), amount0_fee
                            )
                        );
                }
                if (amount1_fee.is_non_zero()) {
                    self
                        .protocol_fees_collected
                        .write(
                            pool_key.token1,
                            accumulate_fee_amount(
                                self.protocol_fees_collected.read(pool_key.token1), amount1_fee
                            )
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
                        position_liquidity_next
                    );

                // update the position
                self
                    .positions
                    .write(
                        (pool_key, position_key),
                        Position {
                            liquidity: position_liquidity_next,
                            fees_per_liquidity_inside_last: fees_per_liquidity_inside_last,
                        }
                    );
            } else {
                assert(
                    (get_position_result.fees0.is_zero()) & (get_position_result.fees1.is_zero()),
                    'MUST_COLLECT_FEES'
                );
                // delete the position from storage
                self.positions.write((pool_key, position_key), Zeroable::zero());
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

            if (price.call_points.after_update_position) {
                if (pool_key.extension != locker) {
                    IExtensionDispatcher { contract_address: pool_key.extension }
                        .after_update_position(locker, pool_key, params, delta);
                }
            }

            delta
        }

        fn collect_fees(
            ref self: ContractState, pool_key: PoolKey, salt: u64, bounds: Bounds
        ) -> Delta {
            let (id, locker) = self.require_locker();

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
                    }
                );

            let delta = Delta {
                amount0: i129 { mag: result.fees0, sign: true },
                amount1: i129 { mag: result.fees1, sign: true },
            };

            self.account_pool_delta(id, pool_key, delta);

            self.emit(PositionFeesCollected { pool_key, position_key, delta });

            delta
        }


        fn swap(ref self: ContractState, pool_key: PoolKey, params: SwapParameters) -> Delta {
            let (id, locker) = self.require_locker();

            let pool_price_storage_address = storage_base_address_from_felt252(
                LegacyHash::hash(selector!("pool_price"), pool_key)
            );

            let price: PoolPrice = Store::read(0, pool_price_storage_address)
                .expect('FAILED_READ_POOL_PRICE');

            // pool must be initialized
            assert(price.sqrt_ratio.is_non_zero(), 'NOT_INITIALIZED');

            if (price.call_points.before_swap) {
                if (pool_key.extension != locker) {
                    IExtensionDispatcher { contract_address: pool_key.extension }
                        .before_swap(locker, pool_key, params);
                }
            }

            let increasing = is_price_increasing(params.amount.sign, params.is_token1);

            // check the limit is not in the wrong direction and is within the price bounds
            assert((params.sqrt_ratio_limit > price.sqrt_ratio) == increasing, 'LIMIT_DIRECTION');
            assert(
                (params.sqrt_ratio_limit >= min_sqrt_ratio())
                    & (params.sqrt_ratio_limit <= max_sqrt_ratio()),
                'LIMIT_MAG'
            );

            let mut tick = price.tick;
            let mut amount_remaining = params.amount;
            let mut sqrt_ratio = price.sqrt_ratio;

            let liquidity_storage_address = storage_base_address_from_felt252(
                LegacyHash::hash(selector!("pool_liquidity"), pool_key)
            );

            let mut liquidity: u128 = Store::read(0, liquidity_storage_address)
                .expect('FAILED_READ_POOL_LIQUIDITY');
            let mut calculated_amount: u128 = Zeroable::zero();

            let fees_per_liquidity_storage_address = storage_base_address_from_felt252(
                LegacyHash::hash(selector!("pool_fees"), pool_key)
            );

            let mut fees_per_liquidity: FeesPerLiquidity = Store::read(
                0, fees_per_liquidity_storage_address
            )
                .expect('FAILED_READ_POOL_FEES');

            // we need to take a snapshot to call view methods within the loop
            let self_snap = @self;

            let tick_bitmap_storage_prefix = LegacyHash::hash(selector!("tick_bitmaps"), pool_key);

            let mut tick_crossing_storage_prefixes: Option<(felt252, felt252)> = Option::None(());

            loop {
                if (amount_remaining.is_zero()) {
                    break ();
                }

                if (sqrt_ratio == params.sqrt_ratio_limit) {
                    break ();
                }

                let (next_tick, is_initialized) = if (increasing) {
                    self_snap
                        .prefix_next_initialized_tick(
                            tick_bitmap_storage_prefix,
                            pool_key.tick_spacing,
                            tick,
                            params.skip_ahead
                        )
                } else {
                    self_snap
                        .prefix_prev_initialized_tick(
                            tick_bitmap_storage_prefix,
                            pool_key.tick_spacing,
                            tick,
                            params.skip_ahead
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
                    fee: pool_key.fee
                );

                amount_remaining -= swap_result.consumed_amount;
                sqrt_ratio = swap_result.sqrt_ratio_next;
                calculated_amount += swap_result.calculated_amount;

                // we know this only happens when liquidity is non zero
                if (swap_result.fee_amount.is_non_zero()) {
                    fees_per_liquidity = fees_per_liquidity
                        + if increasing {
                            fees_per_liquidity_from_amount1(
                                swap_result.fee_amount, liquidity.into()
                            )
                        } else {
                            fees_per_liquidity_from_amount0(
                                swap_result.fee_amount, liquidity.into()
                            )
                        };
                }

                if (sqrt_ratio == next_tick_sqrt_ratio) {
                    // we are crossing the tick, so the tick is changed to the next tick
                    tick =
                        if (increasing) {
                            next_tick
                        } else {
                            next_tick - i129 { mag: 1, sign: false }
                        };

                    if (is_initialized) {
                        tick_crossing_storage_prefixes = match tick_crossing_storage_prefixes {
                            Option::Some(prefixes) => { tick_crossing_storage_prefixes },
                            Option::None => {
                                Option::Some(
                                    (
                                        LegacyHash::hash(
                                            selector!("tick_liquidity_delta"), pool_key
                                        ),
                                        LegacyHash::hash(selector!("tick_fees_outside"), pool_key)
                                    )
                                )
                            }
                        };

                        let (liquidity_delta_storage_prefix, fees_per_liquidity_storage_prefix) =
                            tick_crossing_storage_prefixes
                            .unwrap();

                        let liquidity_delta: i129 = Store::read(
                            0,
                            storage_base_address_from_felt252(
                                LegacyHash::hash(liquidity_delta_storage_prefix, next_tick)
                            )
                        )
                            .expect('FAILED_READ_LIQ_DELTA');
                        // update our working liquidity based on the direction we are crossing the tick
                        if (increasing) {
                            liquidity = liquidity.add(liquidity_delta);
                        } else {
                            liquidity = liquidity.sub(liquidity_delta);
                        }

                        // update the tick fee state
                        let fpl_storage_base_address = storage_base_address_from_felt252(
                            LegacyHash::hash(fees_per_liquidity_storage_prefix, next_tick)
                        );
                        Store::write(
                            0,
                            fpl_storage_base_address,
                            fees_per_liquidity
                                - Store::read(0, fpl_storage_base_address)
                                    .expect('FAILED_READ_TICK_FPL')
                        )
                            .expect('FAILED_WRITE_TICK_FPL');
                    }
                } else {
                    tick = sqrt_ratio_to_tick(sqrt_ratio);
                };
            };

            let delta = if (params.is_token1) {
                Delta {
                    amount0: i129 { mag: calculated_amount, sign: !params.amount.sign },
                    amount1: params.amount - amount_remaining
                }
            } else {
                Delta {
                    amount0: params.amount - amount_remaining,
                    amount1: i129 { mag: calculated_amount, sign: !params.amount.sign }
                }
            };

            Store::write(
                0,
                pool_price_storage_address,
                PoolPrice { sqrt_ratio, tick, call_points: price.call_points }
            )
                .expect('FAILED_WRITE_POOL_PRICE');
            Store::write(0, liquidity_storage_address, liquidity).expect('FAILED_WRITE_LIQUIDITY');
            Store::write(0, fees_per_liquidity_storage_address, fees_per_liquidity)
                .expect('FAILED_WRITE_FEES');

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
                        liquidity_after: liquidity
                    }
                );

            if (price.call_points.after_swap) {
                if (pool_key.extension != locker) {
                    IExtensionDispatcher { contract_address: pool_key.extension }
                        .after_swap(locker, pool_key, params, delta);
                }
            }

            delta
        }

        fn accumulate_as_fees(
            ref self: ContractState, pool_key: PoolKey, amount0: u128, amount1: u128
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
                            amount0, amount1, self.pool_liquidity.read(pool_key)
                        )
                );

            self
                .account_pool_delta(
                    id,
                    pool_key,
                    Delta {
                        amount0: i129 { mag: amount0, sign: false },
                        amount1: i129 { mag: amount1, sign: false },
                    }
                );

            self.emit(FeesAccumulated { pool_key, amount0, amount1, });
        }
    }
}
