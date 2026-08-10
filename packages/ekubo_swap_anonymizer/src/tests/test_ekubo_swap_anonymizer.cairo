use core::num::traits::Zero;
use ekubo::types::keys::PoolKey;
use ekubo_swap_anonymizer::ekubo_swap_anonymizer::{
    IEkuboSwapAnonymizerDispatcher, IEkuboSwapAnonymizerDispatcherTrait,
    IEkuboSwapAnonymizerSafeDispatcher, IEkuboSwapAnonymizerSafeDispatcherTrait, PrivateRouteNode,
    PrivateSwap, errors,
};
use ekubo_swap_anonymizer::test_utils_contracts::mock_ekubo_amm::{
    IMockEkuboAMMControlDispatcher, IMockEkuboAMMControlDispatcherTrait, SwapBehavior,
};
use ekubo_swap_anonymizer::test_utils_contracts::mock_erc20::{
    IMockERC20Dispatcher, IMockERC20DispatcherTrait, MockERC20DispatcherImpl,
    MockERC20DispatcherTrait,
};
use privacy::objects::OpenNoteDeposit;
use snforge_std::{ContractClassTrait, DeclareResultTrait, declare};
use starknet::ContractAddress;

const AMOUNT: u128 = 100;

fn deploy_contract(name: ByteArray) -> ContractAddress {
    let class = declare(name).unwrap().contract_class();
    let (address, _) = class.deploy(@array![]).unwrap();
    address
}

fn deploy_anonymizer() -> ContractAddress {
    deploy_contract("EkuboSwapAnonymizer")
}

fn deploy_router() -> ContractAddress {
    deploy_contract("MockEkuboAMM")
}

fn deploy_token() -> IMockERC20Dispatcher {
    IMockERC20Dispatcher { contract_address: deploy_contract("MockERC20") }
}

fn pool_key(token_a: ContractAddress, token_b: ContractAddress) -> PoolKey {
    let (token0, token1) = if token_a < token_b {
        (token_a, token_b)
    } else {
        (token_b, token_a)
    };
    PoolKey { token0, token1, fee: 0, tick_spacing: 1, extension: Zero::zero() }
}

fn node(token_a: ContractAddress, token_b: ContractAddress) -> PrivateRouteNode {
    PrivateRouteNode { pool_key: pool_key(token_a, token_b), skip_ahead: 0 }
}

fn invoke(
    anonymizer: ContractAddress,
    router: ContractAddress,
    in_token: ContractAddress,
    out_token: ContractAddress,
    swaps: Array<PrivateSwap>,
    minimum_received: u256,
) -> Span<OpenNoteDeposit> {
    IEkuboSwapAnonymizerDispatcher { contract_address: anonymizer }
        .privacy_invoke(
            router_addr: router,
            :in_token,
            :out_token,
            in_amount: AMOUNT,
            :swaps,
            :minimum_received,
            note_id: 'NOTE',
        )
}

#[feature("safe_dispatcher")]
fn safe_invoke(
    anonymizer: ContractAddress,
    router: ContractAddress,
    in_token: ContractAddress,
    out_token: ContractAddress,
    in_amount: u128,
    swaps: Array<PrivateSwap>,
    minimum_received: u256,
) -> Result<Span<OpenNoteDeposit>, Array<felt252>> {
    IEkuboSwapAnonymizerSafeDispatcher { contract_address: anonymizer }
        .privacy_invoke(
            router_addr: router,
            :in_token,
            :out_token,
            :in_amount,
            :swaps,
            :minimum_received,
            note_id: 'NOTE',
        )
}

fn assert_felt_error<T, +Drop<T>>(result: Result<T, Array<felt252>>, expected: felt252) {
    let error = result.unwrap_err();
    assert(*error.at(0) == expected, 'UNEXPECTED_ERROR');
}

#[test]
fn single_hop_swap() {
    let anonymizer = deploy_anonymizer();
    let router = deploy_router();
    let input = deploy_token();
    let output = deploy_token();
    input.mint(anonymizer, AMOUNT);
    output.mint(router, AMOUNT);

    let deposits = invoke(
        anonymizer,
        router,
        input.contract_address,
        output.contract_address,
        array![
            PrivateSwap {
                input_amount: AMOUNT,
                route: array![node(input.contract_address, output.contract_address)],
            },
        ],
        AMOUNT.into(),
    );

    assert(
        *deposits
            .at(
                0,
            ) == OpenNoteDeposit {
                note_id: 'NOTE', token: output.contract_address, amount: AMOUNT,
            },
        'INVALID_DEPOSIT',
    );
    assert(input.balance_of(anonymizer).is_zero(), 'INPUT_RETAINED');
    assert(input.balance_of(router).is_zero(), 'ROUTER_INPUT_RETAINED');
    assert(output.balance_of(anonymizer) == AMOUNT.into(), 'OUTPUT_NOT_RECEIVED');
}

#[test]
fn multihop_split_swap() {
    let anonymizer = deploy_anonymizer();
    let router = deploy_router();
    let input = deploy_token();
    let middle_a = deploy_token();
    let middle_b = deploy_token();
    let output = deploy_token();
    input.mint(anonymizer, AMOUNT);
    output.mint(router, AMOUNT);

    let deposits = invoke(
        anonymizer,
        router,
        input.contract_address,
        output.contract_address,
        array![
            PrivateSwap {
                input_amount: 60,
                route: array![
                    node(input.contract_address, middle_a.contract_address),
                    node(middle_a.contract_address, output.contract_address),
                ],
            },
            PrivateSwap {
                input_amount: 40,
                route: array![
                    node(input.contract_address, middle_b.contract_address),
                    node(middle_b.contract_address, output.contract_address),
                ],
            },
        ],
        AMOUNT.into(),
    );

    assert(deposits.len() == 1, 'INVALID_DEPOSIT_COUNT');
    assert((*deposits.at(0)).amount == AMOUNT, 'INVALID_OUTPUT_AMOUNT');
    assert(input.balance_of(router).is_zero(), 'ROUTER_INPUT_RETAINED');
}

#[test]
fn rejects_invalid_routes_and_split_totals() {
    let anonymizer = deploy_anonymizer();
    let router = deploy_router();
    let input = deploy_token();
    let middle = deploy_token();
    let output = deploy_token();

    assert_felt_error(
        safe_invoke(
            anonymizer,
            router,
            input.contract_address,
            output.contract_address,
            AMOUNT,
            array![],
            0,
        ),
        errors::EMPTY_SWAPS,
    );
    assert_felt_error(
        safe_invoke(
            anonymizer,
            router,
            input.contract_address,
            output.contract_address,
            AMOUNT,
            array![
                PrivateSwap {
                    input_amount: AMOUNT - 1,
                    route: array![node(input.contract_address, output.contract_address)],
                },
            ],
            0,
        ),
        errors::SPLIT_AMOUNT_MISMATCH,
    );
    assert_felt_error(
        safe_invoke(
            anonymizer,
            router,
            input.contract_address,
            output.contract_address,
            AMOUNT,
            array![
                PrivateSwap {
                    input_amount: AMOUNT,
                    route: array![node(middle.contract_address, output.contract_address)],
                },
            ],
            0,
        ),
        errors::ROUTE_TOKEN_MISMATCH,
    );
    assert_felt_error(
        safe_invoke(
            anonymizer,
            router,
            input.contract_address,
            output.contract_address,
            AMOUNT,
            array![
                PrivateSwap {
                    input_amount: AMOUNT,
                    route: array![node(input.contract_address, middle.contract_address)],
                },
            ],
            0,
        ),
        errors::ROUTE_OUTPUT_MISMATCH,
    );
}

#[test]
fn rejects_partial_fill_and_slippage() {
    let anonymizer = deploy_anonymizer();
    let router = deploy_router();
    let input = deploy_token();
    let output = deploy_token();
    let route = array![node(input.contract_address, output.contract_address)];

    input.mint(anonymizer, AMOUNT);
    output.mint(router, AMOUNT);
    IMockEkuboAMMControlDispatcher { contract_address: router }
        .set_swap_behavior(SwapBehavior::PartialSwap);
    assert_felt_error(
        safe_invoke(
            anonymizer,
            router,
            input.contract_address,
            output.contract_address,
            AMOUNT,
            array![PrivateSwap { input_amount: AMOUNT, route }],
            0,
        ),
        errors::IN_TOKEN_NOT_CLEARED,
    );

    IMockEkuboAMMControlDispatcher { contract_address: router }
        .set_swap_behavior(SwapBehavior::Normal);
    assert_felt_error(
        safe_invoke(
            anonymizer,
            router,
            input.contract_address,
            output.contract_address,
            AMOUNT,
            array![
                PrivateSwap {
                    input_amount: AMOUNT,
                    route: array![node(input.contract_address, output.contract_address)],
                },
            ],
            (AMOUNT + 1).into(),
        ),
        'CLEAR_MINIMUM_NOT_MET',
    );
}
