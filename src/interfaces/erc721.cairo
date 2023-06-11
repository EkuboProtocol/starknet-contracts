use starknet::{ContractAddress};
use ekubo::types::i129::i129;
use ekubo::types::keys::{PoolKey};

#[starknet::interface]
trait IERC721<Storage> {
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
}
