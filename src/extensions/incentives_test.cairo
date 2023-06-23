use ekubo::interfaces::positions::IPositionsDispatcherTrait;
use ekubo::interfaces::core::{ICoreDispatcherTrait, ICoreDispatcher};
use ekubo::tests::mocks::mock_erc20::{IMockERC20Dispatcher, IMockERC20DispatcherTrait};
use ekubo::tests::helper::{
    deploy_core, deploy_positions, deploy_incentives, deploy_two_mock_tokens
};
use ekubo::types::keys::{PoolKey};
use ekubo::types::i129::{i129};
use ekubo::types::bounds::{Bounds};
use ekubo::types::call_points::{CallPoints};
use starknet::{get_contract_address};

fn setup_pool_with_extension() -> (ICoreDispatcher, PoolKey) {
    let core = deploy_core();
    let incentives = deploy_incentives(core);
    let (token0, token1) = deploy_two_mock_tokens();

    let key = PoolKey {
        token0: token0.contract_address,
        token1: token1.contract_address,
        fee: 0,
        tick_spacing: 1,
        extension: incentives.contract_address,
    };

    core.initialize_pool(key, Zeroable::zero());

    (core, key)
}

#[test]
#[available_gas(300000000)]
fn test_before_initialize_call_points() {
    let (core, key) = setup_pool_with_extension();

    let pool = core.get_pool(key);

    assert(
        pool.call_points == CallPoints {
            after_initialize_pool: false,
            before_swap: true,
            after_swap: true,
            before_update_position: true,
            after_update_position: false,
        },
        'call points'
    );
}

#[test]
#[available_gas(300000000)]
fn test_add_liquidity() {
    let (core, key) = setup_pool_with_extension();

    let positions = deploy_positions(core);

    positions
        .mint(
            recipient: get_contract_address(),
            pool_key: key,
            bounds: Bounds {
                lower: i129 { mag: 100, sign: true }, upper: i129 { mag: 100, sign: false }
            }
        );
}
