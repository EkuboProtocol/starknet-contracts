use starknet::{contract_address_const, get_contract_address};
use starknet::testing::{set_contract_address};
use ekubo::tests::mocks::mock_erc20::{IMockERC20Dispatcher, IMockERC20DispatcherTrait};
use ekubo::interfaces::core::{
    ICoreDispatcher, ICoreDispatcherTrait, ILockerDispatcher, ILockerDispatcherTrait
};
use ekubo::interfaces::erc721::{IERC721Dispatcher, IERC721DispatcherTrait};
use ekubo::interfaces::positions::{IPositionsDispatcher, IPositionsDispatcherTrait, Bounds};
use ekubo::types::keys::{PoolKey};
use ekubo::math::ticks::{constants as tick_constants};
use ekubo::types::i129::{i129};
use ekubo::math::ticks::{min_sqrt_ratio, max_sqrt_ratio};
use zeroable::Zeroable;

use ekubo::tests::helper::{
    deploy_core, setup_pool, deploy_positions, FEE_ONE_PERCENT, swap,
    IPositionsDispatcherIntoIERC721Dispatcher, IPositionsDispatcherIntoILockerDispatcher
};

use debug::PrintTrait;

#[test]
#[available_gas(300000000)]
fn test_maybe_initialize_pool_twice() {
    let core = deploy_core();
    let positions = deploy_positions(core);
    let pool_key = PoolKey {
        token0: contract_address_const::<1>(),
        token1: contract_address_const::<2>(),
        fee: Zeroable::zero(),
        tick_spacing: 1,
        extension: Zeroable::zero(),
    };
    positions.maybe_initialize_pool(pool_key, Zeroable::zero());
    positions.maybe_initialize_pool(pool_key, i129 { mag: 1000, sign: false });

    assert(core.get_pool(pool_key).sqrt_ratio == u256 { low: 0, high: 1 }, 'ratio');
}

#[test]
#[available_gas(300000000)]
fn test_nft_name_symbol() {
    let core = deploy_core();
    let positions = IPositionsDispatcherIntoIERC721Dispatcher::into(deploy_positions(core));
    assert(positions.name() == 'Ekubo Position NFT', 'name');
    assert(positions.symbol() == 'EpNFT', 'symbol');
    assert(positions.token_uri(u256 { low: 1, high: 0 }) == 'https://nft.ekubo.org/1', 'token_uri');
}

#[test]
#[available_gas(300000000)]
#[should_panic(expected: ('OWNER', 'ENTRYPOINT_FAILED', ))]
fn test_nft_approve_fails_id_not_exists() {
    let core = deploy_core();
    let positions = IPositionsDispatcherIntoIERC721Dispatcher::into(deploy_positions(core));
    set_contract_address(contract_address_const::<1>());
    positions.approve(contract_address_const::<2>(), 1);
}

#[test]
#[available_gas(300000000)]
fn test_nft_approve_succeeds_after_mint() {
    let core = deploy_core();
    let positions = deploy_positions(core);
    set_contract_address(contract_address_const::<1>());

    let token_id = positions
        .mint(
            contract_address_const::<1>(),
            pool_key: PoolKey {
                token0: Zeroable::zero(),
                token1: Zeroable::zero(),
                fee: Zeroable::zero(),
                tick_spacing: Zeroable::zero(),
                extension: Zeroable::zero(),
            },
            bounds: Bounds { tick_lower: Zeroable::zero(), tick_upper: Zeroable::zero(),  }
        );

    IPositionsDispatcherIntoIERC721Dispatcher::into(positions)
        .approve(contract_address_const::<2>(), token_id);
    assert(
        IPositionsDispatcherIntoIERC721Dispatcher::into(positions)
            .get_approved(token_id) == contract_address_const::<2>(),
        'approved'
    );
}

#[test]
#[available_gas(300000000)]
fn test_nft_token_uri() {
    let core = deploy_core();
    let positions = IPositionsDispatcherIntoIERC721Dispatcher::into(deploy_positions(core));

    assert(positions.token_uri(u256 { low: 1, high: 0 }) == 'https://nft.ekubo.org/1', 'token_uri');
    assert(
        positions.token_uri(u256 { low: 9999999, high: 0 }) == 'https://nft.ekubo.org/9999999',
        'token_uri'
    );
    assert(
        positions.token_uri(u256 { low: 239020510, high: 0 }) == 'https://nft.ekubo.org/239020510',
        'token_uri'
    );
    assert(
        positions.token_uri(u256 { low: 999999999, high: 0 }) == 'https://nft.ekubo.org/999999999',
        'max token_uri'
    );
}

#[test]
#[available_gas(300000000)]
#[should_panic(expected: ('URI_LENGTH', 'ENTRYPOINT_FAILED'))]
fn test_nft_token_uri_reverts_too_long() {
    let core = deploy_core();
    let positions = IPositionsDispatcherIntoIERC721Dispatcher::into(deploy_positions(core));

    positions.token_uri(u256 { low: 9999999999, high: 0 });
}

#[test]
#[available_gas(300000000)]
#[should_panic(expected: ('TOKEN_ID', 'ENTRYPOINT_FAILED'))]
fn test_nft_token_uri_reverts_token_id_too_big() {
    let core = deploy_core();
    let positions = IPositionsDispatcherIntoIERC721Dispatcher::into(deploy_positions(core));

    positions.token_uri(u256 { low: 10000000000000000000000000000000, high: 0 });
}

#[test]
#[available_gas(300000000)]
#[should_panic(expected: ('OWNER', 'ENTRYPOINT_FAILED', ))]
fn test_nft_approve_only_owner_can_approve() {
    let core = deploy_core();
    let positions = deploy_positions(core);

    let token_id = positions
        .mint(
            contract_address_const::<1>(),
            pool_key: PoolKey {
                token0: Zeroable::zero(),
                token1: Zeroable::zero(),
                fee: Zeroable::zero(),
                tick_spacing: Zeroable::zero(),
                extension: Zeroable::zero(),
            },
            bounds: Bounds { tick_lower: Zeroable::zero(), tick_upper: Zeroable::zero(),  }
        );

    set_contract_address(contract_address_const::<2>());
    IPositionsDispatcherIntoIERC721Dispatcher::into(positions)
        .approve(contract_address_const::<2>(), token_id);
}

#[test]
#[available_gas(300000000)]
fn test_nft_balance_of() {
    let core = deploy_core();
    let positions = deploy_positions(core);

    let recipient = contract_address_const::<2>();
    assert(
        IPositionsDispatcherIntoIERC721Dispatcher::into(positions)
            .balance_of(recipient) == Zeroable::zero(),
        'balance check'
    );
    // note we do not check the validity of the position key, it only comes into play when trying to add liquidity fails
    assert(
        positions
            .mint(
                recipient,
                pool_key: PoolKey {
                    token0: Zeroable::zero(),
                    token1: Zeroable::zero(),
                    fee: Zeroable::zero(),
                    tick_spacing: Zeroable::zero(),
                    extension: Zeroable::zero(),
                },
                bounds: Bounds { tick_lower: Zeroable::zero(), tick_upper: Zeroable::zero(),  }
            ) == 1,
        'token id'
    );
    assert(
        IPositionsDispatcherIntoIERC721Dispatcher::into(positions).owner_of(1) == recipient, 'owner'
    );
    assert(
        IPositionsDispatcherIntoIERC721Dispatcher::into(positions).balance_of(recipient) == u256 {
            low: 1, high: 0
        },
        'balance check after'
    );
}

#[test]
#[available_gas(20000000)]
fn test_deposit_liquidity_full_range() {
    let setup = setup_pool(
        fee: FEE_ONE_PERCENT,
        tick_spacing: 1,
        initial_tick: Zeroable::zero(),
        extension: Zeroable::zero(),
    );
    let positions = deploy_positions(setup.core);
    let token_id = positions
        .mint(
            recipient: get_contract_address(), pool_key: setup.pool_key, bounds: Default::default()
        );
    assert(token_id == 1, 'token id');
    setup.token0.increase_balance(positions.contract_address, 100000000);
    setup.token1.increase_balance(positions.contract_address, 100000000);
    let liquidity = positions
        .deposit_last(pool_key: setup.pool_key, bounds: Default::default(), min_liquidity: 100);

    assert(liquidity == 100000000, 'liquidity');
}

#[test]
#[available_gas(20000000)]
fn test_deposit_liquidity_concentrated() {
    let caller = contract_address_const::<1>();
    set_contract_address(caller);
    let setup = setup_pool(
        fee: FEE_ONE_PERCENT,
        tick_spacing: 1,
        initial_tick: Zeroable::zero(),
        extension: Zeroable::zero(),
    );
    let positions = deploy_positions(setup.core);
    let bounds = Bounds {
        tick_lower: i129 { mag: 1000, sign: true }, tick_upper: i129 { mag: 1000, sign: false }, 
    };
    let token_id = positions.mint(caller, pool_key: setup.pool_key, bounds: bounds);
    assert(token_id == 1, 'token id');
    setup.token0.increase_balance(positions.contract_address, 100000000);
    setup.token1.increase_balance(positions.contract_address, 100000000);
    let liquidity = positions
        .deposit_last(pool_key: setup.pool_key, bounds: bounds, min_liquidity: 100);

    let balance0 = positions.clear(setup.token0.contract_address, contract_address_const::<2>());
    let balance1 = positions.clear(setup.token1.contract_address, contract_address_const::<2>());

    assert(
        setup.token0.balance_of(contract_address_const::<2>()) == Zeroable::zero(),
        'balance0 transfer'
    );
    assert(
        setup.token1.balance_of(contract_address_const::<2>()) == Zeroable::zero(),
        'balance1 transfer'
    );

    assert(balance0 == Zeroable::zero(), 'balance0');
    assert(balance1 == Zeroable::zero(), 'balance1');

    assert(liquidity == 200050104166, 'liquidity');
}

#[test]
#[available_gas(20000000)]
fn test_deposit_liquidity_concentrated_unbalanced_in_range_price_higher() {
    let caller = contract_address_const::<1>();
    set_contract_address(caller);
    let setup = setup_pool(
        fee: FEE_ONE_PERCENT,
        tick_spacing: 1,
        initial_tick: i129 { mag: 500, sign: false },
        extension: Zeroable::zero(),
    );
    let positions = deploy_positions(setup.core);
    let bounds = Bounds {
        tick_lower: i129 { mag: 1000, sign: true }, tick_upper: i129 { mag: 1000, sign: false }, 
    };
    let token_id = positions.mint(caller, pool_key: setup.pool_key, bounds: bounds);
    assert(token_id == 1, 'token id');
    setup.token0.increase_balance(positions.contract_address, 100000000);
    setup.token1.increase_balance(positions.contract_address, 100000000);
    let liquidity = positions
        .deposit_last(pool_key: setup.pool_key, bounds: bounds, min_liquidity: 100);

    let balance0 = positions.clear(setup.token0.contract_address, contract_address_const::<2>());
    let balance1 = positions.clear(setup.token1.contract_address, contract_address_const::<2>());

    assert(
        setup.token0.balance_of(contract_address_const::<2>()) == u256 { low: 66674999, high: 0 },
        'balance0 transfer'
    );
    assert(
        setup.token1.balance_of(contract_address_const::<2>()) == Zeroable::zero(),
        'balance1 transfer'
    );

    assert(balance0 == u256 { low: 66674999, high: 0 }, 'balance0');
    assert(balance1 == Zeroable::zero(), 'balance1');
    assert(liquidity == 133350064582, 'liquidity');
}

#[test]
#[available_gas(20000000)]
fn test_deposit_liquidity_concentrated_unbalanced_in_range_price_lower() {
    let caller = contract_address_const::<1>();
    set_contract_address(caller);
    let setup = setup_pool(
        fee: FEE_ONE_PERCENT,
        tick_spacing: 1,
        initial_tick: i129 { mag: 500, sign: true },
        extension: Zeroable::zero(),
    );
    let positions = deploy_positions(setup.core);
    let bounds = Bounds {
        tick_lower: i129 { mag: 1000, sign: true }, tick_upper: i129 { mag: 1000, sign: false }, 
    };
    let token_id = positions.mint(caller, pool_key: setup.pool_key, bounds: bounds);
    assert(token_id == 1, 'token id');
    setup.token0.increase_balance(positions.contract_address, 100000000);
    setup.token1.increase_balance(positions.contract_address, 100000000);
    let liquidity = positions
        .deposit_last(pool_key: setup.pool_key, bounds: bounds, min_liquidity: 100);

    let balance0 = positions.clear(setup.token0.contract_address, contract_address_const::<2>());
    let balance1 = positions.clear(setup.token1.contract_address, contract_address_const::<2>());

    assert(
        setup.token0.balance_of(contract_address_const::<2>()) == Zeroable::zero(),
        'balance0 transfer'
    );
    assert(
        setup.token1.balance_of(contract_address_const::<2>()) == u256 { low: 66674999, high: 0 },
        'balance1 transfer'
    );

    assert(balance0 == Zeroable::zero(), 'balance0');
    assert(balance1 == u256 { low: 66674999, high: 0 }, 'balance1');
    assert(liquidity == 133350064582, 'liquidity');
}

#[test]
#[available_gas(20000000)]
fn test_deposit_liquidity_concentrated_out_of_range_price_upper() {
    let caller = contract_address_const::<1>();
    set_contract_address(caller);
    let setup = setup_pool(
        fee: FEE_ONE_PERCENT,
        tick_spacing: 1,
        initial_tick: i129 { mag: 1000, sign: false },
        extension: Zeroable::zero(),
    );
    let positions = deploy_positions(setup.core);
    let bounds = Bounds {
        tick_lower: i129 { mag: 1000, sign: true }, tick_upper: i129 { mag: 1000, sign: false }, 
    };
    let token_id = positions.mint(caller, pool_key: setup.pool_key, bounds: bounds);
    assert(token_id == 1, 'token id');
    setup.token0.increase_balance(positions.contract_address, 100000000);
    setup.token1.increase_balance(positions.contract_address, 100000000);
    let liquidity = positions
        .deposit_last(pool_key: setup.pool_key, bounds: bounds, min_liquidity: 100);

    let balance0 = positions.clear(setup.token0.contract_address, contract_address_const::<2>());
    let balance1 = positions.clear(setup.token1.contract_address, contract_address_const::<2>());

    assert(
        setup.token0.balance_of(contract_address_const::<2>()) == u256 { low: 100000000, high: 0 },
        'balance0 transfer'
    );
    assert(
        setup.token1.balance_of(contract_address_const::<2>()) == Zeroable::zero(),
        'balance1 transfer'
    );

    assert(balance0 == u256 { low: 100000000, high: 0 }, 'balance0');
    assert(balance1 == Zeroable::zero(), 'balance1');
    assert(liquidity == 100000045833, 'liquidity');
}

#[test]
#[available_gas(20000000)]
fn test_deposit_liquidity_concentrated_out_of_range_price_lower() {
    let caller = contract_address_const::<1>();
    set_contract_address(caller);
    let setup = setup_pool(
        fee: FEE_ONE_PERCENT,
        tick_spacing: 1,
        initial_tick: i129 { mag: 1000, sign: true },
        extension: Zeroable::zero(),
    );
    let positions = deploy_positions(setup.core);
    let bounds = Bounds {
        tick_lower: i129 { mag: 1000, sign: true }, tick_upper: i129 { mag: 1000, sign: false }, 
    };
    let token_id = positions.mint(caller, pool_key: setup.pool_key, bounds: bounds);
    assert(token_id == 1, 'token id');
    setup.token0.increase_balance(positions.contract_address, 100000000);
    setup.token1.increase_balance(positions.contract_address, 100000000);
    let liquidity = positions
        .deposit_last(pool_key: setup.pool_key, bounds: bounds, min_liquidity: 100);

    let balance0 = positions.clear(setup.token0.contract_address, contract_address_const::<2>());
    let balance1 = positions.clear(setup.token1.contract_address, contract_address_const::<2>());

    assert(
        setup.token0.balance_of(contract_address_const::<2>()) == Zeroable::zero(),
        'balance0 transfer'
    );
    assert(
        setup.token1.balance_of(contract_address_const::<2>()) == u256 { low: 100000000, high: 0 },
        'balance1 transfer'
    );

    assert(balance0 == Zeroable::zero(), 'balance0');
    assert(balance1 == u256 { low: 100000000, high: 0 }, 'balance1');
    assert(liquidity == 100000045833, 'liquidity');
}

#[test]
#[available_gas(80000000)]
fn test_deposit_then_withdraw_with_fees() {
    let caller = contract_address_const::<1>();
    set_contract_address(caller);
    let setup = setup_pool(
        fee: FEE_ONE_PERCENT,
        tick_spacing: 1,
        initial_tick: Zeroable::zero(),
        extension: Zeroable::zero(),
    );
    let positions = deploy_positions(setup.core);
    let bounds = Bounds {
        tick_lower: i129 { mag: 1000, sign: true }, tick_upper: i129 { mag: 1000, sign: false }, 
    };
    let token_id = positions.mint(caller, pool_key: setup.pool_key, bounds: bounds);

    setup.token0.increase_balance(positions.contract_address, 100000000);
    setup.token1.increase_balance(positions.contract_address, 100000000);
    positions.deposit_last(pool_key: setup.pool_key, bounds: bounds, min_liquidity: 100);

    setup.token0.increase_balance(setup.locker.contract_address, 100000000000);
    setup.token1.increase_balance(setup.locker.contract_address, 100000000000);
    let delta_first_swap = swap(
        setup: setup,
        amount: i129 { mag: 1000, sign: false },
        is_token1: true,
        sqrt_ratio_limit: max_sqrt_ratio(),
        recipient: Zeroable::zero(),
        skip_ahead: 0
    );
    let delta_second_swap = swap(
        setup: setup,
        amount: i129 { mag: 2000, sign: false },
        is_token1: false,
        sqrt_ratio_limit: min_sqrt_ratio(),
        recipient: Zeroable::zero(),
        skip_ahead: 0
    );

    let get_position_result = positions.get_position_info(token_id, setup.pool_key, bounds);

    assert(get_position_result.fees0 == 20, 'fees0');
    assert(get_position_result.fees1 == 9, 'fees1');
}

#[test]
#[available_gas(80000000)]
fn test_deposit_then_partial_withdraw_with_fees() {
    let caller = contract_address_const::<1>();
    set_contract_address(caller);
    let setup = setup_pool(
        fee: FEE_ONE_PERCENT,
        tick_spacing: 1,
        initial_tick: Zeroable::zero(),
        extension: Zeroable::zero(),
    );
    let positions = deploy_positions(setup.core);
    let bounds = Bounds {
        tick_lower: i129 { mag: 1000, sign: true }, tick_upper: i129 { mag: 1000, sign: false }, 
    };
    let token_id = positions.mint(caller, pool_key: setup.pool_key, bounds: bounds);

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
        recipient: Zeroable::zero(),
        skip_ahead: 0
    );
    swap(
        setup: setup,
        amount: i129 { mag: 2000, sign: false },
        is_token1: false,
        sqrt_ratio_limit: min_sqrt_ratio(),
        recipient: Zeroable::zero(),
        skip_ahead: 0
    );

    let (amount0, amount1) = positions
        .withdraw(
            token_id: token_id,
            pool_key: setup.pool_key,
            bounds: bounds,
            liquidity: (liquidity / 2),
            min_token0: 1000,
            min_token1: 1000,
            collect_fees: false,
        );

    assert(amount0 == 49500494, 'amount0 less 1%');
    assert(amount1 == 49499505, 'amount1 less 1%');

    // fees are not withdrawn with the principal
    let get_position_result = positions.get_position_info(token_id, setup.pool_key, bounds);

    assert(get_position_result.fees0 == 19, 'fees0');
    assert(get_position_result.fees1 == 8, 'fees1');

    // withdraw fees only
    let (amount0, amount1) = positions
        .withdraw(
            token_id: token_id,
            pool_key: setup.pool_key,
            bounds: bounds,
            liquidity: 0,
            min_token0: 0,
            min_token1: 0,
            collect_fees: true,
        );

    assert(amount0 == 19, 'fees0 withdrawn');
    assert(amount1 == 8, 'fees1 withdrawn');

    // withdraw quarter
    let (amount0, amount1) = positions
        .withdraw(
            token_id: token_id,
            pool_key: setup.pool_key,
            bounds: bounds,
            liquidity: (liquidity / 4),
            min_token0: 0,
            min_token1: 0,
            collect_fees: false,
        );

    assert(amount0 == 24750246, 'quarter');
    assert(amount1 == 24749752, 'quarter');

    // withdraw remainder
    let (amount0, amount1) = positions
        .withdraw(
            token_id: token_id,
            pool_key: setup.pool_key,
            bounds: bounds,
            liquidity: liquidity - (liquidity / 2) - (liquidity / 4),
            min_token0: 0,
            min_token1: 0,
            collect_fees: false,
        );

    assert(amount0 == 24750246, 'remainder');
    assert(amount1 == 24749752, 'remainder');
}
