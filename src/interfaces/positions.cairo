use starknet::{ContractAddress};
use ekubo::types::keys::{PoolKey};
use ekubo::types::pool_price::{PoolPrice};
use ekubo::types::i129::{i129};
use ekubo::types::bounds::{Bounds};

#[derive(Copy, Drop, Serde)]
struct GetTokenInfoResult {
    pool_price: PoolPrice,
    liquidity: u128,
    amount0: u128,
    amount1: u128,
    fees0: u128,
    fees1: u128,
}

#[starknet::interface]
trait IPositions<TStorage> {
    fn get_nft_address(self: @TStorage) -> ContractAddress;

    // Return the principal and fee amounts owed to a position
    fn get_token_info(
        self: @TStorage, id: u64, pool_key: PoolKey, bounds: Bounds
    ) -> GetTokenInfoResult;

    // Create a new NFT that represents liquidity in a pool. Returns the newly minted token ID
    fn mint(ref self: TStorage, pool_key: PoolKey, bounds: Bounds) -> u64;

    // Delete the NFT. The NFT must have zero liquidity. Must be called by an operator, approved address or the owner
    fn burn(ref self: TStorage, id: u64, pool_key: PoolKey, bounds: Bounds);

    // Deposit in the most recently created token ID. Must be called by an operator, approved address or the owner
    fn deposit_last(
        ref self: TStorage, pool_key: PoolKey, bounds: Bounds, min_liquidity: u128
    ) -> u128;

    // Deposit in a specific token ID. Must be called by an operator, approved address or the owner
    fn deposit(
        ref self: TStorage, id: u64, pool_key: PoolKey, bounds: Bounds, min_liquidity: u128
    ) -> u128;

    // Mint and deposit in a single call
    fn mint_and_deposit(
        ref self: TStorage, pool_key: PoolKey, bounds: Bounds, min_liquidity: u128
    ) -> (u64, u128);

    // Withdraw liquidity from a specific token ID. Must be called by an operator, approved address or the owner
    fn withdraw(
        ref self: TStorage,
        id: u64,
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
