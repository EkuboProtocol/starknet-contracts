use starknet::{ContractAddress};
use ekubo::types::keys::{PoolKey};
use ekubo::types::pool_price::{PoolPrice};
use ekubo::types::i129::{i129};
use ekubo::types::bounds::{Bounds};

#[derive(Copy, Drop, Serde, starknet::Store)]
struct TokenInfo {
    key_hash: felt252,
    liquidity: u128,
}

#[derive(Copy, Drop, Serde)]
struct GetPositionInfoResult {
    pool_price: PoolPrice,
    liquidity: u128,
    amount0: u128,
    amount1: u128,
    fees0: u128,
    fees1: u128,
}

#[starknet::interface]
trait IPositions<TStorage> {
    // Get a full list of all the position IDs held by an account
    fn get_all_positions(self: @TStorage, account: ContractAddress) -> Array<u64>;

    // Return the principal and fee amounts owed to a position
    fn get_position_info(
        self: @TStorage, token_id: u256, pool_key: PoolKey, bounds: Bounds
    ) -> GetPositionInfoResult;

    // Initializes a pool only if it's not already initialized
    // This is useful as part of a batch of operations, to avoid failing the entire batch because the pool was already initialized
    fn maybe_initialize_pool(ref self: TStorage, pool_key: PoolKey, initial_tick: i129);

    // Create a new NFT that represents liquidity in a pool. Returns the newly minted token ID
    fn mint(ref self: TStorage, pool_key: PoolKey, bounds: Bounds) -> u256;

    // Delete the NFT. The NFT must have zero liquidity. Must be called by an operator, approved address or the owner
    fn burn(ref self: TStorage, token_id: u256, pool_key: PoolKey, bounds: Bounds);

    // Deposit in the most recently created token ID. Must be called by an operator, approved address or the owner
    fn deposit_last(
        ref self: TStorage, pool_key: PoolKey, bounds: Bounds, min_liquidity: u128
    ) -> u128;

    // Deposit in a specific token ID. Must be called by an operator, approved address or the owner
    fn deposit(
        ref self: TStorage, token_id: u256, pool_key: PoolKey, bounds: Bounds, min_liquidity: u128
    ) -> u128;

    // Withdraw liquidity from a specific token ID. Must be called by an operator, approved address or the owner
    fn withdraw(
        ref self: TStorage,
        token_id: u256,
        pool_key: PoolKey,
        bounds: Bounds,
        liquidity: u128,
        min_token0: u128,
        min_token1: u128,
        collect_fees: bool
    ) -> (u128, u128);

    // Clear the balance held by this contract. Used for collecting remaining tokens after doing a deposit, or collecting withdrawn tokens/fees
    fn clear(ref self: TStorage, token: ContractAddress) -> u256;
}
