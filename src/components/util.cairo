use core::num::traits::Zero;
use core::option::OptionTrait;
use core::serde::Serde;
use starknet::{ContractAddress, get_caller_address};
use crate::interfaces::core::{ICoreDispatcher, ICoreDispatcherTrait, IForwardeeDispatcher};
use crate::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
use crate::types::i129::i129;

pub fn serialize<T, +Serde<T>>(t: @T) -> Array<felt252> {
    let mut result: Array<felt252> = ArrayTrait::new();
    Serde::serialize(t, ref result);
    result
}

pub fn call_core_with_callback<TInput, TOutput, +Serde<TInput>, +Serde<TOutput>>(
    core: ICoreDispatcher, input: @TInput,
) -> TOutput {
    let mut output_span = core.lock(serialize(input).span());

    Serde::deserialize(ref output_span).expect('DESERIALIZE_RESULT_FAILED')
}

pub fn forward_lock<TInput, TOutput, +Serde<TInput>, +Serde<TOutput>>(
    core: ICoreDispatcher, forwardee: IForwardeeDispatcher, input: @TInput,
) -> TOutput {
    let mut output_span = core.forward(forwardee, serialize(input).span());

    Serde::deserialize(ref output_span).expect('DESERIALIZE_RESULT_FAILED')
}

pub fn check_caller_is_core(core: ICoreDispatcher) {
    assert(get_caller_address() == core.contract_address, 'CORE_ONLY');
}

pub fn consume_callback_data<TInput, +Serde<TInput>>(
    core: ICoreDispatcher, mut callback_data: Span<felt252>,
) -> TInput {
    check_caller_is_core(core);
    Serde::deserialize(ref callback_data).expect('DESERIALIZE_INPUT_FAILED')
}

pub fn handle_delta(
    core: ICoreDispatcher, token: ContractAddress, delta: i129, recipient: ContractAddress,
) {
    if (delta.is_non_zero()) {
        if (delta.sign) {
            core.withdraw(token, recipient, delta.mag);
        } else {
            let token = IERC20Dispatcher { contract_address: token };
            token.approve(core.contract_address, delta.mag.into());
            core.pay(token.contract_address);
        }
    }
}

