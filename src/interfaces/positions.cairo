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

#[derive(Copy, Drop, Serde)]
struct TokenInfo {
    key_hash: felt252,
    liquidity: u128,
    fee_growth_inside_last_token0: u256,
    fee_growth_inside_last_token1: u256,
    fees_token0: u128,
    fees_token1: u128,
}

#[abi]
trait IPositions {
    #[view]
    fn name() -> felt252;
    #[view]
    fn symbol() -> felt252;
    #[external]
    fn approve(to: ContractAddress, token_id: u256);
    #[view]
    fn balance_of(account: ContractAddress) -> u256;
    #[view]
    fn owner_of(token_id: u256) -> ContractAddress;
    #[external]
    fn transfer_from(from: ContractAddress, to: ContractAddress, token_id: u256);
    // #[external]
    // fn safe_transfer_from(
    //     from: ContractAddress, to: ContractAddress, token_id: u256, data: Span<felt252>
    // );
    #[external]
    fn set_approval_for_all(operator: ContractAddress, approved: bool);
    #[view]
    fn get_approved(token_id: u256) -> ContractAddress;
    #[view]
    fn is_approved_for_all(owner: ContractAddress, operator: ContractAddress) -> bool;
    #[view]
    fn token_uri(token_id: u256) -> felt252;

    #[external]
    fn maybe_initialize_pool(pool_key: PoolKey, initial_tick: i129);

    #[external]
    fn mint(recipient: ContractAddress, pool_key: PoolKey, bounds: Bounds) -> u128;

    #[external]
    fn deposit_last(pool_key: PoolKey, bounds: Bounds, min_liquidity: u128) -> u128;

    #[external]
    fn deposit(token_id: u256, pool_key: PoolKey, bounds: Bounds, min_liquidity: u128) -> u128;

    #[external]
    fn clear(token: ContractAddress, recipient: ContractAddress);

    #[external]
    fn withdraw(
        token_id: u256,
        pool_key: PoolKey,
        bounds: Bounds,
        liquidity: u128,
        min_token0: u128,
        min_token1: u128
    ) -> (u128, u128);
}
