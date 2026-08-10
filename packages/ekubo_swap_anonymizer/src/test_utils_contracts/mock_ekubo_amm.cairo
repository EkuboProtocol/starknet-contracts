use ekubo::interfaces::erc20::IERC20Dispatcher;
use ekubo::interfaces::router::Swap;

#[derive(Copy, Drop, Serde, PartialEq, starknet::Store)]
pub enum SwapBehavior {
    #[default]
    Normal,
    Noop,
    PartialSwap,
}

#[starknet::interface]
pub trait IMockEkuboAMMControl<T> {
    fn set_swap_behavior(ref self: T, behavior: SwapBehavior);
}

#[starknet::interface]
pub trait IMultiMultihopRouter<T> {
    fn multi_multihop_swap(
        ref self: T, swaps: Array<Swap>,
    ) -> Array<Array<ekubo::types::delta::Delta>>;
}

#[starknet::interface]
pub trait IClear<T> {
    fn clear(self: @T, token: IERC20Dispatcher) -> u256;
    fn clear_minimum(self: @T, token: IERC20Dispatcher, minimum: u256) -> u256;
}

#[starknet::contract]
pub mod MockEkuboAMM {
    use core::num::traits::Zero;
    use ekubo::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use ekubo::interfaces::router::Swap;
    use ekubo::types::delta::Delta;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::{ContractAddress, get_caller_address, get_contract_address};
    use super::{IClear, IMockEkuboAMMControl, IMultiMultihopRouter, SwapBehavior};

    const DEAD_ADDRESS: ContractAddress = 'DEAD_ADDRESS'.try_into().unwrap();

    #[storage]
    struct Storage {
        swap_behavior: SwapBehavior,
    }

    #[constructor]
    fn constructor(ref self: ContractState) {}

    #[abi(embed_v0)]
    impl MockEkuboAMMControlImpl of IMockEkuboAMMControl<ContractState> {
        fn set_swap_behavior(ref self: ContractState, behavior: SwapBehavior) {
            self.swap_behavior.write(behavior);
        }
    }

    #[abi(embed_v0)]
    impl MultiMultihopRouterImpl of IMultiMultihopRouter<ContractState> {
        fn multi_multihop_swap(
            ref self: ContractState, mut swaps: Array<Swap>,
        ) -> Array<Array<Delta>> {
            let mut result = array![];

            while let Option::Some(swap) = swaps.pop_front() {
                let amount = swap.token_amount.amount.mag;
                let consumed = match self.swap_behavior.read() {
                    SwapBehavior::Normal | SwapBehavior::Noop => amount,
                    SwapBehavior::PartialSwap => amount / 2,
                };
                IERC20Dispatcher { contract_address: swap.token_amount.token }
                    .transfer(recipient: DEAD_ADDRESS, amount: consumed.into());
                result.append(array![]);
            }

            result
        }
    }

    #[abi(embed_v0)]
    impl ClearImpl of IClear<ContractState> {
        fn clear(self: @ContractState, token: IERC20Dispatcher) -> u256 {
            self.clear_minimum(:token, minimum: 0)
        }

        fn clear_minimum(self: @ContractState, token: IERC20Dispatcher, minimum: u256) -> u256 {
            if self.swap_behavior.read() == SwapBehavior::Noop {
                return Zero::zero();
            }

            let balance = token.balanceOf(get_contract_address());
            assert(balance >= minimum, 'CLEAR_MINIMUM_NOT_MET');
            if balance.is_non_zero() {
                token.transfer(recipient: get_caller_address(), amount: balance);
            }
            balance
        }
    }
}
