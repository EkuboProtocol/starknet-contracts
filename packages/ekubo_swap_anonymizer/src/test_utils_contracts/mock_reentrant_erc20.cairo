use starknet::ContractAddress;

/// An ERC20 that calls `privacy_invoke` again from inside its own `transfer`.
///
/// The anonymizer credits `balance_after - balance_before` around
/// `clear_minimum`, and `clear_minimum` moves the output token by calling
/// `transfer` on it. A token that re-enters at that moment can make a second
/// invocation's proceeds land inside the first one's measurement window, so
/// this exists to pin down what happens when it does.
#[starknet::interface]
pub trait IMockReentrantERC20<T> {
    fn mint(ref self: T, recipient: ContractAddress, amount: u128);
    /// Re-enter once, on the next `transfer`, with this swap.
    fn arm(
        ref self: T,
        anonymizer: ContractAddress,
        router: ContractAddress,
        in_token: ContractAddress,
        in_amount: u128,
        minimum_received: u256,
    );
    fn did_reenter(self: @T) -> bool;
}

#[starknet::contract]
pub mod MockReentrantERC20 {
    use core::num::traits::Zero;
    use ekubo::interfaces::erc20::IERC20;
    use ekubo::types::keys::PoolKey;
    use ekubo_swap_anonymizer::ekubo_swap_anonymizer::{
        IEkuboSwapAnonymizerDispatcher, IEkuboSwapAnonymizerDispatcherTrait, PrivateRouteNode,
        PrivateSwap,
    };
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_caller_address, get_contract_address};
    use super::IMockReentrantERC20;

    #[storage]
    struct Storage {
        balances: Map<ContractAddress, u128>,
        allowances: Map<(ContractAddress, ContractAddress), u128>,
        armed: bool,
        fired: bool,
        anonymizer: ContractAddress,
        router: ContractAddress,
        in_token: ContractAddress,
        in_amount: u128,
        minimum_received: u256,
    }

    #[constructor]
    fn constructor(ref self: ContractState) {}

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn maybe_reenter(ref self: ContractState) {
            if !self.armed.read() || self.fired.read() {
                return;
            }
            // Once only: the inner invocation transfers this token too.
            self.fired.write(true);

            let out_token = get_contract_address();
            let in_token = self.in_token.read();
            let (token0, token1) = if in_token < out_token {
                (in_token, out_token)
            } else {
                (out_token, in_token)
            };

            IEkuboSwapAnonymizerDispatcher { contract_address: self.anonymizer.read() }
                .privacy_invoke(
                    router_addr: self.router.read(),
                    :in_token,
                    :out_token,
                    in_amount: self.in_amount.read(),
                    swaps: array![
                        PrivateSwap {
                            input_amount: self.in_amount.read(),
                            route: array![
                                PrivateRouteNode {
                                    pool_key: PoolKey {
                                        token0,
                                        token1,
                                        fee: 0,
                                        tick_spacing: 1,
                                        extension: Zero::zero(),
                                    },
                                    skip_ahead: 0,
                                },
                            ],
                        },
                    ],
                    minimum_received: self.minimum_received.read(),
                    note_id: 'INNER',
                );
        }
    }

    #[abi(embed_v0)]
    impl ERC20Impl of IERC20<ContractState> {
        fn transfer(ref self: ContractState, recipient: ContractAddress, amount: u256) -> bool {
            assert(amount.high.is_zero(), 'AMOUNT_OVERFLOW');
            let sender = get_caller_address();
            let sender_balance = self.balances.read(sender);
            assert(sender_balance >= amount.low, 'INSUFFICIENT_BALANCE');
            self.balances.write(sender, sender_balance - amount.low);
            self.balances.write(recipient, self.balances.read(recipient) + amount.low);
            self.maybe_reenter();
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
    impl MockReentrantERC20Impl of IMockReentrantERC20<ContractState> {
        fn mint(ref self: ContractState, recipient: ContractAddress, amount: u128) {
            self.balances.write(recipient, self.balances.read(recipient) + amount);
        }

        fn arm(
            ref self: ContractState,
            anonymizer: ContractAddress,
            router: ContractAddress,
            in_token: ContractAddress,
            in_amount: u128,
            minimum_received: u256,
        ) {
            self.armed.write(true);
            self.fired.write(false);
            self.anonymizer.write(anonymizer);
            self.router.write(router);
            self.in_token.write(in_token);
            self.in_amount.write(in_amount);
            self.minimum_received.write(minimum_received);
        }

        fn did_reenter(self: @ContractState) -> bool {
            self.fired.read()
        }
    }
}
