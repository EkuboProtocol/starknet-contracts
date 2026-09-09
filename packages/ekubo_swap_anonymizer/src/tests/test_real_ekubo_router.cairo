use core::ec::EcPointTrait;
use core::num::traits::Zero;
use core::poseidon::poseidon_hash_span;
use ekubo::components::util::serialize;
use ekubo::interfaces::core::{ICoreDispatcher, ICoreDispatcherTrait};
use ekubo::interfaces::positions::{IPositionsDispatcher, IPositionsDispatcherTrait};
use ekubo::interfaces::router::IRouterDispatcher;
use ekubo::types::bounds::Bounds;
use ekubo::types::i129::i129;
use ekubo::types::keys::PoolKey;
use ekubo_swap_anonymizer::ekubo_swap_anonymizer::{
    IEkuboSwapAnonymizerDispatcher, IEkuboSwapAnonymizerDispatcherTrait, PrivateRouteNode,
    PrivateSwap,
};
use ekubo_swap_anonymizer::test_utils_contracts::mock_erc20::{
    IMockERC20Dispatcher, IMockERC20DispatcherTrait, MockERC20DispatcherImpl,
    MockERC20DispatcherTrait,
};
use privacy::actions::{InvokeInput, ServerAction, TransferToInput, WriteOnceInput};
use privacy::events::OpenNoteCreated;
use privacy::interface::{
    IServerSafeDispatcher, IServerSafeDispatcherTrait, IViewsDispatcher, IViewsDispatcherTrait,
};
use snforge_std::{
    CheatSpan, ContractClassTrait, DeclareResultTrait, cheat_caller_address, cheat_proof_facts,
    declare, map_entry_address, start_cheat_block_number,
};
use starknet::ContractAddress;

const INPUT_AMOUNT: u128 = 100;
const LIQUIDITY_TOKEN_AMOUNT: u128 = 10_000;
const FEE: u128 = 0xc49ba5e353f7ced916872b020c49ba;
const TICK_SPACING: u128 = 5982;

fn deploy_contract(name: ByteArray, calldata: Array<felt252>) -> ContractAddress {
    let class = declare(name).unwrap().contract_class();
    let (address, _) = class.deploy(@calldata).unwrap();
    address
}

fn deploy_token() -> IMockERC20Dispatcher {
    IMockERC20Dispatcher { contract_address: deploy_contract("MockERC20", array![]) }
}

fn ordered_tokens() -> (IMockERC20Dispatcher, IMockERC20Dispatcher, IMockERC20Dispatcher) {
    let token_a = deploy_token();
    let token_b = deploy_token();
    let token_c = deploy_token();

    if token_a.contract_address < token_b.contract_address {
        if token_b.contract_address < token_c.contract_address {
            (token_a, token_b, token_c)
        } else if token_a.contract_address < token_c.contract_address {
            (token_a, token_c, token_b)
        } else {
            (token_c, token_a, token_b)
        }
    } else if token_a.contract_address < token_c.contract_address {
        (token_b, token_a, token_c)
    } else if token_b.contract_address < token_c.contract_address {
        (token_b, token_c, token_a)
    } else {
        (token_c, token_b, token_a)
    }
}

fn pool_key(token0: ContractAddress, token1: ContractAddress) -> PoolKey {
    let (token0, token1) = if token0 < token1 {
        (token0, token1)
    } else {
        (token1, token0)
    };
    PoolKey { token0, token1, fee: FEE, tick_spacing: TICK_SPACING, extension: Zero::zero() }
}

fn provide_liquidity(
    core: ICoreDispatcher,
    positions: IPositionsDispatcher,
    token0: IMockERC20Dispatcher,
    token1: IMockERC20Dispatcher,
    pool_key: PoolKey,
    user: ContractAddress,
) {
    let bounds = Bounds {
        lower: i129 { mag: TICK_SPACING, sign: true },
        upper: i129 { mag: TICK_SPACING, sign: false },
    };
    core.initialize_pool(pool_key, Zero::zero());
    token0.mint(positions.contract_address, LIQUIDITY_TOKEN_AMOUNT);
    token1.mint(positions.contract_address, LIQUIDITY_TOKEN_AMOUNT);

    cheat_caller_address(positions.contract_address, user, CheatSpan::TargetCalls(1));
    positions.mint(:pool_key, :bounds);
    cheat_caller_address(positions.contract_address, user, CheatSpan::TargetCalls(1));
    positions.deposit_last(:pool_key, :bounds, min_liquidity: 0);
}

fn split_multihop_case(donation: u128, reverse: bool) {
    let owner: ContractAddress = 0x111.try_into().unwrap();
    let liquidity_provider: ContractAddress = 0x222.try_into().unwrap();
    let core = ICoreDispatcher { contract_address: deploy_contract("Core", serialize(@owner)) };
    let router = IRouterDispatcher {
        contract_address: deploy_contract("Router", serialize(@core)),
    };

    let owned_nft_class = declare("OwnedNFT").unwrap().contract_class();
    let positions = IPositionsDispatcher {
        contract_address: deploy_contract(
            "Positions",
            serialize(@(owner, core, *owned_nft_class.class_hash, 'https://positions.example/')),
        ),
    };
    let anonymizer = deploy_contract("EkuboSwapAnonymizer", array![]);
    let (low, middle, high) = ordered_tokens();
    let (input, output) = if reverse {
        (high, low)
    } else {
        (low, high)
    };
    let first_pool = pool_key(input.contract_address, middle.contract_address);
    let second_pool = pool_key(middle.contract_address, output.contract_address);
    let direct_pool = pool_key(input.contract_address, output.contract_address);

    provide_liquidity(core, positions, input, middle, first_pool, liquidity_provider);
    provide_liquidity(core, positions, middle, output, second_pool, liquidity_provider);
    provide_liquidity(core, positions, input, output, direct_pool, liquidity_provider);
    input.mint(anonymizer, INPUT_AMOUNT);
    input.mint(router.contract_address, donation);

    let deposits = IEkuboSwapAnonymizerDispatcher { contract_address: anonymizer }
        .privacy_invoke(
            router_addr: router.contract_address,
            in_token: input.contract_address,
            out_token: output.contract_address,
            in_amount: INPUT_AMOUNT,
            swaps: array![
                PrivateSwap {
                    input_amount: 60,
                    route: array![
                        PrivateRouteNode { pool_key: first_pool, skip_ahead: 0 },
                        PrivateRouteNode { pool_key: second_pool, skip_ahead: 0 },
                    ],
                },
                PrivateSwap {
                    input_amount: 40,
                    route: array![PrivateRouteNode { pool_key: direct_pool, skip_ahead: 0 }],
                },
            ],
            minimum_received: 1,
            note_id: 'REAL_ROUTER_NOTE',
        );

    assert(deposits.len() == 1, 'INVALID_DEPOSIT_COUNT');
    let deposit = *deposits.at(0);
    assert(deposit.token == output.contract_address, 'INVALID_OUTPUT_TOKEN');
    assert(deposit.amount > 0, 'ZERO_REAL_ROUTER_OUTPUT');
    assert(input.balance_of(anonymizer).is_zero(), 'INPUT_RETAINED');
    assert(input.balance_of(router.contract_address) == donation.into(), 'ROUTER_DONATION_CHANGED');
    assert(output.balance_of(anonymizer) == deposit.amount.into(), 'OUTPUT_BALANCE_MISMATCH');
}

#[test]
fn split_multihop_swap_settles_against_real_router_and_core() {
    split_multihop_case(0, false);
}

#[test]
fn router_input_donation_does_not_block_valid_swap() {
    split_multihop_case(1, false);
}

#[test]
fn reverse_split_multihop_settles_against_real_router_and_core() {
    split_multihop_case(1, true);
}

// Exercises the production Privacy server, Router and Core together. Proof facts
// are injected as in upstream Privacy tests; this does not test proof generation.
#[feature("safe_dispatcher")]
fn privacy_settlement_case(wrong_note_token: bool, excessive_minimum: bool, partial_fill: bool) {
    let owner: ContractAddress = 0x111.try_into().unwrap();
    let core = ICoreDispatcher { contract_address: deploy_contract("Core", serialize(@owner)) };
    let router = deploy_contract("Router", serialize(@core));
    let owned_nft_class = declare("OwnedNFT").unwrap().contract_class();
    let positions = IPositionsDispatcher {
        contract_address: deploy_contract(
            "Positions", serialize(@(owner, core, *owned_nft_class.class_hash, 'uri')),
        ),
    };
    let anonymizer = deploy_contract("EkuboSwapAnonymizer", array![]);
    let (input, _, output) = ordered_tokens();
    let key = pool_key(input.contract_address, output.contract_address);
    provide_liquidity(core, positions, input, output, key, owner);

    let mut public_key = 1;
    while EcPointTrait::new_from_x(public_key).is_none() {
        public_key += 1;
    }
    let privacy_class = declare("Privacy").unwrap().contract_class();
    let (pool, _) = privacy_class
        .deploy(@array![owner.into(), public_key, public_key, 100])
        .unwrap();
    let amount = if partial_fill {
        100_000
    } else {
        INPUT_AMOUNT
    };
    input.mint(pool, amount);
    // Pre-existing helper output must stay outside the newly deposited note.
    output.mint(anonymizer, 7);
    let note_id = 'POOL_INTEGRATION_NOTE';
    let note_token = if wrong_note_token {
        input.contract_address
    } else {
        output.contract_address
    };
    let empty_note: felt252 = 0x100000000000000000000000000000000;
    let mut event_data = array![public_key, 1, 1, note_token.into(), note_id].span();
    let event: OpenNoteCreated = Serde::deserialize(ref event_data).unwrap();
    let minimum: u256 = if excessive_minimum {
        1000
    } else {
        1
    };
    let calldata = serialize(
        @(
            router,
            input.contract_address,
            output.contract_address,
            amount,
            array![
                PrivateSwap {
                    input_amount: amount,
                    route: array![PrivateRouteNode { pool_key: key, skip_ahead: 0 }],
                },
            ],
            minimum,
            note_id,
        ),
    );
    let actions = array![
        ServerAction::WriteOnce(
            WriteOnceInput {
                storage_address: map_entry_address(selector!("notes"), array![note_id].span())
                    .into(),
                value: array![empty_note, note_token.into()].span(),
            },
        ),
        ServerAction::EmitOpenNoteCreated(event),
        ServerAction::TransferTo(
            TransferToInput { to_addr: anonymizer, token: input.contract_address, amount: amount },
        ),
        ServerAction::Invoke(
            InvokeInput { contract_address: anonymizer, calldata: calldata.span() },
        ),
    ];
    let mut payload = array![(*privacy_class.class_hash).into()];
    actions.span().serialize(ref payload);
    let mut message = array![pool.into(), 0];
    payload.serialize(ref message);
    let facts = array![
        0, 'VIRTUAL_SNOS', 0, 'VIRTUAL_SNOS0', 99, 0, 0, 1, poseidon_hash_span(message.span()),
    ];
    start_cheat_block_number(pool, 100);
    cheat_proof_facts(pool, facts.span(), CheatSpan::TargetCalls(1));
    let core_input_before = input.balance_of(core.contract_address);
    let core_output_before = output.balance_of(core.contract_address);
    let result = IServerSafeDispatcher { contract_address: pool }
        .apply_actions(actions.span(), Option::None);
    let note = IViewsDispatcher { contract_address: pool }.get_note(note_id);
    if wrong_note_token || excessive_minimum || partial_fill {
        let error = result.unwrap_err();
        let expected = if wrong_note_token {
            privacy::errors::TOKEN_MISMATCH
        } else if partial_fill {
            ekubo_swap_anonymizer::ekubo_swap_anonymizer::errors::IN_TOKEN_NOT_CLEARED
        } else {
            'CLEAR_AT_LEAST_MINIMUM'
        };
        assert(*error.at(0) == expected, 'WRONG_SETTLEMENT_ERROR');
        assert(note.packed_value == 0, 'FAILED_NOTE_PERSISTED');
        assert(input.balance_of(pool) == amount.into(), 'POOL_INPUT_NOT_RESTORED');
        assert(input.balance_of(anonymizer).is_zero(), 'FAILED_HELPER_INPUT');
        assert(output.balance_of(pool).is_zero(), 'FAILED_POOL_OUTPUT');
        assert(
            input.balance_of(core.contract_address) == core_input_before, 'CORE_INPUT_NOT_RESTORED',
        );
        assert(
            output.balance_of(core.contract_address) == core_output_before,
            'CORE_OUTPUT_NOT_RESTORED',
        );
    } else {
        result.unwrap();
        let output_amount: u128 = (note.packed_value - empty_note).try_into().unwrap();
        assert(output_amount > 0, 'EMPTY_DEPOSITED_NOTE');
        assert(note.token == output.contract_address, 'WRONG_NOTE_TOKEN');
        assert(input.balance_of(pool).is_zero(), 'POOL_INPUT_RETAINED');
        assert(input.balance_of(anonymizer).is_zero(), 'HELPER_INPUT_RETAINED');
        assert(output.balance_of(pool) == output_amount.into(), 'NOTE_NOT_COLLATERALIZED');
        assert(
            input.balance_of(core.contract_address) == core_input_before + amount.into(),
            'CORE_INPUT_MISMATCH',
        );
        assert(
            output.balance_of(core.contract_address) + output_amount.into() == core_output_before,
            'CORE_OUTPUT_MISMATCH',
        );
    }
    assert(output.balance_of(anonymizer) == 7, 'HELPER_DONATION_CHANGED');
    assert(output.allowance(anonymizer, pool).is_zero(), 'POOL_ALLOWANCE_RETAINED');
    assert(input.balance_of(router).is_zero(), 'ROUTER_INPUT_RETAINED');
    assert(output.balance_of(router).is_zero(), 'ROUTER_OUTPUT_RETAINED');
}

#[test]
fn real_privacy_pool_consumes_swap_note() {
    privacy_settlement_case(false, false, false);
}

#[test]
fn real_privacy_pool_rolls_back_wrong_note_token() {
    privacy_settlement_case(true, false, false);
}

#[test]
fn real_privacy_pool_rolls_back_slippage_failure() {
    privacy_settlement_case(false, true, false);
}

#[test]
fn real_privacy_pool_rolls_back_partial_fill() {
    privacy_settlement_case(false, false, true);
}
