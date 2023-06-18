use ekubo::types::i129::i129;
use starknet::{ContractAddress};

#[derive(Drop, Copy, Serde)]
struct FindParameters {
    amount: i129,
    specified_token: ContractAddress,
    other_token: ContractAddress,
}

#[derive(Drop, Copy, Serde)]
struct FindResult {
    found: bool, 
}

#[starknet::interface]
trait IRouteFinder<TStorage> {
    // Finds a route between the specified token amount and the other token
    fn find(ref self: TStorage, params: FindParameters) -> FindResult;
}

#[starknet::contract]
mod RouteFinder {
    use array::{ArrayTrait};
    use option::{OptionTrait};
    use result::{ResultTrait};
    use zeroable::{Zeroable};

    use ekubo::interfaces::core::{ICoreDispatcher, ICoreDispatcherTrait, ILocker};
    use super::{i129, ContractAddress, IRouteFinder, FindParameters, FindResult};

    use starknet::{get_caller_address};
    use starknet::syscalls::{call_contract_syscall};

    #[storage]
    struct Storage {
        core: ContractAddress, 
    }


    #[constructor]
    fn constructor(ref self: ContractState, _core: ContractAddress) {
        self.core.write(_core);
    }

    impl RouteFinderLockerImpl of ILocker<ContractState> {
        fn locked(ref self: ContractState, id: u32, data: Array<felt252>) -> Array<felt252> {
            assert(get_caller_address() == self.core.read(), 'UNAUTHORIZED');

            let mut input_span = data.span();
            let mut params: FindParameters = Serde::<FindParameters>::deserialize(ref input_span)
                .expect('LOCKED_DESERIALIZE_FAILED');

            // todo: do stuff to compute result
            let result = FindResult { found: params.amount.is_zero() };

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
            Serde::<FindParameters>::serialize(@params, ref input);

            let output = call_contract_syscall(
                self.core.read(),
                0x168652c307c1e813ca11cfb3a601f1cf3b22452021a5052d8b05f1f1f8a3e92,
                input.span()
            )
                .unwrap_err();

            let mut output_span = output.span();
            let mut result: FindResult = Serde::<FindResult>::deserialize(ref output_span)
                .expect('DESERIALIZE_RESULT_FAILED');
            result
        }
    }
}
