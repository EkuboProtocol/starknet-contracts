use starknet::{ContractAddress};

#[starknet::interface]
pub trait IERC721<TContractState> {
    fn name(self: @TContractState) -> felt252;
    fn symbol(self: @TContractState) -> felt252;
    fn approve(ref self: TContractState, to: ContractAddress, token_id: u256);
    fn balanceOf(self: @TContractState, account: ContractAddress) -> u256;
    fn ownerOf(self: @TContractState, token_id: u256) -> ContractAddress;
    fn transferFrom(
        ref self: TContractState, from: ContractAddress, to: ContractAddress, token_id: u256
    );
    fn setApprovalForAll(ref self: TContractState, operator: ContractAddress, approved: bool);
    fn getApproved(self: @TContractState, token_id: u256) -> ContractAddress;
    fn isApprovedForAll(
        self: @TContractState, owner: ContractAddress, operator: ContractAddress
    ) -> bool;
    fn tokenURI(self: @TContractState, token_id: u256) -> Array<felt252>;

    // snake_case
    fn balance_of(self: @TContractState, account: ContractAddress) -> u256;
    fn owner_of(self: @TContractState, token_id: u256) -> ContractAddress;
    fn transfer_from(
        ref self: TContractState, from: ContractAddress, to: ContractAddress, token_id: u256
    );
    fn set_approval_for_all(ref self: TContractState, operator: ContractAddress, approved: bool);
    fn get_approved(self: @TContractState, token_id: u256) -> ContractAddress;
    fn is_approved_for_all(
        self: @TContractState, owner: ContractAddress, operator: ContractAddress
    ) -> bool;
    fn token_uri(self: @TContractState, token_id: u256) -> Array<felt252>;
}
