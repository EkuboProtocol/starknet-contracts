use ekubo::types::i129::i129;
use ekubo::types::keys::{PoolKey};
use starknet::{ContractAddress};

#[derive(Drop, Copy, Serde)]
struct FindParameters {
    amount: i129,
    specified_token: ContractAddress,
    other_token: ContractAddress,
    pool_keys: Span<PoolKey>,
}

#[derive(Drop, Copy, Serde)]
struct Route {
    pool_keys: Span<PoolKey>, 
}

#[derive(Drop, Copy, Serde)]
struct FindResult {
    route: Route,
    other_token_amount: i129,
}

#[derive(Drop, Copy, Serde)]
struct QuoteParameters {
    amount: i129,
    specified_token: ContractAddress,
    route: Route,
}

#[derive(Drop, Copy, Serde)]
struct QuoteResult {
    amount: i129,
    other_token: ContractAddress,
}

#[starknet::interface]
trait IRouteFinder<TStorage> {
    // Finds a route between the specified token amount and the other token
    fn find(ref self: TStorage, params: FindParameters) -> FindResult;

    // Compute the quote for executing the given route
    fn quote(ref self: TStorage, params: QuoteParameters) -> QuoteResult;
}

#[starknet::contract]
mod RouteFinder {
    use array::{Array, ArrayTrait, SpanTrait};
    use option::{OptionTrait};
    use result::{ResultTrait};
    use zeroable::{Zeroable};

    use ekubo::interfaces::core::{ICoreDispatcher, ICoreDispatcherTrait, SwapParameters, ILocker};
    use ekubo::math::swap::{is_price_increasing};
    use ekubo::math::ticks::{max_sqrt_ratio, min_sqrt_ratio};
    use super::{
        i129, ContractAddress, IRouteFinder, FindParameters, FindResult, PoolKey, Route,
        QuoteParameters, QuoteResult
    };

    use starknet::{get_caller_address};
    use starknet::syscalls::{call_contract_syscall};

    use debug::PrintTrait;

    impl PrintSpanFelt252 of PrintTrait<Span<felt252>> {
        fn print(self: Span<felt252>) {
            let mut span = self.slice(0, self.len());
            loop {
                match span.pop_front() {
                    Option::Some(x) => {
                        (*x).print();
                    },
                    Option::None(()) => {
                        break ();
                    },
                };
            };
        }
    }

    #[storage]
    struct Storage {
        core: ContractAddress, 
    }


    #[constructor]
    fn constructor(ref self: ContractState, core: ContractAddress) {
        self.core.write(core);
    }

    // Filter the pools in the span to those that contain the specified token
    fn filter_to_relevant_pools(mut x: Span<PoolKey>, token: ContractAddress) -> Array<PoolKey> {
        let mut res: Array<PoolKey> = Default::default();

        loop {
            match x.pop_front() {
                Option::Some(pool_key) => {
                    if ((*pool_key.token0 == token) | (*pool_key.token1 == token)) {
                        res.append(*pool_key);
                    }
                },
                Option::None(()) => {
                    break ();
                },
            };
        };

        res
    }

    #[derive(Drop, Copy, Serde)]
    enum CallbackParameters {
        FindParameters: FindParameters,
        QuoteParameters: QuoteParameters,
    }

    const FUNCTION_DID_NOT_ERROR_FLAG: felt252 =
        0x3f532df6e73f94d604f4eb8c661635595c91adc1d387931451eacd418cfbd14; // hash of function_did_not_error

    #[external(v0)]
    impl RouteFinderLockerImpl of ILocker<ContractState> {
        fn locked(ref self: ContractState, id: u32, data: Array<felt252>) -> Array<felt252> {
            let core = ICoreDispatcher { contract_address: self.core.read() };

            assert(get_caller_address() == core.contract_address, 'UNAUTHORIZED');

            let mut input_span = data.span();
            let mut params_enum: CallbackParameters = Serde::<CallbackParameters>::deserialize(
                ref input_span
            )
                .expect('LOCKED_DESERIALIZE_FAILED');

            let mut output: Array<felt252> = ArrayTrait::new();
            Serde::<felt252>::serialize(@FUNCTION_DID_NOT_ERROR_FLAG, ref output);

            match params_enum {
                CallbackParameters::FindParameters(params) => {
                    let pools_containing_both_tokens = filter_to_relevant_pools(
                        filter_to_relevant_pools(params.pool_keys, params.specified_token).span(),
                        params.other_token
                    );

                    // todo: compute a route across all the pools
                    let route: Route = Route { pool_keys: pools_containing_both_tokens.span() };
                    let result = FindResult {
                        route: route, other_token_amount: Zeroable::zero(), 
                    };

                    Serde::<FindResult>::serialize(@result, ref output);
                    panic(output);
                },
                CallbackParameters::QuoteParameters(params) => {
                    let mut pool_keys = params.route.pool_keys;
                    let mut amount: i129 = params.amount;
                    let mut current_token: ContractAddress = params.specified_token;

                    loop {
                        let next = pool_keys.pop_front();

                        match next {
                            Option::Some(pool_key) => {
                                let is_token1 = if (*pool_key.token0 == current_token) {
                                    false
                                } else {
                                    assert(*pool_key.token1 == current_token, 'INVALID_ROUTE');
                                    true
                                };

                                let sqrt_ratio_limit = if is_price_increasing(
                                    amount.sign, is_token1
                                ) {
                                    max_sqrt_ratio()
                                } else {
                                    min_sqrt_ratio()
                                };

                                let delta = core
                                    .swap(
                                        *pool_key,
                                        SwapParameters {
                                            amount: amount,
                                            is_token1: is_token1,
                                            sqrt_ratio_limit: sqrt_ratio_limit,
                                            skip_ahead: 0,
                                        }
                                    );

                                if is_token1 {
                                    amount = delta.amount0;
                                    current_token = *pool_key.token0;
                                } else {
                                    amount = delta.amount1;
                                    current_token = *pool_key.token1;
                                };

                                if (pool_keys.len() != 0) {
                                    amount = -amount;
                                };
                            },
                            Option::None(_) => {
                                break ();
                            },
                        };
                    };

                    Serde::<QuoteResult>::serialize(
                        @QuoteResult { amount, other_token: current_token }, ref output
                    );
                    panic(output);
                }
            };

            // we have to return something here because the compiler doesn't consider panic terminal even though it's never reached
            ArrayTrait::new()
        }
    }

    fn call_core_with_callback<
        TInput, impl TSerdeInput: Serde<TInput>, TOutput, impl TSerdeOutput: Serde<TOutput>, 
    >(
        core: ContractAddress, input: @TInput
    ) -> TOutput {
        let mut input_data: Array<felt252> = ArrayTrait::new();
        Serde::serialize(input, ref input_data);

        // todo: we can do a little better by just appending the length of the array to input before serializing params to input instead of another round of serialization
        let mut lock_call_arguments: Array<felt252> = ArrayTrait::new();
        Serde::<Array<felt252>>::serialize(@input_data, ref lock_call_arguments);

        let output = call_contract_syscall(
            core,
            0x168652c307c1e813ca11cfb3a601f1cf3b22452021a5052d8b05f1f1f8a3e92,
            lock_call_arguments.span()
        )
            .unwrap_err();

        if (*output.at(0) != FUNCTION_DID_NOT_ERROR_FLAG) {
            // whole output is an internal panic
            panic(output);
        }

        let mut output_span = output.span().slice(1, output.len() - 1);
        let mut result: TOutput = Serde::deserialize(ref output_span)
            .expect('DESERIALIZE_RESULT_FAILED');
        result
    }

    #[external(v0)]
    impl RouteFinderImpl of IRouteFinder<ContractState> {
        fn find(ref self: ContractState, params: FindParameters) -> FindResult {
            call_core_with_callback(self.core.read(), @CallbackParameters::FindParameters(params))
        }

        fn quote(ref self: ContractState, params: QuoteParameters) -> QuoteResult {
            call_core_with_callback(self.core.read(), @CallbackParameters::QuoteParameters(params))
        }
    }
}
