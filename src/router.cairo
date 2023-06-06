use ekubo::types::keys::{PoolKey, PositionKey};
use ekubo::types::i129::i129;
use starknet::ContractAddress;
use serde::Serde;
use array::ArrayTrait;
use option::{Option, OptionTrait};
use ekubo::core::{
    UpdatePositionParameters, SwapParameters, Delta, IERC20Dispatcher, IERC20DispatcherTrait,
    ILockerDispatcher, ILockerDispatcherTrait, IEkuboDispatcher, IEkuboDispatcherTrait
};
use starknet::get_caller_address;
use core::hash::LegacyHash;
use traits::{Into};


#[derive(Copy, Drop, Serde)]
enum AmountOrPercent {
    amount: u128, // fixed amount
    percent: u128 // 64.64
}

#[derive(Copy, Drop, Serde)]
struct SplitTarget {
    id: felt252,
    amount_or_percent: AmountOrPercent
}

// A step in a plan that splits the input into multiple outputs.
#[derive(Drop, Serde)]
struct SplitStep {
    id: felt252,
    token: ContractAddress,
    targets: Array<SplitTarget>,
}

// A terminal step in a plan that sends the entire amount of tokens to a recipient
#[derive(Copy, Drop, Serde)]
struct SendStep {
    id: felt252,
    token: ContractAddress,
    minimum_amount: Option<u128>,
    recipient: ContractAddress,
}

// A step in a plan that aggregates the output of multiple other steps
#[derive(Copy, Drop, Serde)]
struct MergeStep {
    id: felt252,
    token: ContractAddress,
    next: felt252,
}

// A step in a plan that swaps against a pool
#[derive(Copy, Drop, Serde)]
struct SwapStep {
    id: felt252,
    pool_key: PoolKey,
    specified_amount: i129,
    computed_amount_limit: Option<u128>,
    next: felt252
}

// A step in a plan that executes inside a lock
#[derive(Drop, Serde)]
enum PlanStep {
    Swap: SwapStep,
    Merge: MergeStep,
    Split: SplitStep,
    Send: SendStep
}

// A plan is a list of steps that can be executed within the context of a single lock.
#[derive(Drop, Serde)]
struct Plan {
    steps: Array<PlanStep>
}

#[derive(Drop, Serde)]
struct GetExecutionPlanParams {
    pool_keys: Array<PoolKey>,
    max_hops: u128,
    amount: i129,
    token: ContractAddress,
    other_token: ContractAddress,
    recipient: ContractAddress
}

#[derive(Drop, Serde)]
struct ExecuteResult {
    consumed_amount: i129,
    computed_amount: i129
}

#[derive(Drop, Serde)]
enum CallbackData {
    GetExecutionPlan: GetExecutionPlanParams,
    Execute: Plan
}

#[derive(Copy, Drop, Serde)]
struct StepBalancesKey {
    id: felt252,
    token: ContractAddress
}

impl StepBalancesKeyHash of LegacyHash<StepBalancesKey> {
    fn hash(state: felt252, value: StepBalancesKey) -> felt252 {
        pedersen(state, pedersen(value.id, value.token.into()))
    }
}


#[abi]
trait IRouter {
    // Returns the an execution plan for swapping from A to B
    #[external]
    fn get_execution_plan(params: GetExecutionPlanParams) -> Plan;

    // Execute a plan
    #[external]
    fn execute(plan: Plan);
}

#[contract]
mod Router {
    use super::{
        ContractAddress, Serde, PoolKey, i129, IEkuboDispatcher, IEkuboDispatcherTrait,
        CallbackData, GetExecutionPlanParams, Plan, ArrayTrait, Option, OptionTrait,
        IERC20Dispatcher, IERC20DispatcherTrait, ExecuteResult, get_caller_address, StepBalancesKey,
        PlanStep
    };

    struct Storage {
        core: ContractAddress,
        balances: LegacyMap<StepBalancesKey, u128>,
        nonzero_count: u128
    }

    #[constructor]
    fn constructor(_core: ContractAddress) {
        core::write(_core);
    }

    #[external]
    fn get_execution_plan(params: GetExecutionPlanParams) -> Plan {
        let mut arr: Array<felt252> = ArrayTrait::new();
        Serde::<CallbackData>::serialize(@CallbackData::GetExecutionPlan(params), ref arr);

        let result = IEkuboDispatcher { contract_address: core::read() }.lock(arr);

        let mut result_data = result.span();
        Serde::<Plan>::deserialize(ref result_data).expect('DESERIALIZE')
    }

    #[external]
    fn execute(plan: Plan) {
        let mut arr: Array<felt252> = ArrayTrait::new();
        Serde::<Plan>::serialize(@plan, ref arr);

        let result = IEkuboDispatcher { contract_address: core::read() }.lock(arr);

        let mut result_data = result.span();
        let mut action_result: ExecuteResult = Serde::<ExecuteResult>::deserialize(ref result_data)
            .expect('DESERIALIZE');
    }

    #[external]
    fn locked(id: felt252, data: Array<felt252>) -> Array<felt252> {
        let caller = get_caller_address();
        assert(caller == core::read(), 'UNAUTHORIZED_CALLBACK');

        let mut callback_data_raw = data.span();
        let mut callback_data: CallbackData = Serde::<CallbackData>::deserialize(
            ref callback_data_raw
        )
            .expect('DESERIALIZE_FAILED');

        match callback_data {
            CallbackData::GetExecutionPlan(params) => {
                let mut arr: Array<felt252> = ArrayTrait::new();
                // Serde::<Plan>::serialize(@result, ref arr);
                arr
            },
            CallbackData::Execute(plan) => {
                let mut i: usize = 0;
                loop {
                    if (i >= plan.steps.len()) {
                        break ();
                    }
                    let step = plan.steps.at(i);

                    match step {
                        PlanStep::Swap(params) => {},
                        PlanStep::Merge(params) => {},
                        PlanStep::Split(params) => {},
                        PlanStep::Send(params) => {},
                    };

                    i = i + 1;
                };

                let mut arr: Array<felt252> = ArrayTrait::new();
                // Serde::<ExecuteResult>::serialize(@result, ref arr);
                arr
            },
        }
    }

    #[internal]
    fn pay(core: ContractAddress, token: ContractAddress, amount: u128) {
        IERC20Dispatcher { contract_address: token }.transfer(core, u256 { low: amount, high: 0 });
        IEkuboDispatcher { contract_address: core }.deposit(token);
    }

    #[internal]
    fn take(
        core: ContractAddress, token: ContractAddress, amount: u128, recipient: ContractAddress
    ) {
        IEkuboDispatcher { contract_address: core }.withdraw(token, recipient, amount);
    }
}
