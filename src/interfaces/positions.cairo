use starknet::{ContractAddress};
use ekubo::types::keys::{PoolKey};
use ekubo::types::i129::{i129};
use ekubo::types::bounds::{Bounds};

#[derive(Copy, Drop, Serde, storage_access::StorageAccess)]
struct TokenInfo {
    key_hash: felt252,
    liquidity: u128,
}

#[derive(Copy, Drop, Serde)]
struct GetPositionInfoResult {
    liquidity: u128,
    fees0: u128,
    fees1: u128,
}

#[starknet::interface]
trait IPositions<TStorage> {
    // See IERC721
    fn name(self: @TStorage) -> felt252;
    fn symbol(self: @TStorage) -> felt252;
    fn approve(ref self: TStorage, to: ContractAddress, token_id: u256);
    fn balance_of(self: @TStorage, account: ContractAddress) -> u256;
    fn owner_of(self: @TStorage, token_id: u256) -> ContractAddress;
    fn transfer_from(
        ref self: TStorage, from: ContractAddress, to: ContractAddress, token_id: u256
    );
    fn safe_transfer_from(
        ref self: TStorage,
        from: ContractAddress,
        to: ContractAddress,
        token_id: u256,
        data: Span<felt252>
    );
    fn set_approval_for_all(ref self: TStorage, operator: ContractAddress, approved: bool);
    fn get_approved(self: @TStorage, token_id: u256) -> ContractAddress;
    fn is_approved_for_all(
        self: @TStorage, owner: ContractAddress, operator: ContractAddress
    ) -> bool;
    fn token_uri(self: @TStorage, token_id: u256) -> felt252;

    // See ILocker
    fn locked(ref self: TStorage, id: felt252, data: Array<felt252>) -> Array<felt252>;

    // Return the principal and fee amounts owed to a position
    fn get_position_info(
        self: @TStorage, token_id: u256, pool_key: PoolKey, bounds: Bounds
    ) -> GetPositionInfoResult;

    // Initializes a pool only if it's not already initialized
    // This is useful as part of a batch of operations, to avoid failing the entire batch because the pool was already initialized
    fn maybe_initialize_pool(ref self: TStorage, pool_key: PoolKey, initial_tick: i129);

    // Create a new NFT that represents liquidity in a pool. Returns the newly minted token ID
    fn mint(
        ref self: TStorage, recipient: ContractAddress, pool_key: PoolKey, bounds: Bounds
    ) -> u256;

    // Delete the NFT. The NFT must have zero liquidity. Must be called by an operator, approved address or the owner
    fn burn(ref self: TStorage, token_id: u256);

    // Deposit in the most recently created token ID. Must be called by an operator, approved address or the owner
    fn deposit_last(
        ref self: TStorage, pool_key: PoolKey, bounds: Bounds, min_liquidity: u128
    ) -> u128;

    // Deposit in a specific token ID. Must be called by an operator, approved address or the owner
    fn deposit(
        ref self: TStorage,
        token_id: u256,
        pool_key: PoolKey,
        bounds: Bounds,
        min_liquidity: u128,
        collect_fees: bool
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
    fn clear(ref self: TStorage, token: ContractAddress, recipient: ContractAddress) -> u256;
}
