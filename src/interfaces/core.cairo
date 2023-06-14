use starknet::{ContractAddress, ClassHash};
use ekubo::types::storage::{Tick, Position, Pool};
use ekubo::types::keys::{PositionKey, PoolKey};
use ekubo::types::i129::{i129};
use ekubo::types::bounds::{Bounds};
use ekubo::types::delta::{Delta};

// This interface must be implemented by any contract that intends to call ICore#lock
#[starknet::interface]
trait ILocker<TStorage> {
    // This function is called on the caller of lock, i.e. a callback
    // The input is the data passed to ICore#lock, the output is passed back through as the return value of #lock
    fn locked(ref self: TStorage, id: felt252, data: Array<felt252>) -> Array<felt252>;
}

// Passed as an argument to update a position. The owner of the position is implicitly the locker.
// bounds is the lower and upper price range of the position, expressed in terms of log base sqrt 1.000001 of token1/token0.
// liquidity_delta is how the position's liquidity should be updated.
#[derive(Copy, Drop, Serde)]
struct UpdatePositionParameters {
    salt: felt252,
    bounds: Bounds,
    liquidity_delta: i129,
}

// The amount is the amount of token0 or token1 to swap, depending on is_token1. A negative amount implies an exact-output swap.
// is_token1 Indicates whether the amount is in terms of token0 or token1.
// sqrt_ratio_limit is a limit on how far the price can move as part of the swap. Note this must always be specified, and must be between the maximum and minimum sqrt ratio.
// skip_ahead is an optimization parameter for large swaps across many uninitialized ticks to reduce the number of swap iterations that must be performed
#[derive(Copy, Drop, Serde)]
struct SwapParameters {
    amount: i129,
    is_token1: bool,
    sqrt_ratio_limit: u256,
    skip_ahead: u128,
}

// Details about a liquidity position. Note the position may not exist, i.e. a position may be returned that has never had non-zero liquidity.
#[derive(Copy, Drop, Serde)]
struct GetPositionResult {
    position: Position,
    fees0: u128,
    fees1: u128,
    fee_growth_inside_token0: u256,
    fee_growth_inside_token1: u256,
}

// The current state of the queried locker
#[derive(Copy, Drop, Serde)]
struct LockerState {
    id: felt252,
    address: ContractAddress,
    nonzero_delta_count: felt252
}

// An extension is an optional contract that can be specified as part of a pool key to modify pool behavior
#[starknet::interface]
trait IExtension<TStorage> {
    // Called before a pool is initialized
    fn before_initialize_pool(ref self: TStorage, pool_key: PoolKey, initial_tick: i129);
    // Called after a pool is initialized
    fn after_initialize_pool(ref self: TStorage, pool_key: PoolKey, initial_tick: i129);

    // Called before a swap happens
    fn before_swap(ref self: TStorage, pool_key: PoolKey, params: SwapParameters);
    // Called after a swap happens with the result of the swap
    fn after_swap(ref self: TStorage, pool_key: PoolKey, params: SwapParameters, delta: Delta);

    // Called before an update to a position
    fn before_update_position(
        ref self: TStorage, pool_key: PoolKey, params: UpdatePositionParameters
    );
    // Called after the position is updated with the result of the update
    fn after_update_position(
        ref self: TStorage, pool_key: PoolKey, params: UpdatePositionParameters, delta: Delta
    );
}

#[starknet::interface]
trait ICore<TStorage> {
    // The address that has the right to any fees collected by this contract
    fn get_owner(self: @TStorage) -> ContractAddress;

    // Get the state of the locker with the given ID
    fn get_locker_state(self: @TStorage, id: felt252) -> LockerState;

    // Get the current state of the given pool
    fn get_pool(self: @TStorage, pool_key: PoolKey) -> Pool;

    // Get the fee growth inside for a given tick range
    fn get_pool_fee_growth_inside(
        self: @TStorage, pool_key: PoolKey, bounds: Bounds
    ) -> (u256, u256);

    // Get the state of a given tick for the given pool
    fn get_tick(self: @TStorage, pool_key: PoolKey, index: i129) -> Tick;

    // Get the state of a given position for the given pool
    fn get_position(
        self: @TStorage, pool_key: PoolKey, position_key: PositionKey
    ) -> GetPositionResult;

    // Get the last recorded balance of a token for core, used by core for computing payment amounts
    fn get_reserves(self: @TStorage, token: ContractAddress) -> u256;

    // Get the balance that is saved in core for a given account for use in a future lock (i.e. methods #save and #load)
    fn get_saved_balance(self: @TStorage, owner: ContractAddress, token: ContractAddress) -> u128;

    // Set the owner of the contract to a new owner (only the current owner can call the function)
    fn set_owner(ref self: TStorage, new_owner: ContractAddress);

    // The owner can update the class hash of the contract.
    fn replace_class_hash(ref self: TStorage, class_hash: ClassHash);

    // Withdraw any fees collected by the contract (only the owner can call this function)
    fn withdraw_fees_collected(
        ref self: TStorage, recipient: ContractAddress, token: ContractAddress, amount: u128
    );

    // Main entrypoint for any actions, which must be called before any other pool functions can be called.
    // Other functions must be called within the callback to lock. The lock callback is called with the input data, and the returned array is passed through to the caller.
    fn lock(ref self: TStorage, data: Array<felt252>) -> Array<felt252>;

    // Withdraw a given token from core. This is used to withdraw the output of swaps or burnt liquidity, and also for flash loans.
    // Note you must call this within a lock callback
    fn withdraw(
        ref self: TStorage, token_address: ContractAddress, recipient: ContractAddress, amount: u128
    );

    // Save a given token balance in core for a given account for use in a future lock. It can be recalled by calling load.
    // Note you must call this within a lock callback
    fn save(
        ref self: TStorage, token_address: ContractAddress, recipient: ContractAddress, amount: u128
    );

    // Deposit a given token into core. This is how payments are made to core. First send the token to core, and then call deposit to account the delta.
    // Note this is how reserves are used.
    // Note you must call this within a lock callback
    fn deposit(ref self: TStorage, token_address: ContractAddress) -> u128;

    // Recall a balance previously saved via #save
    // Note you must call this within a lock callback
    fn load(ref self: TStorage, token_address: ContractAddress, amount: u128);

    // Initialize a pool. This can happen outside of a lock callback because it does not require any tokens to be spent.
    fn initialize_pool(ref self: TStorage, pool_key: PoolKey, initial_tick: i129);

    // Update a liquidity position in a pool. The owner of the position is always the locker.
    // Note you must call this within a lock callback. Note also that a position cannot be burned to 0 unless all fees have been collected
    fn update_position(
        ref self: TStorage, pool_key: PoolKey, params: UpdatePositionParameters
    ) -> Delta;

    // Collect the fees owed on a position
    fn collect_fees(ref self: TStorage, pool_key: PoolKey, salt: felt252, bounds: Bounds) -> Delta;

    // Make a swap against a pool.
    // You must call this within a lock callback.
    fn swap(ref self: TStorage, pool_key: PoolKey, params: SwapParameters) -> Delta;

    // Return the next initialized tick from the given tick, i.e. the initialized tick that is greater than the given `from` tick
    fn next_initialized_tick(
        ref self: TStorage, pool_key: PoolKey, from: i129, skip_ahead: u128
    ) -> (i129, bool);

    // Return the previous initialized tick from the given tick, i.e. the initialized tick that is less than or equal to the given `from` tick
    // Note this can also be used to check if the tick is initialized
    fn prev_initialized_tick(
        ref self: TStorage, pool_key: PoolKey, from: i129, skip_ahead: u128
    ) -> (i129, bool);
}
