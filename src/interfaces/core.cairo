use starknet::ContractAddress;
use ekubo::types::storage::{Tick, Position, Pool, TickTreeNode};
use ekubo::types::keys::{PositionKey, PoolKey};
use ekubo::types::i129::{i129};

#[abi]
trait ILocker {
    // This function is called on the caller of lock, i.e. a callback
    // The input is the data passed to ICore#lock, the output is passed back through as the return value of #lock
    fn locked(id: felt252, data: Array<felt252>) -> Array<felt252>;
}

// Passed as an argument to update a position. The owner of the position is implicit in the locker.
// tick_lower is the lower bound of the position's price range
// tick_upper is the upper bound of the position's price range
// liquidity_delta is how the position's liquidity should be modified.
#[derive(Copy, Drop, Serde)]
struct UpdatePositionParameters {
    tick_lower: i129,
    tick_upper: i129,
    liquidity_delta: i129,
}

// The amount is the amount of token0 or token1 to swap, depending on is_token1. A negative amount implies an exact-output swap.
// is_token1 Indicates whether the amount is in terms of token0 or token1.
// sqrt_ratio_limit is a limit on how far the price can move as part of the swap. Note this must always be specified, and must be between the maximum and minimum sqrt ratio.
#[derive(Copy, Drop, Serde)]
struct SwapParameters {
    amount: i129,
    is_token1: bool,
    sqrt_ratio_limit: u256,
}

// From the perspective of the core contract, this represents the change in balances.
// For example, swapping 100 token0 for 150 token1 would result in a Delta of { amount0_delta: 100, amount1_delta: -150 }
// Note in case the price limit is reached, the amount0_delta or amount1_delta may be less than the amount specified in the swap parameters.
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

// The current state of the queried locker
#[derive(Copy, Drop, Serde)]
struct LockerState {
    id: felt252,
    address: ContractAddress,
    nonzero_delta_count: felt252
}

#[abi]
trait ICore {
    // The address that has the right to any fees collected by this contract
    #[view]
    fn get_owner() -> ContractAddress;

    // Get the state of the locker with the given ID
    #[view]
    fn get_locker_state(id: felt252) -> LockerState;

    // Get the current state of the given pool
    #[view]
    fn get_pool(pool_key: PoolKey) -> Pool;

    // Get the fee growth inside for a given tick range
    #[view]
    fn get_pool_fee_growth_inside(
        pool_key: PoolKey, tick_lower: i129, tick_upper: i129
    ) -> (u256, u256);

    // Get the state of a given tick for the given pool
    #[view]
    fn get_tick(pool_key: PoolKey, index: i129) -> Tick;

    // Get the state of a given position for the given pool
    #[view]
    fn get_position(pool_key: PoolKey, position_key: PositionKey) -> Position;

    // Get the last recorded balance of a token for core, used by core for computing payment amounts
    #[view]
    fn get_reserves(token: ContractAddress) -> u256;

    // Get the balance that is saved in core for a given account for use in a future lock (i.e. methods #save and #load)
    #[view]
    fn get_saved_balance(owner: ContractAddress, token: ContractAddress) -> u128;

    // Set the owner of the contract to a new owner (only the current owner can call the function)
    #[external]
    fn set_owner(new_owner: ContractAddress);

    // Withdraw any fees collected by the contract (only the owner can call this function)
    #[external]
    fn withdraw_fees_collected(recipient: ContractAddress, token: ContractAddress, amount: u128);

    // Main entrypoint for any actions, which must be called before any other pool functions can be called.
    // Other functions must be called within the callback to lock. The lock callback is called with the input data, and the returned array is passed through to the caller.
    #[external]
    fn lock(data: Array<felt252>) -> Array<felt252>;

    // Withdraw a given token from core. This is used to withdraw the output of swaps or burnt liquidity, and also for flash loans.
    // Note you must call this within a lock callback
    #[external]
    fn withdraw(token_address: ContractAddress, recipient: ContractAddress, amount: u128);

    // Save a given token balance in core for a given account for use in a future lock. It can be recalled by calling load.
    // Note you must call this within a lock callback
    #[external]
    fn save(token_address: ContractAddress, recipient: ContractAddress, amount: u128);

    // Deposit a given token into core. This is how payments are made to core. First send the token to core, and then call deposit to account the delta.
    // Note this is how reserves are used.
    // Note you must call this within a lock callback
    #[external]
    fn deposit(token_address: ContractAddress) -> u128;

    // Recall a balance previously saved via #save
    // Note you must call this within a lock callback
    #[external]
    fn load(token_address: ContractAddress, amount: u128);

    // Initialize a pool. This can happen outside of a lock callback because it does not require any tokens to be spent.
    #[external]
    fn initialize_pool(pool_key: PoolKey, initial_tick: i129);

    // Update a liquidity position in a pool. The owner of the position is always the locker.
    // Note you must call this within a lock callback
    #[external]
    fn update_position(pool_key: PoolKey, params: UpdatePositionParameters) -> Delta;

    // Make a swap against a pool.
    // Note you must call this within a lock callback
    #[external]
    fn swap(pool_key: PoolKey, params: SwapParameters) -> Delta;
}
