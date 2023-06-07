use starknet::{ContractAddress};
use ekubo::types::keys::{PoolKey};
use ekubo::types::i129::{i129};

#[derive(Copy, Drop, Serde)]
struct PositionKey {
    pool_key: PoolKey,
    tick_lower: i129,
    tick_upper: i129
}

#[derive(Copy, Drop, Serde)]
struct TokenInfo {
    position_key_hash: felt252,
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
    fn mint(recipient: ContractAddress, position_key: PositionKey) -> u128;

    #[external]
    fn deposit(token_id: u256, position_key: PositionKey, min_liquidity: u128) -> u128;

    #[external]
    fn clear(token: ContractAddress, recipient: ContractAddress);

    #[external]
    fn withdraw(
        token_id: u256,
        position_key: PositionKey,
        liquidity: u128,
        min_token0: u128,
        min_token1: u128
    ) -> (u128, u128);
}
