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
struct FindResult {
    found: bool,
    relevant_pool_count: u32,
}

#[starknet::interface]
trait IRouteFinder<TStorage> {
    // Finds a route between the specified token amount and the other token
    fn find(ref self: TStorage, params: FindParameters) -> FindResult;
}

#[starknet::contract]
mod RouteFinder {
    use array::{Array, ArrayTrait, SpanTrait};
    use option::{OptionTrait};
    use result::{ResultTrait};
    use zeroable::{Zeroable};

    use ekubo::interfaces::core::{ICoreDispatcher, ICoreDispatcherTrait, ILocker};
    use super::{i129, ContractAddress, IRouteFinder, FindParameters, FindResult, PoolKey};

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

    #[external(v0)]
    impl RouteFinderLockerImpl of ILocker<ContractState> {
        fn locked(ref self: ContractState, id: u32, data: Array<felt252>) -> Array<felt252> {
            assert(get_caller_address() == self.core.read(), 'UNAUTHORIZED');

            let mut input_span = data.span();
            let mut params: FindParameters = Serde::<FindParameters>::deserialize(ref input_span)
                .expect('LOCKED_DESERIALIZE_FAILED');

            // todo: compute a route across all the pools
            let result = FindResult {
                found: params.amount.is_zero(),
                relevant_pool_count: filter_to_relevant_pools(
                    params.pool_keys, params.specified_token
                )
                    .len()
            };

            let mut output: Array<felt252> = ArrayTrait::new();
            Serde::<FindResult>::serialize(@result, ref output);

            panic(output);
            // we have to return something here because the compiler doesn't consider panic terminal even though it's never reached
            output
        }
    }

    #[external(v0)]
    impl RouteFinderImpl of IRouteFinder<ContractState> {
        fn find(ref self: ContractState, params: FindParameters) -> FindResult {
            let mut input: Array<felt252> = ArrayTrait::new();
            Serde::<FindParameters>::serialize(@params, ref input);

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
    }
}
