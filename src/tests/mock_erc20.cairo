use starknet::ContractAddress;
use crate::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};

#[starknet::interface]
pub trait IMockERC20<TContractState> {
    fn set_balance(ref self: TContractState, address: ContractAddress, amount: u128);
    fn increase_balance(ref self: TContractState, address: ContractAddress, amount: u128);
    fn decrease_balance(ref self: TContractState, address: ContractAddress, amount: u128);
}

#[starknet::interface]
trait IERC20StableMetadata<TContractState> {
    fn name(self: @TContractState) -> felt252;
    fn symbol(self: @TContractState) -> felt252;
    fn totalSupply(ref self: TContractState) -> u256;
    fn total_supply(ref self: TContractState) -> u256;
    fn decimals(ref self: TContractState) -> u8;
}


#[generate_trait]
pub impl MockERC20IERC20Impl of MockERC20IERC20ImplTrait {
    fn transfer(self: IMockERC20Dispatcher, recipient: ContractAddress, amount: u256) -> bool {
        IERC20Dispatcher { contract_address: self.contract_address }.transfer(recipient, amount)
    }
    fn balanceOf(self: IMockERC20Dispatcher, account: ContractAddress) -> u256 {
        IERC20Dispatcher { contract_address: self.contract_address }.balanceOf(account)
    }

    fn approve(self: IMockERC20Dispatcher, spender: ContractAddress, amount: u256) -> bool {
        IERC20Dispatcher { contract_address: self.contract_address }.approve(spender, amount)
    }

    fn transferFrom(
        self: IMockERC20Dispatcher,
        sender: ContractAddress,
        recipient: ContractAddress,
        amount: u256,
    ) -> bool {
        IERC20Dispatcher { contract_address: self.contract_address }
            .transferFrom(sender, recipient, amount)
    }
}

#[starknet::contract]
pub mod MockERC20 {
    use core::num::traits::Zero;
    use core::traits::Into;
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_caller_address};
    use crate::interfaces::erc20::IERC20;
    use super::{IERC20StableMetadata, IMockERC20};

    #[storage]
    struct Storage {
        name: felt252,
        symbol: felt252,
        balances: Map<ContractAddress, u128>,
        allowances: Map<(ContractAddress, ContractAddress), u128>,
        total_supply: u128,
    }

    #[derive(starknet::Event, Drop)]
    pub struct Transfer {
        pub from: ContractAddress,
        pub to: ContractAddress,
        pub amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct Approval {
        pub owner: ContractAddress,
        pub spender: ContractAddress,
        pub value: u256,
    }


    #[derive(starknet::Event, Drop)]
    #[event]
    enum Event {
        Transfer: Transfer,
        Approval: Approval,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner: ContractAddress,
        starting_balance: u128,
        name: felt252,
        symbol: felt252,
    ) {
        self.name.write(name);
        self.symbol.write(symbol);
        self.total_supply.write(starting_balance);
        self.balances.write(owner, starting_balance);
        self
            .emit(
                Transfer {
                    from: 0.try_into().unwrap(), to: owner, amount: starting_balance.into(),
                },
            );
    }

    #[abi(embed_v0)]
    impl ERC20Impl of IERC20<ContractState> {
        fn transfer(ref self: ContractState, recipient: ContractAddress, amount: u256) -> bool {
            assert(amount.high.is_zero(), 'AMOUNT_OVERFLOW');
            let from = get_caller_address();
            let from_balance = self.balances.read(from);
            assert(from_balance >= amount.low, 'INSUFFICIENT_BALANCE');
            self.balances.write(from, from_balance - amount.low);
            self.balances.write(recipient, self.balances.read(recipient) + amount.low);
            self.emit(Transfer { from, to: recipient, amount });
            true
        }

        fn balanceOf(self: @ContractState, account: ContractAddress) -> u256 {
            self.balances.read(account).into()
        }

        fn approve(ref self: ContractState, spender: ContractAddress, amount: u256) -> bool {
            let owner = get_caller_address();
            assert(amount.high.is_zero(), 'AMOUNT_OVERFLOW');
            self.allowances.write((owner, spender), amount.low);
            self.emit(Approval { owner, spender, value: amount });
            true
        }

        fn transferFrom(
            ref self: ContractState,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u256,
        ) -> bool {
            assert(amount.high.is_zero(), 'AMOUNT_OVERFLOW');
            let key = (sender, get_caller_address());
            let allowance = self.allowances.read(key);
            assert(allowance >= amount.low, 'INSUFFICIENT_ALLOWANCE');
            let balance_before = self.balances.read(sender);
            assert(balance_before >= amount.low, 'INSUFFICIENT_TF_BALANCE');

            self.allowances.write(key, allowance - amount.low);
            self.balances.write(sender, balance_before - amount.low);
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
        fn set_balance(ref self: ContractState, address: ContractAddress, amount: u128) {
            self.balances.write(address, amount);
        }

        fn increase_balance(ref self: ContractState, address: ContractAddress, amount: u128) {
            self.balances.write(address, self.balances.read(address) + amount);
            self.total_supply.write(self.total_supply.read() + amount);
        }

        fn decrease_balance(ref self: ContractState, address: ContractAddress, amount: u128) {
            self.balances.write(address, self.balances.read(address) - amount);
            self.total_supply.write(self.total_supply.read() - amount);
        }
    }

    #[abi(embed_v0)]
    impl MetadataImpl of IERC20StableMetadata<ContractState> {
        fn name(self: @ContractState) -> felt252 {
            self.name.read()
        }
        fn symbol(self: @ContractState) -> felt252 {
            self.symbol.read()
        }
        fn totalSupply(ref self: ContractState) -> u256 {
            self.total_supply()
        }
        fn total_supply(ref self: ContractState) -> u256 {
            self.total_supply.read().into()
        }
        fn decimals(ref self: ContractState) -> u8 {
            18
        }
    }
}
