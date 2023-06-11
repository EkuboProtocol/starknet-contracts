use starknet::{contract_address_const};
use starknet::testing::{set_caller_address};
use ekubo::tests::helper::{deploy_core, setup_pool, deploy_positions, FEE_ONE_PERCENT};
use ekubo::tests::mocks::mock_erc20::{IMockERC20Dispatcher, IMockERC20DispatcherTrait};
use ekubo::interfaces::core::{ICoreDispatcher, ICoreDispatcherTrait};
use ekubo::interfaces::positions::{IPositionsDispatcher, IPositionsDispatcherTrait, Bounds};
use ekubo::types::keys::{PoolKey};
use ekubo::math::ticks::{constants as tick_constants};
use ekubo::types::i129::{i129};
use debug::PrintTrait;

#[test]
#[available_gas(300000000)]
fn test_maybe_initialize_pool_twice() {
    let core = deploy_core(contract_address_const::<1>());
    let positions = deploy_positions(core);
    let pool_key = PoolKey {
        token0: contract_address_const::<1>(),
        token1: contract_address_const::<2>(),
        fee: Default::default(),
        tick_spacing: 1,
    };
    positions.maybe_initialize_pool(pool_key, i129 { mag: 0, sign: false });
    positions.maybe_initialize_pool(pool_key, i129 { mag: 1000, sign: false });

    assert(core.get_pool(pool_key).sqrt_ratio == u256 { low: 0, high: 1 }, 'ratio');
}

#[test]
#[available_gas(300000000)]
fn test_nft_balance_of() {
    let core = deploy_core(contract_address_const::<1>());
    let positions = deploy_positions(core);

    let recipient = contract_address_const::<2>();
    assert(positions.balance_of(recipient) == Default::default(), 'balance check');
    // note we do not check the validity of the position key, it only comes into play when trying to add liquidity fails
    assert(
        positions
            .mint(
                recipient,
                pool_key: PoolKey {
                    token0: contract_address_const::<0>(),
                    token1: contract_address_const::<0>(),
                    fee: Default::default(),
                    tick_spacing: Default::default(),
                },
                bounds: Bounds { tick_lower: Default::default(), tick_upper: Default::default(),  }
            ) == 1,
        'token id'
    );
    assert(positions.balance_of(recipient) == u256 { low: 1, high: 0 }, 'balance check after');
}

#[test]
#[available_gas(20000000)]
fn test_deposit_liquidity_full_range() {
    let caller = contract_address_const::<1>();
    set_caller_address(caller);
    let setup = setup_pool(caller, FEE_ONE_PERCENT, 1, i129 { mag: 0, sign: false });
    let positions = deploy_positions(setup.core);
    let token_id = positions.mint(caller, pool_key: setup.pool_key, bounds: Default::default());
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
    set_caller_address(caller);
    let setup = setup_pool(caller, FEE_ONE_PERCENT, 1, i129 { mag: 0, sign: false });
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
        setup.token0.balance_of(contract_address_const::<2>()) == Default::default(),
        'balance0 transfer'
    );
    assert(
        setup.token1.balance_of(contract_address_const::<2>()) == Default::default(),
        'balance1 transfer'
    );

    assert(balance0 == Default::default(), 'balance0');
    assert(balance1 == Default::default(), 'balance1');

    assert(liquidity == 200050104166, 'liquidity');
}

#[test]
#[available_gas(20000000)]
fn test_deposit_liquidity_concentrated_unbalanced_in_range_price_higher() {
    let caller = contract_address_const::<1>();
    set_caller_address(caller);
    let setup = setup_pool(caller, FEE_ONE_PERCENT, 1, i129 { mag: 500, sign: false });
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
        setup.token1.balance_of(contract_address_const::<2>()) == Default::default(),
        'balance1 transfer'
    );

    assert(balance0 == u256 { low: 66674999, high: 0 }, 'balance0');
    assert(balance1 == Default::default(), 'balance1');
    assert(liquidity == 133350064582, 'liquidity');
}

#[test]
#[available_gas(20000000)]
fn test_deposit_liquidity_concentrated_unbalanced_in_range_price_lower() {
    let caller = contract_address_const::<1>();
    set_caller_address(caller);
    let setup = setup_pool(caller, FEE_ONE_PERCENT, 1, i129 { mag: 500, sign: true });
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
        setup.token0.balance_of(contract_address_const::<2>()) == Default::default(),
        'balance0 transfer'
    );
    assert(
        setup.token1.balance_of(contract_address_const::<2>()) == u256 { low: 66674999, high: 0 },
        'balance1 transfer'
    );

    assert(balance0 == Default::default(), 'balance0');
    assert(balance1 == u256 { low: 66674999, high: 0 }, 'balance1');
    assert(liquidity == 133350064582, 'liquidity');
}

#[test]
#[available_gas(20000000)]
fn test_deposit_liquidity_concentrated_out_of_range_price_upper() {
    let caller = contract_address_const::<1>();
    set_caller_address(caller);
    let setup = setup_pool(caller, FEE_ONE_PERCENT, 1, i129 { mag: 1000, sign: false });
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
        setup.token1.balance_of(contract_address_const::<2>()) == Default::default(),
        'balance1 transfer'
    );

    assert(balance0 == u256 { low: 100000000, high: 0 }, 'balance0');
    assert(balance1 == Default::default(), 'balance1');
    assert(liquidity == 100000045833, 'liquidity');
}

#[test]
#[available_gas(20000000)]
fn test_deposit_liquidity_concentrated_out_of_range_price_lower() {
    let caller = contract_address_const::<1>();
    set_caller_address(caller);
    let setup = setup_pool(caller, FEE_ONE_PERCENT, 1, i129 { mag: 1000, sign: true });
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
        setup.token0.balance_of(contract_address_const::<2>()) == Default::default(),
        'balance0 transfer'
    );
    assert(
        setup.token1.balance_of(contract_address_const::<2>()) == u256 { low: 100000000, high: 0 },
        'balance1 transfer'
    );

    assert(balance0 == Default::default(), 'balance0');
    assert(balance1 == u256 { low: 100000000, high: 0 }, 'balance1');
    assert(liquidity == 100000045833, 'liquidity');
}
