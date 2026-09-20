use core::num::traits::Zero;
use core::traits::TryInto;
use snforge_std::{ContractClassTrait, DeclareResultTrait, declare};
use starknet::ContractAddress;
use crate::components::util::serialize;
use crate::extensions::limit_orders_topup::{
    ILimitOrdersTopUpDispatcher, ILimitOrdersTopUpDispatcherTrait, TopUp,
};
use crate::interfaces::core::{ICoreDispatcher, ICoreDispatcherTrait};
use crate::tests::helper::{Deployer, DeployerTrait, default_owner, set_caller_address_once};
use crate::tests::mock_erc20::{IMockERC20DispatcherTrait, MockERC20IERC20ImplTrait};
use crate::types::keys::SavedBalanceKey;

// Exact shortfalls from the limit-orders post-mortem, used to prove the top-up path handles the
// real production amounts.
const USDC_SHORTFALL: u128 = 47123330423;
const ETH_SHORTFALL: u128 = 457141578614531148;

fn deploy_topup(
    owner: ContractAddress, core: ICoreDispatcher, limit_orders: ContractAddress,
) -> ILimitOrdersTopUpDispatcher {
    let contract = declare("LimitOrdersTopUp").unwrap().contract_class();
    let (address, _) = contract
        .deploy(@serialize(@(owner, core, limit_orders)))
        .expect('topup deploy failed');
    ILimitOrdersTopUpDispatcher { contract_address: address }
}

#[test]
fn test_top_up_credits_extension_saved_balances() {
    let mut d: Deployer = Default::default();
    let core = d.deploy_core();
    let limit_orders = d.deploy_limit_orders(core);
    let (token0, token1) = d.deploy_two_mock_tokens();

    let topup = deploy_topup(default_owner(), core, limit_orders.contract_address);

    assert(topup.get_core() == core.contract_address, 'wrong core');
    assert(topup.get_limit_orders() == limit_orders.contract_address, 'wrong extension');

    // Fund the top-up contract the way the company wallet will on mainnet.
    token0.increase_balance(topup.contract_address, USDC_SHORTFALL);
    token1.increase_balance(topup.contract_address, ETH_SHORTFALL);

    set_caller_address_once(topup.contract_address, default_owner());
    topup
        .top_up(
            array![
                TopUp { token: token0.contract_address, amount: USDC_SHORTFALL },
                TopUp { token: token1.contract_address, amount: ETH_SHORTFALL },
            ],
        );

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
#[should_panic(expected: 'OWNER_ONLY')]
fn test_top_up_non_owner_reverts() {
    let mut d: Deployer = Default::default();
    let core = d.deploy_core();
    let limit_orders = d.deploy_limit_orders(core);
    let token = d.deploy_mock_token();

    let topup = deploy_topup(default_owner(), core, limit_orders.contract_address);
    token.increase_balance(topup.contract_address, 100);

    topup.top_up(array![TopUp { token: token.contract_address, amount: 100 }]);
}

#[test]
fn test_rescue_returns_overfunded_remainder() {
    let mut d: Deployer = Default::default();
    let core = d.deploy_core();
    let limit_orders = d.deploy_limit_orders(core);
    let token = d.deploy_mock_token();

    let topup = deploy_topup(default_owner(), core, limit_orders.contract_address);

    // Overfund by 1 wei on purpose.
    token.increase_balance(topup.contract_address, USDC_SHORTFALL + 1);

    set_caller_address_once(topup.contract_address, default_owner());
    topup.top_up(array![TopUp { token: token.contract_address, amount: USDC_SHORTFALL }]);

    let recipient: ContractAddress = 999999.try_into().unwrap();
    set_caller_address_once(topup.contract_address, default_owner());
    topup.rescue(token.contract_address, recipient, 1);

    assert(token.balanceOf(recipient) == 1.into(), 'rescue failed');
    assert(token.balanceOf(topup.contract_address).is_zero(), 'remainder left');
}

#[test]
fn test_top_up_skips_zero_amounts() {
    let mut d: Deployer = Default::default();
    let core = d.deploy_core();
    let limit_orders = d.deploy_limit_orders(core);
    let (token0, token1) = d.deploy_two_mock_tokens();

    let topup = deploy_topup(default_owner(), core, limit_orders.contract_address);
    token1.increase_balance(topup.contract_address, 50);

    set_caller_address_once(topup.contract_address, default_owner());
    topup
        .top_up(
            array![
                TopUp { token: token0.contract_address, amount: 0 },
                TopUp { token: token1.contract_address, amount: 50 },
            ],
        );

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
}
