use starknet::{ContractAddress};

#[abi]
trait IERC20 {
    fn transfer(recipient: ContractAddress, amount: u256);
    fn balance_of(account: ContractAddress) -> u256;
}
