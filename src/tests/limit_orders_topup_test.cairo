use core::num::traits::Zero;
use snforge_std::{ContractClassTrait, DeclareResultTrait, declare};
use starknet::ContractAddress;
use crate::components::util::serialize;
use crate::extensions::limit_orders_topup::{
    ILimitOrdersTopUpDispatcher, ILimitOrdersTopUpDispatcherTrait,
};
use crate::interfaces::core::{ICoreDispatcher, ICoreDispatcherTrait};
use crate::tests::helper::{Deployer, DeployerTrait};
use crate::tests::mock_erc20::{IMockERC20DispatcherTrait, MockERC20IERC20ImplTrait};
use crate::types::keys::SavedBalanceKey;

// Exact shortfalls from the limit-orders post-mortem, used to prove the top-up path handles the
// real production amounts.
const USDC_SHORTFALL: u128 = 47123330423;
const ETH_SHORTFALL: u128 = 457141578614531148;

fn deploy_topup(
    core: ICoreDispatcher, limit_orders: ContractAddress,
) -> ILimitOrdersTopUpDispatcher {
    let contract = declare("LimitOrdersTopUp").unwrap().contract_class();
    let (address, _) = contract
        .deploy(@serialize(@(core, limit_orders)))
        .expect('topup deploy failed');
    ILimitOrdersTopUpDispatcher { contract_address: address }
}

#[test]
fn test_top_up_sweeps_full_balances_into_extension_pools() {
    let mut d: Deployer = Default::default();
    let core = d.deploy_core();
    let limit_orders = d.deploy_limit_orders(core);
    let (token0, token1) = d.deploy_two_mock_tokens();

    let topup = deploy_topup(core, limit_orders.contract_address);

    assert(topup.get_core() == core.contract_address, 'wrong core');
    assert(topup.get_limit_orders() == limit_orders.contract_address, 'wrong extension');

    // Fund the top-up contract the way the company wallet will on mainnet.
    token0.increase_balance(topup.contract_address, USDC_SHORTFALL);
    token1.increase_balance(topup.contract_address, ETH_SHORTFALL);

    // Permissionless: the caller is just the test contract, no owner cheat needed.
    topup.top_up(array![token0.contract_address, token1.contract_address]);

    // Each pool is credited with exactly its shortfall...
    assert(
        core
            .get_saved_balance(
                SavedBalanceKey {
                    owner: limit_orders.contract_address, token: token0.contract_address, salt: 0,
                },
            ) == USDC_SHORTFALL,
        'token0 pool not funded',
    );
    assert(
        core
            .get_saved_balance(
                SavedBalanceKey {
                    owner: limit_orders.contract_address, token: token1.contract_address, salt: 0,
                },
            ) == ETH_SHORTFALL,
        'token1 pool not funded',
    );

    // ...Core actually holds the tokens, and nothing is left stranded in the top-up contract.
    assert(token0.balanceOf(core.contract_address) == USDC_SHORTFALL.into(), 'core missing token0');
    assert(token1.balanceOf(core.contract_address) == ETH_SHORTFALL.into(), 'core missing token1');
    assert(token0.balanceOf(topup.contract_address).is_zero(), 'token0 remainder');
    assert(token1.balanceOf(topup.contract_address).is_zero(), 'token1 remainder');
}

#[test]
fn test_top_up_skips_zero_balances() {
    let mut d: Deployer = Default::default();
    let core = d.deploy_core();
    let limit_orders = d.deploy_limit_orders(core);
    let (token0, token1) = d.deploy_two_mock_tokens();

    let topup = deploy_topup(core, limit_orders.contract_address);
    // Only token1 is funded; token0's zero balance must be skipped, not reverted on.
    token1.increase_balance(topup.contract_address, 50);

    topup.top_up(array![token0.contract_address, token1.contract_address]);

    assert(
        core
            .get_saved_balance(
                SavedBalanceKey {
                    owner: limit_orders.contract_address, token: token1.contract_address, salt: 0,
                },
            ) == 50,
        'token1 pool not funded',
    );
    assert(token1.balanceOf(core.contract_address) == 50.into(), 'core missing token1');
    assert(
        core
            .get_saved_balance(
                SavedBalanceKey {
                    owner: limit_orders.contract_address, token: token0.contract_address, salt: 0,
                },
            )
            .is_zero(),
        'token0 pool touched',
    );
}

#[test]
fn test_top_up_sweeps_partial_top_up_and_can_be_called_again() {
    let mut d: Deployer = Default::default();
    let core = d.deploy_core();
    let limit_orders = d.deploy_limit_orders(core);
    let token = d.deploy_mock_token();

    let topup = deploy_topup(core, limit_orders.contract_address);

    // A first installment, then the rest: each call sweeps whatever is there.
    token.increase_balance(topup.contract_address, 40);
    topup.top_up(array![token.contract_address]);

    token.increase_balance(topup.contract_address, 60);
    topup.top_up(array![token.contract_address]);

    assert(
        core
            .get_saved_balance(
                SavedBalanceKey {
                    owner: limit_orders.contract_address, token: token.contract_address, salt: 0,
                },
            ) == 100,
        'pool not fully funded',
    );
    assert(token.balanceOf(core.contract_address) == 100.into(), 'core missing tokens');
}
