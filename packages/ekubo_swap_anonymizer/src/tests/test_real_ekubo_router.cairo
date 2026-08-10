use core::num::traits::Zero;
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
use snforge_std::{CheatSpan, ContractClassTrait, DeclareResultTrait, cheat_caller_address, declare};
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

#[test]
fn split_multihop_swap_settles_against_real_router_and_core() {
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
    let (input, middle, output) = ordered_tokens();
    let first_pool = pool_key(input.contract_address, middle.contract_address);
    let second_pool = pool_key(middle.contract_address, output.contract_address);
    let direct_pool = pool_key(input.contract_address, output.contract_address);

    provide_liquidity(core, positions, input, middle, first_pool, liquidity_provider);
    provide_liquidity(core, positions, middle, output, second_pool, liquidity_provider);
    provide_liquidity(core, positions, input, output, direct_pool, liquidity_provider);
    input.mint(anonymizer, INPUT_AMOUNT);

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
    assert(input.balance_of(router.contract_address).is_zero(), 'ROUTER_INPUT_RETAINED');
    assert(output.balance_of(anonymizer) == deposit.amount.into(), 'OUTPUT_BALANCE_MISMATCH');
}
