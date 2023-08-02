use ekubo::interfaces::positions::{IPositionsDispatcher, IPositionsDispatcherTrait};
use ekubo::interfaces::core::{ICoreDispatcherTrait, ICoreDispatcher};
use ekubo::extensions::limit_orders::{ILimitOrdersDispatcher, ILimitOrdersDispatcherTrait};
use ekubo::tests::mocks::mock_erc20::{IMockERC20Dispatcher, IMockERC20DispatcherTrait};
use ekubo::tests::helper::{
    deploy_core, deploy_positions, deploy_limit_orders, deploy_two_mock_tokens, swap_inner,
    deploy_locker
};
use ekubo::types::keys::{PoolKey, PositionKey};
use ekubo::types::i129::{i129};
use ekubo::types::bounds::{Bounds};
use ekubo::types::call_points::{CallPoints};
use starknet::{get_contract_address, get_block_timestamp, contract_address_const};
use starknet::testing::{set_contract_address, set_block_timestamp};
use option::{OptionTrait};
use traits::{TryInto};
use zeroable::{Zeroable};
use ekubo::math::liquidity::{liquidity_delta_to_amount_delta};
use ekubo::math::ticks::{tick_to_sqrt_ratio};
use debug::PrintTrait;

fn setup_pool_with_extension(
    initial_tick: i129
) -> (ICoreDispatcher, ILimitOrdersDispatcher, PoolKey) {
    let core = deploy_core();
    let limit_orders = deploy_limit_orders(core);
    let (token0, token1) = deploy_two_mock_tokens();

    let key = PoolKey {
        token0: token0.contract_address,
        token1: token1.contract_address,
        fee: 0,
        tick_spacing: 1,
        extension: limit_orders.contract_address,
    };

    core.initialize_pool(key, initial_tick);

    (core, ILimitOrdersDispatcher { contract_address: limit_orders.contract_address }, key)
}

#[test]
#[available_gas(3000000000)]
fn test_deploy() {
    let (core, lo, pk) = setup_pool_with_extension(Zeroable::zero());
}
