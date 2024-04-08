use core::array::{ArrayTrait};
use core::num::traits::{Zero};
use core::option::{OptionTrait};
use core::serde::Serde;
use ekubo::components::util::{serialize};
use ekubo::interfaces::core::{ICoreDispatcher, ICoreDispatcherTrait};
use ekubo::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
use ekubo::types::i129::{i129};
use ekubo::types::keys::{PoolKey, SavedBalanceKey};
use starknet::{
    get_caller_address, get_contract_address, syscalls::{call_contract_syscall}, ContractAddress,
    SyscallResultTrait
};

pub fn call_core_with_callback<TInput, TOutput, +Serde<TInput>, +Serde<TOutput>>(
    core: ICoreDispatcher, input: @TInput
) -> TOutput {
    let mut output_span = core.lock(serialize(input).span());

    Serde::deserialize(ref output_span).expect('DESERIALIZE_RESULT_FAILED')
}

pub fn safe_call_core_with_callback<TInput, TOutput, +Serde<TInput>, +Serde<TOutput>>(
    core: ICoreDispatcher, pool_key: PoolKey, input: @TInput
) -> TOutput {
    let sqrt_ratio = core.get_pool_price(pool_key).sqrt_ratio;
    assert(sqrt_ratio.is_non_zero(), 'POOL_NOT_INITIALIZED');

    call_core_with_callback(core, input)
}

pub fn check_caller_is_core(core: ICoreDispatcher) {
    assert(get_caller_address() == core.contract_address, 'CORE_ONLY');
}

pub fn consume_callback_data<TInput, +Serde<TInput>>(
    core: ICoreDispatcher, mut callback_data: Span<felt252>
) -> TInput {
    check_caller_is_core(core);
    Serde::deserialize(ref callback_data).expect('DESERIALIZE_INPUT_FAILED')
}

pub fn handle_delta(
    core: ICoreDispatcher, token: ContractAddress, delta: i129, recipient: ContractAddress
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

pub fn handle_delta_with_saved_balances(
    core: ICoreDispatcher,
    owner: ContractAddress,
    token: ContractAddress,
    salt: felt252,
    delta: i129
) {
    if delta.is_non_zero() {
        if (delta.sign) {
            core.save(key: SavedBalanceKey { owner, token, salt }, amount: delta.mag);
        } else {
            core.load(token, salt, amount: delta.mag);
        }
    }
}
