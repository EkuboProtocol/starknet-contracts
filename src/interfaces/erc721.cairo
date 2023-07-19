use starknet::{ContractAddress};
use ekubo::types::i129::i129;
use ekubo::types::keys::{PoolKey};

// must be checked to support interface first
const IERC721_RECEIVER_INTERFACE_ID: u32 = 0x150b7a02;
const IACCOUNT_INTERFACE_ID: u32 = 0xa66bd575;

#[starknet::interface]
trait IERC721Receiver<TStorage> {
    fn on_erc721_received(
        ref self: TStorage,
        operator: ContractAddress,
        from: ContractAddress,
        token_id: u256,
        data: Span<felt252>
    ) -> u32;
}

#[starknet::interface]
trait IERC721<TStorage> {
    fn name(self: @TStorage) -> felt252;
    fn symbol(self: @TStorage) -> felt252;
    fn approve(ref self: TStorage, to: ContractAddress, token_id: u256);
    fn balanceOf(self: @TStorage, account: ContractAddress) -> u256;
    fn ownerOf(self: @TStorage, token_id: u256) -> ContractAddress;
    fn transferFrom(ref self: TStorage, from: ContractAddress, to: ContractAddress, token_id: u256);
    fn safeTransferFrom(
        ref self: TStorage,
        from: ContractAddress,
        to: ContractAddress,
        token_id: u256,
        data: Span<felt252>
    );
    fn setApprovalForAll(ref self: TStorage, operator: ContractAddress, approved: bool);
    fn getApproved(self: @TStorage, token_id: u256) -> ContractAddress;
    fn isApprovedForAll(self: @TStorage, owner: ContractAddress, operator: ContractAddress) -> bool;
    fn tokenUri(self: @TStorage, token_id: u256) -> felt252;


    // camel case entry points
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
