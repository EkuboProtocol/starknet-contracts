use starknet::{ContractAddress};

#[starknet::interface]
trait IMockERC20<TStorage> {
    fn balanceOf(self: @TStorage, address: ContractAddress) -> u256;
    fn transfer(ref self: TStorage, to: ContractAddress, amount: u256) -> bool;
    fn set_balance(ref self: TStorage, address: ContractAddress, amount: u256);
    fn increase_balance(ref self: TStorage, address: ContractAddress, amount: u128);
    fn decrease_balance(ref self: TStorage, address: ContractAddress, amount: u128);
}

#[starknet::contract]
mod MockERC20 {
    use starknet::{ContractAddress, get_caller_address};
    use super::{IMockERC20};

    #[storage]
    struct Storage {
        balances: LegacyMap<ContractAddress, u256>
    }

    #[external(v0)]
    impl MockERC20Impl of IMockERC20<ContractState> {
        fn balanceOf(self: @ContractState, address: ContractAddress) -> u256 {
            self.balances.read(address)
        }

        fn transfer(ref self: ContractState, to: ContractAddress, amount: u256) -> bool {
            let caller = get_caller_address();
            assert(self.balanceOf(caller) >= amount, 'INSUFFICIENT_BALANCE');
            self.balances.write(caller, self.balanceOf(caller) - amount);
            self.balances.write(to, self.balanceOf(to) + amount);
            true
        }

        fn set_balance(ref self: ContractState, address: ContractAddress, amount: u256) {
            self.balances.write(address, amount);
        }

        fn increase_balance(ref self: ContractState, address: ContractAddress, amount: u128) {
            self.balances.write(address, self.balanceOf(address) + u256 { low: amount, high: 0 });
        }

        fn decrease_balance(ref self: ContractState, address: ContractAddress, amount: u128) {
            self.balances.write(address, self.balanceOf(address) - u256 { low: amount, high: 0 });
        }
    }
}
