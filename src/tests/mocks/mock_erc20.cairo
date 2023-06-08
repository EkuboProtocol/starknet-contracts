use starknet::{ContractAddress};

#[abi]
trait IMockERC20 {
    #[view]
    fn balance_of(address: ContractAddress) -> u256;
    #[external]
    fn transfer(to: ContractAddress, amount: u256);
    #[external]
    fn set_balance(address: ContractAddress, amount: u256);
    #[external]
    fn increase_balance(address: ContractAddress, amount: u128);
    #[external]
    fn decrease_balance(address: ContractAddress, amount: u128);
}

#[contract]
mod MockERC20 {
    use starknet::{ContractAddress, get_caller_address};

    struct Storage {
        balances: LegacyMap<ContractAddress, u256>
    }

    #[view]
    fn balance_of(address: ContractAddress) -> u256 {
        balances::read(address)
    }

    #[external]
    fn transfer(to: ContractAddress, amount: u256) {
        let caller = get_caller_address();
        assert(balance_of(caller) >= amount, 'INSUFFICIENT_BALANCE');
        balances::write(caller, balance_of(caller) - amount);
        balances::write(to, balance_of(to) + amount);
    }

    #[external]
    fn set_balance(address: ContractAddress, amount: u256) {
        balances::write(address, amount);
    }

    #[external]
    fn increase_balance(address: ContractAddress, amount: u128) {
        balances::write(address, balance_of(address) + u256 { low: amount, high: 0 });
    }

    #[external]
    fn decrease_balance(address: ContractAddress, amount: u128) {
        balances::write(address, balance_of(address) - u256 { low: amount, high: 0 });
    }
}
