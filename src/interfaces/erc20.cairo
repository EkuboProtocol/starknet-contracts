use starknet::{ContractAddress};

// ERC20 is only used externally
#[starknet::interface]
trait IERC20<TStorage> {
    fn transfer(ref self: TStorage, recipient: ContractAddress, amount: u256);
    fn balanceOf(self: @TStorage, account: ContractAddress) -> u256;
}
