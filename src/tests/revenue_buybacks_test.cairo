use starknet::ContractAddress;
use crate::components::owned::{IOwnedDispatcher, IOwnedDispatcherTrait};
use crate::interfaces::erc721::{IERC721Dispatcher, IERC721DispatcherTrait};
use crate::interfaces::positions::IPositionsDispatcherTrait;
use crate::revenue_buybacks::{Config, IRevenueBuybacksDispatcherTrait};
use crate::tests::helper::{
    Deployer, DeployerTrait, default_owner, set_caller_address_global, set_caller_address_once,
    stop_caller_address_global,
};

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
