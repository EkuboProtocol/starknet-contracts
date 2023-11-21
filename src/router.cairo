use ekubo::types::delta::{Delta};
use ekubo::types::keys::{PoolKey};
use starknet::{ContractAddress};
use ekubo::types::i129::{i129};
use array::{Span};

#[derive(Serde, Copy, Drop)]
struct RouteNode {
    pool_key: PoolKey,
    sqrt_ratio_limit: u256,
    skip_ahead: u128,
}

#[derive(Serde, Copy, Drop)]
struct TokenAmount {
    token: ContractAddress,
    amount: i129,
}

#[derive(Serde, Drop)]
struct Swap {
    token_amount: TokenAmount,
    route: Array<RouteNode>,
    calculated_amount_threshold: u128,
    recipient: ContractAddress
}

#[starknet::interface]
trait IRouter<TStorage> {
    // Execute a swap against a route. The input tokens must already be transferred to this contract.
    fn execute(ref self: TStorage, swap: Swap) -> TokenAmount;

    // Clear the balance held by this contract. Used for collecting remaining tokens after a swap.
    fn clear(ref self: TStorage, token: ContractAddress) -> u256;
}

#[starknet::contract]
mod Router {
    use array::{Array, ArrayTrait, SpanTrait};

    use super::{ContractAddress, PoolKey, Delta, IRouter, RouteNode, Swap, TokenAmount};
    use ekubo::interfaces::core::{ICoreDispatcher, ICoreDispatcherTrait, ILocker, SwapParameters};
    use ekubo::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use ekubo::math::swap::{is_price_increasing};
    use ekubo::shared_locker::{consume_callback_data, call_core_with_callback};
    use ekubo::types::i129::{i129Trait};
    use option::{OptionTrait};
    use result::{ResultTrait};
    use starknet::syscalls::{call_contract_syscall};

    use starknet::{get_caller_address, get_contract_address};
    use traits::{Into};
    use zeroable::{Zeroable};

    #[storage]
    struct Storage {
        core: ICoreDispatcher,
    }

    #[constructor]
    fn constructor(ref self: ContractState, core: ICoreDispatcher) {
        self.core.write(core);
    }

    #[external(v0)]
    impl LockerImpl of ILocker<ContractState> {
        fn locked(ref self: ContractState, id: u32, data: Array<felt252>) -> Array<felt252> {
            let core = self.core.read();

            let swap = consume_callback_data::<Swap>(core, data);

            let mut calculated_token_amount: TokenAmount = swap.token_amount;
            let mut route = swap.route.span();

            calculated_token_amount =
                loop {
                    calculated_token_amount = match route.pop_front() {
                        Option::Some(node) => {
                            let is_token1 = calculated_token_amount.token == *node.pool_key.token1;

                            let delta = core
                                .swap(
                                    *node.pool_key,
                                    SwapParameters {
                                        amount: calculated_token_amount.amount,
                                        is_token1: is_token1,
                                        sqrt_ratio_limit: *node.sqrt_ratio_limit,
                                        skip_ahead: *node.skip_ahead,
                                    }
                                );

                            if (is_token1) {
                                TokenAmount { amount: -delta.amount0, token: *node.pool_key.token0 }
                            } else {
                                TokenAmount { amount: -delta.amount1, token: *node.pool_key.token1 }
                            }
                        },
                        Option::None => { break calculated_token_amount; }
                    };
                };

            // check the result of the swap exceeds the threshold
            if swap.token_amount.amount.sign {
                assert(
                    calculated_token_amount.amount.mag >= swap.calculated_amount_threshold,
                    'MIN_AMOUNT_OUT'
                );

                // pay the computed input amount
                IERC20Dispatcher { contract_address: calculated_token_amount.token }
                    .transfer(core.contract_address, calculated_token_amount.amount.mag.into());
                let paid_amount = core.deposit(calculated_token_amount.token);
                if (paid_amount > calculated_token_amount.amount.mag) {
                    core
                        .withdraw(
                            calculated_token_amount.token,
                            get_contract_address(),
                            paid_amount - calculated_token_amount.amount.mag
                        );
                }
                // withdraw the output amount
                core
                    .withdraw(
                        swap.token_amount.token, swap.recipient, swap.token_amount.amount.mag
                    );
            } else {
                assert(
                    calculated_token_amount.amount.mag <= swap.calculated_amount_threshold,
                    'MAX_AMOUNT_IN'
                );

                // pay the specified input amount
                IERC20Dispatcher { contract_address: swap.token_amount.token }
                    .transfer(core.contract_address, swap.token_amount.amount.mag.into());
                let paid_amount = core.deposit(swap.token_amount.token);
                if (paid_amount > swap.token_amount.amount.mag) {
                    core
                        .withdraw(
                            swap.token_amount.token,
                            get_contract_address(),
                            paid_amount - swap.token_amount.amount.mag
                        );
                }

                // withdraw the calculated output amount
                core
                    .withdraw(
                        calculated_token_amount.token,
                        swap.recipient,
                        calculated_token_amount.amount.mag
                    );
            }

            let mut output: Array<felt252> = ArrayTrait::new();
            Serde::serialize(@calculated_token_amount, ref output);
            output
        }
    }


    #[external(v0)]
    impl RouterImpl of IRouter<ContractState> {
        fn execute(ref self: ContractState, swap: Swap) -> TokenAmount {
            call_core_with_callback(self.core.read(), @swap)
        }

        fn clear(ref self: ContractState, token: ContractAddress) -> u256 {
            let dispatcher = IERC20Dispatcher { contract_address: token };
            let balance = dispatcher.balanceOf(get_contract_address());
            if (balance.is_non_zero()) {
                dispatcher.transfer(get_caller_address(), balance);
            }
            balance
        }
    }
}
