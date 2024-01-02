use core::array::{Span};
use ekubo::types::delta::{Delta};
use ekubo::types::i129::{i129};
use ekubo::types::keys::{PoolKey};
use starknet::{ContractAddress};

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
    route: Array<RouteNode>
}

#[derive(Serde, Copy, Drop)]
struct Depth {
    token0: u128,
    token1: u128,
}

#[starknet::interface]
trait IRouter<TContractState> {
    // Execute a swap against a route, and revert if it does not return at least the calculated amount. 
    // The required input amount must already be transferred to this contract.
    fn execute(
        ref self: TContractState,
        swap: Swap,
        calculated_amount_threshold: u128,
        recipient: ContractAddress
    ) -> TokenAmount;

    // Does a single swap against a single node using tokens held by this contract, and receives the output to this contract
    fn raw_swap(ref self: TContractState, node: RouteNode, token_amount: TokenAmount) -> Delta;

    // Quote the given token amount against the route in the swap
    fn quote(ref self: TContractState, swap: Swap) -> TokenAmount;

    // Returns the delta for swapping a pool to the given price
    fn get_delta_to_sqrt_ratio(self: @TContractState, pool_key: PoolKey, sqrt_ratio: u256) -> Delta;

    // Returns the amount available for purchase for swapping +/- the given percent, expressed as a 0.128 number
    // Note this is a square root of the percent
    // e.g. if you want to get the 2% market depth, you'd pass FLOOR((sqrt(1.02) - 1) * 2**128) = 3385977594616997568912048723923598803
    fn get_market_depth(self: @TContractState, pool_key: PoolKey, sqrt_percent: u128) -> Depth;
}

#[starknet::contract]
mod Router {
    use core::array::{Array, ArrayTrait, SpanTrait};
    use core::num::traits::{Zero};
    use core::option::{OptionTrait};
    use core::result::{ResultTrait};
    use core::traits::{Into};
    use ekubo::clear::{ClearImpl};
    use ekubo::interfaces::core::{ICoreDispatcher, ICoreDispatcherTrait, ILocker, SwapParameters};
    use ekubo::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use ekubo::math::muldiv::{muldiv};
    use ekubo::math::swap::{is_price_increasing};
    use ekubo::math::ticks::{max_sqrt_ratio, min_sqrt_ratio, sqrt_ratio_to_tick};
    use ekubo::shared_locker::{consume_callback_data, handle_delta, call_core_with_callback};
    use ekubo::types::i129::{i129, i129Trait};
    use starknet::syscalls::{call_contract_syscall};

    use starknet::{get_caller_address, get_contract_address};

    use super::{ContractAddress, PoolKey, Delta, IRouter, RouteNode, Swap, TokenAmount, Depth};

    #[abi(embed_v0)]
    impl Clear = ekubo::clear::ClearImpl<ContractState>;

    #[storage]
    struct Storage {
        core: ICoreDispatcher,
    }

    #[constructor]
    fn constructor(ref self: ContractState, core: ICoreDispatcher) {
        self.core.write(core);
    }

    #[derive(Drop, Serde)]
    enum CallbackParameters {
        Execute: (Swap, u128, ContractAddress),
        RawSwap: (RouteNode, TokenAmount),
        Quote: Swap,
        GetDeltaToSqrtRatio: (PoolKey, u256),
        GetMarketDepth: (PoolKey, u128),
    }

    const FUNCTION_DID_NOT_ERROR_FLAG: felt252 =
        0x3f532df6e73f94d604f4eb8c661635595c91adc1d387931451eacd418cfbd14; // hash of function_did_not_error

    #[external(v0)]
    impl LockerImpl of ILocker<ContractState> {
        fn locked(ref self: ContractState, id: u32, data: Array<felt252>) -> Array<felt252> {
            let core = self.core.read();

            match consume_callback_data::<CallbackParameters>(core, data) {
                CallbackParameters::Execute((
                    swap, calculated_amount_threshold, recipient
                )) => {
                    let mut calculated_token_amount: TokenAmount = swap.token_amount;
                    let mut route = swap.route;
                    let mut payment_amount: Option<u128> = Option::None;

                    loop {
                        calculated_token_amount = match route.pop_front() {
                            Option::Some(node) => {
                                let is_token1 = calculated_token_amount
                                    .token == node
                                    .pool_key
                                    .token1;

                                let mut sqrt_ratio_limit = node.sqrt_ratio_limit;
                                if (sqrt_ratio_limit.is_zero()) {
                                    sqrt_ratio_limit =
                                        if is_price_increasing(
                                            calculated_token_amount.amount.sign, is_token1
                                        ) {
                                            max_sqrt_ratio()
                                        } else {
                                            min_sqrt_ratio()
                                        };
                                }

                                let delta = core
                                    .swap(
                                        node.pool_key,
                                        SwapParameters {
                                            amount: calculated_token_amount.amount,
                                            is_token1: is_token1,
                                            sqrt_ratio_limit,
                                            skip_ahead: node.skip_ahead,
                                        }
                                    );

                                let is_first_exact_input = !swap.token_amount.amount.sign
                                    & payment_amount.is_none();

                                if (is_token1) {
                                    if (is_first_exact_input) {
                                        payment_amount = Option::Some(delta.amount1.mag);
                                    }
                                    TokenAmount {
                                        amount: -delta.amount0, token: node.pool_key.token0
                                    }
                                } else {
                                    if (is_first_exact_input) {
                                        payment_amount = Option::Some(delta.amount0.mag);
                                    }
                                    TokenAmount {
                                        amount: -delta.amount1, token: node.pool_key.token1
                                    }
                                }
                            },
                            Option::None => { break calculated_token_amount; }
                        };
                    };

                    if swap.token_amount.amount.sign {
                        assert(
                            calculated_token_amount.amount.mag <= calculated_amount_threshold,
                            'MAX_AMOUNT_IN'
                        );

                        // pay the computed input amount
                        IERC20Dispatcher { contract_address: calculated_token_amount.token }
                            .transfer(
                                core.contract_address, calculated_token_amount.amount.mag.into()
                            );
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
                                swap.token_amount.token, recipient, swap.token_amount.amount.mag
                            );
                    } else {
                        assert(
                            calculated_token_amount.amount.mag >= calculated_amount_threshold,
                            'MIN_AMOUNT_OUT'
                        );

                        // pay the computed input amount
                        match payment_amount {
                            Option::Some(amount) => {
                                if (amount > 0) {
                                    IERC20Dispatcher { contract_address: swap.token_amount.token }
                                        .transfer(core.contract_address, amount.into());
                                    let paid_amount = core.deposit(swap.token_amount.token);
                                    if (paid_amount > amount) {
                                        core
                                            .withdraw(
                                                swap.token_amount.token,
                                                get_contract_address(),
                                                paid_amount - swap.token_amount.amount.mag
                                            );
                                    }
                                }
                            },
                            Option::None => {}
                        }

                        // withdraw the calculated output amount
                        core
                            .withdraw(
                                calculated_token_amount.token,
                                recipient,
                                calculated_token_amount.amount.mag
                            );
                    }

                    let mut output: Array<felt252> = ArrayTrait::new();
                    Serde::serialize(@calculated_token_amount, ref output);
                    output
                },
                CallbackParameters::RawSwap((
                    node, token_amount
                )) => {
                    let is_token1 = token_amount.token == node.pool_key.token1;

                    let mut sqrt_ratio_limit = node.sqrt_ratio_limit;
                    if (sqrt_ratio_limit.is_zero()) {
                        sqrt_ratio_limit =
                            if is_price_increasing(token_amount.amount.sign, is_token1) {
                                max_sqrt_ratio()
                            } else {
                                min_sqrt_ratio()
                            };
                    }

                    let delta = core
                        .swap(
                            node.pool_key,
                            SwapParameters {
                                amount: token_amount.amount,
                                is_token1,
                                sqrt_ratio_limit,
                                skip_ahead: node.skip_ahead,
                            }
                        );

                    let contract_address = get_contract_address();
                    handle_delta(core, node.pool_key.token0, delta.amount0, contract_address);
                    handle_delta(core, node.pool_key.token1, delta.amount1, contract_address);

                    let mut output: Array<felt252> = ArrayTrait::new();
                    Serde::serialize(@delta, ref output);
                    output
                },
                CallbackParameters::Quote(swap) => {
                    let mut route = swap.route;
                    let mut amount: i129 = swap.token_amount.amount;
                    let mut current_token: ContractAddress = swap.token_amount.token;

                    loop {
                        match route.pop_front() {
                            Option::Some(node) => {
                                let is_token1 = if (node.pool_key.token0 == current_token) {
                                    false
                                } else {
                                    assert(node.pool_key.token1 == current_token, 'INVALID_ROUTE');
                                    true
                                };

                                let mut sqrt_ratio_limit = node.sqrt_ratio_limit;
                                if (sqrt_ratio_limit.is_zero()) {
                                    sqrt_ratio_limit =
                                        if is_price_increasing(amount.sign, is_token1) {
                                            max_sqrt_ratio()
                                        } else {
                                            min_sqrt_ratio()
                                        };
                                }

                                let delta = core
                                    .swap(
                                        node.pool_key,
                                        SwapParameters {
                                            amount: amount,
                                            is_token1: is_token1,
                                            sqrt_ratio_limit: sqrt_ratio_limit,
                                            skip_ahead: 0,
                                        }
                                    );

                                if is_token1 {
                                    amount = delta.amount0;
                                    current_token = node.pool_key.token0;
                                } else {
                                    amount = delta.amount1;
                                    current_token = node.pool_key.token1;
                                };

                                if (route.len().is_non_zero()) {
                                    amount = -amount;
                                };
                            },
                            Option::None => { break (); },
                        };
                    };

                    let mut output: Array<felt252> = ArrayTrait::new();

                    Serde::serialize(@FUNCTION_DID_NOT_ERROR_FLAG, ref output);
                    Serde::serialize(@TokenAmount { amount, token: current_token }, ref output);
                    panic(output);

                    // this isn't actually used, but we have to return it because panic is not recognized as end of execution
                    ArrayTrait::new()
                },
                CallbackParameters::GetDeltaToSqrtRatio((
                    pool_key, sqrt_ratio
                )) => {
                    let current_pool_price = core.get_pool_price(pool_key);
                    let skip_ahead: u128 = ((current_pool_price.tick
                        - sqrt_ratio_to_tick(sqrt_ratio))
                        .mag
                        / (pool_key.tick_spacing * 127_u128))
                        .try_into()
                        .expect('TICK_DIFF_TOO_LARGE');

                    let delta = core
                        .swap(
                            pool_key,
                            SwapParameters {
                                amount: i129 {
                                    mag: 340282366920938463463374607431768211455, sign: true
                                },
                                is_token1: sqrt_ratio <= current_pool_price.sqrt_ratio,
                                sqrt_ratio_limit: sqrt_ratio,
                                skip_ahead,
                            }
                        );

                    let mut output: Array<felt252> = ArrayTrait::new();

                    Serde::serialize(@FUNCTION_DID_NOT_ERROR_FLAG, ref output);
                    Serde::serialize(@delta, ref output);
                    panic(output);

                    // this isn't actually used, but we have to return it because panic is not recognized as end of execution
                    ArrayTrait::new()
                },
                CallbackParameters::GetMarketDepth((
                    pool_key, sqrt_percent
                )) => {
                    let current_pool_price = core.get_pool_price(pool_key);
                    let price_high = muldiv(
                        current_pool_price.sqrt_ratio,
                        u256 { high: 1, low: sqrt_percent },
                        u256 { high: 1, low: 0 },
                        false
                    )
                        .unwrap_or(max_sqrt_ratio());
                    let price_low = muldiv(
                        current_pool_price.sqrt_ratio,
                        u256 { high: 1, low: 0 } - u256 { high: 0, low: sqrt_percent },
                        u256 { high: 1, low: 0 },
                        false
                    )
                        .unwrap_or(min_sqrt_ratio());

                    let delta_high = core
                        .swap(
                            pool_key,
                            SwapParameters {
                                amount: i129 {
                                    mag: 340282366920938463463374607431768211455, sign: true
                                },
                                is_token1: false,
                                sqrt_ratio_limit: price_high,
                                skip_ahead: 0,
                            }
                        );

                    // swap back to starting price
                    core
                        .swap(
                            pool_key,
                            SwapParameters {
                                amount: i129 {
                                    mag: 340282366920938463463374607431768211455, sign: true
                                },
                                is_token1: true,
                                sqrt_ratio_limit: current_pool_price.sqrt_ratio,
                                skip_ahead: 0,
                            }
                        );

                    let delta_low = core
                        .swap(
                            pool_key,
                            SwapParameters {
                                amount: i129 {
                                    mag: 340282366920938463463374607431768211455, sign: true
                                },
                                is_token1: true,
                                sqrt_ratio_limit: price_low,
                                skip_ahead: 0,
                            }
                        );

                    let mut output: Array<felt252> = ArrayTrait::new();

                    Serde::serialize(@FUNCTION_DID_NOT_ERROR_FLAG, ref output);

                    let depth = Depth {
                        token0: delta_high.amount0.mag, token1: delta_low.amount1.mag,
                    };

                    Serde::serialize(@depth, ref output);
                    panic(output);

                    // this isn't actually used, but we have to return it because panic is not recognized as end of execution
                    ArrayTrait::new()
                },
            }
        }
    }

    fn call_core_with_reverting_callback<TInput, TOutput, +Serde<TInput>, +Serde<TOutput>>(
        core: ICoreDispatcher, input: @TInput
    ) -> TOutput {
        let mut input_data: Array<felt252> = ArrayTrait::new();
        Serde::serialize(input, ref input_data);

        // todo: we can do a little better by just appending the length of the array to input before serializing params to input instead of another round of serialization
        let mut lock_call_arguments: Array<felt252> = ArrayTrait::new();
        Serde::<Array<felt252>>::serialize(@input_data, ref lock_call_arguments);

        let output = call_contract_syscall(
            core.contract_address,
            0x168652c307c1e813ca11cfb3a601f1cf3b22452021a5052d8b05f1f1f8a3e92,
            lock_call_arguments.span()
        )
            .unwrap_err();

        if (*output.at(0) != FUNCTION_DID_NOT_ERROR_FLAG) {
            // whole output is an internal panic
            panic(output);
        }

        let mut output_span = output.span();
        output_span.pop_front();
        let mut result: TOutput = Serde::deserialize(ref output_span)
            .expect('DESERIALIZE_RESULT_FAILED');
        result
    }

    #[external(v0)]
    impl RouterImpl of IRouter<ContractState> {
        fn execute(
            ref self: ContractState,
            swap: Swap,
            calculated_amount_threshold: u128,
            recipient: ContractAddress
        ) -> TokenAmount {
            call_core_with_callback(
                self.core.read(),
                @CallbackParameters::Execute((swap, calculated_amount_threshold, recipient))
            )
        }

        fn raw_swap(ref self: ContractState, node: RouteNode, token_amount: TokenAmount) -> Delta {
            call_core_with_callback(
                self.core.read(), @CallbackParameters::RawSwap((node, token_amount))
            )
        }

        // Quote the given token amount against the route in the swap
        fn quote(ref self: ContractState, swap: Swap) -> TokenAmount {
            call_core_with_reverting_callback(self.core.read(), @CallbackParameters::Quote(swap))
        }

        // Returns the delta for swapping a pool to the given price
        fn get_delta_to_sqrt_ratio(
            self: @ContractState, pool_key: PoolKey, sqrt_ratio: u256
        ) -> Delta {
            call_core_with_reverting_callback(
                self.core.read(), @CallbackParameters::GetDeltaToSqrtRatio((pool_key, sqrt_ratio))
            )
        }

        // Returns the amount available for purchase for swapping +/- the given percent, expressed as a 0.128 number
        fn get_market_depth(self: @ContractState, pool_key: PoolKey, sqrt_percent: u128) -> Depth {
            call_core_with_reverting_callback(
                self.core.read(), @CallbackParameters::GetMarketDepth((pool_key, sqrt_percent))
            )
        }
    }
}
