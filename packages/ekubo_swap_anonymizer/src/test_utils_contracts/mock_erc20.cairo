use ekubo::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
use starknet::ContractAddress;

#[starknet::interface]
pub trait IMockERC20<T> {
    fn mint(ref self: T, recipient: ContractAddress, amount: u128);
}

#[generate_trait]
pub impl MockERC20DispatcherImpl of MockERC20DispatcherTrait {
    fn balance_of(self: IMockERC20Dispatcher, account: ContractAddress) -> u256 {
        IERC20Dispatcher { contract_address: self.contract_address }.balanceOf(account)
    }

    fn allowance(
        self: IMockERC20Dispatcher, owner: ContractAddress, spender: ContractAddress,
    ) -> u256 {
        IERC20Dispatcher { contract_address: self.contract_address }.allowance(owner, spender)
    }
}

#[starknet::contract]
pub mod MockERC20 {
    use core::num::traits::Zero;
    use ekubo::interfaces::erc20::IERC20;
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_caller_address};
    use super::IMockERC20;

    #[storage]
    struct Storage {
        balances: Map<ContractAddress, u128>,
        allowances: Map<(ContractAddress, ContractAddress), u128>,
        total_supply: u128,
    }

    #[constructor]
    fn constructor(ref self: ContractState) {}

    #[abi(embed_v0)]
    impl ERC20Impl of IERC20<ContractState> {
        fn transfer(ref self: ContractState, recipient: ContractAddress, amount: u256) -> bool {
            assert(amount.high.is_zero(), 'AMOUNT_OVERFLOW');
            let sender = get_caller_address();
            let sender_balance = self.balances.read(sender);
            assert(sender_balance >= amount.low, 'INSUFFICIENT_BALANCE');
            self.balances.write(sender, sender_balance - amount.low);
            self.balances.write(recipient, self.balances.read(recipient) + amount.low);
            true
        }

        fn balanceOf(self: @ContractState, account: ContractAddress) -> u256 {
            self.balances.read(account).into()
        }

        fn approve(ref self: ContractState, spender: ContractAddress, amount: u256) -> bool {
            assert(amount.high.is_zero(), 'AMOUNT_OVERFLOW');
            self.allowances.write((get_caller_address(), spender), amount.low);
            true
        }

        fn transferFrom(
            ref self: ContractState,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u256,
        ) -> bool {
            assert(amount.high.is_zero(), 'AMOUNT_OVERFLOW');
            let allowance_key = (sender, get_caller_address());
            let allowance = self.allowances.read(allowance_key);
            let sender_balance = self.balances.read(sender);
            assert(allowance >= amount.low, 'INSUFFICIENT_ALLOWANCE');
            assert(sender_balance >= amount.low, 'INSUFFICIENT_BALANCE');
            self.allowances.write(allowance_key, allowance - amount.low);
            self.balances.write(sender, sender_balance - amount.low);
            self.balances.write(recipient, self.balances.read(recipient) + amount.low);
            true
        }

        fn allowance(
            self: @ContractState, owner: ContractAddress, spender: ContractAddress,
        ) -> u256 {
            self.allowances.read((owner, spender)).into()
        }
    }

    #[abi(embed_v0)]
    impl MockERC20Impl of IMockERC20<ContractState> {
        fn mint(ref self: ContractState, recipient: ContractAddress, amount: u128) {
            self.balances.write(recipient, self.balances.read(recipient) + amount);
            self.total_supply.write(self.total_supply.read() + amount);
        }
    }
}
