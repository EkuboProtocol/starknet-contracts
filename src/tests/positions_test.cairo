use core::array::ArrayTrait;
use core::num::traits::{Zero};
use core::option::{OptionTrait};
use core::traits::{Into};
use ekubo::components::clear::{IClearDispatcher, IClearDispatcherTrait};
use ekubo::interfaces::core::{ICoreDispatcherTrait, ILockerDispatcher, ILockerDispatcherTrait};
use ekubo::interfaces::erc20::{IERC20Dispatcher};
use ekubo::interfaces::erc721::{IERC721Dispatcher, IERC721DispatcherTrait};
use ekubo::interfaces::extensions::limit_orders::{
    GetOrderInfoResult as GetLimitOrderInfoResult, OrderKey as LimitOrderKey,
    OrderState as LimitOrderState,
};
use ekubo::interfaces::positions::{
    GetTokenInfoRequest, IPositionsDispatcher, IPositionsDispatcherTrait,
};
use ekubo::interfaces::upgradeable::{IUpgradeableDispatcher, IUpgradeableDispatcherTrait};
use ekubo::math::ticks::{max_sqrt_ratio, min_sqrt_ratio};
use ekubo::math::ticks::{tick_to_sqrt_ratio};
use ekubo::positions::{Positions};

use ekubo::tests::helper::{
    Deployer, DeployerTrait, FEE_ONE_PERCENT, IPositionsDispatcherIntoILockerDispatcher,
    SetupPoolResult, default_owner, swap,
};

use ekubo::tests::mock_erc20::{
    IMockERC20Dispatcher, IMockERC20DispatcherTrait, MockERC20IERC20ImplTrait,
};
use ekubo::types::bounds::{Bounds, max_bounds};
use ekubo::types::i129::{i129};
use ekubo::types::keys::{PoolKey};
use starknet::testing::{pop_log, set_contract_address};
use starknet::{ClassHash, contract_address_const, get_contract_address};

#[test]
fn test_replace_class_hash_can_be_called_by_owner() {
    let mut d: Deployer = Default::default();

    let setup = d
        .setup_pool(
            fee: FEE_ONE_PERCENT,
            tick_spacing: 1,
            initial_tick: Zero::zero(),
            extension: Zero::zero(),
        );
    let positions = d.deploy_positions(setup.core);

    pop_log::<ekubo::components::owned::Owned::OwnershipTransferred>(positions.contract_address)
        .unwrap();

    let class_hash: ClassHash = Positions::TEST_CLASS_HASH.try_into().unwrap();

    set_contract_address(default_owner());
    IUpgradeableDispatcher { contract_address: positions.contract_address }
        .replace_class_hash(class_hash);

    let event: ekubo::components::upgradeable::Upgradeable::ClassHashReplaced = pop_log(
        positions.contract_address,
    )
        .unwrap();
    assert(event.new_class_hash == class_hash, 'event.class_hash');
}

#[test]
fn test_deposit_liquidity_full_range() {
    let mut d: Deployer = Default::default();
    let setup = d
        .setup_pool(
            fee: FEE_ONE_PERCENT,
            tick_spacing: 1,
            initial_tick: Zero::zero(),
            extension: Zero::zero(),
        );
    let positions = d.deploy_positions(setup.core);
    let token_id = positions.mint(pool_key: setup.pool_key, bounds: max_bounds(1));
    assert(token_id == 1, 'token id');
    setup.token0.increase_balance(positions.contract_address, 100000000);
    setup.token1.increase_balance(positions.contract_address, 100000000);
    let liquidity = positions
        .deposit_last(pool_key: setup.pool_key, bounds: max_bounds(1), min_liquidity: 100000000);

    assert(liquidity == 100000000, 'liquidity');

    let nft = IERC721Dispatcher { contract_address: positions.get_nft_address() };

    assert(nft.balance_of(get_contract_address()) == 1, 'balance');
    assert(nft.owner_of(token_id.into()) == get_contract_address(), 'owner');
}

#[test]
#[should_panic(expected: ('CORE_ONLY', 'ENTRYPOINT_FAILED'))]
fn test_locked_cannot_be_called_directly() {
    let mut d: Deployer = Default::default();
    let setup = d
        .setup_pool(
            fee: FEE_ONE_PERCENT,
            tick_spacing: 1,
            initial_tick: Zero::zero(),
            extension: Zero::zero(),
        );
    let positions = d.deploy_positions(setup.core);
    ILockerDispatcher { contract_address: positions.contract_address }
        .locked(1, ArrayTrait::new().span());
}

#[test]
#[should_panic(
    expected: ('MIN_LIQUIDITY', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED'),
)]
fn test_deposit_fails_min_liquidity() {
    let mut d: Deployer = Default::default();
    let setup = d
        .setup_pool(
            fee: FEE_ONE_PERCENT,
            tick_spacing: 1,
            initial_tick: Zero::zero(),
            extension: Zero::zero(),
        );
    let positions = d.deploy_positions(setup.core);
    let token_id = positions.mint(pool_key: setup.pool_key, bounds: max_bounds(1));
    assert(token_id == 1, 'token id');
    setup.token0.increase_balance(positions.contract_address, 100000000);
    setup.token1.increase_balance(positions.contract_address, 100000000);
    positions
        .deposit_last(pool_key: setup.pool_key, bounds: max_bounds(1), min_liquidity: 100000001);
}

#[test]
fn test_deposit_liquidity_concentrated() {
    let caller = contract_address_const::<1>();
    set_contract_address(caller);
    let mut d: Deployer = Default::default();
    let setup = d
        .setup_pool(
            fee: FEE_ONE_PERCENT,
            tick_spacing: 1,
            initial_tick: Zero::zero(),
            extension: Zero::zero(),
        );
    let positions = d.deploy_positions(setup.core);
    let bounds = Bounds {
        lower: i129 { mag: 1000, sign: true }, upper: i129 { mag: 1000, sign: false },
    };
    let token_id = positions.mint(pool_key: setup.pool_key, bounds: bounds);
    assert(token_id == 1, 'token id');
    setup.token0.increase_balance(positions.contract_address, 100000000);
    setup.token1.increase_balance(positions.contract_address, 100000000);
    let liquidity = positions
        .deposit_last(pool_key: setup.pool_key, bounds: bounds, min_liquidity: 100);

    set_contract_address(contract_address_const::<2>());
    let balance0 = IClearDispatcher { contract_address: positions.contract_address }
        .clear(IERC20Dispatcher { contract_address: setup.token0.contract_address });
    let balance1 = IClearDispatcher { contract_address: positions.contract_address }
        .clear(IERC20Dispatcher { contract_address: setup.token0.contract_address });

    assert(
        setup.token0.balanceOf(contract_address_const::<2>()) == Zero::zero(), 'balance0 transfer',
    );
    assert(
        setup.token1.balanceOf(contract_address_const::<2>()) == Zero::zero(), 'balance1 transfer',
    );

    assert(balance0 == Zero::zero(), 'balance0');
    assert(balance1 == Zero::zero(), 'balance1');

    assert(liquidity == 200050104166, 'liquidity');
}


#[test]
fn test_deposit_liquidity_concentrated_mint_and_deposit() {
    let caller = contract_address_const::<1>();
    set_contract_address(caller);
    let mut d: Deployer = Default::default();
    let setup = d
        .setup_pool(
            fee: FEE_ONE_PERCENT,
            tick_spacing: 1,
            initial_tick: Zero::zero(),
            extension: Zero::zero(),
        );
    let positions = d.deploy_positions(setup.core);
    let bounds = Bounds {
        lower: i129 { mag: 1000, sign: true }, upper: i129 { mag: 1000, sign: false },
    };

    setup.token0.increase_balance(positions.contract_address, 100000000);
    setup.token1.increase_balance(positions.contract_address, 100000000);
    let (token_id, liquidity) = positions
        .mint_and_deposit(pool_key: setup.pool_key, bounds: bounds, min_liquidity: 100);

    assert(token_id == 1, 'token_id');
    assert(liquidity == 200050104166, 'liquidity');
}

#[test]
fn test_deposit_liquidity_concentrated_unbalanced_in_range_price_higher() {
    let caller = contract_address_const::<1>();
    set_contract_address(caller);
    let mut d: Deployer = Default::default();
    let setup = d
        .setup_pool(
            fee: FEE_ONE_PERCENT,
            tick_spacing: 1,
            initial_tick: i129 { mag: 500, sign: false },
            extension: Zero::zero(),
        );
    let positions = d.deploy_positions(setup.core);
    let bounds = Bounds {
        lower: i129 { mag: 1000, sign: true }, upper: i129 { mag: 1000, sign: false },
    };
    let token_id = positions.mint(pool_key: setup.pool_key, bounds: bounds);
    assert(token_id == 1, 'token id');
    setup.token0.increase_balance(positions.contract_address, 100000000);
    setup.token1.increase_balance(positions.contract_address, 100000000);
    let liquidity = positions
        .deposit_last(pool_key: setup.pool_key, bounds: bounds, min_liquidity: 100);

    set_contract_address(contract_address_const::<2>());
    let balance0 = IClearDispatcher { contract_address: positions.contract_address }
        .clear(IERC20Dispatcher { contract_address: setup.token0.contract_address });
    let balance1 = IClearDispatcher { contract_address: positions.contract_address }
        .clear(IERC20Dispatcher { contract_address: setup.token1.contract_address });

    assert(
        setup.token0.balanceOf(contract_address_const::<2>()) == u256 { low: 66674999, high: 0 },
        'balance0 transfer',
    );
    assert(
        setup.token1.balanceOf(contract_address_const::<2>()) == Zero::zero(), 'balance1 transfer',
    );

    assert(balance0 == u256 { low: 66674999, high: 0 }, 'balance0');
    assert(balance1 == Zero::zero(), 'balance1');
    assert(liquidity == 133350064582, 'liquidity');
}

#[test]
fn test_create_limit_order_token0() {
    let caller = contract_address_const::<1>();
    set_contract_address(caller);
    let mut d: Deployer = Default::default();
    let setup = d
        .setup_pool(
            fee: FEE_ONE_PERCENT,
            tick_spacing: 1,
            initial_tick: i129 { mag: 500, sign: false },
            extension: Zero::zero(),
        );
    let positions = d.deploy_positions(setup.core);
    let limit_orders = d.deploy_limit_orders(setup.core);
    set_contract_address(default_owner());
    positions.set_limit_orders(limit_orders.contract_address);

    setup.token0.increase_balance(positions.contract_address, 100);
    let (id, liquidity) = positions
        .mint_and_place_limit_order(
            LimitOrderKey {
                token0: setup.token0.contract_address,
                token1: setup.token1.contract_address,
                tick: i129 { mag: 0, sign: false },
            },
            amount: 100,
        );

    assert_eq!(id, 1);
    assert_eq!(liquidity, 1562550);

    let (amount0, amount1) = positions
        .close_limit_order(
            id,
            LimitOrderKey {
                token0: setup.token0.contract_address,
                token1: setup.token1.contract_address,
                tick: i129 { mag: 0, sign: false },
            },
        );

    assert_eq!(amount0, 99);
    assert_eq!(amount1, 0);
}

#[test]
fn test_create_limit_order_token1() {
    let caller = contract_address_const::<1>();
    set_contract_address(caller);
    let mut d: Deployer = Default::default();
    let setup = d
        .setup_pool(
            fee: FEE_ONE_PERCENT,
            tick_spacing: 1,
            initial_tick: i129 { mag: 500, sign: false },
            extension: Zero::zero(),
        );
    let positions = d.deploy_positions(setup.core);
    let limit_orders = d.deploy_limit_orders(setup.core);
    set_contract_address(default_owner());
    positions.set_limit_orders(limit_orders.contract_address);

    setup.token1.increase_balance(positions.contract_address, 100);
    let (id, liquidity) = positions
        .mint_and_place_limit_order(
            LimitOrderKey {
                token0: setup.token0.contract_address,
                token1: setup.token1.contract_address,
                tick: i129 { mag: 128, sign: false },
            },
            amount: 100,
        );

    assert_eq!(id, 1);
    assert_eq!(liquidity, 1562350);

    let (amount0, amount1) = positions
        .close_limit_order(
            id,
            LimitOrderKey {
                token0: setup.token0.contract_address,
                token1: setup.token1.contract_address,
                tick: i129 { mag: 128, sign: false },
            },
        );

    assert_eq!(amount0, 0);
    assert_eq!(amount1, 99);
}

#[test]
fn test_create_limit_order_token0_then_token1() {
    let caller = contract_address_const::<1>();
    set_contract_address(caller);
    let mut d: Deployer = Default::default();
    let setup = d
        .setup_pool(
            fee: FEE_ONE_PERCENT,
            tick_spacing: 1,
            initial_tick: i129 { mag: 500, sign: false },
            extension: Zero::zero(),
        );
    let positions = d.deploy_positions(setup.core);
    let limit_orders = d.deploy_limit_orders(setup.core);
    set_contract_address(default_owner());
    positions.set_limit_orders(limit_orders.contract_address);

    setup.token0.increase_balance(positions.contract_address, 100);
    positions
        .mint_and_place_limit_order(
            LimitOrderKey {
                token0: setup.token0.contract_address,
                token1: setup.token1.contract_address,
                tick: i129 { mag: 0, sign: false },
            },
            amount: 100,
        );

    setup.token1.increase_balance(positions.contract_address, 50);
    let (amount_sold, amount_bought, mint_result) = positions
        .swap_to_limit_order_price_and_maybe_mint_and_place_limit_order(
            LimitOrderKey {
                token0: setup.token0.contract_address,
                token1: setup.token1.contract_address,
                tick: i129 { mag: 128, sign: false },
            },
            amount: 50,
        );

    assert_eq!(amount_sold, 50);
    assert_eq!(amount_bought, 49);
    assert_eq!(mint_result, Option::None);
}

#[test]
fn test_create_limit_order_token1_then_token0() {
    let caller = contract_address_const::<1>();
    set_contract_address(caller);
    let mut d: Deployer = Default::default();
    let setup = d
        .setup_pool(
            fee: FEE_ONE_PERCENT,
            tick_spacing: 1,
            initial_tick: i129 { mag: 500, sign: false },
            extension: Zero::zero(),
        );
    let positions = d.deploy_positions(setup.core);
    let limit_orders = d.deploy_limit_orders(setup.core);
    set_contract_address(default_owner());
    positions.set_limit_orders(limit_orders.contract_address);

    setup.token1.increase_balance(positions.contract_address, 100);
    positions
        .mint_and_place_limit_order(
            LimitOrderKey {
                token0: setup.token0.contract_address,
                token1: setup.token1.contract_address,
                tick: i129 { mag: 128, sign: false },
            },
            amount: 100,
        );

    setup.token0.increase_balance(positions.contract_address, 50);
    let (amount_sold, amount_bought, mint_result) = positions
        .swap_to_limit_order_price_and_maybe_mint_and_place_limit_order(
            LimitOrderKey {
                token0: setup.token0.contract_address,
                token1: setup.token1.contract_address,
                tick: i129 { mag: 0, sign: false },
            },
            amount: 50,
        );

    assert_eq!(amount_sold, 50);
    assert_eq!(amount_bought, 49);
    assert_eq!(mint_result, Option::None);
}

#[test]
fn test_create_limit_order_token0_then_token1_fully_execute() {
    let caller = contract_address_const::<1>();
    set_contract_address(caller);
    let mut d: Deployer = Default::default();
    let setup = d
        .setup_pool(
            fee: FEE_ONE_PERCENT,
            tick_spacing: 1,
            initial_tick: i129 { mag: 500, sign: false },
            extension: Zero::zero(),
        );
    let positions = d.deploy_positions(setup.core);
    let limit_orders = d.deploy_limit_orders(setup.core);
    set_contract_address(default_owner());
    positions.set_limit_orders(limit_orders.contract_address);

    setup.token0.increase_balance(positions.contract_address, 100);
    positions
        .mint_and_place_limit_order(
            LimitOrderKey {
                token0: setup.token0.contract_address,
                token1: setup.token1.contract_address,
                tick: i129 { mag: 0, sign: false },
            },
            amount: 100,
        );

    setup.token1.increase_balance(positions.contract_address, 150);
    let (amount_sold, amount_bought, mint_result) = positions
        .swap_to_limit_order_price_and_maybe_mint_and_place_limit_order(
            LimitOrderKey {
                token0: setup.token0.contract_address,
                token1: setup.token1.contract_address,
                tick: i129 { mag: 128, sign: false },
            },
            amount: 150,
        );

    let (id, liquidity) = mint_result.expect('mint did not happen');
    assert_eq!(id, 2);
    assert_eq!(liquidity, 765551);
    assert_eq!(amount_sold, 100);
    assert_eq!(amount_bought, 99);

    assert_eq!(
        positions
            .get_limit_orders_info(
                array![
                    (
                        id,
                        LimitOrderKey {
                            token0: setup.token0.contract_address,
                            token1: setup.token1.contract_address,
                            tick: i129 { mag: 128, sign: false },
                        },
                    ),
                ]
                    .span(),
            ),
        array![
            GetLimitOrderInfoResult {
                state: LimitOrderState { initialized_ticks_crossed_snapshot: 2, liquidity: 765551 },
                executed: false,
                amount0: 0,
                amount1: 48,
            },
        ]
            .span(),
    );

    let (amount0, amount1) = positions
        .close_limit_order(
            id,
            LimitOrderKey {
                token0: setup.token0.contract_address,
                token1: setup.token1.contract_address,
                tick: i129 { mag: 128, sign: false },
            },
        );

    assert_eq!(amount0, 99);
    assert_eq!(amount1, 48);
}

#[test]
fn test_create_limit_order_token1_then_token0_fully_execute() {
    let caller = contract_address_const::<1>();
    set_contract_address(caller);
    let mut d: Deployer = Default::default();
    let setup = d
        .setup_pool(
            fee: FEE_ONE_PERCENT,
            tick_spacing: 1,
            initial_tick: i129 { mag: 500, sign: false },
            extension: Zero::zero(),
        );
    let positions = d.deploy_positions(setup.core);
    let limit_orders = d.deploy_limit_orders(setup.core);
    set_contract_address(default_owner());
    positions.set_limit_orders(limit_orders.contract_address);

    setup.token1.increase_balance(positions.contract_address, 100);
    positions
        .mint_and_place_limit_order(
            LimitOrderKey {
                token0: setup.token0.contract_address,
                token1: setup.token1.contract_address,
                tick: i129 { mag: 128, sign: false },
            },
            amount: 100,
        );

    setup.token0.increase_balance(positions.contract_address, 150);
    let (amount_sold, amount_bought, mint_result) = positions
        .swap_to_limit_order_price_and_maybe_mint_and_place_limit_order(
            LimitOrderKey {
                token0: setup.token0.contract_address,
                token1: setup.token1.contract_address,
                tick: i129 { mag: 0, sign: false },
            },
            amount: 150,
        );

    let (id, liquidity) = mint_result.expect('mint did not happen');
    assert_eq!(id, 2);
    assert_eq!(liquidity, 781275);
    assert_eq!(amount_sold, 100);
    assert_eq!(amount_bought, 99);

    assert_eq!(
        positions
            .get_limit_orders_info(
                array![
                    (
                        id,
                        LimitOrderKey {
                            token0: setup.token0.contract_address,
                            token1: setup.token1.contract_address,
                            tick: i129 { mag: 0, sign: false },
                        },
                    ),
                ]
                    .span(),
            ),
        array![
            GetLimitOrderInfoResult {
                state: LimitOrderState { initialized_ticks_crossed_snapshot: 2, liquidity: 781275 },
                executed: false,
                amount0: 49,
                amount1: 0,
            },
        ]
            .span(),
    );

    let (amount0, amount1) = positions
        .close_limit_order(
            id,
            LimitOrderKey {
                token0: setup.token0.contract_address,
                token1: setup.token1.contract_address,
                tick: i129 { mag: 0, sign: false },
            },
        );

    assert_eq!(amount0, 49);
    assert_eq!(amount1, 99);
}

#[test]
fn test_deposit_liquidity_concentrated_unbalanced_in_range_price_lower() {
    let caller = contract_address_const::<1>();
    set_contract_address(caller);
    let mut d: Deployer = Default::default();
    let setup = d
        .setup_pool(
            fee: FEE_ONE_PERCENT,
            tick_spacing: 1,
            initial_tick: i129 { mag: 500, sign: true },
            extension: Zero::zero(),
        );
    let positions = d.deploy_positions(setup.core);
    let bounds = Bounds {
        lower: i129 { mag: 1000, sign: true }, upper: i129 { mag: 1000, sign: false },
    };
    let token_id = positions.mint(pool_key: setup.pool_key, bounds: bounds);
    assert(token_id == 1, 'token id');
    setup.token0.increase_balance(positions.contract_address, 100000000);
    setup.token1.increase_balance(positions.contract_address, 100000000);
    let liquidity = positions
        .deposit_last(pool_key: setup.pool_key, bounds: bounds, min_liquidity: 100);

    set_contract_address(contract_address_const::<2>());

    let balance0 = IClearDispatcher { contract_address: positions.contract_address }
        .clear(IERC20Dispatcher { contract_address: setup.token0.contract_address });
    let balance1 = IClearDispatcher { contract_address: positions.contract_address }
        .clear(IERC20Dispatcher { contract_address: setup.token1.contract_address });

    assert(
        setup.token0.balanceOf(contract_address_const::<2>()) == Zero::zero(), 'balance0 transfer',
    );
    assert(
        setup.token1.balanceOf(contract_address_const::<2>()) == u256 { low: 66674999, high: 0 },
        'balance1 transfer',
    );

    assert(balance0 == Zero::zero(), 'balance0');
    assert(balance1 == u256 { low: 66674999, high: 0 }, 'balance1');
    assert(liquidity == 133350064582, 'liquidity');
}

#[test]
fn test_deposit_liquidity_concentrated_out_of_range_price_upper() {
    let caller = contract_address_const::<1>();
    set_contract_address(caller);
    let mut d: Deployer = Default::default();
    let setup = d
        .setup_pool(
            fee: FEE_ONE_PERCENT,
            tick_spacing: 1,
            initial_tick: i129 { mag: 1000, sign: false },
            extension: Zero::zero(),
        );
    let positions = d.deploy_positions(setup.core);
    let bounds = Bounds {
        lower: i129 { mag: 1000, sign: true }, upper: i129 { mag: 1000, sign: false },
    };
    let token_id = positions.mint(pool_key: setup.pool_key, bounds: bounds);
    assert(token_id == 1, 'token id');
    setup.token0.increase_balance(positions.contract_address, 100000000);
    setup.token1.increase_balance(positions.contract_address, 100000000);
    let liquidity = positions
        .deposit_last(pool_key: setup.pool_key, bounds: bounds, min_liquidity: 100);

    set_contract_address(contract_address_const::<2>());

    let balance0 = IClearDispatcher { contract_address: positions.contract_address }
        .clear(IERC20Dispatcher { contract_address: setup.token0.contract_address });
    let balance1 = IClearDispatcher { contract_address: positions.contract_address }
        .clear(IERC20Dispatcher { contract_address: setup.token1.contract_address });

    assert(
        setup.token0.balanceOf(contract_address_const::<2>()) == u256 { low: 100000000, high: 0 },
        'balance0 transfer',
    );
    assert(
        setup.token1.balanceOf(contract_address_const::<2>()) == Zero::zero(), 'balance1 transfer',
    );

    assert(balance0 == u256 { low: 100000000, high: 0 }, 'balance0');
    assert(balance1 == Zero::zero(), 'balance1');
    assert(liquidity == 100000045833, 'liquidity');
}

#[test]
fn test_deposit_liquidity_concentrated_out_of_range_price_lower() {
    let caller = contract_address_const::<1>();
    set_contract_address(caller);
    let mut d: Deployer = Default::default();
    let setup = d
        .setup_pool(
            fee: FEE_ONE_PERCENT,
            tick_spacing: 1,
            initial_tick: i129 { mag: 1000, sign: true },
            extension: Zero::zero(),
        );
    let positions = d.deploy_positions(setup.core);
    let bounds = Bounds {
        lower: i129 { mag: 1000, sign: true }, upper: i129 { mag: 1000, sign: false },
    };
    let token_id = positions.mint(pool_key: setup.pool_key, bounds: bounds);
    assert(token_id == 1, 'token id');
    setup.token0.increase_balance(positions.contract_address, 100000000);
    setup.token1.increase_balance(positions.contract_address, 100000000);
    let liquidity = positions
        .deposit_last(pool_key: setup.pool_key, bounds: bounds, min_liquidity: 100);

    set_contract_address(contract_address_const::<2>());
    let balance0 = IClearDispatcher { contract_address: positions.contract_address }
        .clear(IERC20Dispatcher { contract_address: setup.token0.contract_address });
    let balance1 = IClearDispatcher { contract_address: positions.contract_address }
        .clear(IERC20Dispatcher { contract_address: setup.token1.contract_address });

    assert(
        setup.token0.balanceOf(contract_address_const::<2>()) == Zero::zero(), 'balance0 transfer',
    );
    assert(
        setup.token1.balanceOf(contract_address_const::<2>()) == u256 { low: 100000000, high: 0 },
        'balance1 transfer',
    );

    assert(balance0 == Zero::zero(), 'balance0');
    assert(balance1 == u256 { low: 100000000, high: 0 }, 'balance1');
    assert(liquidity == 100000045833, 'liquidity');
}

#[test]
fn test_deposit_then_withdraw_with_fees() {
    let caller = contract_address_const::<1>();
    set_contract_address(caller);
    let mut d: Deployer = Default::default();
    let setup = d
        .setup_pool(
            fee: FEE_ONE_PERCENT,
            tick_spacing: 1,
            initial_tick: Zero::zero(),
            extension: Zero::zero(),
        );
    let positions = d.deploy_positions(setup.core);
    let bounds = Bounds {
        lower: i129 { mag: 1000, sign: true }, upper: i129 { mag: 1000, sign: false },
    };
    let token_id = positions.mint(pool_key: setup.pool_key, bounds: bounds);

    setup.token0.increase_balance(positions.contract_address, 100000000);
    setup.token1.increase_balance(positions.contract_address, 100000000);
    positions.deposit_last(pool_key: setup.pool_key, bounds: bounds, min_liquidity: 100);

    setup.token0.increase_balance(setup.locker.contract_address, 100000000000);
    setup.token1.increase_balance(setup.locker.contract_address, 100000000000);
    swap(
        setup: setup,
        amount: i129 { mag: 1000, sign: false },
        is_token1: true,
        sqrt_ratio_limit: max_sqrt_ratio(),
        recipient: Zero::zero(),
        skip_ahead: 0,
    );
    swap(
        setup: setup,
        amount: i129 { mag: 2000, sign: false },
        is_token1: false,
        sqrt_ratio_limit: min_sqrt_ratio(),
        recipient: Zero::zero(),
        skip_ahead: 0,
    );

    let token_info = positions.get_token_info(token_id, setup.pool_key, bounds);

    assert(token_info.liquidity == 200050104166, 'liquidity');
    assert(token_info.amount0 == 100000989, 'amount0');
    assert(token_info.amount1 == 99999009, 'amount1');
    assert(token_info.fees0 == 19, 'fees0');
    assert(token_info.fees1 == 9, 'fees1');
}

#[test]
fn test_deposit_then_partial_withdraw_with_fees() {
    let caller = contract_address_const::<12345678>();
    set_contract_address(caller);
    let mut d: Deployer = Default::default();
    let setup = d
        .setup_pool(
            fee: FEE_ONE_PERCENT,
            tick_spacing: 1,
            initial_tick: Zero::zero(),
            extension: Zero::zero(),
        );
    let positions = d.deploy_positions(setup.core);
    let bounds = Bounds {
        lower: i129 { mag: 1000, sign: true }, upper: i129 { mag: 1000, sign: false },
    };
    let token_id = positions.mint(pool_key: setup.pool_key, bounds: bounds);

    setup.token0.increase_balance(positions.contract_address, 100000000);
    setup.token1.increase_balance(positions.contract_address, 100000000);
    let liquidity = positions
        .deposit_last(pool_key: setup.pool_key, bounds: bounds, min_liquidity: 100);

    setup.token0.increase_balance(setup.locker.contract_address, 100000000000);
    setup.token1.increase_balance(setup.locker.contract_address, 100000000000);
    swap(
        setup: setup,
        amount: i129 { mag: 1000, sign: false },
        is_token1: true,
        sqrt_ratio_limit: max_sqrt_ratio(),
        recipient: Zero::zero(),
        skip_ahead: 0,
    );
    swap(
        setup: setup,
        amount: i129 { mag: 2000, sign: false },
        is_token1: false,
        sqrt_ratio_limit: min_sqrt_ratio(),
        recipient: Zero::zero(),
        skip_ahead: 0,
    );

    let (amount0, amount1) = positions
        .withdraw(
            id: token_id,
            pool_key: setup.pool_key,
            bounds: bounds,
            liquidity: (liquidity / 2),
            min_token0: 1000,
            min_token1: 1000,
            collect_fees: false,
        );

    assert(amount0 == 49500489, 'amount0 less 1%');
    assert(amount1 == 49499508, 'amount1 less 1%');
    assert(
        IMockERC20Dispatcher { contract_address: setup.pool_key.token0 }
            .balanceOf(caller) == amount0
            .into(),
        'balance0',
    );
    assert(
        IMockERC20Dispatcher { contract_address: setup.pool_key.token1 }
            .balanceOf(caller) == amount1
            .into(),
        'balance1',
    );

    // fees are not withdrawn with the principal
    let token_info = positions.get_token_info(token_id, setup.pool_key, bounds);

    assert(token_info.liquidity == 100025052083, 'liquidity');
    assert(token_info.amount0 == 50000494, 'amount0');
    assert(token_info.amount1 == 49999504, 'amount1');
    assert(token_info.fees0 == 18, 'fees0');
    assert(token_info.fees1 == 8, 'fees1');

    // withdraw 0 liquidity
    let (amount0, amount1) = positions
        .withdraw_v2(
            id: token_id,
            pool_key: setup.pool_key,
            bounds: bounds,
            liquidity: 0,
            min_token0: 0,
            min_token1: 0,
        );

    assert(amount0 == 0, 'fees not withdrawn');
    assert(amount1 == 0, 'fees not withdrawn');

    let (amount0, amount1) = positions
        .collect_fees(id: token_id, pool_key: setup.pool_key, bounds: bounds);

    assert(amount0 == 17, 'fees0 withdrawn');
    assert(amount1 == 7, 'fees1 withdrawn');

    assert(
        IMockERC20Dispatcher { contract_address: setup.pool_key.token0 }
            .balanceOf(caller) == (49500489 + 17),
        'balance0',
    );
    assert(
        IMockERC20Dispatcher { contract_address: setup.pool_key.token1 }
            .balanceOf(caller) == (49499508 + 7),
        'balance1',
    );

    // withdraw quarter
    let (amount0, amount1) = positions
        .withdraw_v2(
            id: token_id,
            pool_key: setup.pool_key,
            bounds: bounds,
            liquidity: (liquidity / 4),
            min_token0: 0,
            min_token1: 0,
        );

    assert(amount0 == 24750244, 'quarter');
    assert(amount1 == 24749754, 'quarter');

    assert(
        IMockERC20Dispatcher { contract_address: setup.pool_key.token0 }
            .balanceOf(caller) == (49500489 + 17 + 24750244),
        'balance0',
    );
    assert(
        IMockERC20Dispatcher { contract_address: setup.pool_key.token1 }
            .balanceOf(caller) == (49499508 + 7 + 24749754),
        'balance1',
    );

    // withdraw remainder
    let (amount0, amount1) = positions
        .withdraw_v2(
            id: token_id,
            pool_key: setup.pool_key,
            bounds: bounds,
            liquidity: liquidity - (liquidity / 2) - (liquidity / 4),
            min_token0: 0,
            min_token1: 0,
        );

    assert(amount0 == 24750244, 'remainder');
    assert(amount1 == 24749754, 'remainder');

    assert(
        IMockERC20Dispatcher { contract_address: setup.pool_key.token0 }
            .balanceOf(caller) == (49500489 + 17 + 24750244 + amount0.into()),
        'balance0',
    );
    assert(
        IMockERC20Dispatcher { contract_address: setup.pool_key.token1 }
            .balanceOf(caller) == (49499508 + 7 + 24749754 + amount1.into()),
        'balance1',
    );
}


#[test]
fn test_deposit_withdraw_protocol_fee_then_deposit() {
    let caller = contract_address_const::<1>();
    set_contract_address(caller);
    let mut d: Deployer = Default::default();
    let setup = d
        .setup_pool(
            fee: FEE_ONE_PERCENT,
            tick_spacing: 1,
            initial_tick: Zero::zero(),
            extension: Zero::zero(),
        );
    let positions = d.deploy_positions(setup.core);
    let bounds = Bounds {
        lower: i129 { mag: 1000, sign: true }, upper: i129 { mag: 1000, sign: false },
    };
    let token_id = positions.mint(pool_key: setup.pool_key, bounds: bounds);

    let recipient = contract_address_const::<80085>();

    setup.token0.increase_balance(positions.contract_address, 100000000);
    setup.token1.increase_balance(positions.contract_address, 100000000);
    let liquidity = positions
        .deposit_last(pool_key: setup.pool_key, bounds: bounds, min_liquidity: 100);

    positions
        .withdraw_v2(
            id: token_id,
            pool_key: setup.pool_key,
            bounds: bounds,
            liquidity: liquidity,
            min_token0: 0,
            min_token1: 0,
        );

    let caller = get_contract_address();
    set_contract_address(default_owner());
    setup
        .core
        .withdraw_protocol_fees(recipient: recipient, token: setup.pool_key.token0, amount: 1);
    setup.core.withdraw_all_protocol_fees(recipient: recipient, token: setup.pool_key.token1);

    set_contract_address(caller);
    setup.token0.increase_balance(positions.contract_address, 100000000);
    setup.token1.increase_balance(positions.contract_address, 100000000);
    positions.deposit_last(pool_key: setup.pool_key, bounds: bounds, min_liquidity: 100);
}

#[test]
fn test_deposit_liquidity_updates_tick_states_at_bounds() {
    let caller = contract_address_const::<1>();
    set_contract_address(caller);
    let mut d: Deployer = Default::default();
    let setup = d
        .setup_pool(
            fee: FEE_ONE_PERCENT,
            tick_spacing: 1,
            initial_tick: Zero::zero(),
            extension: Zero::zero(),
        );
    let positions = d.deploy_positions(setup.core);
    let bounds = Bounds { lower: i129 { mag: 1, sign: true }, upper: i129 { mag: 1, sign: false } };
    positions.mint(pool_key: setup.pool_key, bounds: bounds);

    setup.token0.increase_balance(positions.contract_address, 10000);
    setup.token1.increase_balance(positions.contract_address, 10000);
    let liquidity = positions
        .deposit_last(pool_key: setup.pool_key, bounds: bounds, min_liquidity: 1);
    let tick_lower_liquidity_delta = setup
        .core
        .get_pool_tick_liquidity_delta(setup.pool_key, i129 { mag: 1, sign: true });
    let tick_lower_liquidity_net = setup
        .core
        .get_pool_tick_liquidity_net(setup.pool_key, i129 { mag: 1, sign: true });
    let tick_upper_liquidity_delta = setup
        .core
        .get_pool_tick_liquidity_delta(setup.pool_key, i129 { mag: 1, sign: false });
    let tick_upper_liquidity_net = setup
        .core
        .get_pool_tick_liquidity_net(setup.pool_key, i129 { mag: 1, sign: false });
    assert(
        tick_upper_liquidity_delta == i129 { mag: liquidity, sign: true }, 'upper.liquidity_delta',
    );
    assert(tick_upper_liquidity_net == liquidity, 'upper.liquidity_net');
    assert(
        setup
            .core
            .get_pool_tick_fees_outside(setup.pool_key, i129 { mag: 1, sign: false })
            .is_zero(),
        'upper.fees',
    );

    assert(
        tick_lower_liquidity_delta == i129 { mag: liquidity, sign: false }, 'lower.liquidity_delta',
    );
    assert(tick_lower_liquidity_net == liquidity, 'lower.liquidity_net');
    assert(
        setup
            .core
            .get_pool_tick_fees_outside(setup.pool_key, i129 { mag: 1, sign: true })
            .is_zero(),
        'lower.fees',
    );
}

#[test]
fn test_deposit_swap_through_upper_tick_fees_accounting() {
    let caller = contract_address_const::<1>();
    set_contract_address(caller);
    let mut d: Deployer = Default::default();
    let setup = d
        .setup_pool(
            fee: FEE_ONE_PERCENT,
            tick_spacing: 1,
            initial_tick: Zero::zero(),
            extension: Zero::zero(),
        );
    let positions = d.deploy_positions(setup.core);
    let bounds = Bounds { lower: i129 { mag: 1, sign: true }, upper: i129 { mag: 1, sign: false } };
    let token_id = positions.mint(pool_key: setup.pool_key, bounds: bounds);

    setup.token0.increase_balance(positions.contract_address, 10000);
    setup.token1.increase_balance(positions.contract_address, 10000);
    let liquidity = positions
        .deposit_last(pool_key: setup.pool_key, bounds: bounds, min_liquidity: 1);

    let mut info = positions.get_token_info(token_id, setup.pool_key, bounds);

    assert(info.liquidity == liquidity, 'liquidity before');
    assert(info.amount0 == 9999, 'amount0 before');
    assert(info.amount1 == 9999, 'amount1 before');
    assert(info.fees0 == 0, 'fees0 before');
    assert(info.fees1 == 0, 'fees1 before');

    setup.token1.increase_balance(setup.locker.contract_address, 20000);
    let delta_swap = swap(
        setup: setup,
        amount: i129 { mag: 100000, sign: true },
        is_token1: false,
        sqrt_ratio_limit: tick_to_sqrt_ratio(i129 { mag: 2, sign: false }),
        recipient: Zero::zero(),
        skip_ahead: 0,
    );

    assert(delta_swap.amount0 == i129 { mag: 9999, sign: true }, 'first swap delta0');
    assert(delta_swap.amount1 == i129 { mag: 10103, sign: false }, 'first swap delta1');

    info = positions.get_token_info(token_id, setup.pool_key, bounds);

    assert(info.liquidity == liquidity, 'liquidity after');
    assert(info.amount0 == 0, 'amount0 after');
    assert(info.amount1 == 20000, 'amount1 after');
    assert(info.fees0 == 0, 'fees0 after');
    assert(info.fees1 == 101, 'fees1 after');
}

#[test]
fn test_deposit_swap_through_lower_tick_fees_accounting() {
    let caller = contract_address_const::<1>();
    set_contract_address(caller);
    let mut d: Deployer = Default::default();
    let setup = d
        .setup_pool(
            fee: FEE_ONE_PERCENT,
            tick_spacing: 1,
            initial_tick: Zero::zero(),
            extension: Zero::zero(),
        );
    let positions = d.deploy_positions(setup.core);
    let bounds = Bounds { lower: i129 { mag: 1, sign: true }, upper: i129 { mag: 1, sign: false } };
    let token_id = positions.mint(pool_key: setup.pool_key, bounds: bounds);

    setup.token0.increase_balance(positions.contract_address, 10000);
    setup.token1.increase_balance(positions.contract_address, 10000);
    let liquidity = positions
        .deposit_last(pool_key: setup.pool_key, bounds: bounds, min_liquidity: 1);

    let mut info = positions.get_token_info(token_id, setup.pool_key, bounds);

    assert(info.liquidity == liquidity, 'liquidity before');
    assert(info.amount0 == 9999, 'amount0 before');
    assert(info.amount1 == 9999, 'amount1 before');
    assert(info.fees0 == 0, 'fees0 before');
    assert(info.fees1 == 0, 'fees1 before');

    setup.token0.increase_balance(setup.locker.contract_address, 20000);
    let delta_swap = swap(
        setup: setup,
        amount: i129 { mag: 100000, sign: true },
        is_token1: true,
        sqrt_ratio_limit: tick_to_sqrt_ratio(i129 { mag: 2, sign: true }),
        recipient: Zero::zero(),
        skip_ahead: 0,
    );

    assert(delta_swap.amount0 == i129 { mag: 10103, sign: false }, 'swap delta0');
    assert(delta_swap.amount1 == i129 { mag: 9999, sign: true }, 'swap delta1');

    info = positions.get_token_info(token_id, setup.pool_key, bounds);

    assert(info.liquidity == liquidity, 'liquidity after');
    assert(info.amount0 == 20000, 'amount0 after');
    assert(info.amount1 == 0, 'amount1 after');
    assert(info.fees0 == 101, 'fees0 after');
    assert(info.fees1 == 0, 'fees1 after');
}

#[test]
fn test_deposit_swap_round_trip_accounting() {
    let caller = contract_address_const::<1>();
    set_contract_address(caller);
    let mut d: Deployer = Default::default();
    let setup = d
        .setup_pool(
            fee: FEE_ONE_PERCENT,
            tick_spacing: 1,
            initial_tick: Zero::zero(),
            extension: Zero::zero(),
        );
    let positions = d.deploy_positions(setup.core);
    let bounds = Bounds { lower: i129 { mag: 1, sign: true }, upper: i129 { mag: 1, sign: false } };
    let token_id = positions.mint(pool_key: setup.pool_key, bounds: bounds);

    setup.token0.increase_balance(positions.contract_address, 10000);
    setup.token1.increase_balance(positions.contract_address, 10000);
    let liquidity = positions
        .deposit_last(pool_key: setup.pool_key, bounds: bounds, min_liquidity: 1);

    let mut info = positions.get_token_info(token_id, setup.pool_key, bounds);

    assert(info.liquidity == liquidity, 'liquidity before');
    assert(info.amount0 == 9999, 'amount0 before');
    assert(info.amount1 == 9999, 'amount1 before');
    assert(info.fees0 == 0, 'fees0 before');
    assert(info.fees1 == 0, 'fees1 before');

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

    info = positions.get_token_info(token_id, setup.pool_key, bounds);

    assert(info.liquidity == liquidity, 'liquidity after');
    assert(info.amount0 == 9999, 'amount0 after');
    assert(info.amount1 == 9999, 'amount1 after');
    assert(info.fees0 == 203, 'fees0 after');
    assert(info.fees1 == 203, 'fees1 after');

    let (amount0, amount1) = positions
        .withdraw(
            id: token_id,
            pool_key: setup.pool_key,
            bounds: bounds,
            liquidity: 0,
            min_token0: 0,
            min_token1: 0,
            collect_fees: true,
        );

    assert(amount0 == 203, 'amount0 withdrawn');
    assert(amount1 == 203, 'amount1 withdrawn');
    info = positions.get_token_info(token_id, setup.pool_key, bounds);
    assert(info.liquidity == liquidity, 'liquidity after');
    assert(info.amount0 == 9999, 'amount0 after');
    assert(info.amount1 == 9999, 'amount1 after');
    assert(info.fees0 == 0, 'fees0 withdrawn');
    assert(info.fees1 == 0, 'fees1 withdrawn');
}

#[derive(Copy, Drop)]
struct CreatePositionResult {
    id: u64,
    bounds: Bounds,
    liquidity: u128,
}

fn create_position(
    setup: SetupPoolResult,
    positions: IPositionsDispatcher,
    bounds: Bounds,
    amount0: u128,
    amount1: u128,
) -> CreatePositionResult {
    let token_id = positions.mint(pool_key: setup.pool_key, bounds: bounds);
    setup.token0.set_balance(positions.contract_address, amount0.into());
    setup.token1.set_balance(positions.contract_address, amount1.into());

    let liquidity = positions
        .deposit(id: token_id, pool_key: setup.pool_key, bounds: bounds, min_liquidity: 1);

    CreatePositionResult { id: token_id, bounds, liquidity }
}


#[test]
fn test_deposit_existing_position() {
    let mut d: Deployer = Default::default();
    let setup = d
        .setup_pool(
            fee: FEE_ONE_PERCENT,
            tick_spacing: 1,
            initial_tick: Zero::zero(),
            extension: Zero::zero(),
        );
    let positions = d.deploy_positions(setup.core);

    let caller = contract_address_const::<1>();
    set_contract_address(caller);

    let p0 = create_position(
        setup,
        positions,
        Bounds { lower: i129 { mag: 10, sign: true }, upper: i129 { mag: 10, sign: false } },
        10000,
        10000,
    );

    setup.token0.set_balance(positions.contract_address, 15000);
    setup.token1.set_balance(positions.contract_address, 30000);
    positions.deposit(id: p0.id, pool_key: setup.pool_key, bounds: p0.bounds, min_liquidity: 1);

    let info = positions.get_token_info(p0.id, setup.pool_key, p0.bounds);

    assert(info.liquidity == 5000015000, 'liquidity');
    assert(info.amount0 == 24999, 'amount0');
    assert(info.amount1 == 24999, 'amount1');
    assert(info.fees0.is_zero(), 'fees0');
    assert(info.fees1.is_zero(), 'fees1');

    setup.token1.increase_balance(setup.locker.contract_address, 300000);
    swap(
        setup: setup,
        amount: i129 { mag: 100000, sign: false },
        is_token1: true,
        sqrt_ratio_limit: tick_to_sqrt_ratio(i129 { mag: 2, sign: false }),
        recipient: Zero::zero(),
        skip_ahead: 0,
    );

    let info = positions.get_token_info(p0.id, setup.pool_key, p0.bounds);

    assert(info.liquidity == 5000015000, 'liquidity');
    assert(info.amount0 == 19999, 'amount0');
    assert(info.amount1 == 30000, 'amount1');
    assert(info.fees0.is_zero(), 'fees0');
    assert(info.fees1 == 50, 'fees1');

    setup.token0.set_balance(positions.contract_address, 15000);
    setup.token1.set_balance(positions.contract_address, 15000);
    positions.deposit(id: p0.id, pool_key: setup.pool_key, bounds: p0.bounds, min_liquidity: 1);

    let info = positions.get_token_info(p0.id, setup.pool_key, p0.bounds);

    assert(info.liquidity == 7500021250, 'liquidity');
    assert(info.amount0 == 29999, 'amount0');
    assert(info.amount1 == 45000, 'amount1');
    assert(info.fees0.is_zero(), 'fees0');
    assert(info.fees1 == 49, 'fees1');
}

#[test]
fn test_deposit_swap_multiple_positions() {
    let caller = contract_address_const::<1>();
    set_contract_address(caller);
    let mut d: Deployer = Default::default();
    let setup = d
        .setup_pool(
            fee: FEE_ONE_PERCENT,
            tick_spacing: 1,
            initial_tick: Zero::zero(),
            extension: Zero::zero(),
        );
    let positions = d.deploy_positions(setup.core);
    let p0 = create_position(
        setup,
        positions,
        Bounds { lower: i129 { mag: 1, sign: true }, upper: i129 { mag: 1, sign: false } },
        10000,
        10000,
    );
    let p1 = create_position(
        setup,
        positions,
        Bounds { lower: i129 { mag: 0, sign: false }, upper: i129 { mag: 1, sign: false } },
        10000,
        0,
    );
    let p2 = create_position(
        setup,
        positions,
        Bounds { lower: i129 { mag: 1, sign: true }, upper: i129 { mag: 0, sign: false } },
        0,
        10000,
    );

    setup.token0.increase_balance(setup.locker.contract_address, 300000);
    setup.token1.increase_balance(setup.locker.contract_address, 300000);
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

    let p0_info = positions.get_token_info(p0.id, setup.pool_key, p0.bounds);
    let p1_info = positions.get_token_info(p1.id, setup.pool_key, p1.bounds);
    let p2_info = positions.get_token_info(p2.id, setup.pool_key, p2.bounds);

    assert(p0_info.liquidity == p0.liquidity, 'p0 liquidity');
    assert(p0_info.amount0 == 9999, 'p0 amount0');
    assert(p0_info.amount1 == 9999, 'p0 amount1');
    assert(p0_info.fees0 == 202, 'p0 fees0');
    assert(p0_info.fees1 == 202, 'p0 fees1');

    assert(p1_info.liquidity == p1.liquidity, 'p1 liquidity');
    assert(p1_info.amount0 == 9999, 'p1 amount0');
    assert(p1_info.amount1 == 0, 'p1 amount1');
    assert(p1_info.fees0 == 101, 'p1 fees0');
    assert(p1_info.fees1 == 101, 'p1 fees1');

    assert(p2_info.liquidity == p2.liquidity, 'p2 liquidity');
    assert(p2_info.amount0 == 0, 'p2 amount0');
    assert(p2_info.amount1 == 9999, 'p2 amount1');
    assert(p2_info.fees0 == 101, 'p2 fees0');
    assert(p2_info.fees1 == 101, 'p2 fees1');
}


#[test]
fn test_create_position_in_range_after_swap_no_fees() {
    let mut d: Deployer = Default::default();
    let setup = d
        .setup_pool(
            fee: FEE_ONE_PERCENT,
            tick_spacing: 1,
            initial_tick: Zero::zero(),
            extension: Zero::zero(),
        );
    let positions = d.deploy_positions(setup.core);

    let caller = contract_address_const::<1>();
    set_contract_address(caller);

    let p0 = create_position(
        setup,
        positions,
        Bounds { lower: i129 { mag: 10, sign: true }, upper: i129 { mag: 10, sign: false } },
        10000,
        10000,
    );

    setup.token0.increase_balance(setup.locker.contract_address, 300000);
    setup.token1.increase_balance(setup.locker.contract_address, 300000);
    swap(
        setup: setup,
        amount: i129 { mag: 100000, sign: false },
        is_token1: true,
        sqrt_ratio_limit: tick_to_sqrt_ratio(i129 { mag: 5, sign: false }),
        recipient: Zero::zero(),
        skip_ahead: 0,
    );
    swap(
        setup: setup,
        amount: i129 { mag: 100000, sign: false },
        is_token1: false,
        sqrt_ratio_limit: 0x100000000000000000000000000000000_u256,
        recipient: Zero::zero(),
        skip_ahead: 0,
    );

    let p1 = create_position(
        setup,
        positions,
        Bounds { lower: i129 { mag: 10, sign: true }, upper: i129 { mag: 10, sign: false } },
        5000,
        5000,
    );
    let p2 = create_position(
        setup,
        positions,
        Bounds { lower: i129 { mag: 10, sign: true }, upper: i129 { mag: 0, sign: false } },
        0,
        5000,
    );
    let p3 = create_position(
        setup,
        positions,
        Bounds { lower: i129 { mag: 0, sign: false }, upper: i129 { mag: 10, sign: false } },
        5000,
        0,
    );

    let p0_info = positions.get_token_info(p0.id, setup.pool_key, p0.bounds);
    let p1_info = positions.get_token_info(p1.id, setup.pool_key, p1.bounds);
    let p2_info = positions.get_token_info(p2.id, setup.pool_key, p2.bounds);
    let p3_info = positions.get_token_info(p3.id, setup.pool_key, p3.bounds);

    let mut all_info = positions
        .get_tokens_info(
            array![
                GetTokenInfoRequest { id: p0.id, pool_key: setup.pool_key, bounds: p0.bounds },
                GetTokenInfoRequest { id: p1.id, pool_key: setup.pool_key, bounds: p1.bounds },
                GetTokenInfoRequest { id: p2.id, pool_key: setup.pool_key, bounds: p2.bounds },
                GetTokenInfoRequest { id: p3.id, pool_key: setup.pool_key, bounds: p3.bounds },
            ]
                .span(),
        );
    assert(all_info.pop_front().unwrap() == @p0_info, 'p0_info');
    assert(all_info.pop_front().unwrap() == @p1_info, 'p1_info');
    assert(all_info.pop_front().unwrap() == @p2_info, 'p2_info');
    assert(all_info.pop_front().unwrap() == @p3_info, 'p3_info');
    assert(all_info.pop_front().is_none(), 'no others');

    assert(p0_info.liquidity == p0.liquidity, 'p0 liquidity');
    assert(p0_info.amount0 == 9999, 'p0 amount0');
    assert(p0_info.amount1 == 9999, 'p0 amount1');
    assert(p0_info.fees0 == 50, 'p0 fees0');
    assert(p0_info.fees1 == 50, 'p0 fees1');

    assert(p1_info.liquidity == p1.liquidity, 'p1 liquidity');
    assert(p1_info.amount0 == 4999, 'p1 amount0');
    assert(p1_info.amount1 == 4999, 'p1 amount1');
    assert(p1_info.fees0.is_zero(), 'p1 fees0');
    assert(p1_info.fees1.is_zero(), 'p1 fees1');

    assert(p2_info.liquidity == p1.liquidity, 'p2 liquidity');
    assert(p2_info.amount0 == 0, 'p2 amount0');
    assert(p2_info.amount1 == 4999, 'p2 amount1');
    assert(p2_info.fees0.is_zero(), 'p2 fees0');
    assert(p2_info.fees1.is_zero(), 'p2 fees1');

    assert(p3_info.liquidity == p1.liquidity, 'p3 liquidity');
    assert(p3_info.amount0 == 4999, 'p3 amount0');
    assert(p3_info.amount1 == 0, 'p3 amount1');
    assert(p3_info.fees0.is_zero(), 'p3 fees0');
    assert(p3_info.fees1.is_zero(), 'p3 fees1');
}

#[test]
#[should_panic(
    expected: (
        'MUST_COLLECT_FEES',
        'ENTRYPOINT_FAILED',
        'ENTRYPOINT_FAILED',
        'ENTRYPOINT_FAILED',
        'ENTRYPOINT_FAILED',
    ),
)]
fn test_withdraw_not_collected_fees_token1() {
    let caller = contract_address_const::<1>();
    set_contract_address(caller);
    let mut d: Deployer = Default::default();
    let setup = d
        .setup_pool(
            fee: FEE_ONE_PERCENT,
            tick_spacing: 1,
            initial_tick: Zero::zero(),
            extension: Zero::zero(),
        );
    let positions = d.deploy_positions(setup.core);
    let p0 = create_position(
        setup,
        positions,
        Bounds { lower: i129 { mag: 1, sign: true }, upper: i129 { mag: 1, sign: false } },
        10000,
        10000,
    );

    setup.token0.increase_balance(setup.locker.contract_address, 300000);
    setup.token1.increase_balance(setup.locker.contract_address, 300000);
    swap(
        setup: setup,
        amount: i129 { mag: 100000, sign: false },
        is_token1: true,
        sqrt_ratio_limit: tick_to_sqrt_ratio(i129 { mag: 2, sign: false }),
        recipient: Zero::zero(),
        skip_ahead: 0,
    );

    positions
        .withdraw_v2(
            id: p0.id,
            pool_key: setup.pool_key,
            bounds: p0.bounds,
            liquidity: (p0.liquidity),
            min_token0: 0,
            min_token1: 0,
        );
}

#[test]
#[should_panic(
    expected: (
        'MUST_COLLECT_FEES',
        'ENTRYPOINT_FAILED',
        'ENTRYPOINT_FAILED',
        'ENTRYPOINT_FAILED',
        'ENTRYPOINT_FAILED',
    ),
)]
fn test_withdraw_not_collected_fees_token0() {
    let caller = contract_address_const::<1>();
    set_contract_address(caller);
    let mut d: Deployer = Default::default();
    let setup = d
        .setup_pool(
            fee: FEE_ONE_PERCENT,
            tick_spacing: 1,
            initial_tick: Zero::zero(),
            extension: Zero::zero(),
        );
    let positions = d.deploy_positions(setup.core);
    let p0 = create_position(
        setup,
        positions,
        Bounds { lower: i129 { mag: 1, sign: true }, upper: i129 { mag: 1, sign: false } },
        10000,
        10000,
    );

    setup.token0.increase_balance(setup.locker.contract_address, 300000);
    setup.token1.increase_balance(setup.locker.contract_address, 300000);
    swap(
        setup: setup,
        amount: i129 { mag: 100000, sign: false },
        is_token1: false,
        sqrt_ratio_limit: tick_to_sqrt_ratio(i129 { mag: 2, sign: true }),
        recipient: Zero::zero(),
        skip_ahead: 0,
    );

    positions
        .withdraw_v2(
            id: p0.id,
            pool_key: setup.pool_key,
            bounds: p0.bounds,
            liquidity: (p0.liquidity),
            min_token0: 0,
            min_token1: 0,
        );
}


#[test]
fn test_withdraw_partial_leave_fees() {
    let caller = contract_address_const::<1>();
    set_contract_address(caller);
    let mut d: Deployer = Default::default();
    let setup = d
        .setup_pool(
            fee: FEE_ONE_PERCENT,
            tick_spacing: 1,
            initial_tick: Zero::zero(),
            extension: Zero::zero(),
        );
    let mut d: Deployer = Default::default();
    let positions = d.deploy_positions(setup.core);
    let p0 = create_position(
        setup,
        positions,
        Bounds { lower: i129 { mag: 1, sign: true }, upper: i129 { mag: 1, sign: false } },
        10000,
        10000,
    );

    setup.token0.increase_balance(setup.locker.contract_address, 300000);
    setup.token1.increase_balance(setup.locker.contract_address, 300000);
    swap(
        setup: setup,
        amount: i129 { mag: 100000, sign: false },
        is_token1: false,
        sqrt_ratio_limit: tick_to_sqrt_ratio(i129 { mag: 2, sign: true }),
        recipient: Zero::zero(),
        skip_ahead: 0,
    );

    positions
        .withdraw_v2(
            id: p0.id,
            pool_key: setup.pool_key,
            bounds: p0.bounds,
            liquidity: (p0.liquidity / 3),
            min_token0: 0,
            min_token1: 0,
        );

    let info = positions.get_token_info(p0.id, setup.pool_key, p0.bounds);
    assert(info.liquidity == (p0.liquidity - (p0.liquidity / 3)), 'liquidity');
    assert(info.amount0 == 13333, 'amount0'); // 2/3 of 20k
    assert(info.amount1 == 0, 'amount1');
    assert(info.fees0 == 100, 'fees0'); // 1% of 10k
    assert(info.fees1 == 0, 'fees1');
}

#[test]
fn test_failure_case_integration_tests_amount_cannot_be_met_due_to_overflow() {
    let caller = contract_address_const::<1>();
    set_contract_address(caller);
    let mut d: Deployer = Default::default();
    let setup = d
        .setup_pool(
            // 30 bips
            fee: 1020847100762815390390123822295304634,
            tick_spacing: 5982,
            initial_tick: Zero::zero(),
            extension: Zero::zero(),
        );
    let positions = d.deploy_positions(setup.core);

    let ONE_E18 = 1000000000000000000;
    let p0 = create_position(setup, positions, max_bounds(5982), ONE_E18, ONE_E18);

    assert(p0.liquidity == ONE_E18, 'liquidity');
    setup.token1.increase_balance(setup.locker.contract_address, ONE_E18 * 2);
    swap(
        setup: setup,
        amount: i129 { mag: ONE_E18, sign: true },
        is_token1: false,
        sqrt_ratio_limit: u256 { high: 2, low: 0 },
        recipient: Zero::zero(),
        skip_ahead: 0,
    );

    positions
        .withdraw(
            id: p0.id,
            pool_key: setup.pool_key,
            bounds: p0.bounds,
            liquidity: p0.liquidity,
            min_token0: 0,
            min_token1: 0,
            collect_fees: true,
        );
}

#[test]
fn test_get_pool_price_normal_pool() {
    let mut d: Deployer = Default::default();
    let setup = d
        .setup_pool(
            fee: FEE_ONE_PERCENT,
            tick_spacing: 1,
            initial_tick: Zero::zero(),
            extension: Zero::zero(),
        );
    let positions = d.deploy_positions(setup.core);
    let price = positions.get_pool_price(setup.pool_key);
    assert_eq!(price.sqrt_ratio, u256 { high: 1, low: 0 });
}

#[test]
fn test_get_pool_price_uninitialized_pool() {
    let mut d: Deployer = Default::default();
    let core = d.deploy_core();
    let positions = d.deploy_positions(core);
    let price = positions
        .get_pool_price(
            PoolKey {
                token0: contract_address_const::<1234>(),
                token1: contract_address_const::<2345>(),
                fee: 1234,
                tick_spacing: 2345,
                extension: Zero::zero(),
            },
        );
    assert_eq!(price.sqrt_ratio, Zero::zero());
}

#[test]
#[should_panic(expected: ('LIQUIDITY_IS_NON_ZERO', 'ENTRYPOINT_FAILED'))]
fn test_check_liquidity_is_zero() {
    let mut d: Deployer = Default::default();
    let setup = d
        .setup_pool(
            fee: FEE_ONE_PERCENT,
            tick_spacing: 1,
            initial_tick: Zero::zero(),
            extension: Zero::zero(),
        );
    let positions = d.deploy_positions(setup.core);
    let bounds = Bounds {
        lower: i129 { mag: 10, sign: true }, upper: i129 { mag: 10, sign: false },
    };
    let p0 = create_position(
        setup: setup, positions: positions, bounds: bounds, amount0: 1000, amount1: 1000,
    );
    positions.check_liquidity_is_zero(id: p0.id, pool_key: setup.pool_key, bounds: bounds);
}

#[test]
fn test_check_liquidity_is_zero_succeeds() {
    let mut d: Deployer = Default::default();
    let setup = d
        .setup_pool(
            fee: FEE_ONE_PERCENT,
            tick_spacing: 1,
            initial_tick: Zero::zero(),
            extension: Zero::zero(),
        );
    let positions = d.deploy_positions(setup.core);
    let bounds = Bounds {
        lower: i129 { mag: 10, sign: true }, upper: i129 { mag: 10, sign: false },
    };
    let id = positions.mint_v2(Zero::zero());
    positions.check_liquidity_is_zero(id: id, pool_key: setup.pool_key, bounds: bounds);
}
