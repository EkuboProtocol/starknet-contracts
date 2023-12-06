use starknet::{ContractAddress, get_contract_address, get_caller_address};
use ekubo::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};

#[starknet::interface]
trait IClear<TContractState> {
    fn clear(self: @TContractState, token: IERC20Dispatcher) -> u256;
}

#[starknet::embeddable]
impl ClearImpl<TContractState> of IClear<TContractState> {
    fn clear(self: @TContractState, token: IERC20Dispatcher) -> u256 {
        let balance = token.balanceOf(get_contract_address());
        if (balance.is_non_zero()) {
            token.transfer(get_caller_address(), balance);
        }
        balance
    }
}
