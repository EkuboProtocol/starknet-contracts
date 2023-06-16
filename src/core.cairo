#[starknet::contract]
mod Core {
    use ekubo::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use ekubo::interfaces::core::{
        SwapParameters, UpdatePositionParameters, ILockerDispatcher, ILockerDispatcherTrait,
        LockerState, ICore, IExtensionDispatcher, IExtensionDispatcherTrait, GetPositionResult
    };
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
    use ekubo::math::muldiv::{muldiv};
    use ekubo::math::bitmap::{tick_to_word_and_bit_index, word_and_bit_index_to_tick};
    use ekubo::math::bits::{msb, lsb};
    use ekubo::math::utils::{unsafe_sub, add_delta, ContractAddressOrder, u128_max};
    use ekubo::types::i129::{i129, i129_min, i129_max, i129OptionPartialEq};
    use ekubo::types::storage::{Tick, Position, Pool};
    use ekubo::types::keys::{PositionKey, PoolKey};
    use ekubo::types::bounds::{Bounds, CheckBoundsValidTrait};
    use ekubo::types::delta::{Delta};
    use ekubo::types::call_points::{CallPoints};

    use debug::PrintTrait;


    #[storage]
    struct Storage {
        // the owner is the one who controls withdrawal fees
        owner: ContractAddress,
        // withdrawal fees collected, controlled by the owner
        fees_collected: LegacyMap<ContractAddress, u128>,
        // the last recorded balance of each token, used for checking payment
        reserves: LegacyMap<ContractAddress, u256>,
        // transient state of the lockers, which always starts and ends at zero
        lock_count: felt252,
        locker_addresses: LegacyMap<felt252, ContractAddress>,
        nonzero_delta_counts: LegacyMap::<felt252, felt252>,
        // locker_id, token_address => delta
        // delta is from the perspective of the core contract, thus:
        // a positive delta means the contract is owed tokens, a negative delta means it owes tokens
        deltas: LegacyMap::<(felt252, ContractAddress), i129>,
        // the persistent state of all the pools is stored in these structs
        pools: LegacyMap::<PoolKey, Pool>,
        ticks: LegacyMap::<(PoolKey, i129), Tick>,
        positions: LegacyMap::<(PoolKey, PositionKey), Position>,
        tick_bitmaps: LegacyMap<(PoolKey, u128), u128>,
        // users may save balances in the singleton to avoid transfers, keyed by (owner, token)
        // note a transfer can only be effected by calling load and save to another address
        saved_balances: LegacyMap<(ContractAddress, ContractAddress), u128>,
    }

    #[derive(starknet::Event, Drop)]
    struct OwnerChanged {
        old_owner: ContractAddress,
        new_owner: ContractAddress
    }

    #[derive(starknet::Event, Drop)]
    struct FeesWithdrawn {
        recipient: ContractAddress,
        token: ContractAddress,
        amount: u128
    }

    #[derive(starknet::Event, Drop)]
    struct PoolInitialized {
        pool_key: PoolKey,
        initial_tick: i129
    }

    #[derive(starknet::Event, Drop)]
    struct PositionUpdated {
        pool_key: PoolKey,
        params: UpdatePositionParameters,
        delta: Delta,
    }

    #[derive(starknet::Event, Drop)]
    struct Swapped {
        pool_key: PoolKey,
        params: SwapParameters,
        delta: Delta,
    }

    #[derive(starknet::Event, Drop)]
    #[event]
    enum Event {
        OwnerChanged: OwnerChanged,
        FeesWithdrawn: FeesWithdrawn,
        PoolInitialized: PoolInitialized,
        PositionUpdated: PositionUpdated,
        Swapped: Swapped,
    }


    #[constructor]
    fn constructor(ref self: ContractState) {
        // todo: choose the value for this constant, ideally a multisig and/or timelock
        self.owner.write(contract_address_const::<0x01234567>());
    }

    #[generate_trait]
    impl Internal of InternalTrait {
        fn require_locker(ref self: ContractState) -> (felt252, ContractAddress) {
            let id = self.lock_count.read() - 1;
            let locker = self.locker_addresses.read(id);
            assert(locker == get_caller_address(), 'NOT_LOCKER');
            (id, locker)
        }

        fn account_delta(
            ref self: ContractState, id: felt252, token_address: ContractAddress, delta: i129
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

            let next_liquidity_net = add_delta(tick.liquidity_net, liquidity_delta);

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
                        // we don't ever set these values, because the initial value doesn't matter, only the differences of position snapshots matter
                        fee_growth_outside_token0: tick.fee_growth_outside_token0,
                        fee_growth_outside_token1: tick.fee_growth_outside_token1
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
    impl Core of ICore<ContractState> {
        fn get_owner(self: @ContractState) -> ContractAddress {
            self.owner.read()
        }

        fn get_locker_state(self: @ContractState, id: felt252) -> LockerState {
            let address = self.locker_addresses.read(id);
            let nonzero_delta_count = self.nonzero_delta_counts.read(id);
            LockerState { id, address, nonzero_delta_count }
        }

        fn get_pool(self: @ContractState, pool_key: PoolKey) -> Pool {
            self.pools.read(pool_key)
        }

        fn get_reserves(self: @ContractState, token: ContractAddress) -> u256 {
            self.reserves.read(token)
        }

        fn get_tick(self: @ContractState, pool_key: PoolKey, index: i129) -> Tick {
            self.ticks.read((pool_key, index))
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
                    fee_growth_inside_token0: Zeroable::zero(),
                    fee_growth_inside_token1: Zeroable::zero()
                }
            } else {
                let (fee_growth_inside_token0, fee_growth_inside_token1) = self
                    .get_pool_fee_growth_inside(pool_key, position_key.bounds);

                // WARNING: we only use the lower 128 bits from this calculation, and if accumulated fees overflow a u128 they are simply discarded
                // we discard the fees instead of asserting because we do not want to fail a withdrawal due to too many fees
                let (amount0_fees, _) = muldiv(
                    unsafe_sub(fee_growth_inside_token0, position.fee_growth_inside_last_token0),
                    u256 { low: position.liquidity, high: 0 },
                    u256 { high: 1, low: 0 },
                    false
                );

                let (amount1_fees, _) = muldiv(
                    unsafe_sub(fee_growth_inside_token1, position.fee_growth_inside_last_token1),
                    u256 { low: position.liquidity, high: 0 },
                    u256 { high: 1, low: 0 },
                    false
                );

                GetPositionResult {
                    liquidity: position.liquidity,
                    fees0: amount0_fees.low,
                    fees1: amount1_fees.low,
                    fee_growth_inside_token0,
                    fee_growth_inside_token1
                }
            }
        }

        fn get_saved_balance(
            self: @ContractState, owner: ContractAddress, token: ContractAddress
        ) -> u128 {
            self.saved_balances.read((owner, token))
        }

        fn set_owner(ref self: ContractState, new_owner: ContractAddress) {
            let old_owner = self.owner.read();
            assert(get_caller_address() == old_owner, 'OWNER_ONLY');
            self.owner.write(new_owner);
            self.emit(Event::OwnerChanged(OwnerChanged { old_owner, new_owner }));
        }

        fn replace_class_hash(ref self: ContractState, class_hash: ClassHash) {
            assert(get_caller_address() == self.owner.read(), 'OWNER_ONLY');
            replace_class_syscall(class_hash);
        }

        fn withdraw_fees_collected(
            ref self: ContractState,
            recipient: ContractAddress,
            token: ContractAddress,
            amount: u128
        ) {
            let collected: u128 = self.fees_collected.read(token);
            self.fees_collected.write(token, collected - amount);
            IERC20Dispatcher {
                contract_address: token
            }.transfer(recipient, u256 { low: amount, high: 0 });
            self.emit(Event::FeesWithdrawn(FeesWithdrawn { recipient, token, amount }));
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
            assert(res >= u256 { low: amount, high: 0 }, 'INSUFFICIENT_RESERVES');
            self.reserves.write(token_address, res - u256 { high: 0, low: amount });

            // tracks the delta for the given token address
            self.account_delta(id, token_address, i129 { mag: amount, sign: false });

            IERC20Dispatcher {
                contract_address: token_address
            }.transfer(recipient, u256 { low: amount, high: 0 });
        }

        fn save(
            ref self: ContractState,
            token_address: ContractAddress,
            recipient: ContractAddress,
            amount: u128
        ) {
            let (id, _) = self.require_locker();

            let saved_balance = self.saved_balances.read((recipient, token_address));
            self.saved_balances.write((recipient, token_address), saved_balance + amount);

            // tracks the delta for the given token address
            self.account_delta(id, token_address, i129 { mag: amount, sign: false });
        }

        fn deposit(ref self: ContractState, token_address: ContractAddress) -> u128 {
            let (id, _) = self.require_locker();

            let balance = IERC20Dispatcher {
                contract_address: token_address
            }.balance_of(get_contract_address());

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

        fn load(ref self: ContractState, token_address: ContractAddress, amount: u128) {
            let (id, locker) = self.require_locker();

            let saved_balance = self.saved_balances.read((locker, token_address));
            self.saved_balances.write((locker, token_address), saved_balance - amount);

            self.account_delta(id, token_address, i129 { mag: amount, sign: true });
        }

        fn initialize_pool(ref self: ContractState, pool_key: PoolKey, initial_tick: i129) {
            // token0 is always l.t. token1
            assert(pool_key.token0 < pool_key.token1, 'TOKEN_ORDER');
            assert(pool_key.token0.is_non_zero(), 'TOKEN_ZERO');
            assert(
                (pool_key.tick_spacing.is_non_zero())
                    & (pool_key.tick_spacing < tick_constants::TICKS_IN_DOUBLE_SQRT_RATIO),
                'TICK_SPACING'
            );

            let pool = self.pools.read(pool_key);
            assert(pool.sqrt_ratio.is_zero(), 'ALREADY_INITIALIZED');

            let call_points = if (pool_key.extension.is_non_zero()) {
                IExtensionDispatcher {
                    contract_address: pool_key.extension
                }.before_initialize_pool(pool_key, initial_tick)
            } else {
                Default::<CallPoints>::default()
            };

            self
                .pools
                .write(
                    pool_key,
                    Pool {
                        sqrt_ratio: tick_to_sqrt_ratio(initial_tick),
                        tick: initial_tick,
                        call_points,
                        liquidity: Zeroable::zero(),
                        fee_growth_global_token0: Zeroable::zero(),
                        fee_growth_global_token1: Zeroable::zero(),
                    }
                );

            if (call_points.after_initialize_pool) {
                IExtensionDispatcher {
                    contract_address: pool_key.extension
                }.after_initialize_pool(pool_key, initial_tick);
            }

            self.emit(Event::PoolInitialized(PoolInitialized { pool_key, initial_tick }));
        }

        fn next_initialized_tick(
            ref self: ContractState, pool_key: PoolKey, from: i129, skip_ahead: u128
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
            ref self: ContractState, pool_key: PoolKey, from: i129, skip_ahead: u128
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

        fn get_pool_fee_growth_inside(
            self: @ContractState, pool_key: PoolKey, bounds: Bounds
        ) -> (u256, u256) {
            let pool = self.pools.read(pool_key);
            assert(pool.sqrt_ratio.is_non_zero(), 'NOT_INITIALIZED');

            if (pool.tick < bounds.tick_lower) {
                let tick_lower_state = self.ticks.read((pool_key, bounds.tick_lower));
                (
                    unsafe_sub(
                        pool.fee_growth_global_token0, tick_lower_state.fee_growth_outside_token0
                    ),
                    unsafe_sub(
                        pool.fee_growth_global_token1, tick_lower_state.fee_growth_outside_token1
                    )
                )
            } else if (pool.tick < bounds.tick_upper) {
                let tick_lower_state = self.ticks.read((pool_key, bounds.tick_lower));
                let tick_upper_state = self.ticks.read((pool_key, bounds.tick_upper));

                (
                    unsafe_sub(
                        unsafe_sub(
                            pool.fee_growth_global_token0,
                            tick_lower_state.fee_growth_outside_token0
                        ),
                        tick_upper_state.fee_growth_outside_token0
                    ),
                    unsafe_sub(
                        unsafe_sub(
                            pool.fee_growth_global_token1,
                            tick_lower_state.fee_growth_outside_token1
                        ),
                        tick_upper_state.fee_growth_outside_token1
                    )
                )
            } else {
                let tick_upper_state = self.ticks.read((pool_key, bounds.tick_upper));
                (
                    unsafe_sub(
                        pool.fee_growth_global_token0, tick_upper_state.fee_growth_outside_token0
                    ),
                    unsafe_sub(
                        pool.fee_growth_global_token1, tick_upper_state.fee_growth_outside_token1
                    )
                )
            }
        }

        fn update_position(
            ref self: ContractState, pool_key: PoolKey, params: UpdatePositionParameters
        ) -> Delta {
            let (id, locker) = self.require_locker();

            let pool = self.pools.read(pool_key);

            if (pool.call_points.before_update_position) {
                IExtensionDispatcher {
                    contract_address: pool_key.extension
                }.before_update_position(pool_key, params);
            }

            params.bounds.check_valid(pool_key.tick_spacing);

            // pool must be initialized
            assert(pool.sqrt_ratio != Zeroable::zero(), 'NOT_INITIALIZED');

            let (sqrt_ratio_lower, sqrt_ratio_upper) = (
                tick_to_sqrt_ratio(params.bounds.tick_lower),
                tick_to_sqrt_ratio(params.bounds.tick_upper)
            );

            // compute the amount deltas due to the liquidity delta
            let mut delta = liquidity_delta_to_amount_delta(
                pool.sqrt_ratio, params.liquidity_delta, sqrt_ratio_lower, sqrt_ratio_upper
            );

            // account the withdrawal protocol fee, because it's based on the deltas
            if (params.liquidity_delta.sign) {
                let amount0_fee = compute_fee(delta.amount0.mag, pool_key.fee);
                let amount1_fee = compute_fee(delta.amount1.mag, pool_key.fee);

                delta += Delta {
                    amount0: i129 {
                        mag: amount0_fee, sign: false
                        }, amount1: i129 {
                        mag: amount1_fee, sign: false
                    },
                };

                self
                    .fees_collected
                    .write(
                        pool_key.token0,
                        accumulate_fee_amount(
                            self.fees_collected.read(pool_key.token0), amount0_fee
                        )
                    );
                self
                    .fees_collected
                    .write(
                        pool_key.token1,
                        accumulate_fee_amount(
                            self.fees_collected.read(pool_key.token1), amount1_fee
                        )
                    );
            }

            // here we are accumulating fees owed to the position based on its current liquidity
            let position_key = PositionKey {
                owner: locker, salt: params.salt, bounds: params.bounds
            };
            let get_position_result = self.get_position(pool_key, position_key);

            let position_liquidity_next: u128 = add_delta(
                get_position_result.liquidity, params.liquidity_delta
            );

            let (fee_growth_inside_token0_next, fee_growth_inside_token1_next) =
                if (position_liquidity_next
                .is_zero()) {
                assert(
                    (get_position_result.fees0.is_zero()) & (get_position_result.fees0.is_zero()),
                    'MUST_COLLECT_FEES'
                );
                (Zeroable::zero(), Zeroable::zero())
            } else {
                (
                    unsafe_sub(
                        pool.fee_growth_global_token0,
                        u256 {
                            high: get_position_result.fees0, low: 0
                            } / u256 {
                            low: position_liquidity_next, high: 0
                        }
                    ),
                    unsafe_sub(
                        pool.fee_growth_global_token1,
                        u256 {
                            high: get_position_result.fees1, low: 0
                            } / u256 {
                            low: position_liquidity_next, high: 0
                        }
                    )
                )
            };

            // update the position
            self
                .positions
                .write(
                    (pool_key, position_key),
                    Position {
                        liquidity: position_liquidity_next,
                        fee_growth_inside_last_token0: fee_growth_inside_token0_next,
                        fee_growth_inside_last_token1: fee_growth_inside_token1_next,
                    }
                );

            self.update_tick(pool_key, params.bounds.tick_lower, params.liquidity_delta, false);
            self.update_tick(pool_key, params.bounds.tick_upper, params.liquidity_delta, true);

            // update pool liquidity if it changed
            if ((pool.tick >= params.bounds.tick_lower) & (pool.tick < params.bounds.tick_upper)) {
                self
                    .pools
                    .write(
                        pool_key,
                        Pool {
                            sqrt_ratio: pool.sqrt_ratio,
                            tick: pool.tick,
                            call_points: pool.call_points,
                            liquidity: add_delta(pool.liquidity, params.liquidity_delta),
                            fee_growth_global_token0: pool.fee_growth_global_token0,
                            fee_growth_global_token1: pool.fee_growth_global_token1
                        }
                    );
            }

            // and finally account the computed deltas
            self.account_delta(id, pool_key.token0, delta.amount0);
            self.account_delta(id, pool_key.token1, delta.amount1);

            self.emit(Event::PositionUpdated(PositionUpdated { pool_key, params, delta }));

            if (pool.call_points.after_update_position) {
                IExtensionDispatcher {
                    contract_address: pool_key.extension
                }.after_update_position(pool_key, params, delta);
            }

            delta
        }

        fn collect_fees(
            ref self: ContractState, pool_key: PoolKey, salt: felt252, bounds: Bounds
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
                        fee_growth_inside_last_token0: result.fee_growth_inside_token0,
                        fee_growth_inside_last_token1: result.fee_growth_inside_token1,
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

            delta
        }


        fn swap(ref self: ContractState, pool_key: PoolKey, params: SwapParameters) -> Delta {
            let (id, _) = self.require_locker();

            let pool = self.pools.read(pool_key);

            // pool must be initialized
            assert(pool.sqrt_ratio != Zeroable::zero(), 'NOT_INITIALIZED');

            if (pool.call_points.before_swap) {
                IExtensionDispatcher {
                    contract_address: pool_key.extension
                }.before_swap(pool_key, params);
            }

            let increasing = is_price_increasing(params.amount.sign, params.is_token1);

            // check the limit is not in the wrong direction and is within the price bounds
            assert((params.sqrt_ratio_limit > pool.sqrt_ratio) == increasing, 'LIMIT_DIRECTION');
            assert(
                (params.sqrt_ratio_limit >= min_sqrt_ratio())
                    & (params.sqrt_ratio_limit <= max_sqrt_ratio()),
                'LIMIT_MAG'
            );

            let mut tick = pool.tick;
            let mut amount_remaining = params.amount;
            let mut sqrt_ratio = pool.sqrt_ratio;
            let mut liquidity = pool.liquidity;
            let mut calculated_amount: u128 = Zeroable::zero();
            let mut fee_growth_global = if params.is_token1 {
                pool.fee_growth_global_token1
            } else {
                pool.fee_growth_global_token0
            };

            loop {
                if (amount_remaining == Zeroable::zero()) {
                    break ();
                }

                if (sqrt_ratio == params.sqrt_ratio_limit) {
                    break ();
                }

                let (next_tick, is_initialized) = if (increasing) {
                    self.next_initialized_tick(pool_key, tick, params.skip_ahead)
                } else {
                    self.prev_initialized_tick(pool_key, tick, params.skip_ahead)
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
                    fee_growth_global += u256 {
                        low: 0, high: swap_result.fee_amount
                        } / u256 {
                        low: liquidity, high: 0
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
                            liquidity = add_delta(liquidity, tick_data.liquidity_delta);
                        } else {
                            liquidity = add_delta(liquidity, -tick_data.liquidity_delta);
                        }

                        let (fee_growth_outside_token0, fee_growth_outside_token1) = if (params
                            .is_token1) {
                            (
                                unsafe_sub(
                                    pool.fee_growth_global_token0,
                                    tick_data.fee_growth_outside_token0
                                ),
                                unsafe_sub(fee_growth_global, tick_data.fee_growth_outside_token1)
                            )
                        } else {
                            (
                                unsafe_sub(fee_growth_global, tick_data.fee_growth_outside_token0),
                                unsafe_sub(
                                    pool.fee_growth_global_token1,
                                    tick_data.fee_growth_outside_token1
                                )
                            )
                        };

                        // update the tick fee state
                        self
                            .ticks
                            .write(
                                (pool_key, next_tick),
                                Tick {
                                    liquidity_delta: tick_data.liquidity_delta,
                                    liquidity_net: tick_data.liquidity_net,
                                    fee_growth_outside_token0,
                                    fee_growth_outside_token1
                                }
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

            let (fee_growth_global_token0_next, fee_growth_global_token1_next) = if params
                .is_token1 {
                (pool.fee_growth_global_token0, fee_growth_global)
            } else {
                (fee_growth_global, pool.fee_growth_global_token1)
            };

            self
                .pools
                .write(
                    pool_key,
                    Pool {
                        sqrt_ratio,
                        tick,
                        call_points: pool.call_points,
                        liquidity,
                        fee_growth_global_token0: fee_growth_global_token0_next,
                        fee_growth_global_token1: fee_growth_global_token1_next,
                    }
                );

            self.account_delta(id, pool_key.token0, delta.amount0);
            self.account_delta(id, pool_key.token1, delta.amount1);

            self.emit(Event::Swapped(Swapped { pool_key, params, delta }));

            if (pool.call_points.after_swap) {
                IExtensionDispatcher {
                    contract_address: pool_key.extension
                }.after_swap(pool_key, params, delta);
            }

            delta
        }
    }
}
