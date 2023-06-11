use starknet::{ContractAddress};

#[starknet::interface]
trait IMockERC20<TStorage> {
    fn balance_of(self: @TStorage, address: ContractAddress) -> u256;
    fn transfer(ref self: TStorage, to: ContractAddress, amount: u256);
    fn set_balance(ref self: TStorage, address: ContractAddress, amount: u256);
    fn increase_balance(ref self: TStorage, address: ContractAddress, amount: u128);
    fn decrease_balance(ref self: TStorage, address: ContractAddress, amount: u128);
}

#[starknet::contract]
mod MockERC20 {
    use super::{IMockERC20};
    use starknet::{ContractAddress, get_caller_address};

    #[storage]
    struct Storage {
        balances: LegacyMap<ContractAddress, u256>
    }

    #[external(v0)]
    impl MockERC20Impl of IMockERC20<Storage> {
        fn balance_of(self: @Storage, address: ContractAddress) -> u256 {
            self.balances.read(address)
        }

        fn transfer(ref self: Storage, to: ContractAddress, amount: u256) {
            let caller = get_caller_address();
            assert(self.balance_of(caller) >= amount, 'INSUFFICIENT_BALANCE');
            self.balances.write(caller, self.balance_of(caller) - amount);
            self.balances.write(to, self.balance_of(to) + amount);
        }

        fn set_balance(ref self: Storage, address: ContractAddress, amount: u256) {
            self.balances.write(address, amount);
        }

        fn increase_balance(ref self: Storage, address: ContractAddress, amount: u128) {
            self.balances.write(address, self.balance_of(address) + u256 { low: amount, high: 0 });
        }

        fn decrease_balance(ref self: Storage, address: ContractAddress, amount: u128) {
            self.balances.write(address, self.balance_of(address) - u256 { low: amount, high: 0 });
        }
    }
}
