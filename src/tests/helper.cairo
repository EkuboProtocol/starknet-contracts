use array::{Array, ArrayTrait};

use debug::PrintTrait;
use ekubo::asset_recovery::{IAssetRecoveryDispatcher, AssetRecovery};
use ekubo::core::{Core};
use ekubo::extensions::limit_orders::{LimitOrders};
use ekubo::extensions::oracle::{Oracle};
use ekubo::extensions::twamm::{TWAMM};
use ekubo::interfaces::core::{
    ICoreDispatcher, ICoreDispatcherTrait, ILockerDispatcher, Delta, IExtensionDispatcher
};
use ekubo::interfaces::erc20::{IERC20Dispatcher};
use ekubo::interfaces::erc721::{IERC721Dispatcher};
use ekubo::interfaces::positions::{IPositionsDispatcher};
use ekubo::math::contract_address::ContractAddressOrder;
use ekubo::math::ticks::{max_sqrt_ratio, min_sqrt_ratio, min_tick, max_tick};
use ekubo::owned_nft::{OwnedNFT, IOwnedNFTDispatcher};
use ekubo::positions::{Positions};
use ekubo::quoter::{IQuoterDispatcher, Quoter};
use ekubo::simple_erc20::{SimpleERC20};
use ekubo::simple_swapper::{ISimpleSwapperDispatcher, SimpleSwapper};
use ekubo::tests::mocks::locker::{
    CoreLocker, Action, ActionResult, ICoreLockerDispatcher, ICoreLockerDispatcherTrait,
    UpdatePositionParameters, SwapParameters
};
use ekubo::tests::mocks::mock_erc20::{MockERC20, IMockERC20Dispatcher, IMockERC20DispatcherTrait};
use ekubo::tests::mocks::mock_extension::{
    MockExtension, IMockExtensionDispatcher, IMockExtensionDispatcherTrait
};
use ekubo::tests::mocks::mock_upgradeable::{MockUpgradeable, IMockUpgradeableDispatcher};
use ekubo::types::bounds::{Bounds};
use ekubo::types::call_points::{CallPoints};
use ekubo::types::i129::i129;

use ekubo::types::keys::PoolKey;
use integer::{u256, u256_from_felt252, BoundedInt};
use option::{Option, OptionTrait};
use result::{Result, ResultTrait};
use starknet::class_hash::Felt252TryIntoClassHash;
use starknet::testing::{set_contract_address};

use starknet::{
    get_contract_address, deploy_syscall, ClassHash, contract_address_const, ContractAddress
};
use traits::{Into, TryInto};

const FEE_ONE_PERCENT: u128 = 0x28f5c28f5c28f5c28f5c28f5c28f5c2;

fn deploy_asset_recovery() -> IAssetRecoveryDispatcher {
    let constructor_args: Array<felt252> = ArrayTrait::new();
    let (address, _) = deploy_syscall(
        AssetRecovery::TEST_CLASS_HASH.try_into().unwrap(), 0, constructor_args.span(), true
    )
        .expect('asset recovery deploy');
    return IAssetRecoveryDispatcher { contract_address: address };
}

fn deploy_mock_token() -> IMockERC20Dispatcher {
    let constructor_args: Array<felt252> = ArrayTrait::new();
    let (token_address, _) = deploy_syscall(
        MockERC20::TEST_CLASS_HASH.try_into().unwrap(), 0, constructor_args.span(), true
    )
        .expect('token deploy failed');
    return IMockERC20Dispatcher { contract_address: token_address };
}

fn deploy_simple_erc20(owner: ContractAddress) -> IERC20Dispatcher {
    let mut constructor_args: Array<felt252> = ArrayTrait::new();
    Serde::serialize(@owner, ref constructor_args);
    let (token_address, _) = deploy_syscall(
        SimpleERC20::TEST_CLASS_HASH.try_into().unwrap(), 0, constructor_args.span(), true
    )
        .expect('simpleerc20 deploy');
    return IERC20Dispatcher { contract_address: token_address };
}

fn deploy_owned_nft(
    owner: ContractAddress, name: felt252, symbol: felt252, token_uri_base: felt252
) -> (IOwnedNFTDispatcher, IERC721Dispatcher) {
    let mut constructor_args: Array<felt252> = ArrayTrait::new();

    Serde::serialize(@(owner, name, symbol, token_uri_base), ref constructor_args);

    let (address, _) = deploy_syscall(
        OwnedNFT::TEST_CLASS_HASH.try_into().unwrap(), 0, constructor_args.span(), true
    )
        .expect('nft deploy failed');
    return (
        IOwnedNFTDispatcher { contract_address: address },
        IERC721Dispatcher { contract_address: address }
    );
}

fn deploy_oracle(core: ICoreDispatcher) -> IExtensionDispatcher {
    let mut constructor_args: Array<felt252> = ArrayTrait::new();
    Serde::serialize(@core, ref constructor_args);

    let (address, _) = deploy_syscall(
        Oracle::TEST_CLASS_HASH.try_into().unwrap(), 0, constructor_args.span(), true
    )
        .expect('oracle deploy failed');

    IExtensionDispatcher { contract_address: address }
}

fn deploy_limit_orders(core: ICoreDispatcher) -> IExtensionDispatcher {
    let mut constructor_args: Array<felt252> = ArrayTrait::new();
    Serde::serialize(@(core, OwnedNFT::TEST_CLASS_HASH, 'limit_orders://'), ref constructor_args);

    let (address, _) = deploy_syscall(
        LimitOrders::TEST_CLASS_HASH.try_into().unwrap(), 0, constructor_args.span(), true
    )
        .expect('limit_orders deploy failed');

    IExtensionDispatcher { contract_address: address }
}

fn deploy_two_mock_tokens() -> (IMockERC20Dispatcher, IMockERC20Dispatcher) {
    let mut token0 = deploy_mock_token();
    let mut token1 = deploy_mock_token();
    if (token0.contract_address > token1.contract_address) {
        let temp = token1;
        token1 = token0;
        token0 = temp;
    }

    (token0, token1)
}

fn deploy_mock_extension(
    core: ICoreDispatcher, call_points: CallPoints
) -> IMockExtensionDispatcher {
    let mut constructor_args: Array<felt252> = ArrayTrait::new();
    Serde::serialize(@(core, call_points), ref constructor_args);
    let (address, _) = deploy_syscall(
        MockExtension::TEST_CLASS_HASH.try_into().unwrap(), 0, constructor_args.span(), true
    )
        .expect('mockext deploy failed');

    IMockExtensionDispatcher { contract_address: address }
}

fn deploy_twamm(core: ICoreDispatcher) -> IExtensionDispatcher {
    let mut constructor_args: Array<felt252> = ArrayTrait::new();
    Serde::serialize(@core.contract_address, ref constructor_args);
    Serde::serialize(@OwnedNFT::TEST_CLASS_HASH, ref constructor_args);
    Serde::serialize(@'twamm://', ref constructor_args);

    let (address, _) = deploy_syscall(
        TWAMM::TEST_CLASS_HASH.try_into().unwrap(), 0, constructor_args.span(), true
    )
        .expect('twamm deploy failed');

    IExtensionDispatcher { contract_address: address }
}

#[derive(Copy, Drop)]
struct SetupPoolResult {
    token0: IMockERC20Dispatcher,
    token1: IMockERC20Dispatcher,
    pool_key: PoolKey,
    core: ICoreDispatcher,
    locker: ICoreLockerDispatcher
}


fn deploy_core() -> ICoreDispatcher {
    let mut constructor_args: Array<felt252> = ArrayTrait::new();
    let (address, _) = deploy_syscall(
        Core::TEST_CLASS_HASH.try_into().unwrap(), 0, constructor_args.span(), true
    )
        .expect('core deploy failed');
    return ICoreDispatcher { contract_address: address };
}


fn deploy_quoter(core: ICoreDispatcher) -> IQuoterDispatcher {
    let mut constructor_args: Array<felt252> = ArrayTrait::new();
    Serde::serialize(@core, ref constructor_args);

    let (address, _) = deploy_syscall(
        Quoter::TEST_CLASS_HASH.try_into().unwrap(), 0, constructor_args.span(), true
    )
        .expect('rf deploy failed');

    IQuoterDispatcher { contract_address: address }
}

fn deploy_simple_swapper(core: ICoreDispatcher) -> ISimpleSwapperDispatcher {
    let mut constructor_args: Array<felt252> = ArrayTrait::new();
    Serde::serialize(@core, ref constructor_args);

    let (address, _) = deploy_syscall(
        SimpleSwapper::TEST_CLASS_HASH.try_into().unwrap(), 0, constructor_args.span(), true
    )
        .expect('ss deploy failed');

    ISimpleSwapperDispatcher { contract_address: address }
}

fn deploy_locker(core: ICoreDispatcher) -> ICoreLockerDispatcher {
    let mut constructor_args: Array<felt252> = ArrayTrait::new();
    Serde::serialize(@core, ref constructor_args);

    let (address, _) = deploy_syscall(
        CoreLocker::TEST_CLASS_HASH.try_into().unwrap(), 0, constructor_args.span(), true
    )
        .expect('locker deploy failed');

    ICoreLockerDispatcher { contract_address: address }
}

impl IPositionsDispatcherIntoILockerDispatcher of Into<IPositionsDispatcher, ILockerDispatcher> {
    fn into(self: IPositionsDispatcher) -> ILockerDispatcher {
        ILockerDispatcher { contract_address: self.contract_address }
    }
}

fn deploy_positions_custom_uri(
    core: ICoreDispatcher, token_uri_base: felt252
) -> IPositionsDispatcher {
    let mut constructor_args: Array<felt252> = ArrayTrait::new();
    Serde::serialize(@(core, OwnedNFT::TEST_CLASS_HASH, token_uri_base), ref constructor_args);

    let (address, _) = deploy_syscall(
        Positions::TEST_CLASS_HASH.try_into().unwrap(), 0, constructor_args.span(), true
    )
        .expect('positions deploy failed');

    IPositionsDispatcher { contract_address: address }
}

fn deploy_positions(core: ICoreDispatcher) -> IPositionsDispatcher {
    deploy_positions_custom_uri(core, 'https://z.ekubo.org/')
}

fn setup_pool(
    fee: u128, tick_spacing: u128, initial_tick: i129, extension: ContractAddress
) -> SetupPoolResult {
    let core = deploy_core();
    let locker = deploy_locker(core);
    let (token0, token1) = deploy_two_mock_tokens();

    let pool_key = PoolKey {
        token0: token0.contract_address,
        token1: token1.contract_address,
        fee,
        tick_spacing,
        extension
    };

    core.initialize_pool(pool_key, initial_tick);

    SetupPoolResult { token0, token1, pool_key, core, locker }
}

fn setup_pool_with_core(
    core: ICoreDispatcher,
    fee: u128,
    tick_spacing: u128,
    initial_tick: i129,
    extension: ContractAddress
) -> SetupPoolResult {
    let locker = deploy_locker(core);
    let (token0, token1) = deploy_two_mock_tokens();

    let pool_key = PoolKey {
        token0: token0.contract_address,
        token1: token1.contract_address,
        fee,
        tick_spacing,
        extension
    };

    core.initialize_pool(pool_key, initial_tick);

    SetupPoolResult { token0, token1, pool_key, core, locker }
}

fn deploy_mock_upgradeable() -> IMockUpgradeableDispatcher {
    let mut constructor_args: Array<felt252> = ArrayTrait::new();
    let (address, _) = deploy_syscall(
        MockUpgradeable::TEST_CLASS_HASH.try_into().unwrap(), 0, constructor_args.span(), true
    )
        .expect('upgradeable deploy failed');
    return IMockUpgradeableDispatcher { contract_address: address };
}

#[derive(Drop, Copy)]
struct Balances {
    token0_balance_core: u256,
    token1_balance_core: u256,
    token0_balance_recipient: u256,
    token1_balance_recipient: u256,
    token0_balance_locker: u256,
    token1_balance_locker: u256,
}
fn get_balances(
    token0: IMockERC20Dispatcher,
    token1: IMockERC20Dispatcher,
    core: ICoreDispatcher,
    locker: ICoreLockerDispatcher,
    recipient: ContractAddress
) -> Balances {
    let token0_balance_core = token0.balanceOf(core.contract_address);
    let token1_balance_core = token1.balanceOf(core.contract_address);
    let token0_balance_recipient = token0.balanceOf(recipient);
    let token1_balance_recipient = token1.balanceOf(recipient);
    let token0_balance_locker = token0.balanceOf(locker.contract_address);
    let token1_balance_locker = token1.balanceOf(locker.contract_address);
    Balances {
        token0_balance_core,
        token1_balance_core,
        token0_balance_recipient,
        token1_balance_recipient,
        token0_balance_locker,
        token1_balance_locker,
    }
}


// this is only shown in the tests, but hidden in the deployed code since we only check against the hash
fn core_owner() -> ContractAddress {
    contract_address_const::<0x03F60aFE30844F556ac1C674678Ac4447840b1C6c26854A2DF6A8A3d2C015610>()
}


fn diff(x: u256, y: u256) -> i129 {
    let (lower, upper) = if x < y {
        (x, y)
    } else {
        (y, x)
    };
    let diff = upper - lower;
    assert(diff.high == 0, 'diff_overflow');
    i129 { mag: diff.low, sign: (x < y) & (diff != 0) }
}

fn assert_balances_delta(before: Balances, after: Balances, delta: Delta) {
    assert(
        diff(after.token0_balance_core, before.token0_balance_core) == delta.amount0,
        'token0_balance_core'
    );
    assert(
        diff(after.token1_balance_core, before.token1_balance_core) == delta.amount1,
        'token1_balance_core'
    );

    if (delta.amount0.sign) {
        assert(
            diff(after.token0_balance_recipient, before.token0_balance_recipient) == -delta.amount0,
            'token0_balance_recipient'
        );
    } else {
        assert(
            diff(after.token0_balance_locker, before.token0_balance_locker) == -delta.amount0,
            'token0_balance_locker'
        );
    }
    if (delta.amount1.sign) {
        assert(
            diff(after.token1_balance_recipient, before.token1_balance_recipient) == -delta.amount1,
            'token1_balance_recipient'
        );
    } else {
        assert(
            diff(after.token1_balance_locker, before.token1_balance_locker) == -delta.amount1,
            'token1_balance_locker'
        );
    }
}

fn update_position_inner(
    core: ICoreDispatcher,
    pool_key: PoolKey,
    locker: ICoreLockerDispatcher,
    bounds: Bounds,
    liquidity_delta: i129,
    recipient: ContractAddress
) -> Delta {
    assert(recipient != core.contract_address, 'recipient is core');
    assert(recipient != locker.contract_address, 'recipient is locker');

    let before: Balances = get_balances(
        token0: IMockERC20Dispatcher { contract_address: pool_key.token0 },
        token1: IMockERC20Dispatcher { contract_address: pool_key.token1 },
        core: core,
        locker: locker,
        recipient: recipient,
    );
    match locker
        .call(
            Action::UpdatePosition(
                (pool_key, UpdatePositionParameters { bounds, liquidity_delta, salt: 0 }, recipient)
            )
        ) {
        ActionResult::AssertLockerId => {
            assert(false, 'unexpected');
            Zeroable::zero()
        },
        ActionResult::Relock => {
            assert(false, 'unexpected');
            Zeroable::zero()
        },
        ActionResult::UpdatePosition(delta) => {
            let after: Balances = get_balances(
                token0: IMockERC20Dispatcher { contract_address: pool_key.token0 },
                token1: IMockERC20Dispatcher { contract_address: pool_key.token1 },
                core: core,
                locker: locker,
                recipient: recipient,
            );
            assert_balances_delta(before, after, delta);
            delta
        },
        ActionResult::Swap(_) => {
            assert(false, 'unexpected');
            Zeroable::zero()
        },
        ActionResult::SaveBalance(_) => {
            assert(false, 'unexpected');
            Zeroable::zero()
        },
        ActionResult::LoadBalance(_) => {
            assert(false, 'unexpected');
            Zeroable::zero()
        },
        ActionResult::AccumulateAsFees(_) => {
            assert(false, 'unexpected');
            Zeroable::zero()
        },
        ActionResult::FlashBorrow(_) => {
            assert(false, 'unexpected');
            Zeroable::zero()
        }
    }
}

fn flash_borrow_inner(
    core: ICoreDispatcher,
    locker: ICoreLockerDispatcher,
    token: ContractAddress,
    amount_borrow: u128,
    amount_repay: u128,
) {
    match locker.call(Action::FlashBorrow((token, amount_borrow, amount_repay))) {
        ActionResult::AssertLockerId => { assert(false, 'unexpected'); },
        ActionResult::Relock => { assert(false, 'unexpected'); },
        ActionResult::UpdatePosition(delta) => { assert(false, 'unexpected'); },
        ActionResult::Swap(_) => { assert(false, 'unexpected'); },
        ActionResult::SaveBalance(_) => { assert(false, 'unexpected'); },
        ActionResult::LoadBalance(_) => { assert(false, 'unexpected'); },
        ActionResult::AccumulateAsFees(_) => { assert(false, 'unexpected'); },
        ActionResult::FlashBorrow(_) => {}
    }
}

fn update_position(
    setup: SetupPoolResult, bounds: Bounds, liquidity_delta: i129, recipient: ContractAddress
) -> Delta {
    update_position_inner(
        setup.core,
        setup.pool_key,
        setup.locker,
        bounds: bounds,
        liquidity_delta: liquidity_delta,
        recipient: recipient
    )
}


fn accumulate_as_fees(setup: SetupPoolResult, amount0: u128, amount1: u128) {
    accumulate_as_fees_inner(setup.core, setup.pool_key, setup.locker, amount0, amount1)
}

fn accumulate_as_fees_inner(
    core: ICoreDispatcher,
    pool_key: PoolKey,
    locker: ICoreLockerDispatcher,
    amount0: u128,
    amount1: u128,
) {
    match locker.call(Action::AccumulateAsFees((pool_key, amount0, amount1))) {
        ActionResult::AssertLockerId => { assert(false, 'unexpected'); },
        ActionResult::Relock => { assert(false, 'unexpected'); },
        ActionResult::UpdatePosition(_) => { assert(false, 'unexpected'); },
        ActionResult::Swap(delta) => { assert(false, 'unexpected'); },
        ActionResult::SaveBalance(_) => { assert(false, 'unexpected'); },
        ActionResult::LoadBalance(_) => { assert(false, 'unexpected'); },
        ActionResult::AccumulateAsFees => {},
        ActionResult::FlashBorrow(_) => { assert(false, 'unexpected'); }
    }
}

fn swap_inner(
    core: ICoreDispatcher,
    pool_key: PoolKey,
    locker: ICoreLockerDispatcher,
    amount: i129,
    is_token1: bool,
    sqrt_ratio_limit: u256,
    recipient: ContractAddress,
    skip_ahead: u128
) -> Delta {
    let before: Balances = get_balances(
        token0: IMockERC20Dispatcher { contract_address: pool_key.token0 },
        token1: IMockERC20Dispatcher { contract_address: pool_key.token1 },
        core: core,
        locker: locker,
        recipient: recipient,
    );

    match locker
        .call(
            Action::Swap(
                (
                    pool_key,
                    SwapParameters { amount, is_token1, sqrt_ratio_limit, skip_ahead },
                    recipient
                )
            )
        ) {
        ActionResult::AssertLockerId => {
            assert(false, 'unexpected');
            Zeroable::zero()
        },
        ActionResult::Relock => {
            assert(false, 'unexpected');
            Zeroable::zero()
        },
        ActionResult::UpdatePosition(_) => {
            assert(false, 'unexpected');
            Zeroable::zero()
        },
        ActionResult::Swap(delta) => {
            let after: Balances = get_balances(
                token0: IMockERC20Dispatcher { contract_address: pool_key.token0 },
                token1: IMockERC20Dispatcher { contract_address: pool_key.token1 },
                core: core,
                locker: locker,
                recipient: recipient,
            );
            assert_balances_delta(before, after, delta);
            delta
        },
        ActionResult::SaveBalance(_) => {
            assert(false, 'unexpected');
            Zeroable::zero()
        },
        ActionResult::LoadBalance(_) => {
            assert(false, 'unexpected');
            Zeroable::zero()
        },
        ActionResult::AccumulateAsFees(_) => {
            assert(false, 'unexpected');
            Zeroable::zero()
        },
        ActionResult::FlashBorrow(_) => {
            assert(false, 'unexpected');
            Zeroable::zero()
        }
    }
}

fn swap(
    setup: SetupPoolResult,
    amount: i129,
    is_token1: bool,
    sqrt_ratio_limit: u256,
    recipient: ContractAddress,
    skip_ahead: u128
) -> Delta {
    swap_inner(
        setup.core,
        setup.pool_key,
        setup.locker,
        amount,
        is_token1,
        sqrt_ratio_limit,
        recipient,
        skip_ahead
    )
}
