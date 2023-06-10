#[contract]
mod Core {
    use ekubo::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use ekubo::interfaces::core::{
        Delta, SwapParameters, UpdatePositionParameters, ILockerDispatcher, ILockerDispatcherTrait,
        LockerState
    };
    use starknet::{
        ContractAddress, contract_address_const, get_caller_address, get_contract_address
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
    use ekubo::math::muldiv::muldiv;
    use ekubo::math::exp2::{exp2};
    use ekubo::math::mask::{mask};
    use ekubo::math::bitmap::{tick_to_word_and_bit_index, word_and_bit_index_to_tick};
    use ekubo::math::bits::{msb_low, lsb_low};
    use ekubo::math::utils::{unsafe_sub, add_delta, ContractAddressOrder, u128_max};
    use ekubo::types::i129::{i129, i129_min, i129_max, i129OptionPartialEq};
    use ekubo::types::storage::{Tick, Position, Pool};
    use ekubo::types::keys::{PositionKey, PoolKey};

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
        saved_balances: LegacyMap<(ContractAddress, ContractAddress), u128>,
    }

    #[event]
    fn OwnerChanged(old_owner: ContractAddress, new_owner: ContractAddress) {}

    #[event]
    fn FeesWithdrawn(recipient: ContractAddress, token: ContractAddress, amount: u128) {}

    #[event]
    fn PoolInitialized(pool_key: PoolKey, initial_tick: i129) {}

    #[event]
    fn PositionUpdated(pool_key: PoolKey, position_key: PositionKey, liquidity_delta: i129) {}

    #[constructor]
    fn constructor(_owner: ContractAddress) {
        owner::write(_owner);
    }

    #[view]
    fn get_owner() -> ContractAddress {
        owner::read()
    }


    #[view]
    fn get_locker_state(id: felt252) -> LockerState {
        let address = locker_addresses::read(id);
        let nonzero_delta_count = nonzero_delta_counts::read(id);
        LockerState { id, address, nonzero_delta_count }
    }

    #[view]
    fn get_pool(pool_key: PoolKey) -> Pool {
        pools::read(pool_key)
    }

    #[view]
    fn get_reserves(token: ContractAddress) -> u256 {
        reserves::read(token)
    }

    #[view]
    fn get_tick(pool_key: PoolKey, index: i129) -> Tick {
        ticks::read((pool_key, index))
    }

    #[view]
    fn get_position(pool_key: PoolKey, position_key: PositionKey) -> Position {
        positions::read((pool_key, position_key))
    }

    #[view]
    fn get_saved_balance(owner: ContractAddress, token: ContractAddress) -> u128 {
        saved_balances::read((owner, token))
    }

    #[external]
    fn set_owner(new_owner: ContractAddress) {
        let old_owner = owner::read();
        assert(get_caller_address() == old_owner, 'OWNER_ONLY');
        owner::write(new_owner);
        OwnerChanged(old_owner, new_owner);
    }

    #[external]
    fn withdraw_fees_collected(recipient: ContractAddress, token: ContractAddress, amount: u128) {
        let collected: u128 = fees_collected::read(token);
        fees_collected::write(token, collected - amount);
        IERC20Dispatcher {
            contract_address: token
        }.transfer(recipient, u256 { low: amount, high: 0 });
        FeesWithdrawn(recipient, token, amount);
    }

    #[external]
    fn lock(data: Array<felt252>) -> Array<felt252> {
        let id = lock_count::read();
        let caller = get_caller_address();

        lock_count::write(id + 1);
        locker_addresses::write(id, caller);

        let result = ILockerDispatcher { contract_address: caller }.locked(id, data);

        assert(nonzero_delta_counts::read(id) == 0, 'NOT_ZEROED');

        lock_count::write(id);
        locker_addresses::write(id, contract_address_const::<0>());

        result
    }

    #[internal]
    fn require_locker() -> (felt252, ContractAddress) {
        let id = lock_count::read() - 1;
        let locker = locker_addresses::read(id);
        assert(locker == get_caller_address(), 'NOT_LOCKER');
        (id, locker)
    }

    #[internal]
    fn account_delta(id: felt252, token_address: ContractAddress, delta: i129) {
        let key = (id, token_address);
        let current = deltas::read(key);
        let next = current + delta;
        deltas::write(key, next);
        if ((current.mag == 0) & (next.mag != 0)) {
            nonzero_delta_counts::write(id, nonzero_delta_counts::read(id) + 1);
        } else if ((current.mag != 0) & (next.mag == 0)) {
            nonzero_delta_counts::write(id, nonzero_delta_counts::read(id) - 1);
        }
    }

    #[external]
    fn withdraw(token_address: ContractAddress, recipient: ContractAddress, amount: u128) {
        let (id, _) = require_locker();

        let res = reserves::read(token_address);
        assert(res >= u256 { low: amount, high: 0 }, 'INSUFFICIENT_RESERVES');
        reserves::write(token_address, res - u256 { high: 0, low: amount });

        // tracks the delta for the given token address
        account_delta(id, token_address, i129 { mag: amount, sign: false });

        IERC20Dispatcher {
            contract_address: token_address
        }.transfer(recipient, u256 { low: amount, high: 0 });
    }

    #[external]
    fn save(token_address: ContractAddress, recipient: ContractAddress, amount: u128) {
        let (id, _) = require_locker();

        let saved_balance = saved_balances::read((recipient, token_address));
        saved_balances::write((recipient, token_address), saved_balance + amount);

        // tracks the delta for the given token address
        account_delta(id, token_address, i129 { mag: amount, sign: false });
    }

    #[external]
    fn deposit(token_address: ContractAddress) -> u128 {
        let (id, _) = require_locker();

        let balance = IERC20Dispatcher {
            contract_address: token_address
        }.balance_of(get_contract_address());

        let reserve = reserves::read(token_address);
        // should never happen, assuming token is well-behaving, e.g. not rebasing or collecting fees on transfers from sender
        assert(balance >= reserve, 'BALANCE_LT_RESERVE');
        let delta = balance - reserve;
        // the delta is limited to u128
        assert(delta.high == 0, 'DELTA_EXCEEDED_MAX');

        account_delta(id, token_address, i129 { mag: delta.low, sign: true });

        reserves::write(token_address, balance);

        delta.low
    }

    #[external]
    fn load(token_address: ContractAddress, amount: u128) {
        let (id, locker) = require_locker();

        let saved_balance = saved_balances::read((locker, token_address));
        saved_balances::write((locker, token_address), saved_balance - amount);

        account_delta(id, token_address, i129 { mag: amount, sign: true });
    }

    #[external]
    fn initialize_pool(pool_key: PoolKey, initial_tick: i129) {
        // token0 is always l.t. token1
        assert(pool_key.token0 < pool_key.token1, 'TOKEN_ORDER');
        assert(pool_key.token0 != contract_address_const::<0>(), 'TOKEN_ZERO');
        assert(
            (pool_key.tick_spacing != Default::default())
                & (pool_key.tick_spacing < tick_constants::TICKS_IN_DOUBLE_SQRT_RATIO),
            'TICK_SPACING'
        );

        let pool = pools::read(pool_key);
        assert(pool.sqrt_ratio == Default::default(), 'ALREADY_INITIALIZED');

        pools::write(
            pool_key,
            Pool {
                sqrt_ratio: tick_to_sqrt_ratio(initial_tick),
                tick: initial_tick,
                liquidity: Default::default(),
                fee_growth_global_token0: Default::default(),
                fee_growth_global_token1: Default::default(),
            }
        );

        PoolInitialized(pool_key, initial_tick);
    }


    // Remove the initialized tick for the given pool
    #[internal]
    fn remove_initialized_tick(pool_key: PoolKey, index: i129) {
        let (word_index, bit_index) = tick_to_word_and_bit_index(index, pool_key.tick_spacing);
        let bitmap = tick_bitmaps::read((pool_key, word_index));
        // it is assumed that bitmap already contains the set bit exp2(bit_index)
        tick_bitmaps::write((pool_key, word_index), bitmap - exp2(bit_index));
    }

    // Insert an initialized tick for the given pool
    #[internal]
    fn insert_initialized_tick(pool_key: PoolKey, index: i129) {
        let (word_index, bit_index) = tick_to_word_and_bit_index(index, pool_key.tick_spacing);
        let bitmap = tick_bitmaps::read((pool_key, word_index));
        // it is assumed that bitmap does not contain the set bit exp2(bit_index) already
        tick_bitmaps::write((pool_key, word_index), bitmap + exp2(bit_index));
    }

    // Returns the tick > from to iterate towards that may or may not be initialized
    #[external]
    fn next_initialized_tick(pool_key: PoolKey, from: i129, skip_ahead: u128) -> (i129, bool) {
        let (word_index, bit_index) = tick_to_word_and_bit_index(
            from + i129 { mag: pool_key.tick_spacing, sign: false }, pool_key.tick_spacing
        );

        let bitmap = tick_bitmaps::read((pool_key, word_index));
        // for exp2(bit_index) - 1, all bits less significant than bit_index are set (representing ticks greater than current tick)
        // now the next tick is at the most significant bit in the masked bitmap
        let masked = bitmap & mask(bit_index);

        // if it's 0, we know there is no set bit in this word
        if (masked == 0) {
            let next = word_and_bit_index_to_tick((word_index, 0), pool_key.tick_spacing);
            if (skip_ahead == 0) {
                (next, false)
            } else {
                next_initialized_tick(pool_key, next, skip_ahead - 1)
            }
        } else {
            (word_and_bit_index_to_tick((word_index, msb_low(masked)), pool_key.tick_spacing), true)
        }
    }

    // Returns the next tick <= from to iterate towards
    #[external]
    fn prev_initialized_tick(pool_key: PoolKey, from: i129, skip_ahead: u128) -> (i129, bool) {
        let (word_index, bit_index) = tick_to_word_and_bit_index(from, pool_key.tick_spacing);

        let bitmap = tick_bitmaps::read((pool_key, word_index));

        let mask = ~(exp2(bit_index) - 1); // all bits at or to the left of from are 0

        let masked = bitmap & mask;

        // if it's 0, we know there is no set bit in this word
        if (masked == 0) {
            let prev = word_and_bit_index_to_tick((word_index, 127), pool_key.tick_spacing);
            if (skip_ahead == 0) {
                (prev, false)
            } else {
                prev_initialized_tick(pool_key, prev - i129 { mag: 1, sign: false }, skip_ahead - 1)
            }
        } else {
            (word_and_bit_index_to_tick((word_index, lsb_low(masked)), pool_key.tick_spacing), true)
        }
    }

    #[internal]
    fn update_tick(pool_key: PoolKey, index: i129, liquidity_delta: i129, is_upper: bool) {
        let tick = ticks::read((pool_key, index));

        let next_liquidity_net = add_delta(tick.liquidity_net, liquidity_delta);

        ticks::write(
            (pool_key, index),
            Tick {
                liquidity_delta: if is_upper {
                    tick.liquidity_delta - liquidity_delta
                } else {
                    tick.liquidity_delta + liquidity_delta
                },
                liquidity_net: next_liquidity_net,
                fee_growth_outside_token0: tick.fee_growth_outside_token0,
                fee_growth_outside_token1: tick.fee_growth_outside_token1
            }
        );

        if ((next_liquidity_net == 0) ^ (tick.liquidity_net == 0)) {
            if (next_liquidity_net == 0) {
                remove_initialized_tick(pool_key, index);
            } else {
                insert_initialized_tick(pool_key, index);
            }
        };
    }

    #[view]
    fn get_pool_fee_growth_inside(
        pool_key: PoolKey, tick_lower: i129, tick_upper: i129
    ) -> (u256, u256) {
        let pool = pools::read(pool_key);
        assert(pool.sqrt_ratio != u256 { low: 0, high: 0 }, 'NOT_INITIALIZED');

        let (fee_growth_inside_token0, fee_growth_inside_token1, _) = get_fee_growth_inside(
            pool_key,
            pool.tick,
            pool.fee_growth_global_token0,
            pool.fee_growth_global_token1,
            tick_lower,
            tick_upper
        );

        (fee_growth_inside_token0, fee_growth_inside_token1)
    }

    #[internal]
    fn get_fee_growth_inside(
        pool_key: PoolKey,
        pool_tick: i129,
        pool_fee_growth_global_token0: u256,
        pool_fee_growth_global_token1: u256,
        tick_lower: i129,
        tick_upper: i129
    ) -> (u256, u256, bool) {
        if (pool_tick < tick_lower) {
            let tick_lower_state = ticks::read((pool_key, tick_lower));
            (
                unsafe_sub(
                    pool_fee_growth_global_token0, tick_lower_state.fee_growth_outside_token0
                ),
                unsafe_sub(
                    pool_fee_growth_global_token1, tick_lower_state.fee_growth_outside_token1
                ),
                false
            )
        } else if (pool_tick < tick_upper) {
            let tick_lower_state = ticks::read((pool_key, tick_lower));
            let tick_upper_state = ticks::read((pool_key, tick_upper));

            (
                unsafe_sub(
                    unsafe_sub(
                        pool_fee_growth_global_token0, tick_lower_state.fee_growth_outside_token0
                    ),
                    tick_upper_state.fee_growth_outside_token0
                ),
                unsafe_sub(
                    unsafe_sub(
                        pool_fee_growth_global_token1, tick_lower_state.fee_growth_outside_token1
                    ),
                    tick_upper_state.fee_growth_outside_token1
                ),
                true
            )
        } else {
            let tick_upper_state = ticks::read((pool_key, tick_upper));
            (
                unsafe_sub(
                    pool_fee_growth_global_token0, tick_upper_state.fee_growth_outside_token0
                ),
                unsafe_sub(
                    pool_fee_growth_global_token1, tick_upper_state.fee_growth_outside_token1
                ),
                false
            )
        }
    }

    #[external]
    fn update_position(pool_key: PoolKey, params: UpdatePositionParameters) -> Delta {
        let (id, locker) = require_locker();

        assert(params.tick_lower < params.tick_upper, 'ORDER');
        assert(params.tick_lower >= min_tick(), 'MIN');
        assert(params.tick_upper <= max_tick(), 'MAX');
        assert(
            ((params.tick_lower.mag % pool_key.tick_spacing) == 0)
                & ((params.tick_upper.mag % pool_key.tick_spacing) == 0),
            'TICK_SPACING'
        );

        let pool = pools::read(pool_key);

        // pool must be initialized
        assert(pool.sqrt_ratio != Default::default(), 'NOT_INITIALIZED');

        let (sqrt_ratio_lower, sqrt_ratio_upper) = (
            tick_to_sqrt_ratio(params.tick_lower), tick_to_sqrt_ratio(params.tick_upper)
        );

        // first compute the amount deltas due to the liquidity delta
        let (mut amount0_delta, mut amount1_delta) = liquidity_delta_to_amount_delta(
            pool.sqrt_ratio, params.liquidity_delta, sqrt_ratio_lower, sqrt_ratio_upper
        );

        // first, account the withdrawal protocol fee, because it's based on the deltas
        if (params.liquidity_delta.sign) {
            let amount0_fee = compute_fee(amount0_delta.mag, pool_key.fee);
            let amount1_fee = compute_fee(amount1_delta.mag, pool_key.fee);

            amount0_delta += i129 { mag: amount0_fee, sign: false };
            amount1_delta += i129 { mag: amount1_fee, sign: false };

            fees_collected::write(
                pool_key.token0,
                accumulate_fee_amount(fees_collected::read(pool_key.token0), amount0_fee)
            );
            fees_collected::write(
                pool_key.token1,
                accumulate_fee_amount(fees_collected::read(pool_key.token1), amount1_fee)
            );
        }

        let (fee_growth_inside_token0, fee_growth_inside_token1, add_delta) = get_fee_growth_inside(
            pool_key,
            pool.tick,
            pool.fee_growth_global_token0,
            pool.fee_growth_global_token1,
            params.tick_lower,
            params.tick_upper
        );

        let pool_liquidity_next: u128 = if (add_delta) {
            add_delta(pool.liquidity, params.liquidity_delta)
        } else {
            pool.liquidity
        };

        // here we are accumulating fees owed to the position based on its current liquidity
        let position_key = PositionKey {
            owner: locker, tick_lower: params.tick_lower, tick_upper: params.tick_upper
        };
        let position: Position = positions::read((pool_key, position_key));

        let amount0_fees = muldiv(
            unsafe_sub(fee_growth_inside_token0, position.fee_growth_inside_last_token0),
            u256 { low: position.liquidity, high: 0 },
            u256 { low: 0, high: 1 },
            false
        )
            .low;
        let amount1_fees = muldiv(
            unsafe_sub(fee_growth_inside_token1, position.fee_growth_inside_last_token1),
            u256 { low: position.liquidity, high: 0 },
            u256 { low: 0, high: 1 },
            false
        )
            .low;

        amount0_delta += i129 { mag: amount0_fees, sign: true };
        amount1_delta += i129 { mag: amount1_fees, sign: true };

        // update the position
        positions::write(
            (pool_key, position_key),
            Position {
                liquidity: add_delta(position.liquidity, params.liquidity_delta),
                fee_growth_inside_last_token0: fee_growth_inside_token0,
                fee_growth_inside_last_token1: fee_growth_inside_token1
            }
        );

        // update each tick, and recompute the root tick if necessary
        update_tick(pool_key, params.tick_lower, params.liquidity_delta, false);

        update_tick(pool_key, params.tick_upper, params.liquidity_delta, true);

        // update pool liquidity if it changed
        if (pool_liquidity_next != pool.liquidity) {
            pools::write(
                pool_key,
                Pool {
                    sqrt_ratio: pool.sqrt_ratio,
                    tick: pool.tick,
                    liquidity: pool_liquidity_next,
                    fee_growth_global_token0: pool.fee_growth_global_token0,
                    fee_growth_global_token1: pool.fee_growth_global_token1
                }
            );
        }

        // and finally account the computed deltas
        account_delta(id, pool_key.token0, amount0_delta);
        account_delta(id, pool_key.token1, amount1_delta);

        PositionUpdated(pool_key, position_key, params.liquidity_delta);

        Delta { amount0_delta, amount1_delta }
    }

    use debug::PrintTrait;

    #[external]
    fn swap(pool_key: PoolKey, params: SwapParameters) -> Delta {
        let (id, _) = require_locker();

        let pool = pools::read(pool_key);

        // pool must be initialized
        assert(pool.sqrt_ratio != Default::default(), 'NOT_INITIALIZED');

        let increasing = is_price_increasing(params.amount.sign, params.is_token1);

        // check the limit is not in the wrong direction and is within the price bounds
        assert((params.sqrt_ratio_limit > pool.sqrt_ratio) == increasing, 'LIMIT_DIRECTION');
        assert(
            (params.sqrt_ratio_limit >= min_sqrt_ratio())
                & params.sqrt_ratio_limit <= max_sqrt_ratio(),
            'LIMIT_MAG'
        );

        let mut tick = pool.tick;
        let mut amount_remaining = params.amount;
        let mut sqrt_ratio = pool.sqrt_ratio;
        let mut liquidity = pool.liquidity;
        let mut calculated_amount: u128 = Default::default();
        let mut fee_growth_global = if params.is_token1 {
            pool.fee_growth_global_token1
        } else {
            pool.fee_growth_global_token0
        };

        loop {
            if (amount_remaining == Default::default()) {
                break ();
            }

            if (sqrt_ratio == params.sqrt_ratio_limit) {
                break ();
            }

            let (next_tick, is_initialized) = if (increasing) {
                next_initialized_tick(pool_key, tick, params.skip_ahead)
            } else {
                prev_initialized_tick(pool_key, tick, params.skip_ahead)
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

            if (liquidity != 0) {
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
                    let tick_data = ticks::read((pool_key, next_tick));
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
                                pool.fee_growth_global_token0, tick_data.fee_growth_outside_token0
                            ),
                            unsafe_sub(fee_growth_global, tick_data.fee_growth_outside_token1)
                        )
                    } else {
                        (
                            unsafe_sub(fee_growth_global, tick_data.fee_growth_outside_token0),
                            unsafe_sub(
                                pool.fee_growth_global_token1, tick_data.fee_growth_outside_token1
                            )
                        )
                    };

                    // update the tick fee state
                    ticks::write(
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

        let (amount0_delta, amount1_delta) = if (params.is_token1) {
            (
                i129 {
                    mag: calculated_amount, sign: !params.amount.sign
                }, params.amount - amount_remaining
            )
        } else {
            (
                params.amount - amount_remaining, i129 {
                    mag: calculated_amount, sign: !params.amount.sign
                }
            )
        };

        let (fee_growth_global_token0_next, fee_growth_global_token1_next) = if params.is_token1 {
            (pool.fee_growth_global_token0, fee_growth_global)
        } else {
            (fee_growth_global, pool.fee_growth_global_token1)
        };

        pools::write(
            pool_key,
            Pool {
                sqrt_ratio,
                tick,
                liquidity,
                fee_growth_global_token0: fee_growth_global_token0_next,
                fee_growth_global_token1: fee_growth_global_token1_next,
            }
        );

        account_delta(id, pool_key.token0, amount0_delta);
        account_delta(id, pool_key.token1, amount1_delta);

        Delta { amount0_delta, amount1_delta }
    }
}
