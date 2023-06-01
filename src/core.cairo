use starknet::ContractAddress;
use parlay::types::storage::{Tick, Position, Pool, TickTreeNode};
use parlay::types::keys::{PositionKey, PoolKey};
use parlay::types::i129::{i129};

#[abi]
trait ILocker {
    fn locked(id: felt252, data: Array<felt252>) -> Array<felt252>;
}

#[abi]
trait IERC20 {
    fn transfer(recipient: ContractAddress, amount: u256);
    fn balance_of(account: ContractAddress) -> u256;
}

#[derive(Copy, Drop, Serde)]
struct UpdatePositionParameters {
    tick_lower: i129,
    tick_upper: i129,
    liquidity_delta: i129,
}

#[derive(Copy, Drop, Serde)]
struct SwapParameters {
    amount: i129,
    is_token1: bool,
    sqrt_ratio_limit: u256,
}

// from the perspective of the core contract, the change in balances
#[derive(Copy, Drop, Serde)]
struct Delta {
    amount0_delta: i129,
    amount1_delta: i129,
}

impl DefaultDelta of Default<Delta> {
    fn default() -> Delta {
        Delta { amount0_delta: Default::default(), amount1_delta: Default::default(),  }
    }
}

#[abi]
trait IParlay {
    #[view]
    fn get_owner() -> ContractAddress;

    #[view]
    fn get_pool(pool_key: PoolKey) -> Pool;

    #[view]
    fn get_tick(pool_key: PoolKey, index: i129) -> Tick;

    #[view]
    fn get_position(pool_key: PoolKey, position_key: PositionKey) -> Position;

    #[external]
    fn set_owner(new_owner: ContractAddress);

    #[external]
    fn withdraw_fees_collected(recipient: ContractAddress, token: ContractAddress, amount: u128);

    #[external]
    fn lock(data: Array<felt252>) -> Array<felt252>;

    #[external]
    fn withdraw(token_address: ContractAddress, recipient: ContractAddress, amount: u128);

    #[external]
    fn deposit(token_address: ContractAddress) -> u128;

    #[external]
    fn initialize_pool(pool_key: PoolKey, initial_tick: i129);

    #[external]
    fn update_position(pool_key: PoolKey, params: UpdatePositionParameters) -> Delta;

    #[external]
    fn swap(pool_key: PoolKey, params: SwapParameters) -> Delta;
}

#[contract]
mod Parlay {
    use super::{
        IERC20Dispatcher, IERC20DispatcherTrait, ILockerDispatcher, ILockerDispatcherTrait,
        ContractAddress, SwapParameters, UpdatePositionParameters, Delta
    };

    use parlay::math::ticks::{
        tick_to_sqrt_ratio, min_tick, max_tick, min_sqrt_ratio, max_sqrt_ratio
    };
    use parlay::math::liquidity::liquidity_delta_to_amount_delta;
    use parlay::math::swap::{swap_result, is_price_increasing};
    use parlay::math::fee::{compute_fee, accumulate_fee_amount};
    use parlay::math::muldiv::muldiv;
    use parlay::math::utils::{unsafe_sub, add_delta, ContractAddressOrder, u128_max};
    use parlay::types::i129::{i129, i129_min, i129_max, i129OptionPartialEq};
    use parlay::types::storage::{Tick, Position, Pool, TickTreeNode};
    use parlay::types::keys::{PositionKey, PoolKey};

    use starknet::{contract_address_const, get_caller_address, get_contract_address};
    use option::{Option, OptionTrait};

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
        initialized_ticks: LegacyMap::<(PoolKey, i129), TickTreeNode>,
        positions: LegacyMap::<(PoolKey, PositionKey), Position>,
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
    fn get_pool(pool_key: PoolKey) -> Pool {
        pools::read(pool_key)
    }

    #[view]
    fn get_tick(pool_key: PoolKey, index: i129) -> Tick {
        ticks::read((pool_key, index))
    }

    #[view]
    fn get_position(pool_key: PoolKey, position_key: PositionKey) -> Position {
        positions::read((pool_key, position_key))
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

    // Returns the current locker of the contract
    #[internal]
    fn current_locker() -> (felt252, ContractAddress) {
        let id = lock_count::read() - 1;
        (id, locker_addresses::read(id))
    }

    #[internal]
    fn require_locker() -> felt252 {
        let (id, locker) = current_locker();
        assert(locker == get_caller_address(), 'NOT_LOCKER');
        id
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
        let id = require_locker();

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
    fn deposit(token_address: ContractAddress) -> u128 {
        let id = require_locker();

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
    fn initialize_pool(pool_key: PoolKey, initial_tick: i129) {
        // token0 is always l.t. token1
        assert(pool_key.token0 < pool_key.token1, 'TOKEN_ORDER');

        let pool = pools::read(pool_key);
        assert(pool.sqrt_ratio == Default::default(), 'ALREADY_INITIALIZED');

        pools::write(
            pool_key,
            Pool {
                sqrt_ratio: tick_to_sqrt_ratio(initial_tick),
                tick: initial_tick,
                root_tick: Option::None(()),
                liquidity: Default::default(),
                fee_growth_global_token0: Default::default(),
                fee_growth_global_token1: Default::default(),
            }
        );

        PoolInitialized(pool_key, initial_tick);
    }

    // Remove the initialized tick and return the new root node of the tree
    #[internal]
    fn remove_initialized_tick(
        pool_key: PoolKey, root_tick: Option<i129>, index: i129
    ) -> Option<i129> {
        assert(root_tick.is_some(), 'TICK_NOT_FOUND');

        let value = root_tick.unwrap();
        let node = initialized_ticks::read((pool_key, value));

        if (index < value) {
            let left = remove_initialized_tick(pool_key, node.left, index);

            initialized_ticks::write(
                (pool_key, value), TickTreeNode { red: node.red, left, right: node.right }
            );

            root_tick
        } else if (index > value) {
            let right = remove_initialized_tick(pool_key, node.right, index);

            initialized_ticks::write(
                (pool_key, value), TickTreeNode { red: node.red, left: node.left, right }
            );

            root_tick
        } else {
            let next_root = if (node.left.is_none()) {
                node.right
            } else if (node.right.is_none()) {
                node.left
            } else {
                // find the in-order successor
                let mut successor = node.right.unwrap();
                let mut successor_node = initialized_ticks::read((pool_key, successor));
                loop {
                    match successor_node.left {
                        Option::Some(left) => {
                            successor = left;
                            successor_node = initialized_ticks::read((pool_key, left));
                        },
                        Option::None(_) => {
                            break ();
                        }
                    };
                };

                let right = remove_initialized_tick(pool_key, node.right, successor);

                initialized_ticks::write(
                    (pool_key, successor), TickTreeNode { red: node.red, left: node.left, right }
                );

                Option::Some(successor)
            };

            next_root
        }
    }


// function LeftRotate(tree, node)
//     right_child = node.right
//     node.right = right_child.left
//     right_child.left = node
//     if node == tree.root
//         tree.root = right_child
//     else if node == node.parent.left
//         node.parent.left = right_child
//     else
//         node.parent.right = right_child
//     right_child.parent = node.parent
//     node.parent = right_child

// function RightRotate(tree, node)
//     left_child = node.left
//     node.left = left_child.right
//     left_child.right = node
//     if node == tree.root
//         tree.root = left_child
//     else if node == node.parent.right
//         node.parent.right = left_child
//     else
//         node.parent.left = left_child
//     left_child.parent = node.parent
//     node.parent = left_child


    // Insert an initialized tick and return the new root node of the tree
    #[internal]
    fn insert_initialized_tick(
        pool_key: PoolKey, root_tick: Option<i129>, index: i129
    ) -> Option<i129> {
        let mut current: (i129, TickTreeNode) = match (root_tick) {
            Option::Some(value) => {
                (value, initialized_ticks::read((pool_key, value)))
            },
            Option::None(_) => {
                // the root tick is always black, so no write is needed, just return the index as the new root
                return Option::Some(index);
            }
        };

        let mut parent: Option<(i129, TickTreeNode)> = Option::None(());
        let mut grandparent: Option<(i129, TickTreeNode)> = Option::None(());

        return loop {
            let (value, node) = current;
            assert(index != value, 'ALREADY_EXISTS');

            if (index < value) {
                match node.left {
                    Option::Some(left) => {
                        grandparent = parent;
                        parent = Option::Some(current);
                        current = (left, initialized_ticks::read((pool_key, left)));
                    },
                    Option::None(_) => {
                        initialized_ticks::write(
                            (pool_key, value),
                            TickTreeNode {
                                red: node.red, left: Option::Some(index), right: node.right
                            }
                        );

                        initialized_ticks::write(
                            (pool_key, index),
                            TickTreeNode {
                                red: true, left: Option::None(()), right: Option::None(())
                            }
                        );

                        break root_tick;
                    }
                }
            } else {
                match node.right {
                    Option::Some(right) => {
                        grandparent = parent;
                        parent = Option::Some(current);
                        current = (right, initialized_ticks::read((pool_key, right)));
                    },
                    Option::None(_) => {
                        initialized_ticks::write(
                            (pool_key, value),
                            TickTreeNode {
                                red: node.red, left: node.left, right: Option::Some(index)
                            }
                        );

                        initialized_ticks::write(
                            (pool_key, index),
                            TickTreeNode {
                                red: true, left: Option::None(()), right: Option::None(())
                            }
                        );

                        // todo: rebalance

                        break root_tick;
                    }
                }
            };
        };
    }

    // Returns the next tick from a given starting tick, i.e. the tick in the set of initialized ticks that is greater than the current tick
    #[internal]
    fn next_initialized_tick(
        pool_key: PoolKey, root_tick: Option<i129>, from: i129
    ) -> Option<i129> {
        let mut at_tick = root_tick?;
        let mut best_answer: Option<i129> = Option::None(());
        let mut node = initialized_ticks::read((pool_key, at_tick));

        let absolute_best = from + i129 { mag: 1, sign: false };
        loop {
            if (at_tick == absolute_best) {
                break Option::Some(absolute_best);
            } else if (at_tick > from) {
                match best_answer {
                    Option::Some(ans) => {
                        best_answer = Option::Some(i129_min(at_tick, ans));
                    },
                    Option::None(_) => {
                        best_answer = Option::Some(at_tick);
                    }
                }

                match node.left {
                    Option::Some(left_tick) => {
                        at_tick = left_tick;
                        node = initialized_ticks::read((pool_key, at_tick));
                    },
                    Option::None(_) => {
                        break best_answer;
                    }
                }
            } else {
                match node.right {
                    Option::Some(right_tick) => {
                        at_tick = right_tick;
                        node = initialized_ticks::read((pool_key, at_tick));
                    },
                    Option::None(_) => {
                        break best_answer;
                    }
                }
            };
        }
    }

    // Returns the previous tick from a given starting tick, i.e. the tick in the set of initialized ticks that is less than or equal to the current tick
    #[internal]
    fn prev_initialized_tick(
        pool_key: PoolKey, root_tick: Option<i129>, from: i129
    ) -> Option<i129> {
        let mut at_tick = root_tick?;
        let mut node = initialized_ticks::read((pool_key, at_tick));
        let mut best_answer: Option<i129> = Option::None(());

        loop {
            if (at_tick == from) {
                break Option::Some(at_tick);
            } else if (at_tick > from) {
                match node.left {
                    Option::Some(left_tick) => {
                        at_tick = left_tick;
                        node = initialized_ticks::read((pool_key, at_tick));
                    },
                    Option::None(_) => {
                        break best_answer;
                    }
                }
            } else {
                // at_tick < from
                match best_answer {
                    Option::Some(ans) => {
                        best_answer = Option::Some(i129_max(at_tick, ans));
                    },
                    Option::None(_) => {
                        best_answer = Option::Some(at_tick);
                    }
                }

                match node.right {
                    Option::Some(right_tick) => {
                        at_tick = right_tick;
                        node = initialized_ticks::read((pool_key, at_tick));
                    },
                    Option::None(_) => {
                        break best_answer;
                    }
                }
            };
        }
    }

    #[internal]
    fn update_tick(
        pool_key: PoolKey, root_tick: Option<i129>, index: i129, liquidity_delta: i129
    ) -> Option<i129> {
        let tick = ticks::read((pool_key, index));

        let next_liquidity_net = add_delta(tick.liquidity_net, liquidity_delta);

        let mut next_root: Option<i129> = root_tick;

        if ((next_liquidity_net == 0) ^ (tick.liquidity_net == 0)) {
            if (next_liquidity_net == 0) {
                next_root = remove_initialized_tick(pool_key, root_tick, index);
            } else {
                next_root = insert_initialized_tick(pool_key, root_tick, index);
            }
        }

        ticks::write(
            (pool_key, index),
            Tick {
                liquidity_delta: tick.liquidity_delta + liquidity_delta,
                liquidity_net: next_liquidity_net,
                fee_growth_outside_token0: tick.fee_growth_outside_token0,
                fee_growth_outside_token1: tick.fee_growth_outside_token1
            }
        );

        next_root
    }


    #[external]
    fn update_position(pool_key: PoolKey, params: UpdatePositionParameters) -> Delta {
        let id = require_locker();

        assert(params.tick_lower < params.tick_upper, 'ORDER');
        assert(params.tick_lower >= min_tick(), 'MIN');
        assert(params.tick_upper <= max_tick(), 'MAX');

        let pool = pools::read(pool_key);

        // pool must be initialized
        assert(pool.sqrt_ratio != Default::default(), 'NOT_INITIALIZED');

        // first compute the amount deltas due to the liquidity delta
        let (mut amount0_delta, mut amount1_delta) = liquidity_delta_to_amount_delta(
            pool.sqrt_ratio, params.liquidity_delta, params.tick_lower, params.tick_upper
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

        // now we need to compute the fee growth inside the tick range, and the next pool liquidity
        let mut pool_liquidity_next: u128 = pool.liquidity;
        let (fee_growth_inside_token0, fee_growth_inside_token1) = if (pool
            .tick < params
            .tick_lower) {
            let tick_lower_state = ticks::read((pool_key, params.tick_lower));
            (
                unsafe_sub(
                    pool.fee_growth_global_token0, tick_lower_state.fee_growth_outside_token0
                ),
                unsafe_sub(
                    pool.fee_growth_global_token1, tick_lower_state.fee_growth_outside_token1
                )
            )
        } else if (pool.tick < params.tick_upper) {
            let tick_lower_state = ticks::read((pool_key, params.tick_lower));
            let tick_upper_state = ticks::read((pool_key, params.tick_upper));

            pool_liquidity_next = add_delta(pool_liquidity_next, params.liquidity_delta);

            (
                unsafe_sub(
                    unsafe_sub(
                        pool.fee_growth_global_token0, tick_lower_state.fee_growth_outside_token0
                    ),
                    tick_upper_state.fee_growth_outside_token0
                ),
                unsafe_sub(
                    unsafe_sub(
                        pool.fee_growth_global_token1, tick_lower_state.fee_growth_outside_token1
                    ),
                    tick_upper_state.fee_growth_outside_token1
                )
            )
        } else {
            let tick_upper_state = ticks::read((pool_key, params.tick_upper));
            (
                unsafe_sub(
                    pool.fee_growth_global_token0, tick_upper_state.fee_growth_outside_token0
                ),
                unsafe_sub(
                    pool.fee_growth_global_token1, tick_upper_state.fee_growth_outside_token1
                )
            )
        };

        // here we are accumulating fees owed to the position based on its current liquidity
        let position_key = PositionKey {
            owner: get_caller_address(),
            tick_lower: params.tick_lower,
            tick_upper: params.tick_upper
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
        let mut root_tick = update_tick(
            pool_key, pool.root_tick, params.tick_lower, params.liquidity_delta
        );
        root_tick = update_tick(pool_key, root_tick, params.tick_upper, params.liquidity_delta);

        // update pool liquidity if it changed
        if ((pool_liquidity_next != pool.liquidity) | (root_tick != pool.root_tick)) {
            pools::write(
                pool_key,
                Pool {
                    sqrt_ratio: pool.sqrt_ratio,
                    root_tick: root_tick,
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

    #[external]
    fn swap(pool_key: PoolKey, params: SwapParameters) -> Delta {
        let id = require_locker();

        let pool = pools::read(pool_key);

        // pool must be initialized
        assert(pool.sqrt_ratio != Default::default(), 'NOT_INITIALIZED');

        let increasing = is_price_increasing(params.amount.sign, params.is_token1);

        // check the limit is not in the wrong direction and is within the price bounds
        assert((params.sqrt_ratio_limit > pool.sqrt_ratio) == increasing, 'DIRECTION');
        assert(
            (params.sqrt_ratio_limit >= min_sqrt_ratio())
                & params.sqrt_ratio_limit < max_sqrt_ratio(),
            'LIMIT'
        );

        let mut delta: Delta = Default::default();
        let mut tick = pool.tick;
        let mut amount = params.amount;
        let mut sqrt_ratio = pool.sqrt_ratio;
        let mut liquidity = pool.liquidity;
        let mut calculated_amount: u128 = Default::default();

        loop {
            if (amount == Default::default()) {
                break ();
            }

            let (next_tick, is_initialized) = if (increasing) {
                match (prev_initialized_tick(pool_key, pool.root_tick, tick)) {
                    Option::Some(tick) => (tick, true),
                    Option::None(_) => if (increasing) {
                        (max_tick(), false)
                    } else {
                        (min_tick(), false)
                    }
                }
            } else {
                match (next_initialized_tick(pool_key, pool.root_tick, tick)) {
                    Option::Some(tick) => (tick, true),
                    Option::None(_) => if (increasing) {
                        (max_tick(), false)
                    } else {
                        (min_tick(), false)
                    }
                }
            };

            let sqrt_ratio_limit = tick_to_sqrt_ratio(next_tick);

            let swap_result = swap_result(
                sqrt_ratio: sqrt_ratio,
                liquidity: liquidity,
                sqrt_ratio_limit: sqrt_ratio_limit,
                amount: amount,
                is_token1: params.is_token1,
                fee: pool_key.fee
            );

            amount -= swap_result.consumed_amount;
            sqrt_ratio = swap_result.sqrt_ratio_next;
            calculated_amount += swap_result.calculated_amount;
        };

        Default::default()
    }
}
