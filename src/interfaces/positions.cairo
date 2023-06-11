use starknet::{ContractAddress};
use ekubo::types::keys::{PoolKey};
use ekubo::types::i129::{i129};
use ekubo::math::ticks::{min_tick, max_tick};

#[derive(Copy, Drop, Serde)]
struct Bounds {
    tick_lower: i129,
    tick_upper: i129
}

impl DefaultBounds of Default<Bounds> {
    fn default() -> Bounds {
        Bounds { tick_lower: min_tick(), tick_upper: max_tick() }
    }
}

#[derive(Copy, Drop, Serde, storage_access::StorageAccess)]
struct TokenInfo {
    key_hash: felt252,
    liquidity: u128,
    fee_growth_inside_last_token0: u256,
    fee_growth_inside_last_token1: u256,
    fees_token0: u128,
    fees_token1: u128,
}

#[starknet::interface]
trait IPositions<Storage> {
    fn name(self: @Storage) -> felt252;
    fn symbol(self: @Storage) -> felt252;
    fn approve(ref self: Storage, to: ContractAddress, token_id: u256);
    fn balance_of(self: @Storage, account: ContractAddress) -> u256;
    fn owner_of(self: @Storage, token_id: u256) -> ContractAddress;
    fn transfer_from(ref self: Storage, from: ContractAddress, to: ContractAddress, token_id: u256);
    fn safe_transfer_from(
        ref self: Storage,
        from: ContractAddress,
        to: ContractAddress,
        token_id: u256,
        data: Span<felt252>
    );
    fn set_approval_for_all(ref self: Storage, operator: ContractAddress, approved: bool);
    fn get_approved(self: @Storage, token_id: u256) -> ContractAddress;
    fn is_approved_for_all(
        self: @Storage, owner: ContractAddress, operator: ContractAddress
    ) -> bool;
    fn token_uri(self: @Storage, token_id: u256) -> felt252;

    fn locked(ref self: Storage, id: felt252, data: Array<felt252>) -> Array<felt252>;

    fn maybe_initialize_pool(ref self: Storage, pool_key: PoolKey, initial_tick: i129);

    fn mint(
        ref self: Storage, recipient: ContractAddress, pool_key: PoolKey, bounds: Bounds
    ) -> u128;

    fn deposit_last(
        ref self: Storage, pool_key: PoolKey, bounds: Bounds, min_liquidity: u128
    ) -> u128;

    fn deposit(
        ref self: Storage, token_id: u256, pool_key: PoolKey, bounds: Bounds, min_liquidity: u128
    ) -> u128;

    fn clear(ref self: Storage, token: ContractAddress, recipient: ContractAddress) -> u256;

    fn withdraw(
        ref self: Storage,
        token_id: u256,
        pool_key: PoolKey,
        bounds: Bounds,
        liquidity: u128,
        min_token0: u128,
        min_token1: u128
    ) -> (u128, u128);
}
