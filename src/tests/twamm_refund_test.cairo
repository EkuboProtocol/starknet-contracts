use starknet::{ClassHash, ContractAddress, get_contract_address};
use crate::extensions::twamm_refund::{ITWAMMRefundDispatcher, ITWAMMRefundDispatcherTrait, Refund};
use crate::interfaces::core::{ICoreDispatcher, ICoreDispatcherTrait};
use crate::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
use crate::interfaces::extensions::twamm::{
    ITWAMMDispatcher, ITWAMMDispatcherTrait, OrderKey, StateKey,
};
use crate::interfaces::positions::{IPositionsDispatcher, IPositionsDispatcherTrait};
use crate::interfaces::upgradeable::{IUpgradeableDispatcher, IUpgradeableDispatcherTrait};
use crate::math::ticks::constants::MAX_TICK_SPACING;
use crate::tests::helper::{
    Deployer, DeployerTrait, default_owner, get_declared_class_hash, set_block_timestamp_global,
    set_caller_address_global, set_caller_address_once, stop_caller_address_global,
};
use crate::tests::mock_erc20::{IMockERC20Dispatcher, IMockERC20DispatcherTrait};
use crate::types::i129::i129;
use crate::types::keys::SavedBalanceKey;

fn state_key(order_key: OrderKey) -> StateKey {
    let (token0, token1) = if order_key.sell_token < order_key.buy_token {
        (order_key.sell_token, order_key.buy_token)
    } else {
        (order_key.buy_token, order_key.sell_token)
    };

    StateKey { token0, token1, fee: order_key.fee }
}

const ORDER_START: u64 = 0x10;
const ORDER_END: u64 = 0x100;
const SELL_AMOUNT: u128 = 1_000_000_000;

// Reproduces the state that stranded the funds: an order sold into a pool with no liquidity, so
// nothing was purchased, and the sale rate was fully consumed by the passage of time. Returns the
// TWAMM, the seller, and the token whose balance is now stuck in Core.
fn strand_funds() -> (
    Deployer,
    ICoreDispatcher,
    ITWAMMDispatcher,
    IPositionsDispatcher,
    IMockERC20Dispatcher,
    IMockERC20Dispatcher,
    ContractAddress,
    OrderKey,
    u64,
    ClassHash,
    ClassHash,
) {
    // Both classes must be declared before any caller address is cheated.
    let refund_class: ClassHash = get_declared_class_hash("TWAMMRefund");
    let twamm_class: ClassHash = get_declared_class_hash("TWAMM");

    let mut d: Deployer = Default::default();
    set_block_timestamp_global(1);

    let core = d.deploy_core();
    let twamm = ITWAMMDispatcher { contract_address: d.deploy_twamm(core).contract_address };
    twamm.update_call_points();

    // A pool with zero liquidity: amount0 and amount1 are both zero.
    let setup = d
        .setup_pool_with_core(
            core,
            fee: 0,
            tick_spacing: MAX_TICK_SPACING,
            initial_tick: i129 { mag: 0, sign: false },
            extension: twamm.contract_address,
        );

    let positions = d.deploy_positions(core);
    set_caller_address_global(default_owner());
    positions.set_twamm(twamm.contract_address);
    // A global cheat would also apply to the calls Positions makes into the NFT contract, which
    // checks its own caller. Drop it before minting.
    stop_caller_address_global();

    let seller = get_contract_address();

    let order_key = OrderKey {
        sell_token: setup.token0.contract_address,
        buy_token: setup.token1.contract_address,
        fee: 0,
        start_time: ORDER_START,
        end_time: ORDER_END,
    };

    // The seller is the test contract itself, so it is already the natural caller; cheating the
    // caller here would name an address that is not deployed.
    setup.token0.increase_balance(positions.contract_address, SELL_AMOUNT);
    let (token_id, _) = positions.mint_and_increase_sell_amount(order_key, SELL_AMOUNT);

    // Run the order past its end. With no liquidity nothing is purchased.
    set_block_timestamp_global(ORDER_END + 1);
    twamm.execute_virtual_orders(state_key(order_key));

    (
        d,
        core,
        twamm,
        positions,
        setup.token0,
        setup.token1,
        seller,
        order_key,
        token_id,
        refund_class,
        twamm_class,
    )
}

#[test]
fn test_refund_returns_stranded_balance_to_the_order_owner() {
    let (
        _d,
        core,
        twamm,
        positions,
        token0,
        _token1,
        seller,
        order_key,
        token_id,
        refund_class,
        twamm_class,
    ) =
        strand_funds();

    // The order bought nothing and has nothing left to sell, so the seller cannot recover it.
    let info = twamm.get_order_info(positions.contract_address, token_id.into(), order_key);
    assert(info.purchased_amount == 0, 'purchased');
    assert(info.remaining_sell_amount == 0, 'remaining');

    // The tokens are in Core, under the TWAMM's own shared saved balance.
    let saved_key = SavedBalanceKey {
        owner: twamm.contract_address, token: token0.contract_address, salt: 0,
    };
    assert(core.get_saved_balance(saved_key) == SELL_AMOUNT, 'stranded');

    let upgradeable = IUpgradeableDispatcher { contract_address: twamm.contract_address };
    // Cheat one call at a time. A global cheat would change who Core sees as the locker, and a
    // sticky cheat on the TWAMM would still be in force when Core calls back into `locked`, which
    // requires its caller to be Core.
    set_caller_address_once(twamm.contract_address, default_owner());

    // Upgrade, refund, and upgrade back -- the sequence a governance proposal executes atomically.
    upgradeable.replace_class_hash(refund_class);

    let token0_erc20 = IERC20Dispatcher { contract_address: token0.contract_address };
    let balance_before = token0_erc20.balanceOf(seller);
    set_caller_address_once(twamm.contract_address, default_owner());
    ITWAMMRefundDispatcher { contract_address: twamm.contract_address }
        .refund(
            array![
                Refund { token: token0.contract_address, recipient: seller, amount: SELL_AMOUNT },
            ],
        );

    set_caller_address_once(twamm.contract_address, default_owner());
    upgradeable.replace_class_hash(twamm_class);

    assert(token0_erc20.balanceOf(seller) == balance_before + SELL_AMOUNT.into(), 'refunded');
    assert(core.get_saved_balance(saved_key) == 0, 'drained');
}

#[test]
fn test_twamm_still_works_after_the_round_trip() {
    let (
        _d,
        _core,
        twamm,
        positions,
        token0,
        token1,
        seller,
        _order_key,
        _token_id,
        refund_class,
        twamm_class,
    ) =
        strand_funds();

    let upgradeable = IUpgradeableDispatcher { contract_address: twamm.contract_address };

    set_caller_address_once(twamm.contract_address, default_owner());
    upgradeable.replace_class_hash(refund_class);

    set_caller_address_once(twamm.contract_address, default_owner());
    ITWAMMRefundDispatcher { contract_address: twamm.contract_address }
        .refund(
            array![
                Refund { token: token0.contract_address, recipient: seller, amount: SELL_AMOUNT },
            ],
        );

    set_caller_address_once(twamm.contract_address, default_owner());
    upgradeable.replace_class_hash(twamm_class);

    // A new order can still be placed and read back through the restored implementation.
    let next_key = OrderKey {
        sell_token: token0.contract_address,
        buy_token: token1.contract_address,
        fee: 0,
        start_time: ORDER_END + 0x10,
        end_time: ORDER_END + 0x100,
    };

    stop_caller_address_global();
    token0.increase_balance(positions.contract_address, SELL_AMOUNT);
    let (next_id, _) = positions.mint_and_increase_sell_amount(next_key, SELL_AMOUNT);

    let info = twamm.get_order_info(positions.contract_address, next_id.into(), next_key);
    assert(info.sale_rate > 0, 'sale rate');
}

#[test]
#[should_panic(expected: 'OWNER_ONLY')]
fn test_refund_is_owner_only() {
    let (
        _d,
        _core,
        twamm,
        _positions,
        token0,
        _token1,
        seller,
        _order_key,
        _token_id,
        refund_class,
        _twamm_class,
    ) =
        strand_funds();

    let upgradeable = IUpgradeableDispatcher { contract_address: twamm.contract_address };
    set_caller_address_once(twamm.contract_address, default_owner());
    upgradeable.replace_class_hash(refund_class);

    // Anyone other than the owner must not be able to move the funds.
    set_caller_address_once(twamm.contract_address, 9999999.try_into().unwrap());
    ITWAMMRefundDispatcher { contract_address: twamm.contract_address }
        .refund(
            array![
                Refund { token: token0.contract_address, recipient: seller, amount: SELL_AMOUNT },
            ],
        );
}

#[test]
#[should_panic(expected: 'INSUFFICIENT_SAVED_BALANCE')]
fn test_refund_cannot_exceed_the_saved_balance() {
    let (
        _d,
        _core,
        twamm,
        _positions,
        token0,
        _token1,
        seller,
        _order_key,
        _token_id,
        refund_class,
        _twamm_class,
    ) =
        strand_funds();

    let upgradeable = IUpgradeableDispatcher { contract_address: twamm.contract_address };
    set_caller_address_once(twamm.contract_address, default_owner());
    upgradeable.replace_class_hash(refund_class);

    set_caller_address_once(twamm.contract_address, default_owner());
    ITWAMMRefundDispatcher { contract_address: twamm.contract_address }
        .refund(
            array![
                Refund {
                    token: token0.contract_address, recipient: seller, amount: SELL_AMOUNT + 1,
                },
            ],
        );
}
