use core::integer::u256;
use core::num::traits::Zero;
use core::option::OptionTrait;
use core::result::ResultTrait;
use core::traits::{Into, TryInto};
use ekubo::components::util::serialize;
use ekubo::core::Core;
use ekubo::extensions::limit_orders::LimitOrders;
use ekubo::extensions::twamm::TWAMM;
use ekubo::interfaces::core::{
    ICoreDispatcher, ICoreDispatcherTrait, IExtensionDispatcher, ILockerDispatcher, SwapParameters,
    UpdatePositionParameters,
};
use ekubo::interfaces::erc721::IERC721Dispatcher;
use ekubo::interfaces::positions::IPositionsDispatcher;
use ekubo::interfaces::upgradeable::IUpgradeableDispatcher;
use ekubo::lens::token_registry::{ITokenRegistryDispatcher, TokenRegistry};
use ekubo::owned_nft::{IOwnedNFTDispatcher, OwnedNFT};
use ekubo::positions::Positions;
use ekubo::router::{IRouterDispatcher, Router};
use ekubo::tests::mock_erc20::{IMockERC20Dispatcher, MockERC20, MockERC20IERC20ImplTrait};
use ekubo::tests::mocks::locker::{
    Action, ActionResult, CoreLocker, ICoreLockerDispatcher, ICoreLockerDispatcherTrait,
};
use ekubo::tests::mocks::mock_extension::{IMockExtensionDispatcher, MockExtension};
use ekubo::tests::mocks::mock_upgradeable::MockUpgradeable;
use ekubo::types::bounds::Bounds;
use ekubo::types::call_points::CallPoints;
use ekubo::types::delta::Delta;
use ekubo::types::i129::i129;
use ekubo::types::keys::PoolKey;
use starknet::ContractAddress;
use starknet::syscalls::deploy_syscall;

pub const FEE_ONE_PERCENT: u128 = 0x28f5c28f5c28f5c28f5c28f5c28f5c2;

#[derive(Drop, Copy)]
pub struct Deployer {
    nonce: felt252,
}

impl DefaultDeployer of core::traits::Default<Deployer> {
    fn default() -> Deployer {
        Deployer { nonce: 0 }
    }
}


pub fn default_owner() -> ContractAddress {
    12121212121212.try_into().unwrap()
}


#[derive(Copy, Drop)]
pub struct SetupPoolResult {
    pub token0: IMockERC20Dispatcher,
    pub token1: IMockERC20Dispatcher,
    pub pool_key: PoolKey,
    pub core: ICoreDispatcher,
    pub locker: ICoreLockerDispatcher,
}

#[generate_trait]
pub impl DeployerTraitImpl of DeployerTrait {
    fn get_next_nonce(ref self: Deployer) -> felt252 {
        let nonce = self.nonce;
        self.nonce += 1;
        nonce
    }

    fn deploy_mock_token_with_balance_and_metadata(
        ref self: Deployer,
        owner: ContractAddress,
        starting_balance: u128,
        name: felt252,
        symbol: felt252,
    ) -> IMockERC20Dispatcher {
        let (address, _) = deploy_syscall(
            MockERC20::TEST_CLASS_HASH.try_into().unwrap(),
            self.get_next_nonce(),
            array![owner.into(), starting_balance.into(), name, symbol].span(),
            true,
        )
            .expect('token deploy failed');
        return IMockERC20Dispatcher { contract_address: address };
    }


    fn deploy_mock_token_with_balance(
        ref self: Deployer, owner: ContractAddress, starting_balance: u128,
    ) -> IMockERC20Dispatcher {
        self.deploy_mock_token_with_balance_and_metadata(owner, starting_balance, '', '')
    }

    fn deploy_mock_token(ref self: Deployer) -> IMockERC20Dispatcher {
        self.deploy_mock_token_with_balance(Zero::zero(), Zero::zero())
    }

    fn deploy_owned_nft(
        ref self: Deployer,
        owner: ContractAddress,
        name: felt252,
        symbol: felt252,
        token_uri_base: felt252,
    ) -> (IOwnedNFTDispatcher, IERC721Dispatcher) {
        let (address, _) = deploy_syscall(
            OwnedNFT::TEST_CLASS_HASH.try_into().unwrap(),
            self.get_next_nonce(),
            serialize(@(owner, name, symbol, token_uri_base)).span(),
            true,
        )
            .expect('nft deploy failed');
        return (
            IOwnedNFTDispatcher { contract_address: address },
            IERC721Dispatcher { contract_address: address },
        );
    }


    fn deploy_two_mock_tokens(ref self: Deployer) -> (IMockERC20Dispatcher, IMockERC20Dispatcher) {
        let tokenA = self.deploy_mock_token();
        let tokenB = self.deploy_mock_token();
        if (tokenA.contract_address < tokenB.contract_address) {
            (tokenA, tokenB)
        } else {
            (tokenB, tokenA)
        }
    }


    fn deploy_mock_extension(
        ref self: Deployer, core: ICoreDispatcher, call_points: CallPoints,
    ) -> IMockExtensionDispatcher {
        let (address, _) = deploy_syscall(
            MockExtension::TEST_CLASS_HASH.try_into().unwrap(),
            self.get_next_nonce(),
            serialize(@(core, call_points)).span(),
            true,
        )
            .expect('mockext deploy failed');

        IMockExtensionDispatcher { contract_address: address }
    }


    fn deploy_core(ref self: Deployer) -> ICoreDispatcher {
        let (address, _) = deploy_syscall(
            Core::TEST_CLASS_HASH.try_into().unwrap(),
            self.get_next_nonce(),
            serialize(@default_owner()).span(),
            true,
        )
            .expect('core deploy failed');
        return ICoreDispatcher { contract_address: address };
    }


    fn deploy_router(ref self: Deployer, core: ICoreDispatcher) -> IRouterDispatcher {
        let (address, _) = deploy_syscall(
            Router::TEST_CLASS_HASH.try_into().unwrap(),
            self.get_next_nonce(),
            serialize(@core).span(),
            true,
        )
            .expect('router deploy failed');

        IRouterDispatcher { contract_address: address }
    }


    fn deploy_locker(ref self: Deployer, core: ICoreDispatcher) -> ICoreLockerDispatcher {
        let (address, _) = deploy_syscall(
            CoreLocker::TEST_CLASS_HASH.try_into().unwrap(),
            self.get_next_nonce(),
            serialize(@core).span(),
            true,
        )
            .expect('locker deploy failed');

        ICoreLockerDispatcher { contract_address: address }
    }


    fn deploy_positions_custom_uri(
        ref self: Deployer, core: ICoreDispatcher, token_uri_base: felt252,
    ) -> IPositionsDispatcher {
        let (address, _) = deploy_syscall(
            Positions::TEST_CLASS_HASH.try_into().unwrap(),
            self.get_next_nonce(),
            serialize(@(default_owner(), core, OwnedNFT::TEST_CLASS_HASH, token_uri_base)).span(),
            true,
        )
            .expect('positions deploy failed');

        IPositionsDispatcher { contract_address: address }
    }

    fn deploy_positions(ref self: Deployer, core: ICoreDispatcher) -> IPositionsDispatcher {
        self.deploy_positions_custom_uri(core, 'https://z.ekubo.org/')
    }


    fn deploy_mock_upgradeable(ref self: Deployer) -> IUpgradeableDispatcher {
        let (address, _) = deploy_syscall(
            MockUpgradeable::TEST_CLASS_HASH.try_into().unwrap(),
            self.get_next_nonce(),
            serialize(@default_owner()).span(),
            true,
        )
            .expect('upgradeable deploy failed');
        return IUpgradeableDispatcher { contract_address: address };
    }


    fn deploy_twamm(ref self: Deployer, core: ICoreDispatcher) -> IExtensionDispatcher {
        let (address, _) = deploy_syscall(
            TWAMM::TEST_CLASS_HASH.try_into().unwrap(),
            self.get_next_nonce(),
            serialize(@(default_owner(), core)).span(),
            true,
        )
            .expect('twamm deploy failed');

        IExtensionDispatcher { contract_address: address }
    }


    fn deploy_limit_orders(ref self: Deployer, core: ICoreDispatcher) -> IExtensionDispatcher {
        let (address, _) = deploy_syscall(
            LimitOrders::TEST_CLASS_HASH.try_into().unwrap(),
            self.get_next_nonce(),
            serialize(@(default_owner(), core)).span(),
            true,
        )
            .expect('limit_orders deploy failed');

        IExtensionDispatcher { contract_address: address }
    }

    fn deploy_token_registry(
        ref self: Deployer, core: ICoreDispatcher,
    ) -> ITokenRegistryDispatcher {
        let (address, _) = deploy_syscall(
            TokenRegistry::TEST_CLASS_HASH.try_into().unwrap(),
            self.get_next_nonce(),
            array![core.contract_address.into()].span(),
            true,
        )
            .expect('token registry deploy');

        ITokenRegistryDispatcher { contract_address: address }
    }


    fn setup_pool(
        ref self: Deployer,
        fee: u128,
        tick_spacing: u128,
        initial_tick: i129,
        extension: ContractAddress,
    ) -> SetupPoolResult {
        let core = self.deploy_core();
        let locker = self.deploy_locker(core);
        let (token0, token1) = self.deploy_two_mock_tokens();

        let pool_key = PoolKey {
            token0: token0.contract_address,
            token1: token1.contract_address,
            fee,
            tick_spacing,
            extension,
        };

        core.initialize_pool(pool_key, initial_tick);

        SetupPoolResult { token0, token1, pool_key, core, locker }
    }

    fn setup_pool_with_core(
        ref self: Deployer,
        core: ICoreDispatcher,
        fee: u128,
        tick_spacing: u128,
        initial_tick: i129,
        extension: ContractAddress,
    ) -> SetupPoolResult {
        let locker = self.deploy_locker(core);
        let (token0, token1) = self.deploy_two_mock_tokens();

        let pool_key = PoolKey {
            token0: token0.contract_address,
            token1: token1.contract_address,
            fee,
            tick_spacing,
            extension,
        };

        core.initialize_pool(pool_key, initial_tick);

        SetupPoolResult { token0, token1, pool_key, core, locker }
    }
}


pub impl IPositionsDispatcherIntoILockerDispatcher of Into<
    IPositionsDispatcher, ILockerDispatcher,
> {
    fn into(self: IPositionsDispatcher) -> ILockerDispatcher {
        ILockerDispatcher { contract_address: self.contract_address }
    }
}


#[derive(Drop, Copy)]
pub struct Balances {
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
    recipient: ContractAddress,
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


pub fn diff(x: u256, y: u256) -> i129 {
    let (lower, upper) = if x < y {
        (x, y)
    } else {
        (y, x)
    };
    let diff = upper - lower;
    assert(diff.high == 0, 'diff_overflow');
    i129 { mag: diff.low, sign: (x < y) & (diff != 0) }
}

pub fn assert_balances_delta(before: Balances, after: Balances, delta: Delta) {
    assert(
        diff(after.token0_balance_core, before.token0_balance_core) == delta.amount0,
        'token0_balance_core',
    );
    assert(
        diff(after.token1_balance_core, before.token1_balance_core) == delta.amount1,
        'token1_balance_core',
    );

    if (delta.amount0.sign) {
        assert(
            diff(after.token0_balance_recipient, before.token0_balance_recipient) == -delta.amount0,
            'token0_balance_recipient',
        );
    } else {
        assert(
            diff(after.token0_balance_locker, before.token0_balance_locker) == -delta.amount0,
            'token0_balance_locker',
        );
    }
    if (delta.amount1.sign) {
        assert(
            diff(after.token1_balance_recipient, before.token1_balance_recipient) == -delta.amount1,
            'token1_balance_recipient',
        );
    } else {
        assert(
            diff(after.token1_balance_locker, before.token1_balance_locker) == -delta.amount1,
            'token1_balance_locker',
        );
    }
}

pub fn update_position_inner(
    core: ICoreDispatcher,
    pool_key: PoolKey,
    locker: ICoreLockerDispatcher,
    bounds: Bounds,
    liquidity_delta: i129,
    recipient: ContractAddress,
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
                (
                    pool_key,
                    UpdatePositionParameters { bounds, liquidity_delta, salt: 0 },
                    recipient,
                ),
            ),
        ) {
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
        _ => {
            assert(false, 'unexpected');
            Zero::zero()
        },
    }
}

pub fn flash_borrow_inner(
    core: ICoreDispatcher,
    locker: ICoreLockerDispatcher,
    token: ContractAddress,
    amount_borrow: u128,
    amount_repay: u128,
) {
    match locker.call(Action::FlashBorrow((token, amount_borrow, amount_repay))) {
        ActionResult::FlashBorrow(_) => {},
        _ => { assert(false, 'expected flash borrow'); },
    }
}

pub fn update_position(
    setup: SetupPoolResult, bounds: Bounds, liquidity_delta: i129, recipient: ContractAddress,
) -> Delta {
    update_position_inner(
        setup.core,
        setup.pool_key,
        setup.locker,
        bounds: bounds,
        liquidity_delta: liquidity_delta,
        recipient: recipient,
    )
}


pub fn accumulate_as_fees(setup: SetupPoolResult, amount0: u128, amount1: u128) {
    accumulate_as_fees_inner(setup.core, setup.pool_key, setup.locker, amount0, amount1)
}

pub fn accumulate_as_fees_inner(
    core: ICoreDispatcher,
    pool_key: PoolKey,
    locker: ICoreLockerDispatcher,
    amount0: u128,
    amount1: u128,
) {
    match locker.call(Action::AccumulateAsFees((pool_key, amount0, amount1))) {
        ActionResult::AccumulateAsFees => {},
        _ => { assert(false, 'unexpected') },
    }
}

pub fn swap_inner(
    core: ICoreDispatcher,
    pool_key: PoolKey,
    locker: ICoreLockerDispatcher,
    amount: i129,
    is_token1: bool,
    sqrt_ratio_limit: u256,
    recipient: ContractAddress,
    skip_ahead: u128,
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
                    recipient,
                ),
            ),
        ) {
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
        _ => {
            assert(false, 'unexpected');
            Zero::zero()
        },
    }
}

pub fn swap(
    setup: SetupPoolResult,
    amount: i129,
    is_token1: bool,
    sqrt_ratio_limit: u256,
    recipient: ContractAddress,
    skip_ahead: u128,
) -> Delta {
    swap_inner(
        setup.core,
        setup.pool_key,
        setup.locker,
        amount,
        is_token1,
        sqrt_ratio_limit,
        recipient,
        skip_ahead,
    )
}
