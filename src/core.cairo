#[starknet::contract]
mod Core {
    use ekubo::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use ekubo::interfaces::core::{
        SwapParameters, UpdatePositionParameters, ILockerDispatcher, ILockerDispatcherTrait,
        LockerState, ICore, IExtensionDispatcher, IExtensionDispatcherTrait, GetPositionResult,
        GetPoolResult
    };
    use ekubo::interfaces::upgradeable::{IUpgradeable};
    use zeroable::Zeroable;
    use starknet::{
        ContractAddress, ClassHash, contract_address_const, get_caller_address,
        get_contract_address, replace_class_syscall
    };
    use option::{Option, OptionTrait};
    use array::{ArrayTrait, SpanTrait};
    use traits::{Neg};
    use ekubo::math::ticks::{
        tick_to_sqrt_ratio, sqrt_ratio_to_tick, min_tick, max_tick, min_sqrt_ratio, max_sqrt_ratio,
        constants as tick_constants
    };
    use ekubo::math::liquidity::liquidity_delta_to_amount_delta;
    use ekubo::math::swap::{swap_result, is_price_increasing};
    use ekubo::math::fee::{compute_fee, accumulate_fee_amount};
    use ekubo::math::exp2::{exp2};
    use ekubo::math::mask::{mask};
    use ekubo::math::muldiv::{muldiv, div};
    use ekubo::math::bitmap::{tick_to_word_and_bit_index, word_and_bit_index_to_tick};
    use ekubo::math::bits::{msb, lsb};
    use ekubo::math::utils::{ContractAddressOrder, u128_max};
    use ekubo::owner::{check_owner_only};
    use ekubo::types::i129::{i129, AddDeltaTrait};
    use ekubo::types::fees_per_liquidity::{
        FeesPerLiquidity, fees_per_liquidity_new, fees_per_liquidity_from_amount0,
        fees_per_liquidity_from_amount1
    };
    use ekubo::types::pool_price::{PoolPrice};
    use ekubo::types::position::{Position};
    use ekubo::types::tick::{Tick};
    use ekubo::types::keys::{PositionKey, PoolKey};
    use ekubo::types::bounds::{Bounds, CheckBoundsValidTrait};
    use ekubo::types::delta::{Delta};
    use ekubo::types::call_points::{CallPoints};
    use traits::{Into};


    #[storage]
    struct Storage {
        // withdrawal fees collected, controlled by the owner
        fees_collected: LegacyMap<ContractAddress, u128>,
        // the last recorded balance of each token, used for checking payment
        reserves: LegacyMap<ContractAddress, u256>,
        // transient state of the lockers, which always starts and ends at zero
        lock_count: u32,
        locker_addresses: LegacyMap<u32, ContractAddress>,
        nonzero_delta_counts: LegacyMap::<u32, u32>,
        // locker_id, token_address => delta
        // delta is from the perspective of the core contract, thus:
        // a positive delta means the contract is owed tokens, a negative delta means it owes tokens
        deltas: LegacyMap::<(u32, ContractAddress), i129>,
        // the persistent state of all the pools is stored in these structs
        pool_price: LegacyMap::<PoolKey, PoolPrice>,
        pool_liquidity: LegacyMap::<PoolKey, u128>,
        pool_fees: LegacyMap::<PoolKey, FeesPerLiquidity>,
        ticks: LegacyMap::<(PoolKey, i129), Tick>,
        tick_fees_outside: LegacyMap::<(PoolKey, i129), FeesPerLiquidity>,
        positions: LegacyMap::<(PoolKey, PositionKey), Position>,
        tick_bitmaps: LegacyMap<(PoolKey, u128), u128>,
        // users may save balances in the singleton to avoid transfers, keyed by (owner, token, cache_key)
        saved_balances: LegacyMap<(ContractAddress, ContractAddress, u64), u128>,
        // in withdrawal only mode, the contract will not accept deposits
        withdrawal_only_mode: bool,
    }

    #[derive(starknet::Event, Drop)]
    struct ClassHashReplaced {
        new_class_hash: ClassHash, 
    }

    #[derive(starknet::Event, Drop)]
    struct FeesWithdrawn {
        recipient: ContractAddress,
        token: ContractAddress,
        amount: u128,
    }

    #[derive(starknet::Event, Drop)]
    struct FeesPaid {
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
    struct SavedBalance {
        to: ContractAddress,
        token: ContractAddress,
        cache_key: u64,
        amount: u128,
    }

    #[derive(starknet::Event, Drop)]
    struct LoadedBalance {
        from: ContractAddress,
        token: ContractAddress,
        cache_key: u64,
        amount: u128,
    }

    #[derive(starknet::Event, Drop)]
    #[event]
    enum Event {
        ClassHashReplaced: ClassHashReplaced,
        FeesPaid: FeesPaid,
        FeesWithdrawn: FeesWithdrawn,
        PoolInitialized: PoolInitialized,
        PositionUpdated: PositionUpdated,
        PositionFeesCollected: PositionFeesCollected,
        Swapped: Swapped,
        SavedBalance: SavedBalance,
        LoadedBalance: LoadedBalance,
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
        fn get_locker(self: @ContractState) -> (u32, ContractAddress) {
            let id = self.get_current_locker_id();
            let locker = self.locker_addresses.read(id);
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
            let key = (id, token_address);
            let current = self.deltas.read(key);
            let next = current + delta;
            self.deltas.write(key, next);
            if ((current.mag == 0) & (next.mag != 0)) {
                self.nonzero_delta_counts.write(id, self.nonzero_delta_counts.read(id) + 1);
            } else if ((current.mag != 0) & (next.mag == 0)) {
                self.nonzero_delta_counts.write(id, self.nonzero_delta_counts.read(id) - 1);
            }
        }

        // Remove the initialized tick for the given pool
        fn remove_initialized_tick(ref self: ContractState, pool_key: PoolKey, index: i129) {
            let (word_index, bit_index) = tick_to_word_and_bit_index(index, pool_key.tick_spacing);
            let bitmap = self.tick_bitmaps.read((pool_key, word_index));
            // it is assumed that bitmap already contains the set bit exp2(bit_index)
            self.tick_bitmaps.write((pool_key, word_index), bitmap - exp2(bit_index));
        }

        // Insert an initialized tick for the given pool
        fn insert_initialized_tick(ref self: ContractState, pool_key: PoolKey, index: i129) {
            let (word_index, bit_index) = tick_to_word_and_bit_index(index, pool_key.tick_spacing);
            let bitmap = self.tick_bitmaps.read((pool_key, word_index));
            // it is assumed that bitmap does not contain the set bit exp2(bit_index) already
            self.tick_bitmaps.write((pool_key, word_index), bitmap + exp2(bit_index));
        }

        fn update_tick(
            ref self: ContractState,
            pool_key: PoolKey,
            index: i129,
            liquidity_delta: i129,
            is_upper: bool
        ) {
            let tick = self.ticks.read((pool_key, index));

            let next_liquidity_net = tick.liquidity_net.add(liquidity_delta);

            self
                .ticks
                .write(
                    (pool_key, index),
                    Tick {
                        liquidity_delta: if is_upper {
                            tick.liquidity_delta - liquidity_delta
                        } else {
                            tick.liquidity_delta + liquidity_delta
                        },
                        liquidity_net: next_liquidity_net,
                    }
                );

            if ((next_liquidity_net == 0) != (tick.liquidity_net == 0)) {
                if (next_liquidity_net == 0) {
                    self.remove_initialized_tick(pool_key, index);
                } else {
                    self.insert_initialized_tick(pool_key, index);
                }
            };
        }
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
    impl Core of ICore<ContractState> {
        fn set_withdrawal_only_mode(ref self: ContractState) {
            self.withdrawal_only_mode.write(true);
        }

        fn get_fees_collected(self: @ContractState, token: ContractAddress) -> u128 {
            self.fees_collected.read(token)
        }

        fn get_locker_state(self: @ContractState, id: u32) -> LockerState {
            let address = self.locker_addresses.read(id);
            let nonzero_delta_count = self.nonzero_delta_counts.read(id);
            LockerState { address, nonzero_delta_count }
        }

        fn get_pool(self: @ContractState, pool_key: PoolKey) -> GetPoolResult {
            let price = self.get_pool_price(pool_key);
            let liquidity = self.get_pool_liquidity(pool_key);
            let fees_per_liquidity = self.get_pool_fees(pool_key);
            GetPoolResult { price, liquidity, fees_per_liquidity,  }
        }

        fn get_pool_price(self: @ContractState, pool_key: PoolKey) -> PoolPrice {
            self.pool_price.read(pool_key)
        }

        fn get_pool_liquidity(self: @ContractState, pool_key: PoolKey) -> u128 {
            self.pool_liquidity.read(pool_key)
        }

        fn get_pool_fees(self: @ContractState, pool_key: PoolKey) -> FeesPerLiquidity {
            self.pool_fees.read(pool_key)
        }

        fn get_reserves(self: @ContractState, token: ContractAddress) -> u256 {
            self.reserves.read(token)
        }

        fn get_tick(self: @ContractState, pool_key: PoolKey, index: i129) -> Tick {
            self.ticks.read((pool_key, index))
        }

        fn get_tick_fees_outside(
            self: @ContractState, pool_key: PoolKey, index: i129
        ) -> FeesPerLiquidity {
            self.tick_fees_outside.read((pool_key, index))
        }

        fn get_position(
            self: @ContractState, pool_key: PoolKey, position_key: PositionKey
        ) -> GetPositionResult {
            let position: Position = self.positions.read((pool_key, position_key));

            if (position.liquidity.is_zero()) {
                GetPositionResult {
                    liquidity: Zeroable::zero(),
                    fees0: Zeroable::zero(),
                    fees1: Zeroable::zero(),
                    // we can return 0 because it's irrelevant for an empty position
                    fees_per_liquidity_inside_current: Zeroable::zero(),
                }
            } else {
                let fees_per_liquidity_inside = self
                    .get_fees_per_liquidity_inside(pool_key, position_key.bounds);

                let diff = fees_per_liquidity_inside - position.fees_per_liquidity_inside_last;

                // WARNING: we only use the lower 128 bits from this calculation, and if accumulated fees overflow a u128 they are simply discarded
                // we discard the fees instead of asserting because we do not want to fail a withdrawal due to too many fees
                let (amount0_fees, _) = muldiv(
                    diff.fees_per_liquidity_token0.into(),
                    position.liquidity.into(),
                    u256 { high: 1, low: 0 },
                    false
                );

                let (amount1_fees, _) = muldiv(
                    diff.fees_per_liquidity_token1.into(),
                    position.liquidity.into(),
                    u256 { high: 1, low: 0 },
                    false
                );

                GetPositionResult {
                    liquidity: position.liquidity,
                    fees0: amount0_fees.low,
                    fees1: amount1_fees.low,
                    fees_per_liquidity_inside_current: fees_per_liquidity_inside,
                }
            }
        }

        fn get_saved_balance(
            self: @ContractState, owner: ContractAddress, token: ContractAddress, cache_key: u64
        ) -> u128 {
            self.saved_balances.read((owner, token, cache_key))
        }


        fn next_initialized_tick(
            self: @ContractState, pool_key: PoolKey, from: i129, skip_ahead: u128
        ) -> (i129, bool) {
            assert(from < max_tick(), 'NEXT_FROM_MAX');

            let (word_index, bit_index) = tick_to_word_and_bit_index(
                from + i129 { mag: pool_key.tick_spacing, sign: false }, pool_key.tick_spacing
            );

            let bitmap = self.tick_bitmaps.read((pool_key, word_index));
            // for exp2(bit_index) - 1, all bits less significant than bit_index are set (representing ticks greater than current tick)
            // now the next tick is at the most significant bit in the masked bitmap
            let masked = bitmap & mask(bit_index);

            // if it's 0, we know there is no set bit in this word
            if (masked == 0) {
                let next = word_and_bit_index_to_tick((word_index, 0), pool_key.tick_spacing);
                if (next > max_tick()) {
                    return (max_tick(), false);
                }
                if (skip_ahead == 0) {
                    (next, false)
                } else {
                    self.next_initialized_tick(pool_key, next, skip_ahead - 1)
                }
            } else {
                (word_and_bit_index_to_tick((word_index, msb(masked)), pool_key.tick_spacing), true)
            }
        }

        fn prev_initialized_tick(
            self: @ContractState, pool_key: PoolKey, from: i129, skip_ahead: u128
        ) -> (i129, bool) {
            assert(from >= min_tick(), 'PREV_FROM_MIN');
            let (word_index, bit_index) = tick_to_word_and_bit_index(from, pool_key.tick_spacing);

            let bitmap = self.tick_bitmaps.read((pool_key, word_index));

            let mask = ~(exp2(bit_index) - 1); // all bits at or to the left of from are 0

            let masked = bitmap & mask;

            // if it's 0, we know there is no set bit in this word
            if (masked == 0) {
                let prev = word_and_bit_index_to_tick((word_index, 127), pool_key.tick_spacing);
                if (prev < min_tick()) {
                    return (min_tick(), false);
                }
                if (skip_ahead == 0) {
                    (prev, false)
                } else {
                    self
                        .prev_initialized_tick(
                            pool_key, prev - i129 { mag: 1, sign: false }, skip_ahead - 1
                        )
                }
            } else {
                (word_and_bit_index_to_tick((word_index, lsb(masked)), pool_key.tick_spacing), true)
            }
        }

        fn withdraw_fees_collected(
            ref self: ContractState,
            recipient: ContractAddress,
            token: ContractAddress,
            amount: u128
        ) {
            check_owner_only();

            let collected: u128 = self.fees_collected.read(token);
            self.fees_collected.write(token, collected - amount);
            self.reserves.write(token, self.reserves.read(token) - amount.into());

            IERC20Dispatcher { contract_address: token }.transfer(recipient, amount.into());
            self.emit(FeesWithdrawn { recipient, token, amount });
        }

        fn lock(ref self: ContractState, data: Array<felt252>) -> Array<felt252> {
            let id = self.lock_count.read();
            let caller = get_caller_address();

            self.lock_count.write(id + 1);
            self.locker_addresses.write(id, caller);

            let result = ILockerDispatcher { contract_address: caller }.locked(id, data);

            assert(self.nonzero_delta_counts.read(id) == 0, 'NOT_ZEROED');

            self.lock_count.write(id);
            self.locker_addresses.write(id, Zeroable::zero());

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

        fn save(
            ref self: ContractState,
            token_address: ContractAddress,
            cache_key: u64,
            recipient: ContractAddress,
            amount: u128
        ) -> u128 {
            let (id, _) = self.require_locker();

            let saved_balance = self.saved_balances.read((recipient, token_address, cache_key));
            let balance_next = saved_balance + amount;
            self.saved_balances.write((recipient, token_address, cache_key), balance_next);

            // tracks the delta for the given token address
            self.account_delta(id, token_address, i129 { mag: amount, sign: false });

            self
                .emit(
                    SavedBalance {
                        to: recipient, token: token_address, cache_key: cache_key, amount: amount
                    }
                );

            balance_next
        }

        fn deposit(ref self: ContractState, token_address: ContractAddress) -> u128 {
            assert(!self.withdrawal_only_mode.read(), 'WITHDRAWALS_ONLY');

            let (id, _) = self.require_locker();

            let balance = IERC20Dispatcher {
                contract_address: token_address
            }.balanceOf(get_contract_address());

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

        fn load(
            ref self: ContractState, token_address: ContractAddress, cache_key: u64, amount: u128
        ) -> u128 {
            let id = self.get_current_locker_id();
            let caller = get_caller_address();

            let saved_balance = self.saved_balances.read((caller, token_address, cache_key));
            assert(amount <= saved_balance, 'INSUFFICIENT_SAVED_BALANCE');
            let balance_next = saved_balance - amount;
            self.saved_balances.write((caller, token_address, cache_key), balance_next);

            self.account_delta(id, token_address, i129 { mag: amount, sign: true });

            self
                .emit(
                    LoadedBalance {
                        from: caller, token: token_address, cache_key: cache_key, amount: amount
                    }
                );

            balance_next
        }

        fn initialize_pool(ref self: ContractState, pool_key: PoolKey, initial_tick: i129) -> u256 {
            // token0 is always l.t. token1
            assert(pool_key.token0 < pool_key.token1, 'TOKEN_ORDER');
            assert(pool_key.token0.is_non_zero(), 'TOKEN_ZERO');
            assert(
                (pool_key.tick_spacing.is_non_zero())
                    & (pool_key.tick_spacing <= tick_constants::MAX_TICK_SPACING),
                'TICK_SPACING'
            );

            let price = self.pool_price.read(pool_key);
            assert(price.sqrt_ratio.is_zero(), 'ALREADY_INITIALIZED');

            let call_points = if (pool_key.extension.is_non_zero()) {
                IExtensionDispatcher {
                    contract_address: pool_key.extension
                }.before_initialize_pool(get_caller_address(), pool_key, initial_tick)
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
                IExtensionDispatcher {
                    contract_address: pool_key.extension
                }.after_initialize_pool(get_caller_address(), pool_key, initial_tick);
            }

            sqrt_ratio
        }

        fn get_fees_per_liquidity_inside(
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
                    IExtensionDispatcher {
                        contract_address: pool_key.extension
                    }.before_update_position(locker, pool_key, params);
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
            if (params.liquidity_delta.sign) {
                let amount0_fee = compute_fee(delta.amount0.mag, pool_key.fee);
                let amount1_fee = compute_fee(delta.amount1.mag, pool_key.fee);

                let withdrawal_fee_delta = Delta {
                    amount0: i129 {
                        mag: amount0_fee, sign: true
                        }, amount1: i129 {
                        mag: amount1_fee, sign: true
                    },
                };

                if (amount0_fee.is_non_zero()) {
                    self
                        .fees_collected
                        .write(
                            pool_key.token0,
                            accumulate_fee_amount(
                                self.fees_collected.read(pool_key.token0), amount0_fee
                            )
                        );
                }
                if (amount1_fee.is_non_zero()) {
                    self
                        .fees_collected
                        .write(
                            pool_key.token1,
                            accumulate_fee_amount(
                                self.fees_collected.read(pool_key.token1), amount1_fee
                            )
                        );
                }

                delta -= withdrawal_fee_delta;
                self.emit(FeesPaid { pool_key, position_key, delta: withdrawal_fee_delta });
            }

            let get_position_result = self.get_position(pool_key, position_key);

            let position_liquidity_next: u128 = get_position_result
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
                self.positions.write((pool_key, position_key), Default::default());
            }

            self.update_tick(pool_key, params.bounds.lower, params.liquidity_delta, false);
            self.update_tick(pool_key, params.bounds.upper, params.liquidity_delta, true);

            // update pool liquidity if it changed
            if ((price.tick >= params.bounds.lower) & (price.tick < params.bounds.upper)) {
                let liquidity = self.pool_liquidity.read(pool_key);
                self.pool_liquidity.write(pool_key, liquidity.add(params.liquidity_delta));
            }

            // and finally account the computed deltas
            self.account_delta(id, pool_key.token0, delta.amount0);
            self.account_delta(id, pool_key.token1, delta.amount1);

            self.emit(PositionUpdated { locker, pool_key, params, delta });

            if (price.call_points.after_update_position) {
                if (pool_key.extension != locker) {
                    IExtensionDispatcher {
                        contract_address: pool_key.extension
                    }.after_update_position(locker, pool_key, params, delta);
                }
            }

            delta
        }

        fn collect_fees(
            ref self: ContractState, pool_key: PoolKey, salt: u64, bounds: Bounds
        ) -> Delta {
            let (id, locker) = self.require_locker();

            let position_key = PositionKey { owner: locker, salt, bounds };
            let result = self.get_position(pool_key, position_key);

            // update the position
            self
                .positions
                .write(
                    (pool_key, position_key),
                    Position {
                        liquidity: result.liquidity,
                        fees_per_liquidity_inside_last: result.fees_per_liquidity_inside_current,
                    }
                );

            let delta = Delta {
                amount0: i129 {
                    mag: result.fees0, sign: true
                    }, amount1: i129 {
                    mag: result.fees1, sign: true
                },
            };

            self.account_delta(id, pool_key.token0, delta.amount0);
            self.account_delta(id, pool_key.token1, delta.amount1);

            self.emit(PositionFeesCollected { pool_key, position_key, delta });

            delta
        }


        fn swap(ref self: ContractState, pool_key: PoolKey, params: SwapParameters) -> Delta {
            let (id, locker) = self.require_locker();

            let price = self.pool_price.read(pool_key);

            // pool must be initialized
            assert(price.sqrt_ratio.is_non_zero(), 'NOT_INITIALIZED');

            if (price.call_points.before_swap) {
                if (pool_key.extension != locker) {
                    IExtensionDispatcher {
                        contract_address: pool_key.extension
                    }.before_swap(locker, pool_key, params);
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

            let mut liquidity = self.pool_liquidity.read(pool_key);
            let mut calculated_amount: u128 = Zeroable::zero();

            let mut fees_per_liquidity = self.pool_fees.read(pool_key);

            // we need to take a snapshot to call view methods within the loop
            let self_snap = @self;

            loop {
                if (amount_remaining == Zeroable::zero()) {
                    break ();
                }

                if (sqrt_ratio == params.sqrt_ratio_limit) {
                    break ();
                }

                let (next_tick, is_initialized) = if (increasing) {
                    self_snap.next_initialized_tick(pool_key, tick, params.skip_ahead)
                } else {
                    self_snap.prev_initialized_tick(pool_key, tick, params.skip_ahead)
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

                // this only happens when liquidity != 0
                if (swap_result.fee_amount != 0) {
                    fees_per_liquidity = fees_per_liquidity
                        + if (params.is_token1) {
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
                        let tick_data = self.ticks.read((pool_key, next_tick));
                        // update our working liquidity based on the direction we are crossing the tick
                        if (increasing) {
                            liquidity = liquidity.add(tick_data.liquidity_delta);
                        } else {
                            liquidity = liquidity.sub(tick_data.liquidity_delta);
                        }

                        // update the tick fee state
                        self
                            .tick_fees_outside
                            .write(
                                (pool_key, next_tick),
                                fees_per_liquidity
                                    - self.tick_fees_outside.read((pool_key, next_tick))
                            );
                    }
                } else {
                    tick = sqrt_ratio_to_tick(sqrt_ratio);
                };
            };

            let delta = if (params.is_token1) {
                Delta {
                    amount0: i129 {
                        mag: calculated_amount, sign: !params.amount.sign
                    }, amount1: params.amount - amount_remaining
                }
            } else {
                Delta {
                    amount0: params.amount - amount_remaining, amount1: i129 {
                        mag: calculated_amount, sign: !params.amount.sign
                    }
                }
            };

            self
                .pool_price
                .write(pool_key, PoolPrice { sqrt_ratio, tick, call_points: price.call_points });
            self.pool_liquidity.write(pool_key, liquidity);
            self.pool_fees.write(pool_key, fees_per_liquidity);

            self.account_delta(id, pool_key.token0, delta.amount0);
            self.account_delta(id, pool_key.token1, delta.amount1);

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
                    IExtensionDispatcher {
                        contract_address: pool_key.extension
                    }.after_swap(locker, pool_key, params, delta);
                }
            }

            delta
        }
    }
}
