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
    other_token: ContractAddress,
    route: Route,
}

#[starknet::interface]
trait IRouteFinder<TStorage> {
    // Finds a route between the specified token amount and the other token
    fn find(ref self: TStorage, params: FindParameters) -> FindResult;

    // Compute the quote for executing the given route
    fn quote(ref self: TStorage, params: QuoteParameters) -> i129;
}

#[starknet::contract]
mod RouteFinder {
    use array::{Array, ArrayTrait, SpanTrait};
    use option::{OptionTrait};
    use result::{ResultTrait};
    use zeroable::{Zeroable};

    use ekubo::interfaces::core::{ICoreDispatcher, ICoreDispatcherTrait, ILocker};
    use super::{
        i129, ContractAddress, IRouteFinder, FindParameters, FindResult, PoolKey, Route,
        QuoteParameters
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
    fn constructor(ref self: ContractState, _core: ContractAddress) {
        self.core.write(_core);
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

    #[external(v0)]
    impl RouteFinderLockerImpl of ILocker<ContractState> {
        fn locked(ref self: ContractState, id: u32, data: Array<felt252>) -> Array<felt252> {
            assert(get_caller_address() == self.core.read(), 'UNAUTHORIZED');

            let mut input_span = data.span();
            let mut params_enum: CallbackParameters = Serde::<CallbackParameters>::deserialize(
                ref input_span
            )
                .expect('LOCKED_DESERIALIZE_FAILED');

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

                    let mut output: Array<felt252> = ArrayTrait::new();
                    Serde::<FindResult>::serialize(@result, ref output);

                    panic(output);
                },
                CallbackParameters::QuoteParameters(quote) => {
                    let mut output: Array<felt252> = ArrayTrait::new();
                    Serde::<i129>::serialize(@i129 { mag: 0, sign: false }, ref output);
                    panic(output);
                }
            };

            // we have to return something here because the compiler doesn't consider panic terminal even though it's never reached
            ArrayTrait::new()
        }
    }

    #[external(v0)]
    impl RouteFinderImpl of IRouteFinder<ContractState> {
        fn find(ref self: ContractState, params: FindParameters) -> FindResult {
            let mut input: Array<felt252> = ArrayTrait::new();
            Serde::<CallbackParameters>::serialize(
                @CallbackParameters::FindParameters(params), ref input
            );

            // todo: we can do a little better by just appending the length of the array to input before serializing params to input instead of another round of serialization
            let mut lock_call_arguments: Array<felt252> = ArrayTrait::new();
            Serde::<Array<felt252>>::serialize(@input, ref lock_call_arguments);

            let output = call_contract_syscall(
                self.core.read(),
                0x168652c307c1e813ca11cfb3a601f1cf3b22452021a5052d8b05f1f1f8a3e92,
                lock_call_arguments.span()
            )
                .unwrap_err();

            let mut output_span = output.span();
            let mut result: FindResult = Serde::<FindResult>::deserialize(ref output_span)
                .expect('DESERIALIZE_RESULT_FAILED');
            result
        }

        fn quote(ref self: ContractState, params: QuoteParameters) -> i129 {
            let mut input: Array<felt252> = ArrayTrait::new();
            Serde::<CallbackParameters>::serialize(
                @CallbackParameters::QuoteParameters(params), ref input
            );

            // todo: we can do a little better by just appending the length of the array to input before serializing params to input instead of another round of serialization
            let mut lock_call_arguments: Array<felt252> = ArrayTrait::new();
            Serde::<Array<felt252>>::serialize(@input, ref lock_call_arguments);

            let output = call_contract_syscall(
                self.core.read(),
                0x168652c307c1e813ca11cfb3a601f1cf3b22452021a5052d8b05f1f1f8a3e92,
                lock_call_arguments.span()
            )
                .unwrap_err();

            let mut output_span = output.span();
            let mut result: i129 = Serde::<i129>::deserialize(ref output_span)
                .expect('DESERIALIZE_RESULT_FAILED');
            result
        }
    }
}
