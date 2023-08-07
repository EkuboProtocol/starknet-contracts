use serde::Serde;
use starknet::{get_caller_address, call_contract_syscall, ContractAddress, SyscallResultTrait};
use ekubo::interfaces::core::{ICoreDispatcher, ICoreDispatcherTrait};
use array::{ArrayTrait};
use option::{OptionTrait};

fn call_core_with_callback<
    TInput, impl TSerdeInput: Serde<TInput>, TOutput, impl TSerdeOutput: Serde<TOutput>, 
>(
    core: ICoreDispatcher, input: @TInput
) -> TOutput {
    let mut input_data: Array<felt252> = ArrayTrait::new();
    Serde::serialize(input, ref input_data);

    let mut output_span = core.lock(input_data).span();

    Serde::deserialize(ref output_span).expect('DESERIALIZE_RESULT_FAILED')
}

fn consume_callback_data<TInput, impl TSerdeInput: Serde<TInput>>(
    core: ICoreDispatcher, callback_data: Array<felt252>
) -> TInput {
    assert(get_caller_address() == core.contract_address, 'CORE_ONLY');
    let mut span = callback_data.span();
    Serde::deserialize(ref span).expect('DESERIALIZE_INPUT_FAILED')
}
