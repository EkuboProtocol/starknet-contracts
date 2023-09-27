#[starknet::contract]
mod SimpleERC20 {
    use ekubo::interfaces::erc20::{IERC20};
    use starknet::{ContractAddress, contract_address_const, get_caller_address};
    use traits::{Into};
    use option::{OptionTrait};
    use zeroable::{Zeroable};

    #[storage]
    struct Storage {
        balances: LegacyMap<ContractAddress, u128>,
    }

    #[derive(starknet::Event, Drop)]
    struct Transfer {
        from: ContractAddress,
        to: ContractAddress,
        amount: u256,
    }

    #[derive(starknet::Event, Drop)]
    #[event]
    enum Event {
        Transfer: Transfer,
    }

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress) {
        self.balances.write(owner, 0xffffffffffffffffffffffffffffffff);
        self
            .emit(
                Transfer {
                    from: contract_address_const::<0>(),
                    to: owner,
                    amount: 0xffffffffffffffffffffffffffffffff.into()
                }
            );
    }

    #[external(v0)]
    impl ERC20Impl of IERC20<ContractState> {
        fn transfer(ref self: ContractState, recipient: ContractAddress, amount: u256) -> bool {
            assert(amount.high.is_zero(), 'AMOUNT_OVERFLOW');
            let from = get_caller_address();
            self.balances.write(from, self.balances.read(from) - amount.low);
            self.balances.write(recipient, self.balances.read(recipient) + amount.low);
            self.emit(Transfer { from, to: recipient, amount });
            true
        }

        fn balanceOf(self: @ContractState, account: ContractAddress) -> u256 {
            self.balances.read(account).into()
        }
    }
}
