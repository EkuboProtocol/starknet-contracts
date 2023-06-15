use integer::{u256, u256_from_felt252, BoundedInt};
use result::{Result, ResultTrait};
use traits::{Into, TryInto};
use array::{Array, ArrayTrait};
use option::{Option, OptionTrait};

use ekubo::types::keys::PoolKey;
use ekubo::types::storage::{Pool};
use ekubo::types::i129::i129;
use ekubo::types::bounds::{Bounds};
use ekubo::math::ticks::{max_sqrt_ratio, min_sqrt_ratio, min_tick, max_tick};
use ekubo::math::utils::ContractAddressOrder;
use ekubo::core::{Core};
use ekubo::interfaces::core::{ICoreDispatcher, ICoreDispatcherTrait, ILockerDispatcher, Delta};
use ekubo::interfaces::positions::{IPositionsDispatcher};
use ekubo::interfaces::erc721::{IERC721Dispatcher};
use ekubo::positions::{Positions};
use ekubo::tests::mocks::mock_erc20::{MockERC20, IMockERC20Dispatcher, IMockERC20DispatcherTrait};
use ekubo::tests::mocks::mock_extension::{
    MockExtension, IMockExtensionDispatcher, IMockExtensionDispatcherTrait
};
use ekubo::tests::mocks::locker::{
    CoreLocker, Action, ActionResult, ICoreLockerDispatcher, ICoreLockerDispatcherTrait,
    UpdatePositionParameters, SwapParameters
};

use starknet::{deploy_syscall, ClassHash, contract_address_const, ContractAddress};
use starknet::class_hash::Felt252TryIntoClassHash;

const FEE_ONE_PERCENT: u128 = 0x28f5c28f5c28f5c28f5c28f5c28f5c2;

fn deploy_mock_token() -> IMockERC20Dispatcher {
    let constructor_calldata: Array<felt252> = ArrayTrait::new();
    let (token_address, _) = deploy_syscall(
        MockERC20::TEST_CLASS_HASH.try_into().unwrap(), 0, constructor_calldata.span(), true
    )
        .expect('token deploy failed');
    return IMockERC20Dispatcher { contract_address: token_address };
}

fn deploy_mock_extension(
    core: ICoreDispatcher, core_locker: ICoreLockerDispatcher
) -> IMockExtensionDispatcher {
    let mut constructor_args: Array<felt252> = ArrayTrait::new();
    constructor_args.append(core.contract_address.into());
    constructor_args.append(core_locker.contract_address.into());
    let (address, _) = deploy_syscall(
        MockExtension::TEST_CLASS_HASH.try_into().unwrap(), 2, constructor_args.span(), true
    )
        .expect('mockext deploy failed');

    IMockExtensionDispatcher { contract_address: address }
}

#[derive(Copy, Drop)]
struct SetupPoolResult {
    token0: IMockERC20Dispatcher,
    token1: IMockERC20Dispatcher,
    pool_key: PoolKey,
    core: ICoreDispatcher,
    locker: ICoreLockerDispatcher
}

fn deploy_core(owner: ContractAddress) -> ICoreDispatcher {
    let mut constructor_args: Array<felt252> = ArrayTrait::new();
    constructor_args.append(owner.into());

    let (core_address, _) = deploy_syscall(
        Core::TEST_CLASS_HASH.try_into().unwrap(), 1, constructor_args.span(), true
    )
        .expect('core deploy failed');

    ICoreDispatcher { contract_address: core_address }
}

fn deploy_locker(core: ICoreDispatcher) -> ICoreLockerDispatcher {
    let mut constructor_args: Array<felt252> = ArrayTrait::new();
    constructor_args.append(core.contract_address.into());
    let (locker_address, _) = deploy_syscall(
        CoreLocker::TEST_CLASS_HASH.try_into().unwrap(), 1, constructor_args.span(), true
    )
        .expect('locker deploy failed');

    ICoreLockerDispatcher { contract_address: locker_address }
}

impl IPositionsDispatcherIntoIERC721Dispatcher of Into<IPositionsDispatcher, IERC721Dispatcher> {
    fn into(self: IPositionsDispatcher) -> IERC721Dispatcher {
        IERC721Dispatcher { contract_address: self.contract_address }
    }
}

impl IPositionsDispatcherIntoILockerDispatcher of Into<IPositionsDispatcher, ILockerDispatcher> {
    fn into(self: IPositionsDispatcher) -> ILockerDispatcher {
        ILockerDispatcher { contract_address: self.contract_address }
    }
}

fn deploy_positions(core: ICoreDispatcher) -> IPositionsDispatcher {
    let mut constructor_args: Array<felt252> = ArrayTrait::new();
    constructor_args.append(core.contract_address.into());
    let (address, _) = deploy_syscall(
        Positions::TEST_CLASS_HASH.try_into().unwrap(), 1, constructor_args.span(), true
    )
        .expect('deploy failed');

    IPositionsDispatcher { contract_address: address }
}

fn setup_pool(
    owner: ContractAddress,
    fee: u128,
    tick_spacing: u128,
    initial_tick: i129,
    extension: ContractAddress
) -> SetupPoolResult {
    let mut token0 = deploy_mock_token();
    let mut token1 = deploy_mock_token();
    if (token0.contract_address > token1.contract_address) {
        let temp = token1;
        token1 = token0;
        token0 = temp;
    }

    let pool_key: PoolKey = PoolKey {
        token0: token0.contract_address,
        token1: token1.contract_address,
        fee,
        tick_spacing,
        extension
    };

    let core = deploy_core(owner);
    core.initialize_pool(pool_key, initial_tick);

    let locker = deploy_locker(core);

    SetupPoolResult { token0, token1, pool_key, core, locker }
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
fn get_balances(_setup: SetupPoolResult, recipient: ContractAddress) -> Balances {
    let token0_balance_core = _setup.token0.balance_of(_setup.core.contract_address);
    let token1_balance_core = _setup.token1.balance_of(_setup.core.contract_address);
    let token0_balance_recipient = _setup.token0.balance_of(recipient);
    let token1_balance_recipient = _setup.token1.balance_of(recipient);
    let token0_balance_locker = _setup.token0.balance_of(_setup.locker.contract_address);
    let token1_balance_locker = _setup.token1.balance_of(_setup.locker.contract_address);
    Balances {
        token0_balance_core,
        token1_balance_core,
        token0_balance_recipient,
        token1_balance_recipient,
        token0_balance_locker,
        token1_balance_locker,
    }
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

fn update_position(
    setup: SetupPoolResult, bounds: Bounds, liquidity_delta: i129, recipient: ContractAddress
) -> Delta {
    let before: Balances = get_balances(setup, recipient);
    match setup
        .locker
        .call(
            Action::UpdatePosition(
                (
                    setup.pool_key, UpdatePositionParameters {
                        bounds, liquidity_delta, salt: 0
                    }, recipient
                )
            )
        ) {
        ActionResult::AssertLockerId(_) => {
            assert(false, 'unexpected');
            Zeroable::zero()
        },
        ActionResult::Relock(_) => {
            assert(false, 'unexpected');
            Zeroable::zero()
        },
        ActionResult::UpdatePosition(delta) => {
            let after: Balances = get_balances(setup, recipient);
            assert_balances_delta(before, after, delta);
            delta
        },
        ActionResult::Swap(_) => {
            assert(false, 'unexpected');
            Zeroable::zero()
        },
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
    let before: Balances = get_balances(setup, recipient);

    match setup
        .locker
        .call(
            Action::Swap(
                (
                    setup.pool_key, SwapParameters {
                        amount, is_token1, sqrt_ratio_limit, skip_ahead
                    }, recipient
                )
            )
        ) {
        ActionResult::AssertLockerId(_) => {
            assert(false, 'unexpected');
            Zeroable::zero()
        },
        ActionResult::Relock(_) => {
            assert(false, 'unexpected');
            Zeroable::zero()
        },
        ActionResult::UpdatePosition(_) => {
            assert(false, 'unexpected');
            Zeroable::zero()
        },
        ActionResult::Swap(delta) => {
            let after: Balances = get_balances(setup, recipient);
            assert_balances_delta(before, after, delta);
            delta
        },
    }
}
