use starknet::{ContractAddress};
use ekubo::types::i129::i129;
use ekubo::types::keys::{PoolKey};

#[starknet::interface]
trait IERC721<TStorage> {
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
}
