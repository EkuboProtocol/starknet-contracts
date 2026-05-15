use core::num::traits::Zero;
use starknet::ContractAddress;
use crate::components::owned::{IOwnedDispatcher, IOwnedDispatcherTrait};
use crate::interfaces::core::ICoreDispatcherTrait;
use crate::interfaces::extensions::twamm::{ITWAMMDispatcher, ITWAMMDispatcherTrait, OrderKey};
use crate::interfaces::erc721::{IERC721Dispatcher, IERC721DispatcherTrait};
use crate::interfaces::positions::IPositionsDispatcherTrait;
use crate::math::ticks::{constants::MAX_TICK_SPACING, tick_to_sqrt_ratio};
use crate::revenue_buybacks::{Config, IRevenueBuybacksDispatcherTrait};
use crate::tests::helper::{
    Deployer, DeployerTrait, FEE_ONE_PERCENT, default_owner, set_caller_address_for_calls,
    set_caller_address_global, set_caller_address_once, stop_caller_address_global, swap,
};
use crate::types::bounds::max_bounds;
use crate::types::i129::i129;
use crate::types::keys::SavedBalanceKey;
use crate::tests::mock_erc20::IMockERC20DispatcherTrait;

fn example_config(buy_token: ContractAddress) -> Config {
    Config {
        buy_token,
        min_delay: 0,
        max_delay: 43200,
        // 30 seconds
        min_duration: 30,
        // 7 days
        max_duration: 604800,
        // 30 bips
        fee: 1020847100762815411640772995208708096,
    }
}

#[test]
fn test_deploy_and_setup() {
    let mut d: Deployer = Default::default();
    let core = d.deploy_core();
    let positions = d.deploy_positions(core);

    let (token0, token1) = d.deploy_two_mock_tokens();
    let config = example_config(token1.contract_address);

    let rb = d.deploy_revenue_buybacks(default_owner(), core, positions, Option::Some(config));

    // Verify basic setup
    assert(rb.get_core() == core.contract_address, 'wrong core');
    assert(rb.get_positions() == positions.contract_address, 'wrong positions');

    // Verify the NFT was minted and owned by the contract
    let nft = IERC721Dispatcher { contract_address: positions.get_nft_address() };
    assert(nft.owner_of(rb.get_token_id().into()) == rb.contract_address, 'wrong nft owner');

    // Verify config
    assert(rb.get_config(token0.contract_address) == config, 'wrong config');
}

#[test]
fn test_config_override() {
    let mut d: Deployer = Default::default();
    let core = d.deploy_core();
    let positions = d.deploy_positions(core);

    let (token0, token1) = d.deploy_two_mock_tokens();
    let default_config = example_config(token1.contract_address);

    let rb = d
        .deploy_revenue_buybacks(default_owner(), core, positions, Option::Some(default_config));

    // Set an override for token0
    let override_config = Config {
        buy_token: token1.contract_address,
        min_delay: 100,
        max_delay: 1000,
        min_duration: 60,
        max_duration: 3600,
        fee: 500000000000000000000000000000000,
    };

    set_caller_address_global(default_owner());
    rb.set_config_override(token0.contract_address, Option::Some(override_config));

    // Verify override is used
    assert(rb.get_config(token0.contract_address) == override_config, 'override not applied');

    // Verify default is still used for other tokens
    let token2 = d.deploy_mock_token();
    assert(rb.get_config(token2.contract_address) == default_config, 'default not used');
}

#[test]
#[should_panic(expected: 'No config for token')]
fn test_no_config_panics() {
    let mut d: Deployer = Default::default();
    let core = d.deploy_core();
    let positions = d.deploy_positions(core);

    let rb = d.deploy_revenue_buybacks(default_owner(), core, positions, Option::None);

    let token = d.deploy_mock_token();
    rb.get_config(token.contract_address);
}

#[test]
#[should_panic(expected: 'Invalid sell token')]
fn test_same_token_buyback_fails() {
    let mut d: Deployer = Default::default();
    let core = d.deploy_core();
    let positions = d.deploy_positions(core);

    let (token0, _token1) = d.deploy_two_mock_tokens();
    let config = example_config(token0.contract_address);

    let rb = d.deploy_revenue_buybacks(default_owner(), core, positions, Option::Some(config));

    // Transfer core ownership to rb
    set_caller_address_global(default_owner());
    IOwnedDispatcher { contract_address: core.contract_address }
        .transfer_ownership(rb.contract_address);

    // Try to start buybacks with same token as buy_token
    rb.start_buybacks(token0.contract_address, 1000, 0, 100);
}

#[test]
#[should_panic(expected: 'Invalid start or end time')]
fn test_invalid_time_range() {
    let mut d: Deployer = Default::default();
    let core = d.deploy_core();
    let positions = d.deploy_positions(core);

    let (token0, token1) = d.deploy_two_mock_tokens();
    let config = example_config(token1.contract_address);

    let rb = d.deploy_revenue_buybacks(default_owner(), core, positions, Option::Some(config));

    // Transfer core ownership to rb
    set_caller_address_global(default_owner());
    IOwnedDispatcher { contract_address: core.contract_address }
        .transfer_ownership(rb.contract_address);

    // Try to start buybacks with end_time <= start_time
    rb.start_buybacks(token0.contract_address, 1000, 100, 50);
}

#[test]
#[should_panic(expected: 'Duration too short')]
fn test_duration_too_short() {
    let mut d: Deployer = Default::default();
    let core = d.deploy_core();
    let positions = d.deploy_positions(core);

    let (token0, token1) = d.deploy_two_mock_tokens();
    let config = example_config(token1.contract_address);

    let rb = d.deploy_revenue_buybacks(default_owner(), core, positions, Option::Some(config));

    // Transfer core ownership to rb
    set_caller_address_global(default_owner());
    IOwnedDispatcher { contract_address: core.contract_address }
        .transfer_ownership(rb.contract_address);

    // Try to start buybacks with duration < min_duration (30 seconds)
    rb.start_buybacks(token0.contract_address, 1000, 0, 20);
}

#[test]
fn test_reclaim_core() {
    let mut d: Deployer = Default::default();
    let core = d.deploy_core();
    let positions = d.deploy_positions(core);

    let (_token0, token1) = d.deploy_two_mock_tokens();
    let config = example_config(token1.contract_address);

    let rb = d.deploy_revenue_buybacks(default_owner(), core, positions, Option::Some(config));

    // Transfer core ownership to rb
    set_caller_address_global(default_owner());
    IOwnedDispatcher { contract_address: core.contract_address }
        .transfer_ownership(rb.contract_address);
    stop_caller_address_global();

    // Verify rb owns core
    let core_owned = IOwnedDispatcher { contract_address: core.contract_address };
    assert(core_owned.get_owner() == rb.contract_address, 'rb should own core');

    // Reclaim core
    set_caller_address_once(rb.contract_address, default_owner());
    rb.reclaim_core();

    // Verify default_owner owns core again
    assert(core_owned.get_owner() == default_owner(), 'owner should own core');

    // Verify rb still owns the NFT
    let nft = IERC721Dispatcher { contract_address: positions.get_nft_address() };
    assert(nft.owner_of(rb.get_token_id().into()) == rb.contract_address, 'rb should own nft');
}

#[test]
fn test_reclaim_positions() {
    let mut d: Deployer = Default::default();
    let core = d.deploy_core();
    let positions = d.deploy_positions(core);

    let (_token0, token1) = d.deploy_two_mock_tokens();
    let config = example_config(token1.contract_address);

    let rb = d.deploy_revenue_buybacks(default_owner(), core, positions, Option::Some(config));

    set_caller_address_global(default_owner());
    IOwnedDispatcher { contract_address: positions.contract_address }
        .transfer_ownership(rb.contract_address);
    stop_caller_address_global();

    let positions_owned = IOwnedDispatcher { contract_address: positions.contract_address };
    assert(positions_owned.get_owner() == rb.contract_address, 'rb should own positions');

    set_caller_address_once(rb.contract_address, default_owner());
    rb.reclaim_positions();
    assert(positions_owned.get_owner() == default_owner(), 'owner should own positions');
}

#[test]
fn test_start_buybacks_all_withdraws_seeded_protocol_fees_and_increases_sale() {
    let mut d: Deployer = Default::default();
    let core = d.deploy_core();
    let twamm = d.deploy_twamm(core);
    ITWAMMDispatcher { contract_address: twamm.contract_address }.update_call_points();
    let setup = d
        .setup_pool_with_core(
            core,
            fee: FEE_ONE_PERCENT,
            tick_spacing: MAX_TICK_SPACING,
            initial_tick: Zero::zero(),
            extension: twamm.contract_address,
        );
    let positions = d.deploy_positions(core);

    set_caller_address_global(default_owner());
    positions.set_twamm(twamm.contract_address);
    stop_caller_address_global();

    let caller = 1.try_into().unwrap();
    let bounds = max_bounds(MAX_TICK_SPACING);
    set_caller_address_for_calls(positions.contract_address, caller, 2);
    let token_id = positions.mint(pool_key: setup.pool_key, bounds: bounds);
    setup.token0.increase_balance(positions.contract_address, 10000);
    setup.token1.increase_balance(positions.contract_address, 10000);
    positions.deposit_last(pool_key: setup.pool_key, bounds: bounds, min_liquidity: 1);

    setup.token0.increase_balance(setup.locker.contract_address, 99999999);
    setup.token1.increase_balance(setup.locker.contract_address, 99999999);
    swap(
        setup: setup,
        amount: i129 { mag: 100000, sign: false },
        is_token1: true,
        sqrt_ratio_limit: tick_to_sqrt_ratio(i129 { mag: 2, sign: false }),
        recipient: Zero::zero(),
        skip_ahead: 0,
    );
    swap(
        setup: setup,
        amount: i129 { mag: 100000, sign: false },
        is_token1: false,
        sqrt_ratio_limit: tick_to_sqrt_ratio(i129 { mag: 2, sign: true }),
        recipient: Zero::zero(),
        skip_ahead: 0,
    );
    swap(
        setup: setup,
        amount: i129 { mag: 100000, sign: false },
        is_token1: true,
        sqrt_ratio_limit: 0x100000000000000000000000000000000_u256,
        recipient: Zero::zero(),
        skip_ahead: 0,
    );

    set_caller_address_once(positions.contract_address, caller);
    positions.collect_fees(id: token_id, pool_key: setup.pool_key, bounds: bounds);
    let seeded_protocol_fees = positions.get_protocol_fees_collected(setup.pool_key.token0);
    assert(seeded_protocol_fees > 0, 'seeded');

    let saved_balance_key = SavedBalanceKey {
        owner: positions.contract_address,
        token: setup.pool_key.token0,
        salt: 'PROTOCOL_FEES',
    };
    assert(core.get_saved_balance(saved_balance_key) == seeded_protocol_fees, 'saved before');
    let order_key = OrderKey {
        sell_token: setup.pool_key.token0,
        buy_token: setup.pool_key.token1,
        fee: example_config(setup.pool_key.token1).fee,
        start_time: 0,
        end_time: 112,
    };

    let rb = d
        .deploy_revenue_buybacks(
            default_owner(),
            core,
            positions,
            Option::Some(example_config(setup.pool_key.token1)),
        );

    set_caller_address_global(default_owner());
    IOwnedDispatcher { contract_address: positions.contract_address }
        .transfer_ownership(rb.contract_address);
    stop_caller_address_global();

    let before_order_info = positions.get_order_info(rb.get_token_id(), order_key);
    rb.start_buybacks_all(setup.pool_key.token0, 0, 112);

    assert(positions.get_protocol_fees_collected(setup.pool_key.token0) == 0, 'fees withdrawn');
    assert(core.get_saved_balance(saved_balance_key) == 0, 'saved withdrawn');

    let order_info = positions.get_order_info(rb.get_token_id(), order_key);
    assert(order_info.sale_rate > before_order_info.sale_rate, 'sale rate');
}
