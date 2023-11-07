use debug::PrintTrait;
use ekubo::owner::owner;
use ekubo::extensions::twamm::{ITWAMMDispatcher, ITWAMMDispatcherTrait,};
use ekubo::interfaces::core::{ICoreDispatcherTrait, ICoreDispatcher, SwapParameters};
use ekubo::interfaces::erc721::{IERC721Dispatcher, IERC721DispatcherTrait};
use ekubo::simple_swapper::{ISimpleSwapperDispatcherTrait};
use ekubo::tests::helper::{deploy_core, deploy_twamm, deploy_two_mock_tokens};
use ekubo::tests::mocks::mock_erc20::{IMockERC20Dispatcher, IMockERC20DispatcherTrait};
use ekubo::tests::mocks::mock_upgradeable::{
    MockUpgradeable, IMockUpgradeableDispatcher, IMockUpgradeableDispatcherTrait
};
use ekubo::types::bounds::{Bounds};
use ekubo::types::call_points::{CallPoints};
use ekubo::types::i129::{i129};
use ekubo::types::keys::{PoolKey};
use ekubo::math::ticks::{constants as tick_constants, min_tick, max_tick};
use option::{OptionTrait};
use starknet::testing::{set_contract_address, set_block_timestamp, pop_log};
use starknet::{get_contract_address, get_block_timestamp, contract_address_const, ClassHash};
use traits::{TryInto, Into};
use zeroable::{Zeroable};

fn setup_pool_with_extension(order_block_interval: u64) -> (ICoreDispatcher, ITWAMMDispatcher) {
    let core = deploy_core();
    let twamm = deploy_twamm(core, order_block_interval);

    (core, ITWAMMDispatcher { contract_address: twamm.contract_address })
}

#[test]
#[available_gas(3000000000)]
fn test_replace_class_hash_can_be_called_by_owner() {
    let core = deploy_core();
    let twamm = deploy_twamm(core, 1_000_u64);

    let class_hash: ClassHash = MockUpgradeable::TEST_CLASS_HASH.try_into().unwrap();

    set_contract_address(owner());
    IMockUpgradeableDispatcher { contract_address: twamm.contract_address }
        .replace_class_hash(class_hash);

    let event: ekubo::upgradeable::Upgradeable::ClassHashReplaced = pop_log(twamm.contract_address)
        .unwrap();
    assert(event.new_class_hash == class_hash, 'event.class_hash');
}

#[test]
#[available_gas(3000000000)]
#[should_panic(expected: ('TICK_SPACING', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED'))]
fn test_before_initialize_pool_invalid_tick_spacing() {
    let core = deploy_core();
    let twamm = deploy_twamm(core, 1_000_u64);
    let (token0, token1) = deploy_two_mock_tokens();

    core
        .initialize_pool(
            PoolKey {
                token0: token0.contract_address,
                token1: token1.contract_address,
                fee: 0,
                tick_spacing: 1,
                extension: twamm.contract_address,
            },
            Zeroable::zero()
        );
}

#[test]
#[available_gas(3000000000)]
fn test_before_initialize_pool_valid_tick_spacing() {
    let core = deploy_core();
    let twamm = deploy_twamm(core, 1_000_u64);
    let (token0, token1) = deploy_two_mock_tokens();

    core
        .initialize_pool(
            PoolKey {
                token0: token0.contract_address,
                token1: token1.contract_address,
                fee: 0,
                tick_spacing: tick_constants::MAX_TICK_SPACING,
                extension: twamm.contract_address,
            },
            Zeroable::zero()
        );
}
