use ekubo::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
use starknet::ContractAddress;

#[starknet::interface]
pub trait IMockERC20<T> {
    fn mint(ref self: T, recipient: ContractAddress, amount: u128);
    fn set_failures(ref self: T, transfer_fails: bool, approve_fails: bool);
    fn set_transfer_fee(ref self: T, fee: u128);
}

#[starknet::interface]
pub trait IERC20Snake<T> {
    fn balance_of(self: @T, account: ContractAddress) -> u256;
    fn transfer_from(
        ref self: T, sender: ContractAddress, recipient: ContractAddress, amount: u256,
    ) -> bool;
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
    use ekubo::interfaces::erc20::IERC20;
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_caller_address};
    use super::{IERC20Snake, IMockERC20};

    #[storage]
    struct Storage {
        balances: Map<ContractAddress, u256>,
        allowances: Map<(ContractAddress, ContractAddress), u256>,
        total_supply: u256,
        transfer_fee: u128,
        transfer_fails: bool,
        approve_fails: bool,
    }

    #[constructor]
    fn constructor(ref self: ContractState) {}

    #[abi(embed_v0)]
    impl ERC20Impl of IERC20<ContractState> {
        fn transfer(ref self: ContractState, recipient: ContractAddress, amount: u256) -> bool {
            if self.transfer_fails.read() {
                return false;
            }
            let sender = get_caller_address();
            let sender_balance = self.balances.read(sender);
            assert(sender_balance >= amount, 'INSUFFICIENT_BALANCE');
            self.balances.write(sender, sender_balance - amount);
            self
                .balances
                .write(
                    recipient,
                    self.balances.read(recipient) + amount - self.transfer_fee.read().into(),
                );
            true
        }

        fn balanceOf(self: @ContractState, account: ContractAddress) -> u256 {
            self.balances.read(account)
        }

        fn approve(ref self: ContractState, spender: ContractAddress, amount: u256) -> bool {
            if self.approve_fails.read() {
                return false;
            }
            self.allowances.write((get_caller_address(), spender), amount);
            true
        }

        fn transferFrom(
            ref self: ContractState,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u256,
        ) -> bool {
            let allowance_key = (sender, get_caller_address());
            let allowance = self.allowances.read(allowance_key);
            let sender_balance = self.balances.read(sender);
            assert(allowance >= amount, 'INSUFFICIENT_ALLOWANCE');
            assert(sender_balance >= amount, 'INSUFFICIENT_BALANCE');
            self.allowances.write(allowance_key, allowance - amount);
            self.balances.write(sender, sender_balance - amount);
            self.balances.write(recipient, self.balances.read(recipient) + amount);
            true
        }

        fn allowance(
            self: @ContractState, owner: ContractAddress, spender: ContractAddress,
        ) -> u256 {
            self.allowances.read((owner, spender))
        }
    }

    #[abi(embed_v0)]
    impl ERC20SnakeImpl of IERC20Snake<ContractState> {
        fn balance_of(self: @ContractState, account: ContractAddress) -> u256 {
            ERC20Impl::balanceOf(self, account)
        }
        fn transfer_from(
            ref self: ContractState,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u256,
        ) -> bool {
            ERC20Impl::transferFrom(ref self, sender, recipient, amount)
        }
    }

    #[abi(embed_v0)]
    impl MockERC20Impl of IMockERC20<ContractState> {
        fn set_failures(ref self: ContractState, transfer_fails: bool, approve_fails: bool) {
            self.transfer_fails.write(transfer_fails);
            self.approve_fails.write(approve_fails);
        }
        fn set_transfer_fee(ref self: ContractState, fee: u128) {
            self.transfer_fee.write(fee);
        }
        fn mint(ref self: ContractState, recipient: ContractAddress, amount: u128) {
            self.balances.write(recipient, self.balances.read(recipient) + amount.into());
            self.total_supply.write(self.total_supply.read() + amount.into());
        }
    }
}
