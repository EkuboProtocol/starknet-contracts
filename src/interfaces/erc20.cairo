use starknet::{ContractAddress};

#[starknet::interface]
trait IERC20<Storage> {
    fn transfer(ref self: Storage, recipient: ContractAddress, amount: u256);
    fn balance_of(self: @Storage, account: ContractAddress) -> u256;
}
