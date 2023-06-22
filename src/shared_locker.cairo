use serde::Serde;
use starknet::{call_contract_syscall, ContractAddress, SyscallResultTrait};
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
