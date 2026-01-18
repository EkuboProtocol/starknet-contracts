use core::byte_array::ByteArray;
use core::integer::u256;
use core::num::traits::Zero;
use core::option::OptionTrait;
use core::result::ResultTrait;
use core::traits::{Into, TryInto};
use snforge_std::{
    CheatSpan, ContractClassTrait, DeclareResultTrait, EventSpy, EventSpyTrait,
    cheat_caller_address, declare, get_class_hash, spy_events, start_cheat_block_timestamp_global,
    start_cheat_caller_address, start_cheat_caller_address_global,
    stop_cheat_block_timestamp_global, stop_cheat_caller_address, stop_cheat_caller_address_global,
};
use starknet::{ClassHash, ContractAddress};
use crate::components::util::serialize;
use crate::interfaces::core::{
    ICoreDispatcher, ICoreDispatcherTrait, IExtensionDispatcher, ILockerDispatcher, SwapParameters,
    UpdatePositionParameters,
};
use crate::interfaces::erc721::IERC721Dispatcher;
use crate::interfaces::positions::IPositionsDispatcher;
use crate::interfaces::router::IRouterDispatcher;
use crate::interfaces::upgradeable::IUpgradeableDispatcher;
use crate::lens::token_registry::ITokenRegistryDispatcher;
use crate::owned_nft::IOwnedNFTDispatcher;
use crate::revenue_buybacks::{Config, IRevenueBuybacksDispatcher};
use crate::streamed_payment::IStreamedPaymentDispatcher;
use crate::tests::mock_erc20::{IMockERC20Dispatcher, MockERC20IERC20ImplTrait};
use crate::tests::mocks::locker::{
    Action, ActionResult, ICoreLockerDispatcher, ICoreLockerDispatcherTrait,
};
use crate::tests::mocks::mock_extension::IMockExtensionDispatcher;
use crate::types::bounds::Bounds;
use crate::types::call_points::CallPoints;
use crate::types::delta::Delta;
use crate::types::i129::i129;
use crate::types::keys::PoolKey;

pub const FEE_ONE_PERCENT: u128 = 0x28f5c28f5c28f5c28f5c28f5c28f5c2;

#[derive(Drop)]
pub struct EventLogger {
    spy: EventSpy,
    index: usize,
}

pub fn event_logger() -> EventLogger {
    EventLogger { spy: spy_events(), index: 0 }
}

#[generate_trait]
pub impl EventLoggerImpl of EventLoggerTrait {
    fn pop_log<T, +starknet::Event<T>, +Drop<T>>(
        ref self: EventLogger, address: ContractAddress,
    ) -> Option<T> {
        let events = self.spy.get_events().events;
        loop {
            if self.index >= events.len() {
                break Option::None;
            }
            let (from, event) = events.at(self.index);
            self.index += 1;
            if *from == address {
                let mut keys = event.keys.span();
                let mut data = event.data.span();
                match starknet::Event::deserialize(ref keys, ref data) {
                    Option::Some(ev) => { break Option::Some(ev); },
                    Option::None => { continue; },
                }
            }
        }
    }
}

#[derive(Drop, Copy)]
pub struct Deployer {
    nonce: felt252,
}

// Global storage to track deployed contract addresses for class hash re-declaration
// This is a simple approach - in practice, tests should call ensure_class_declared_for_contract
// for contracts they deploy, or we can scan known contract addresses
pub fn ensure_class_declared_for_contract(contract_address: ContractAddress) {
    // Get the class hash of the deployed contract
    let class_hash = get_class_hash(contract_address);
    // Declare the class by creating a ContractClass from the class hash
    // Note: This doesn't actually "declare" it, but ensures it's available
    // We still need to declare by name, but we can use this to track which classes are needed
    let _ = ContractClassTrait::new(class_hash);
}

impl DefaultDeployer of core::traits::Default<Deployer> {
    fn default() -> Deployer {
        Deployer { nonce: 0 }
    }
}


pub fn default_owner() -> ContractAddress {
    12121212121212.try_into().unwrap()
}

pub fn set_caller_address_global(caller: ContractAddress) {
    // Reset any previous cheat caller before setting the new one.
    stop_cheat_caller_address_global();
    start_cheat_caller_address_global(caller);
}

pub fn stop_caller_address_global() {
    stop_cheat_caller_address_global();
}

/// Sets the caller address for calls TO a specific contract only.
/// Unlike set_caller_address_global, this does NOT affect calls that the target
/// contract makes to other contracts (i.e., internal contract-to-contract calls
/// will use the real caller, not the cheated one).
///
/// Use this when you need to simulate a user calling a contract, but that contract
/// needs to make internal calls to other contracts that check the real caller.
pub fn set_caller_address(target_contract: ContractAddress, caller: ContractAddress) {
    stop_cheat_caller_address(target_contract);
    start_cheat_caller_address(target_contract, caller);
}

/// Stops the per-contract caller address cheat for the given contract.
pub fn stop_caller_address(target_contract: ContractAddress) {
    stop_cheat_caller_address(target_contract);
}

/// Helper function for tests that need to call positions/owned contracts.
/// Stops any global caller address cheat and ensures the test caller is set correctly
/// without affecting internal contract-to-contract calls.
pub fn setup_test_caller_for_positions(caller: ContractAddress) {
    stop_cheat_caller_address_global();
}

/// Sets the caller address for a specified number of calls to the target contract.
/// This is useful when the target contract makes internal calls (callbacks) that should
/// see the real caller, not the cheated one.
///
/// Use this when you need to simulate a user calling a contract that has lock/callback patterns
/// (like Core -> Positions.locked callbacks).
pub fn set_caller_address_for_calls(
    target_contract: ContractAddress, caller: ContractAddress, num_calls: usize,
) {
    let span: CheatSpan = CheatSpan::TargetCalls(
        num_calls.try_into().expect('num_calls must be > 0'),
    );
    cheat_caller_address(target_contract, caller, span);
}

/// Sets the caller address for a single call to the target contract.
pub fn set_caller_address_once(target_contract: ContractAddress, caller: ContractAddress) {
    let one: usize = 1;
    set_caller_address_for_calls(target_contract, caller, one);
}

pub fn set_block_timestamp_global(block_timestamp: u64) {
    // Reset any previous cheat timestamp before setting the new one.
    stop_cheat_block_timestamp_global();
    start_cheat_block_timestamp_global(block_timestamp);
}

pub fn stop_block_timestamp_global() {
    stop_cheat_block_timestamp_global();
}

/// Gets the declared class hash for a contract.
/// This ensures the class is declared and returns the actual runtime class hash
/// that can be used with library_call_syscall, even after multiple caller address changes.
///
/// IMPORTANT: This function must be called BEFORE any set_caller_address_global() calls
/// to ensure the declaration persists. If called after caller changes, the declaration
/// may not persist to library_call_syscall context.
///
/// `contract_name` - Name of the contract to declare (e.g., "Core", "Positions", "MockERC20")
/// Returns the ClassHash of the declared contract
pub fn get_declared_class_hash(contract_name: ByteArray) -> ClassHash {
    let declare_result = declare(contract_name).expect('Failed to declare contract');
    let contract_class = declare_result.contract_class();
    *contract_class.class_hash
}

/// Ensures a class is declared before caller address changes.
/// This should be called early in tests that use replace_class_hash or library calls.
///
/// `contract_name` - Name of the contract to declare (e.g., "Core", "Positions", "MockERC20")
/// Returns the ClassHash of the declared contract
pub fn ensure_class_declared(contract_name: ByteArray) -> ClassHash {
    get_declared_class_hash(contract_name)
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
        let contract = declare("MockERC20").unwrap().contract_class();
        let (address, _) = contract
            .deploy(@array![owner.into(), starting_balance.into(), name, symbol])
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
        let contract = declare("OwnedNFT").unwrap().contract_class();
        let (address, _) = contract
            .deploy(@serialize(@(owner, name, symbol, token_uri_base)))
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
        let contract = declare("MockExtension").unwrap().contract_class();
        let (address, _) = contract
            .deploy(@serialize(@(core, call_points)))
            .expect('mockext deploy failed');

        IMockExtensionDispatcher { contract_address: address }
    }


    fn deploy_core(ref self: Deployer) -> ICoreDispatcher {
        let contract = declare("Core").unwrap().contract_class();
        let (address, _) = contract
            .deploy(@serialize(@default_owner()))
            .expect('core deploy failed');
        return ICoreDispatcher { contract_address: address };
    }


    fn deploy_router(ref self: Deployer, core: ICoreDispatcher) -> IRouterDispatcher {
        let contract = declare("Router").unwrap().contract_class();
        let (address, _) = contract.deploy(@serialize(@core)).expect('router deploy failed');

        IRouterDispatcher { contract_address: address }
    }


    fn deploy_locker(ref self: Deployer, core: ICoreDispatcher) -> ICoreLockerDispatcher {
        let contract = declare("CoreLocker").unwrap().contract_class();
        let (address, _) = contract.deploy(@serialize(@core)).expect('locker deploy failed');

        ICoreLockerDispatcher { contract_address: address }
    }


    fn deploy_positions_custom_uri(
        ref self: Deployer, core: ICoreDispatcher, token_uri_base: felt252,
    ) -> IPositionsDispatcher {
        // Declare OwnedNFT first to get the actual class hash that's declared in the test runtime.
        // Using TEST_CLASS_HASH would fail because it's not declared.
        let owned_nft_class = declare("OwnedNFT").unwrap().contract_class();
        let contract = declare("Positions").unwrap().contract_class();
        let (address, _) = contract
            .deploy(
                @serialize(@(default_owner(), core, *owned_nft_class.class_hash, token_uri_base)),
            )
            .expect('positions deploy failed');

        IPositionsDispatcher { contract_address: address }
    }

    fn deploy_positions(ref self: Deployer, core: ICoreDispatcher) -> IPositionsDispatcher {
        self.deploy_positions_custom_uri(core, 'https://z.ekubo.org/')
    }


    fn deploy_mock_upgradeable(ref self: Deployer) -> IUpgradeableDispatcher {
        let contract = declare("MockUpgradeable").unwrap().contract_class();
        let (address, _) = contract
            .deploy(@serialize(@default_owner()))
            .expect('upgradeable deploy failed');
        return IUpgradeableDispatcher { contract_address: address };
    }


    fn deploy_twamm(ref self: Deployer, core: ICoreDispatcher) -> IExtensionDispatcher {
        let contract = declare("TWAMM").unwrap().contract_class();
        let (address, _) = contract
            .deploy(@serialize(@(default_owner(), core)))
            .expect('twamm deploy failed');

        IExtensionDispatcher { contract_address: address }
    }


    fn deploy_limit_orders(ref self: Deployer, core: ICoreDispatcher) -> IExtensionDispatcher {
        let contract = declare("LimitOrders").unwrap().contract_class();
        let (address, _) = contract
            .deploy(@serialize(@(default_owner(), core)))
            .expect('limit_orders deploy failed');

        IExtensionDispatcher { contract_address: address }
    }

    fn deploy_token_registry(
        ref self: Deployer, core: ICoreDispatcher,
    ) -> ITokenRegistryDispatcher {
        let contract = declare("TokenRegistry").unwrap().contract_class();
        let (address, _) = contract
            .deploy(@array![core.contract_address.into()])
            .expect('token registry deploy');

        ITokenRegistryDispatcher { contract_address: address }
    }

    fn deploy_streamed_payment(ref self: Deployer) -> IStreamedPaymentDispatcher {
        let contract = declare("StreamedPayment").unwrap().contract_class();

        let (address, _) = contract.deploy(@array![]).expect('streamed payment deploy');

        IStreamedPaymentDispatcher { contract_address: address }
    }

    fn deploy_revenue_buybacks(
        ref self: Deployer,
        owner: ContractAddress,
        core: ICoreDispatcher,
        positions: IPositionsDispatcher,
        default_config: Option<Config>,
    ) -> IRevenueBuybacksDispatcher {
        let contract = declare("RevenueBuybacks").unwrap().contract_class();
        let (address, _) = contract
            .deploy(@serialize(@(owner, core, positions, default_config)))
            .expect('revenue buybacks deploy');

        IRevenueBuybacksDispatcher { contract_address: address }
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
