use starknet::{contract_address_const, get_contract_address};
use starknet::testing::{set_contract_address};
use ekubo::tests::mocks::mock_erc20::{IMockERC20Dispatcher, IMockERC20DispatcherTrait};
use ekubo::interfaces::core::{
    ICoreDispatcher, ICoreDispatcherTrait, ILockerDispatcher, ILockerDispatcherTrait
};
use ekubo::interfaces::erc721::{IERC721Dispatcher, IERC721DispatcherTrait};
use ekubo::interfaces::positions::{IPositionsDispatcher, IPositionsDispatcherTrait, Bounds};
use ekubo::types::keys::{PoolKey};
use ekubo::math::ticks::{constants as tick_constants, tick_to_sqrt_ratio};
use ekubo::types::i129::{i129};
use ekubo::math::ticks::{min_sqrt_ratio, max_sqrt_ratio};
use zeroable::Zeroable;

use ekubo::tests::helper::{
    deploy_core, setup_pool, deploy_positions, deploy_positions_custom_uri, FEE_ONE_PERCENT, swap,
    IPositionsDispatcherIntoIERC721Dispatcher, IPositionsDispatcherIntoILockerDispatcher,
    core_owner, SetupPoolResult
};
use array::ArrayTrait;
use option::OptionTrait;
use traits::{Into};

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
    assert(positions.tokenUri(u256 { low: 1, high: 0 }) == 'https://z.ekubo.org/1', 'token_uri');
}

#[test]
#[available_gas(300000000)]
fn test_nft_indexing_token_ids() {
    let core = deploy_core();
    let positions = deploy_positions(core);
    let positions_721 = IPositionsDispatcherIntoIERC721Dispatcher::into(positions);

    let pool_key = PoolKey {
        token0: Zeroable::zero(),
        token1: Zeroable::zero(),
        fee: Zeroable::zero(),
        tick_spacing: Zeroable::zero(),
        extension: Zeroable::zero(),
    };

    let bounds = Bounds { lower: Zeroable::zero(), upper: Zeroable::zero() };

    let owner = contract_address_const::<912345>();
    let other = contract_address_const::<9123456>();

    assert(positions_721.balanceOf(owner) == 0, 'balance start');
    let mut all = positions.get_all_positions(owner);
    assert(all.len() == 0, 'len before');

    let token_id = positions.mint(owner, pool_key: pool_key, bounds: bounds);

    assert(positions_721.balanceOf(owner) == 1, 'balance after');
    all = positions.get_all_positions(owner);
    assert(all.len() == 1, 'len after');

    set_contract_address(owner);
    positions_721.transferFrom(owner, other, all.pop_front().unwrap().into());

    assert(positions_721.balanceOf(owner) == 0, 'balance after transfer');
    all = positions.get_all_positions(owner);
    assert(all.len() == 0, 'len after transfer');

    assert(positions_721.balanceOf(other) == 1, 'balance other transfer');
    all = positions.get_all_positions(other);
    assert(all.len() == 1, 'len other');
    assert(all.pop_front().unwrap().into() == token_id.low, 'token other');

    let token_id_2 = positions.mint(owner, pool_key: pool_key, bounds: bounds);
    set_contract_address(other);
    positions_721.transferFrom(other, owner, token_id);

    all = positions.get_all_positions(owner);
    assert(all.len() == 2, 'len final');
    assert(all.pop_front().unwrap().into() == token_id.low, 'token1');
    assert(all.pop_front().unwrap().into() == token_id_2.low, 'token2');
}

#[test]
#[available_gas(300000000)]
fn test_nft_custom_uri() {
    let core = deploy_core();
    let positions = IPositionsDispatcherIntoIERC721Dispatcher::into(
        deploy_positions_custom_uri(core, 'ipfs://abcdef/')
    );
    assert(positions.tokenUri(u256 { low: 1, high: 0 }) == 'ipfs://abcdef/1', 'token_uri');
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
            bounds: Bounds { lower: Zeroable::zero(), upper: Zeroable::zero(),  }
        );

    IPositionsDispatcherIntoIERC721Dispatcher::into(positions)
        .approve(contract_address_const::<2>(), token_id);
    assert(
        IPositionsDispatcherIntoIERC721Dispatcher::into(positions)
            .getApproved(token_id) == contract_address_const::<2>(),
        'approved'
    );
}

#[test]
#[available_gas(300000000)]
fn test_nft_transfer_from() {
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
            bounds: Bounds { lower: Zeroable::zero(), upper: Zeroable::zero(),  }
        );

    set_contract_address(contract_address_const::<1>());
    let nft = IPositionsDispatcherIntoIERC721Dispatcher::into(positions);

    nft.approve(contract_address_const::<3>(), token_id);
    nft.transferFrom(contract_address_const::<1>(), contract_address_const::<2>(), token_id);

    assert(nft.balanceOf(contract_address_const::<1>()) == u256 { low: 0, high: 0 }, 'bal from');
    assert(nft.balanceOf(contract_address_const::<2>()) == u256 { low: 1, high: 0 }, 'bal to');
    assert(nft.ownerOf(token_id) == contract_address_const::<2>(), 'owner');
    assert(nft.getApproved(token_id) == Zeroable::zero(), 'zeroed approval');
}

#[test]
#[available_gas(300000000)]
#[should_panic(expected: ('UNAUTHORIZED', 'ENTRYPOINT_FAILED'))]
fn test_nft_transfer_from_fails_not_from_owner() {
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
            bounds: Bounds { lower: Zeroable::zero(), upper: Zeroable::zero(),  }
        );

    set_contract_address(contract_address_const::<2>());

    let nft = IPositionsDispatcherIntoIERC721Dispatcher::into(positions);

    nft.transferFrom(contract_address_const::<1>(), contract_address_const::<2>(), token_id);
}

#[test]
#[available_gas(300000000)]
fn test_nft_transfer_from_succeeds_from_approved() {
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
            bounds: Bounds { lower: Zeroable::zero(), upper: Zeroable::zero(),  }
        );

    set_contract_address(contract_address_const::<1>());
    let nft = IPositionsDispatcherIntoIERC721Dispatcher::into(positions);
    nft.approve(contract_address_const::<2>(), token_id);

    set_contract_address(contract_address_const::<2>());
    nft.transferFrom(contract_address_const::<1>(), contract_address_const::<2>(), token_id);
}

#[test]
#[available_gas(300000000)]
fn test_nft_transfer_from_succeeds_from_approved_for_all() {
    let core = deploy_core();
    let positions = deploy_positions(core);
    let nft = IPositionsDispatcherIntoIERC721Dispatcher::into(positions);

    set_contract_address(contract_address_const::<1>());
    nft.setApprovalForAll(contract_address_const::<2>(), true);

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
            bounds: Bounds { lower: Zeroable::zero(), upper: Zeroable::zero(),  }
        );

    set_contract_address(contract_address_const::<2>());
    nft.transferFrom(contract_address_const::<1>(), contract_address_const::<2>(), token_id);
}

#[test]
#[available_gas(300000000)]
fn test_nft_token_uri() {
    let core = deploy_core();
    let positions = IPositionsDispatcherIntoIERC721Dispatcher::into(deploy_positions(core));

    assert(positions.tokenUri(u256 { low: 1, high: 0 }) == 'https://z.ekubo.org/1', 'token_uri');
    assert(
        positions.tokenUri(u256 { low: 9999999, high: 0 }) == 'https://z.ekubo.org/9999999',
        'token_uri'
    );
    assert(
        positions.tokenUri(u256 { low: 239020510, high: 0 }) == 'https://z.ekubo.org/239020510',
        'token_uri'
    );
    assert(
        positions.tokenUri(u256 { low: 99999999999, high: 0 }) == 'https://z.ekubo.org/99999999999',
        'max token_uri'
    );
}

#[test]
#[available_gas(300000000)]
#[should_panic(expected: ('URI_LENGTH', 'ENTRYPOINT_FAILED'))]
fn test_nft_token_uri_reverts_too_long() {
    let core = deploy_core();
    let positions = IPositionsDispatcherIntoIERC721Dispatcher::into(deploy_positions(core));

    positions.tokenUri(u256 { low: 999999999999, high: 0 });
}

#[test]
#[available_gas(300000000)]
#[should_panic(expected: ('INVALID_ID', 'ENTRYPOINT_FAILED'))]
fn test_nft_token_uri_reverts_token_id_too_big() {
    let core = deploy_core();
    let positions = IPositionsDispatcherIntoIERC721Dispatcher::into(deploy_positions(core));

    positions.tokenUri(u256 { low: 10000000000000000000000000000000, high: 0 });
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
            bounds: Bounds { lower: Zeroable::zero(), upper: Zeroable::zero(),  }
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
            .balanceOf(recipient) == Zeroable::zero(),
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
                bounds: Bounds { lower: Zeroable::zero(), upper: Zeroable::zero(),  }
            ) == 1,
        'token id'
    );
    assert(
        IPositionsDispatcherIntoIERC721Dispatcher::into(positions).ownerOf(1) == recipient, 'owner'
    );
    assert(
        IPositionsDispatcherIntoIERC721Dispatcher::into(positions).balanceOf(recipient) == u256 {
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
        lower: i129 { mag: 1000, sign: true }, upper: i129 { mag: 1000, sign: false }, 
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
        setup.token0.balanceOf(contract_address_const::<2>()) == Zeroable::zero(),
        'balance0 transfer'
    );
    assert(
        setup.token1.balanceOf(contract_address_const::<2>()) == Zeroable::zero(),
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
        lower: i129 { mag: 1000, sign: true }, upper: i129 { mag: 1000, sign: false }, 
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
        setup.token0.balanceOf(contract_address_const::<2>()) == u256 { low: 66674999, high: 0 },
        'balance0 transfer'
    );
    assert(
        setup.token1.balanceOf(contract_address_const::<2>()) == Zeroable::zero(),
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
        lower: i129 { mag: 1000, sign: true }, upper: i129 { mag: 1000, sign: false }, 
    };
    let token_id = positions.mint(caller, pool_key: setup.pool_key, bounds: bounds);
    assert(token_id == 1, 'token id');
    setup.token0.increase_balance(positions.contract_address, 100000000);
    setup.token1.increase_balance(positions.contract_address, 100000000);
    let liquidity = positions
        .deposit_last(pool_key: setup.pool_key, bounds: bounds, min_liquidity: 100);

    set_contract_address(contract_address_const::<2>());

    let balance0 = positions.refund(setup.token0.contract_address);
    let balance1 = positions.refund(setup.token1.contract_address);

    assert(
        setup.token0.balanceOf(contract_address_const::<2>()) == Zeroable::zero(),
        'balance0 transfer'
    );
    assert(
        setup.token1.balanceOf(contract_address_const::<2>()) == u256 { low: 66674999, high: 0 },
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
        lower: i129 { mag: 1000, sign: true }, upper: i129 { mag: 1000, sign: false }, 
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
        setup.token0.balanceOf(contract_address_const::<2>()) == u256 { low: 100000000, high: 0 },
        'balance0 transfer'
    );
    assert(
        setup.token1.balanceOf(contract_address_const::<2>()) == Zeroable::zero(),
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
        lower: i129 { mag: 1000, sign: true }, upper: i129 { mag: 1000, sign: false }, 
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
        setup.token0.balanceOf(contract_address_const::<2>()) == Zeroable::zero(),
        'balance0 transfer'
    );
    assert(
        setup.token1.balanceOf(contract_address_const::<2>()) == u256 { low: 100000000, high: 0 },
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
        lower: i129 { mag: 1000, sign: true }, upper: i129 { mag: 1000, sign: false }, 
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

    assert(get_position_result.liquidity == 200050104166, 'liquidity');
    assert(get_position_result.amount0 == 100000998, 'amount0');
    assert(get_position_result.amount1 == 99999000, 'amount1');
    assert(get_position_result.fees0 == 20, 'fees0');
    assert(get_position_result.fees1 == 9, 'fees1');
}

#[test]
#[available_gas(100000000)]
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
        lower: i129 { mag: 1000, sign: true }, upper: i129 { mag: 1000, sign: false }, 
    };
    let token_id = positions.mint(caller, pool_key: setup.pool_key, bounds: bounds);

    let recipient = contract_address_const::<80085>();

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
            recipient: recipient,
        );

    assert(amount0 == 49500494, 'amount0 less 1%');
    assert(amount1 == 49499505, 'amount1 less 1%');
    assert(
        IMockERC20Dispatcher {
            contract_address: setup.pool_key.token0
        }.balanceOf(recipient) == 49500494,
        'balance0'
    );
    assert(
        IMockERC20Dispatcher {
            contract_address: setup.pool_key.token1
        }.balanceOf(recipient) == 49499505,
        'balance1'
    );

    // fees are not withdrawn with the principal
    let get_position_result = positions.get_position_info(token_id, setup.pool_key, bounds);

    assert(get_position_result.liquidity == 100025052083, 'liquidity');
    assert(get_position_result.amount0 == 50000499, 'amount0');
    assert(get_position_result.amount1 == 49999500, 'amount1');
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
            recipient: recipient,
        );

    assert(amount0 == 19, 'fees0 withdrawn');
    assert(amount1 == 8, 'fees1 withdrawn');

    assert(
        IMockERC20Dispatcher {
            contract_address: setup.pool_key.token0
        }.balanceOf(recipient) == (49500494 + 19),
        'balance0'
    );
    assert(
        IMockERC20Dispatcher {
            contract_address: setup.pool_key.token1
        }.balanceOf(recipient) == (49499505 + 8),
        'balance1'
    );

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
            recipient: recipient,
        );

    assert(amount0 == 24750246, 'quarter');
    assert(amount1 == 24749752, 'quarter');

    assert(
        IMockERC20Dispatcher {
            contract_address: setup.pool_key.token0
        }.balanceOf(recipient) == (49500494 + 19 + 24750246),
        'balance0'
    );
    assert(
        IMockERC20Dispatcher {
            contract_address: setup.pool_key.token1
        }.balanceOf(recipient) == (49499505 + 8 + 24749752),
        'balance1'
    );

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
            recipient: recipient,
        );

    assert(amount0 == 24750246, 'remainder');
    assert(amount1 == 24749752, 'remainder');

    assert(
        IMockERC20Dispatcher {
            contract_address: setup.pool_key.token0
        }.balanceOf(recipient) == (49500494 + 19 + 24750246 + 24750246),
        'balance0'
    );
    assert(
        IMockERC20Dispatcher {
            contract_address: setup.pool_key.token1
        }.balanceOf(recipient) == (49499505 + 8 + 24749752 + 24749752),
        'balance1'
    );
}


#[test]
#[available_gas(80000000)]
fn test_deposit_withdraw_protocol_fee_then_deposit() {
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
        lower: i129 { mag: 1000, sign: true }, upper: i129 { mag: 1000, sign: false }, 
    };
    let token_id = positions.mint(caller, pool_key: setup.pool_key, bounds: bounds);

    let recipient = contract_address_const::<80085>();

    setup.token0.increase_balance(positions.contract_address, 100000000);
    setup.token1.increase_balance(positions.contract_address, 100000000);
    let liquidity = positions
        .deposit_last(pool_key: setup.pool_key, bounds: bounds, min_liquidity: 100);

    let withdrawn = positions
        .withdraw(
            token_id: token_id,
            pool_key: setup.pool_key,
            bounds: bounds,
            liquidity: liquidity,
            min_token0: 0,
            min_token1: 0,
            collect_fees: false,
            recipient: recipient,
        );

    let caller = get_contract_address();
    set_contract_address(core_owner());
    setup
        .core
        .withdraw_fees_collected(recipient: recipient, token: setup.pool_key.token0, amount: 1);
    setup
        .core
        .withdraw_fees_collected(recipient: recipient, token: setup.pool_key.token1, amount: 1);

    set_contract_address(caller);
    setup.token0.increase_balance(positions.contract_address, 100000000);
    setup.token1.increase_balance(positions.contract_address, 100000000);
    let liquidity = positions
        .deposit_last(pool_key: setup.pool_key, bounds: bounds, min_liquidity: 100);
}

#[test]
#[available_gas(80000000)]
fn test_deposit_liquidity_updates_tick_states_at_bounds() {
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
        lower: i129 { mag: 1, sign: true }, upper: i129 { mag: 1, sign: false }, 
    };
    let token_id = positions.mint(caller, pool_key: setup.pool_key, bounds: bounds);

    let recipient = contract_address_const::<80085>();

    setup.token0.increase_balance(positions.contract_address, 10000);
    setup.token1.increase_balance(positions.contract_address, 10000);
    let liquidity = positions
        .deposit_last(pool_key: setup.pool_key, bounds: bounds, min_liquidity: 1);
    let mut tick_lower_state = setup.core.get_tick(setup.pool_key, i129 { mag: 1, sign: true });
    let mut tick_upper_state = setup.core.get_tick(setup.pool_key, i129 { mag: 1, sign: false });
    assert(
        tick_upper_state.liquidity_delta == i129 { mag: liquidity, sign: true },
        'upper.liquidity_delta'
    );
    assert(tick_upper_state.liquidity_net == liquidity, 'upper.liquidity_net');
    assert(tick_upper_state.fee_growth_outside_token0 == 0, 'upper.fgot0');
    assert(tick_upper_state.fee_growth_outside_token1 == 0, 'upper.fgot1');

    assert(
        tick_lower_state.liquidity_delta == i129 { mag: liquidity, sign: false },
        'lower.liquidity_delta'
    );
    assert(tick_lower_state.liquidity_net == liquidity, 'lower.liquidity_net');
    assert(tick_lower_state.fee_growth_outside_token0 == 0, 'lower.fgot0');
    assert(tick_lower_state.fee_growth_outside_token1 == 0, 'lower.fgot1');
}

#[test]
#[available_gas(80000000)]
fn test_deposit_swap_through_upper_tick_fees_accounting() {
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
        lower: i129 { mag: 1, sign: true }, upper: i129 { mag: 1, sign: false }, 
    };
    let token_id = positions.mint(caller, pool_key: setup.pool_key, bounds: bounds);

    let recipient = contract_address_const::<80085>();

    setup.token0.increase_balance(positions.contract_address, 10000);
    setup.token1.increase_balance(positions.contract_address, 10000);
    let liquidity = positions
        .deposit_last(pool_key: setup.pool_key, bounds: bounds, min_liquidity: 1);

    let mut info = positions.get_position_info(token_id, setup.pool_key, bounds);

    assert(info.liquidity == liquidity, 'liquidity before');
    assert(info.amount0 == 9999, 'amount0 before');
    assert(info.amount1 == 9999, 'amount1 before');
    assert(info.fees0 == 0, 'fees0 before');
    assert(info.fees1 == 0, 'fees1 before');

    setup.token1.increase_balance(setup.locker.contract_address, 10010);
    let delta_swap = swap(
        setup: setup,
        amount: i129 { mag: 100000, sign: true },
        is_token1: false,
        sqrt_ratio_limit: tick_to_sqrt_ratio(i129 { mag: 2, sign: false }),
        recipient: Zeroable::zero(),
        skip_ahead: 0
    );

    assert(delta_swap.amount0 == i129 { mag: 10000, sign: true }, 'first swap delta0');
    assert(delta_swap.amount1 == i129 { mag: 10000, sign: false }, 'first swap delta1');

    info = positions.get_position_info(token_id, setup.pool_key, bounds);

    assert(info.liquidity == liquidity, 'liquidity after');
    assert(info.amount0 == 0, 'amount0 after');
    assert(info.amount1 == 20000, 'amount1 after');
    assert(info.fees0 == 99, 'fees0 after');
    assert(info.fees1 == 0, 'fees1 after');
}

#[test]
#[available_gas(80000000)]
fn test_deposit_swap_through_lower_tick_fees_accounting() {
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
        lower: i129 { mag: 1, sign: true }, upper: i129 { mag: 1, sign: false }, 
    };
    let token_id = positions.mint(caller, pool_key: setup.pool_key, bounds: bounds);

    let recipient = contract_address_const::<80085>();

    setup.token0.increase_balance(positions.contract_address, 10000);
    setup.token1.increase_balance(positions.contract_address, 10000);
    let liquidity = positions
        .deposit_last(pool_key: setup.pool_key, bounds: bounds, min_liquidity: 1);

    let mut info = positions.get_position_info(token_id, setup.pool_key, bounds);

    assert(info.liquidity == liquidity, 'liquidity before');
    assert(info.amount0 == 9999, 'amount0 before');
    assert(info.amount1 == 9999, 'amount1 before');
    assert(info.fees0 == 0, 'fees0 before');
    assert(info.fees1 == 0, 'fees1 before');

    setup.token0.increase_balance(setup.locker.contract_address, 10010);
    let delta_swap = swap(
        setup: setup,
        amount: i129 { mag: 100000, sign: true },
        is_token1: true,
        sqrt_ratio_limit: tick_to_sqrt_ratio(i129 { mag: 2, sign: true }),
        recipient: Zeroable::zero(),
        skip_ahead: 0
    );

    assert(delta_swap.amount0 == i129 { mag: 10000, sign: false }, 'swap delta0');
    assert(delta_swap.amount1 == i129 { mag: 10000, sign: true }, 'swap delta1');

    info = positions.get_position_info(token_id, setup.pool_key, bounds);

    assert(info.liquidity == liquidity, 'liquidity after');
    assert(info.amount0 == 20000, 'amount0 after');
    assert(info.amount1 == 0, 'amount1 after');
    assert(info.fees0 == 0, 'fees0 after');
    assert(info.fees1 == 99, 'fees1 after');
}

#[test]
#[available_gas(100000000)]
fn test_deposit_swap_round_trip_accounting() {
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
        lower: i129 { mag: 1, sign: true }, upper: i129 { mag: 1, sign: false }, 
    };
    let token_id = positions.mint(caller, pool_key: setup.pool_key, bounds: bounds);

    let recipient = contract_address_const::<80085>();

    setup.token0.increase_balance(positions.contract_address, 10000);
    setup.token1.increase_balance(positions.contract_address, 10000);
    let liquidity = positions
        .deposit_last(pool_key: setup.pool_key, bounds: bounds, min_liquidity: 1);

    let mut info = positions.get_position_info(token_id, setup.pool_key, bounds);

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
        recipient: Zeroable::zero(),
        skip_ahead: 0
    );
    swap(
        setup: setup,
        amount: i129 { mag: 100000, sign: false },
        is_token1: false,
        sqrt_ratio_limit: tick_to_sqrt_ratio(i129 { mag: 2, sign: true }),
        recipient: Zeroable::zero(),
        skip_ahead: 0
    );
    swap(
        setup: setup,
        amount: i129 { mag: 100000, sign: false },
        is_token1: true,
        sqrt_ratio_limit: u256 { high: 1, low: 0 },
        recipient: Zeroable::zero(),
        skip_ahead: 0
    );

    info = positions.get_position_info(token_id, setup.pool_key, bounds);

    assert(info.liquidity == liquidity, 'liquidity after');
    assert(info.amount0 == 9999, 'amount0 after');
    assert(info.amount1 == 9999, 'amount1 after');
    assert(info.fees0 == 200, 'fees0 after');
    assert(info.fees1 == 200, 'fees1 after');

    let (amount0, amount1) = positions
        .withdraw(
            token_id: token_id,
            pool_key: setup.pool_key,
            bounds: bounds,
            liquidity: 0,
            min_token0: 0,
            min_token1: 0,
            collect_fees: true,
            recipient: recipient,
        );

    assert(amount0 == 200, 'amount0 withdrawn');
    assert(amount1 == 200, 'amount1 withdrawn');
    info = positions.get_position_info(token_id, setup.pool_key, bounds);
    assert(info.liquidity == liquidity, 'liquidity after');
    assert(info.amount0 == 9999, 'amount0 after');
    assert(info.amount1 == 9999, 'amount1 after');
    assert(info.fees0 == 0, 'fees0 withdrawn');
    assert(info.fees1 == 0, 'fees1 withdrawn');
}

#[derive(Copy, Drop)]
struct CreatePositionResult {
    id: u256,
    bounds: Bounds,
    liquidity: u128,
}

fn create_position(
    setup: SetupPoolResult,
    positions: IPositionsDispatcher,
    bounds: Bounds,
    amount0: u128,
    amount1: u128
) -> CreatePositionResult {
    let token_id = positions.mint(get_contract_address(), pool_key: setup.pool_key, bounds: bounds);
    setup.token0.set_balance(positions.contract_address, amount0.into());
    setup.token1.set_balance(positions.contract_address, amount1.into());

    let liquidity = positions
        .deposit(token_id: token_id, pool_key: setup.pool_key, bounds: bounds, min_liquidity: 1);

    CreatePositionResult { id: token_id, bounds, liquidity }
}

#[test]
#[available_gas(1000000000)]
fn test_deposit_swap_multiple_positions() {
    let caller = contract_address_const::<1>();
    set_contract_address(caller);
    let setup = setup_pool(
        fee: FEE_ONE_PERCENT,
        tick_spacing: 1,
        initial_tick: Zeroable::zero(),
        extension: Zeroable::zero(),
    );
    let positions = deploy_positions(setup.core);
    let p0 = create_position(
        setup,
        positions,
        Bounds { lower: i129 { mag: 1, sign: true }, upper: i129 { mag: 1, sign: false } },
        10000,
        10000
    );
    let p1 = create_position(
        setup,
        positions,
        Bounds { lower: i129 { mag: 0, sign: false }, upper: i129 { mag: 1, sign: false } },
        10000,
        0
    );
    let p2 = create_position(
        setup,
        positions,
        Bounds { lower: i129 { mag: 1, sign: true }, upper: i129 { mag: 0, sign: false } },
        0,
        10000
    );

    setup.token0.increase_balance(setup.locker.contract_address, 300000);
    setup.token1.increase_balance(setup.locker.contract_address, 300000);
    swap(
        setup: setup,
        amount: i129 { mag: 100000, sign: false },
        is_token1: true,
        sqrt_ratio_limit: tick_to_sqrt_ratio(i129 { mag: 2, sign: false }),
        recipient: Zeroable::zero(),
        skip_ahead: 0
    );
    swap(
        setup: setup,
        amount: i129 { mag: 100000, sign: false },
        is_token1: false,
        sqrt_ratio_limit: tick_to_sqrt_ratio(i129 { mag: 2, sign: true }),
        recipient: Zeroable::zero(),
        skip_ahead: 0
    );
    swap(
        setup: setup,
        amount: i129 { mag: 100000, sign: false },
        is_token1: true,
        sqrt_ratio_limit: u256 { high: 1, low: 0 },
        recipient: Zeroable::zero(),
        skip_ahead: 0
    );

    let p0_info = positions.get_position_info(p0.id, setup.pool_key, p0.bounds);
    let p1_info = positions.get_position_info(p1.id, setup.pool_key, p1.bounds);
    let p2_info = positions.get_position_info(p2.id, setup.pool_key, p2.bounds);

    assert(p0_info.liquidity == p0.liquidity, 'p0 liquidity');
    assert(p0_info.amount0 == 9999, 'p0 amount0');
    assert(p0_info.amount1 == 9999, 'p0 amount1');
    assert(p0_info.fees0 == 200, 'p0 fees0');
    assert(p0_info.fees1 == 200, 'p0 fees1');

    assert(p1_info.liquidity == p1.liquidity, 'p1 liquidity');
    assert(p1_info.amount0 == 9999, 'p1 amount0');
    assert(p1_info.amount1 == 0, 'p1 amount1');
    assert(p1_info.fees0 == 99, 'p1 fees0');
    assert(p1_info.fees1 == 100, 'p1 fees1');

    assert(p2_info.liquidity == p2.liquidity, 'p2 liquidity');
    assert(p2_info.amount0 == 0, 'p2 amount0');
    assert(p2_info.amount1 == 9999, 'p2 amount1');
    assert(p2_info.fees0 == 100, 'p2 fees0');
    assert(p2_info.fees1 == 99, 'p2 fees1');
}
