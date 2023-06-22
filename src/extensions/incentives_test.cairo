use ekubo::interfaces::core::{ICoreDispatcherTrait};
use ekubo::tests::helper::{deploy_core, deploy_incentives, deploy_two_mock_tokens};
use ekubo::extensions::incentives::{IIncentivesDispatcherTrait};
use ekubo::types::keys::{PoolKey};
use ekubo::types::call_points::{CallPoints};

#[test]
#[available_gas(300000000)]
fn test_before_initialize_incentives() {
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

    core.initialize_pool(key, Zeroable::zero(), );

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
