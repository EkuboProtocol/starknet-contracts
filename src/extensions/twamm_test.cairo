use debug::PrintTrait;
use ekubo::owner::owner;
use ekubo::extensions::twamm::{ITWAMMDispatcher, ITWAMMDispatcherTrait,};
use ekubo::interfaces::core::{ICoreDispatcherTrait, ICoreDispatcher, SwapParameters};
use ekubo::interfaces::erc721::{IERC721Dispatcher, IERC721DispatcherTrait};
use ekubo::simple_swapper::{ISimpleSwapperDispatcherTrait};
use ekubo::tests::helper::{
    deploy_core, deploy_twamm, deploy_two_mock_tokens, deploy_positions, setup_pool_with_core,
    update_position
};
use ekubo::tests::mocks::mock_erc20::{IMockERC20Dispatcher, IMockERC20DispatcherTrait};
use ekubo::tests::mocks::mock_upgradeable::{
    MockUpgradeable, IMockUpgradeableDispatcher, IMockUpgradeableDispatcherTrait
};
use ekubo::tests::mocks::locker::{UpdatePositionParameters};
use ekubo::types::bounds::{Bounds, max_bounds};
use ekubo::interfaces::positions::{
    IPositionsDispatcher, IPositionsDispatcherTrait, GetTokenInfoResult, GetTokenInfoRequest
};
use ekubo::types::call_points::{CallPoints};
use ekubo::types::i129::{i129};
use ekubo::types::keys::{PoolKey};
use ekubo::math::ticks::{tick_to_sqrt_ratio};
use ekubo::math::ticks::constants::{MAX_TICK_SPACING, TICKS_IN_ONE_PERCENT};
use ekubo::math::max_liquidity::{max_liquidity};
use ekubo::math::ticks::{min_tick, max_tick};
use ekubo::extensions::twamm::{OrderKey, TokenKey};
use ekubo::extensions::twamm::TWAMM::{to_token_key};
use option::{OptionTrait};
use starknet::testing::{set_contract_address, set_block_timestamp, pop_log};
use starknet::{get_contract_address, get_block_timestamp, contract_address_const, ClassHash};
use traits::{TryInto, Into};
use zeroable::{Zeroable};

mod UpgradableTest {
    use super::{
        deploy_core, deploy_twamm, deploy_two_mock_tokens, deploy_positions, setup_pool_with_core,
        update_position, ClassHash, MockUpgradeable, IMockUpgradeableDispatcher,
        IMockUpgradeableDispatcherTrait, set_contract_address, owner, pop_log
    };

    #[test]
    #[available_gas(3000000000)]
    fn test_replace_class_hash_can_be_called_by_owner() {
        let core = deploy_core();
        let twamm = deploy_twamm(core);

        let class_hash: ClassHash = MockUpgradeable::TEST_CLASS_HASH.try_into().unwrap();

        set_contract_address(owner());
        IMockUpgradeableDispatcher { contract_address: twamm.contract_address }
            .replace_class_hash(class_hash);

        let event: ekubo::upgradeable::Upgradeable::ClassHashReplaced = pop_log(
            twamm.contract_address
        )
            .unwrap();
        assert(event.new_class_hash == class_hash, 'event.class_hash');
    }
}

mod PoolTests {
    use super::{
        deploy_core, deploy_twamm, deploy_two_mock_tokens, deploy_positions, setup_pool_with_core,
        update_position, ClassHash, MockUpgradeable, IMockUpgradeableDispatcher,
        IMockUpgradeableDispatcherTrait, set_contract_address, owner, pop_log, IPositionsDispatcher,
        IPositionsDispatcherTrait, ICoreDispatcher, ICoreDispatcherTrait, PoolKey, MAX_TICK_SPACING,
        max_bounds, IMockERC20Dispatcher, IMockERC20DispatcherTrait, max_liquidity,
        contract_address_const, tick_to_sqrt_ratio, Bounds, i129, TICKS_IN_ONE_PERCENT
    };

    #[test]
    #[available_gas(3000000000)]
    #[should_panic(expected: ('TICK_SPACING', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED'))]
    fn test_before_initialize_pool_invalid_tick_spacing() {
        let core = deploy_core();
        let twamm = deploy_twamm(core);
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
        let twamm = deploy_twamm(core);
        let (token0, token1) = deploy_two_mock_tokens();

        core
            .initialize_pool(
                PoolKey {
                    token0: token0.contract_address,
                    token1: token1.contract_address,
                    fee: 0,
                    tick_spacing: MAX_TICK_SPACING,
                    extension: twamm.contract_address,
                },
                Zeroable::zero()
            );
    }

    #[test]
    #[available_gas(3000000000)]
    #[should_panic(
        expected: (
            'BOUNDS',
            'ENTRYPOINT_FAILED',
            'ENTRYPOINT_FAILED',
            'ENTRYPOINT_FAILED',
            'ENTRYPOINT_FAILED',
            'ENTRYPOINT_FAILED'
        )
    )]
    fn test_before_update_position_invalid_bounds() {
        let core = deploy_core();
        let twamm = deploy_twamm(core);

        let caller = contract_address_const::<42>();
        set_contract_address(caller);

        let setup = setup_pool_with_core(
            core,
            fee: 0,
            tick_spacing: MAX_TICK_SPACING,
            initial_tick: Zeroable::zero(),
            extension: twamm.contract_address,
        );
        let positions = deploy_positions(setup.core);
        let bounds = max_bounds(MAX_TICK_SPACING);

        setup.token0.increase_balance(positions.contract_address, 100_000_000);
        setup.token1.increase_balance(positions.contract_address, 100_000_000);

        let price = core.get_pool_price(pool_key: setup.pool_key);
        let max_liquidity = max_liquidity(
            price.sqrt_ratio,
            tick_to_sqrt_ratio(bounds.lower),
            tick_to_sqrt_ratio(bounds.upper),
            100_000_000,
            100_000_000,
        );

        let (token_id, liquidity) = positions
            .mint_and_deposit(
                pool_key: setup.pool_key, bounds: bounds, min_liquidity: max_liquidity
            );

        update_position(
            setup,
            bounds: Bounds {
                lower: i129 { mag: TICKS_IN_ONE_PERCENT * 1, sign: true },
                upper: i129 { mag: TICKS_IN_ONE_PERCENT * 10, sign: false },
            },
            liquidity_delta: i129 { mag: 1, sign: false },
            recipient: caller,
        );
    }

    #[test]
    #[available_gas(3000000000)]
    fn test_before_update_position_valid_bounds() {
        let core = deploy_core();
        let twamm = deploy_twamm(core);

        let caller = contract_address_const::<42>();
        set_contract_address(caller);

        let setup = setup_pool_with_core(
            core,
            fee: 0,
            tick_spacing: MAX_TICK_SPACING,
            initial_tick: Zeroable::zero(),
            extension: twamm.contract_address,
        );
        let positions = deploy_positions(setup.core);
        let bounds = max_bounds(MAX_TICK_SPACING);

        setup.token0.increase_balance(positions.contract_address, 100_000_000);
        setup.token1.increase_balance(positions.contract_address, 100_000_000);

        let price = core.get_pool_price(pool_key: setup.pool_key);
        let max_liquidity = max_liquidity(
            price.sqrt_ratio,
            tick_to_sqrt_ratio(bounds.lower),
            tick_to_sqrt_ratio(bounds.upper),
            100_000_000,
            100_000_000,
        );

        let (token_id, liquidity) = positions
            .mint_and_deposit(
                pool_key: setup.pool_key, bounds: bounds, min_liquidity: max_liquidity
            );

        setup.token0.increase_balance(setup.locker.contract_address, 100_000_000);
        setup.token1.increase_balance(setup.locker.contract_address, 100_000_000);
        update_position(
            setup,
            bounds,
            liquidity_delta: i129 { mag: max_liquidity, sign: false },
            recipient: caller,
        );
    }
}

mod PlaceOrderTestsValidateExpiryTime {
    use super::{
        PrintTrait, deploy_core, deploy_twamm, deploy_two_mock_tokens, ICoreDispatcher,
        ICoreDispatcherTrait, PoolKey, MAX_TICK_SPACING, ITWAMMDispatcher, ITWAMMDispatcherTrait,
        OrderKey, get_block_timestamp, set_block_timestamp, pop_log, to_token_key,
        IMockERC20Dispatcher, IMockERC20DispatcherTrait
    };

    #[test]
    #[available_gas(3000000000)]
    #[should_panic(expected: ('INVALID_EXPIRY_TIME', 'ENTRYPOINT_FAILED'))]
    fn test_place_order_at_timestamp() {
        let core = deploy_core();
        let twamm = deploy_twamm(core);
        let (token0, token1) = deploy_two_mock_tokens();

        let order_key = OrderKey {
            // current timestamp is 0
            token0: token0.contract_address, token1: token1.contract_address, expiry_time: 0
        };

        let amount = 100_000_000;
        token0.increase_balance(core.contract_address, amount);
        let token_id = ITWAMMDispatcher { contract_address: twamm.contract_address }
            .place_order(order_key, amount);
    }

    #[test]
    #[available_gas(3000000000)]
    fn test_place_order_expiry_validation() {
        // the tests take too long so we run only the first and last test in each section
        // however, they are all valid/passing

        // timestamp is multiple of 16**N

        // run_place_order_and_validate_expiry(timestamp: 0);
        // run_place_order_and_validate_expiry(timestamp: 16);
        // run_place_order_and_validate_expiry(timestamp: 16 * 16);
        // run_place_order_and_validate_expiry(timestamp: 16 * 16 * 16);
        // run_place_order_and_validate_expiry(timestamp: 16 * 16 * 16 * 16);
        // run_place_order_and_validate_expiry(timestamp: 16 * 16 * 16 * 16 * 16);
        // run_place_order_and_validate_expiry(timestamp: 16 * 16 * 16 * 16 * 16 * 16);
        run_place_order_and_validate_expiry(timestamp: 16 * 16 * 16 * 16 * 16 * 16 * 16);

        // timestamp is not multiple of 16**N

        // run_place_order_and_validate_expiry(timestamp: 1);
        // run_place_order_and_validate_expiry(timestamp: 100);
        // run_place_order_and_validate_expiry(timestamp: 1_000);
        // run_place_order_and_validate_expiry(timestamp: 1_000_000);
        // run_place_order_and_validate_expiry(timestamp: 1_000_000_000);
        // run_place_order_and_validate_expiry(timestamp: 1_000_000_000_000);
        run_place_order_and_validate_expiry(timestamp: 1_000_000_000_000_000);
    }

    fn run_place_order_and_validate_expiry(timestamp: u64) {
        set_block_timestamp(timestamp);

        let core = deploy_core();
        let twamm = deploy_twamm(core);
        let (token0, token1) = deploy_two_mock_tokens();

        let amount = 100_000_000;

        // orders expire in <= 16**1 seconds 
        // allow 16**0 = 1 second precision

        let mut prev_interval = 0;
        let mut interval = 16;
        let mut step = 1;
        let mut order_key = OrderKey {
            token0: token0.contract_address,
            token1: token1.contract_address,
            // first valid expiry time in interval
            expiry_time: timestamp + prev_interval + step // t + 0 + 1
        };
        token0.increase_balance(core.contract_address, amount);
        let mut token_id = ITWAMMDispatcher { contract_address: twamm.contract_address }
            .place_order(order_key, amount);
        let mut order = ITWAMMDispatcher { contract_address: twamm.contract_address }
            .get_order_state(order_key, token_id,);
        assert(
            order.expiry_time == order_key.expiry_time
                || order.expiry_time == (order_key.expiry_time - (order_key.expiry_time % step)),
            'EXPIRY_TIME'
        );

        order_key =
            OrderKey {
                token0: token0.contract_address,
                token1: token1.contract_address,
                // last valid expiry time in interval
                expiry_time: timestamp + interval - step // t + 16**1 - 1
            };
        token0.increase_balance(core.contract_address, amount);
        token_id = ITWAMMDispatcher { contract_address: twamm.contract_address }
            .place_order(order_key, amount);
        order = ITWAMMDispatcher { contract_address: twamm.contract_address }
            .get_order_state(order_key, token_id,);
        assert(
            order.expiry_time == order_key.expiry_time
                || order.expiry_time == (order_key.expiry_time - (order_key.expiry_time % step)),
            'EXPIRY_TIME'
        );

        // orders expire in <= 16**2 = 256 seconds (~4.2min),
        // allow 16**1 = 16 seconds precision

        prev_interval = interval;
        interval = 16 * 16;
        step = 16;
        order_key =
            OrderKey {
                token0: token0.contract_address,
                token1: token1.contract_address,
                // first valid expiry time in interval
                expiry_time: timestamp + prev_interval + step // t + 16**1 + 16
            };
        token0.increase_balance(core.contract_address, amount);
        token_id = ITWAMMDispatcher { contract_address: twamm.contract_address }
            .place_order(order_key, amount);
        order = ITWAMMDispatcher { contract_address: twamm.contract_address }
            .get_order_state(order_key, token_id,);
        assert(
            order.expiry_time == order_key.expiry_time
                || order.expiry_time == (order_key.expiry_time - (order_key.expiry_time % step)),
            'EXPIRY_TIME'
        );

        order_key =
            OrderKey {
                token0: token0.contract_address,
                token1: token1.contract_address,
                // last valid expiry time in interval
                expiry_time: timestamp + interval - step // t + 16**2 - 16**1
            };
        token0.increase_balance(core.contract_address, amount);
        token_id = ITWAMMDispatcher { contract_address: twamm.contract_address }
            .place_order(order_key, amount);
        order = ITWAMMDispatcher { contract_address: twamm.contract_address }
            .get_order_state(order_key, token_id,);
        assert(
            order.expiry_time == order_key.expiry_time
                || order.expiry_time == (order_key.expiry_time - (order_key.expiry_time % step)),
            'EXPIRY_TIME'
        );

        // orders expire in <= 16**3 = 4,096 seconds (~1hr),
        // allow 16**2 = 256 seconds (~4.2min) precision

        prev_interval = interval;
        interval = 16 * 16 * 16;
        step = 16 * 16;
        order_key =
            OrderKey {
                token0: token0.contract_address,
                token1: token1.contract_address,
                // first valid expiry time in interval
                expiry_time: timestamp + prev_interval + step // t + 16**2 + 16**2
            };
        token0.increase_balance(core.contract_address, amount);
        token_id = ITWAMMDispatcher { contract_address: twamm.contract_address }
            .place_order(order_key, amount);
        order = ITWAMMDispatcher { contract_address: twamm.contract_address }
            .get_order_state(order_key, token_id,);
        assert(
            order.expiry_time == order_key.expiry_time
                || order.expiry_time == (order_key.expiry_time - (order_key.expiry_time % step)),
            'EXPIRY_TIME'
        );

        order_key =
            OrderKey {
                token0: token0.contract_address,
                token1: token1.contract_address,
                // last valid expiry time in interval
                expiry_time: timestamp + interval - step // t + 16**3 - 16**2
            };
        token0.increase_balance(core.contract_address, amount);
        token_id = ITWAMMDispatcher { contract_address: twamm.contract_address }
            .place_order(order_key, amount);
        order = ITWAMMDispatcher { contract_address: twamm.contract_address }
            .get_order_state(order_key, token_id,);
        assert(
            order.expiry_time == order_key.expiry_time
                || order.expiry_time == (order_key.expiry_time - (order_key.expiry_time % step)),
            'EXPIRY_TIME'
        );

        // orders expire in <= 16**4 = 65,536 seconds (~18hrs),
        // allow 16**3 = 4,096 seconds (~1hr) precision

        prev_interval = interval;
        interval = 16 * 16 * 16 * 16;
        step = 16 * 16 * 16;
        order_key =
            OrderKey {
                token0: token0.contract_address,
                token1: token1.contract_address,
                // first valid expiry time in interval
                expiry_time: timestamp + prev_interval + step // t + 16**3 + 16**3
            };
        token0.increase_balance(core.contract_address, amount);
        token_id = ITWAMMDispatcher { contract_address: twamm.contract_address }
            .place_order(order_key, amount);
        order = ITWAMMDispatcher { contract_address: twamm.contract_address }
            .get_order_state(order_key, token_id,);
        assert(
            order.expiry_time == order_key.expiry_time
                || order.expiry_time == (order_key.expiry_time - (order_key.expiry_time % step)),
            'EXPIRY_TIME'
        );
        order_key =
            OrderKey {
                token0: token0.contract_address,
                token1: token1.contract_address,
                // last valid expiry time in interval
                expiry_time: timestamp + interval - step // t + 16**4 - 16**3
            };
        token0.increase_balance(core.contract_address, amount);
        token_id = ITWAMMDispatcher { contract_address: twamm.contract_address }
            .place_order(order_key, amount);
        order = ITWAMMDispatcher { contract_address: twamm.contract_address }
            .get_order_state(order_key, token_id,);
        assert(
            order.expiry_time == order_key.expiry_time
                || order.expiry_time == (order_key.expiry_time - (order_key.expiry_time % step)),
            'EXPIRY_TIME'
        );

        // orders expire in <= 16**5 = 1,048,576 seconds (~12 days),
        // allow 16**4 = 65,536 seconds (~18hrs) precision

        prev_interval = interval;
        interval = 16 * 16 * 16 * 16 * 16;
        step = 16 * 16 * 16 * 16;
        order_key =
            OrderKey {
                token0: token0.contract_address,
                token1: token1.contract_address,
                // first valid expiry time in interval
                expiry_time: timestamp + prev_interval + step // t + 16**4 + 16**4
            };
        token0.increase_balance(core.contract_address, amount);
        token_id = ITWAMMDispatcher { contract_address: twamm.contract_address }
            .place_order(order_key, amount);
        order = ITWAMMDispatcher { contract_address: twamm.contract_address }
            .get_order_state(order_key, token_id,);
        assert(
            order.expiry_time == order_key.expiry_time
                || order.expiry_time == (order_key.expiry_time - (order_key.expiry_time % step)),
            'EXPIRY_TIME'
        );

        order_key =
            OrderKey {
                token0: token0.contract_address,
                token1: token1.contract_address,
                // last valid expiry time in interval
                expiry_time: timestamp + interval - step // t + 16**5 - 16**4
            };
        token0.increase_balance(core.contract_address, amount);
        token_id = ITWAMMDispatcher { contract_address: twamm.contract_address }
            .place_order(order_key, amount);
        order = ITWAMMDispatcher { contract_address: twamm.contract_address }
            .get_order_state(order_key, token_id,);
        assert(
            order.expiry_time == order_key.expiry_time
                || order.expiry_time == (order_key.expiry_time - (order_key.expiry_time % step)),
            'EXPIRY_TIME'
        );

        // orders expire in <= 16**6 = 16,777,216 seconds (~6.4 months),
        // allow 16**5 = 1,048,576 seconds (~12 days) precision

        prev_interval = interval;
        interval = 16 * 16 * 16 * 16 * 16 * 16;
        step = 16 * 16 * 16 * 16 * 16;
        order_key =
            OrderKey {
                token0: token0.contract_address,
                token1: token1.contract_address,
                // first valid expiry time in interval
                expiry_time: timestamp + prev_interval + step // t + 16**5 + 16**5
            };
        token0.increase_balance(core.contract_address, amount);
        token_id = ITWAMMDispatcher { contract_address: twamm.contract_address }
            .place_order(order_key, amount);
        order = ITWAMMDispatcher { contract_address: twamm.contract_address }
            .get_order_state(order_key, token_id,);
        assert(
            order.expiry_time == order_key.expiry_time
                || order.expiry_time == (order_key.expiry_time - (order_key.expiry_time % step)),
            'EXPIRY_TIME'
        );

        order_key =
            OrderKey {
                token0: token0.contract_address,
                token1: token1.contract_address,
                // last valid expiry time in interval
                expiry_time: timestamp + interval - step // t + 16**6 - 16**5
            };
        token0.increase_balance(core.contract_address, amount);
        token_id = ITWAMMDispatcher { contract_address: twamm.contract_address }
            .place_order(order_key, amount);
        order = ITWAMMDispatcher { contract_address: twamm.contract_address }
            .get_order_state(order_key, token_id,);
        assert(
            order.expiry_time == order_key.expiry_time
                || order.expiry_time == (order_key.expiry_time - (order_key.expiry_time % step)),
            'EXPIRY_TIME'
        );

        // orders expire in <= 16**7 = 268,435,456 seconds (~8.5 years),
        // allow 16**6 = 16,777,216 (~6.4 month) precision
        // unlikely to be used in practice

        prev_interval = interval;
        interval = 16 * 16 * 16 * 16 * 16 * 16 * 16;
        step = 16 * 16 * 16 * 16 * 16 * 16;
        order_key =
            OrderKey {
                token0: token0.contract_address,
                token1: token1.contract_address,
                // first valid expiry time in interval
                expiry_time: timestamp + prev_interval + step // t + 16**6 + 16**6
            };
        token0.increase_balance(core.contract_address, amount);
        token_id = ITWAMMDispatcher { contract_address: twamm.contract_address }
            .place_order(order_key, amount);
        order = ITWAMMDispatcher { contract_address: twamm.contract_address }
            .get_order_state(order_key, token_id,);
        assert(
            order.expiry_time == order_key.expiry_time
                || order.expiry_time == (order_key.expiry_time - (order_key.expiry_time % step)),
            'EXPIRY_TIME'
        );

        order_key =
            OrderKey {
                token0: token0.contract_address,
                token1: token1.contract_address,
                // last valid expiry time in interval
                expiry_time: timestamp + interval - step // t + 16**7 - 16**6
            };
        token0.increase_balance(core.contract_address, amount);
        token_id = ITWAMMDispatcher { contract_address: twamm.contract_address }
            .place_order(order_key, amount);
        order = ITWAMMDispatcher { contract_address: twamm.contract_address }
            .get_order_state(order_key, token_id,);
        assert(
            order.expiry_time == order_key.expiry_time
                || order.expiry_time == (order_key.expiry_time - (order_key.expiry_time % step)),
            'EXPIRY_TIME'
        );
    }
}

mod PlaceOrderTests {
    use super::{
        PrintTrait, deploy_core, deploy_twamm, deploy_two_mock_tokens, ICoreDispatcher,
        ICoreDispatcherTrait, PoolKey, MAX_TICK_SPACING, ITWAMMDispatcher, ITWAMMDispatcherTrait,
        OrderKey, get_block_timestamp, set_block_timestamp, pop_log, to_token_key,
        IMockERC20Dispatcher, IMockERC20DispatcherTrait, TokenKey
    };

    #[test]
    #[available_gas(3000000000)]
    fn test_place_order_sale_rate() {
        run_place_order_and_validate_sale_rate(
            amount: 100_000_000,
            timestamp: 0,
            expiry_time: 17,
            expected_sale_rate: 0x5f5e1000000000 // 6,250,000 * 2**32
        );
        run_place_order_and_validate_sale_rate(
            amount: 100_000_000,
            timestamp: 0,
            expiry_time: (16 * 16) + 1,
            expected_sale_rate: 0x5f5e100000000 // ~ 390,625 * 2**32
        );
        run_place_order_and_validate_sale_rate(
            amount: 100_000_000,
            timestamp: 0,
            expiry_time: (16 * 16 * 16) + 1,
            // scaled by 2**32
            expected_sale_rate: 0x5f5e10000000 // ~ 24,414.0625 * 2**32
        );
        run_place_order_and_validate_sale_rate(
            amount: 100_000_000,
            timestamp: 0,
            expiry_time: (16 * 16 * 16 * 16) + 1,
            // scaled by 2**32
            expected_sale_rate: 0x5f5e1000000 // ~ 1,525.87890625 * 2**32
        );
        run_place_order_and_validate_sale_rate(
            amount: 100_000_000,
            timestamp: 0,
            expiry_time: (16 * 16 * 16 * 16 * 16) + 1,
            // scaled by 2**32
            expected_sale_rate: 0x5f5e100000 // ~ 95.3674316406 * 2**32
        );
        run_place_order_and_validate_sale_rate(
            amount: 100_000_000,
            timestamp: 0,
            expiry_time: (16 * 16 * 16 * 16 * 16 * 16) + 1,
            // scaled by 2**32
            expected_sale_rate: 0x5f5e10000 // ~ 5.9604644775 * 2**32
        );
        run_place_order_and_validate_sale_rate(
            amount: 100_000_000,
            timestamp: 0,
            expiry_time: (16 * 16 * 16 * 16 * 16 * 16 * 16) + 1,
            // scaled by 2**32
            expected_sale_rate: 0x5f5e1000 // ~ 0.3725290298 * 2**32
        );
    }

    fn run_place_order_and_validate_sale_rate(
        amount: u128, timestamp: u64, expiry_time: u64, expected_sale_rate: u128
    ) {
        set_block_timestamp(timestamp);

        let core = deploy_core();
        let twamm = deploy_twamm(core);
        let (token0, token1) = deploy_two_mock_tokens();

        let order_key = OrderKey {
            token0: token0.contract_address, token1: token1.contract_address, expiry_time,
        };

        token0.increase_balance(core.contract_address, amount);
        let token_id = ITWAMMDispatcher { contract_address: twamm.contract_address }
            .place_order(order_key, amount);

        let order = ITWAMMDispatcher { contract_address: twamm.contract_address }
            .get_order_state(order_key, token_id,);

        assert(order.sale_rate == expected_sale_rate, 'SALE_RATE');
    }

    #[test]
    #[available_gas(3000000000)]
    fn test_two_orders_and_global_rate_no_virtual_orders_executed() {
        let core = deploy_core();
        let twamm = deploy_twamm(core);
        let (token0, token1) = deploy_two_mock_tokens();

        let amount = 100_000_000;

        // order 0
        let order_key_1 = OrderKey {
            token0: token0.contract_address, token1: token1.contract_address, expiry_time: 16 * 16,
        };
        token0.increase_balance(core.contract_address, amount);
        let token_id_1 = ITWAMMDispatcher { contract_address: twamm.contract_address }
            .place_order(order_key_1, amount);
        let order_1 = ITWAMMDispatcher { contract_address: twamm.contract_address }
            .get_order_state(order_key_1, token_id_1,);

        let mut event: ekubo::extensions::twamm::TWAMM::OrderPlaced = pop_log(
            twamm.contract_address
        )
            .unwrap();

        assert(event.id == 1, 'event.id');
        assert(event.order_key.token0 == order_key_1.token0, 'event.order_key.token0');
        assert(event.order_key.token1 == order_key_1.token1, 'event.order_key.token1');
        assert(event.amount == amount, 'event.amount');
        assert(event.expiry_time == order_key_1.expiry_time, 'event.expiry_time');
        assert(event.sale_rate == 0x5f5e100000000, 'event.sale_rate');
        assert(event.global_sale_rate == 0x5f5e100000000, 'event.sale_rate');
        assert(event.sale_rate_ending == 0x5f5e100000000, 'event.sale_rate');

        // order 1
        let order_key_2 = OrderKey {
            token0: token0.contract_address,
            token1: token1.contract_address,
            expiry_time: 16 * 16 * 16,
        };
        token0.increase_balance(core.contract_address, amount);
        let token_id_2 = ITWAMMDispatcher { contract_address: twamm.contract_address }
            .place_order(order_key_2, amount);
        let order_2 = ITWAMMDispatcher { contract_address: twamm.contract_address }
            .get_order_state(order_key_2, token_id_2,);

        event = pop_log(twamm.contract_address).unwrap();

        assert(event.id == 2, 'event.id');
        assert(event.order_key.token0 == order_key_2.token0, 'event.order_key.token0');
        assert(event.order_key.token1 == order_key_2.token1, 'event.order_key.token1');
        assert(event.amount == amount, 'event.amount');
        assert(event.expiry_time == order_key_2.expiry_time, 'event.expiry_time');
        assert(event.sale_rate == 0x5f5e10000000, 'event.sale_rate');
        assert(event.global_sale_rate == 0x5f5e100000000 + 0x5f5e10000000, 'event.sale_rate');
        assert(event.sale_rate_ending == 0x5f5e10000000, 'event.sale_rate');

        // global rate
        let global_rate = ITWAMMDispatcher { contract_address: twamm.contract_address }
            .get_sale_rate(
                TokenKey { token0: token0.contract_address, token1: token1.contract_address }
            );

        assert(global_rate == 0x5f5e100000000 + 0x5f5e10000000, 'GLOBAL_RATE');
    }

    #[test]
    #[available_gas(3000000000)]
    #[should_panic(
        expected: (
            'DEPOSIT_AMOUNT_NE_AMOUNT',
            'ENTRYPOINT_FAILED',
            'ENTRYPOINT_FAILED',
            'ENTRYPOINT_FAILED'
        )
    )]
    fn test_place_order_no_token_transfer() {
        let core = deploy_core();
        let twamm = deploy_twamm(core);
        let (token0, token1) = deploy_two_mock_tokens();

        let amount = 100_000_000;
        let order_key = OrderKey {
            token0: token0.contract_address, token1: token1.contract_address, expiry_time: 16 * 16,
        };

        ITWAMMDispatcher { contract_address: twamm.contract_address }
            .place_order(order_key, amount);
    }
}
// mod CancelOrderTests {
//     use super::{
//         PrintTrait, deploy_core, deploy_twamm, deploy_two_mock_tokens, ICoreDispatcher,
//         ICoreDispatcherTrait, PoolKey, MAX_TICK_SPACING, ITWAMMDispatcher, ITWAMMDispatcherTrait,
//         OrderKey, get_block_timestamp, set_block_timestamp, pop_log, to_token_key,
//         get_contract_address, IMockERC20Dispatcher, IMockERC20DispatcherTrait,
//     };

//     #[test]
//     #[available_gas(3000000000)]
//     #[should_panic(expected: ('ORDER_EXPIRED', 'ENTRYPOINT_FAILED'))]
//     fn test_place_order_and_cancel_after_expiry() {
//         let timestamp = 1_000_000;
//         set_block_timestamp(get_block_timestamp() + timestamp);

//         let core = deploy_core();
//         let twamm = deploy_twamm(core, 1_000_u64);
//         let (token0, token1) = deploy_two_mock_tokens();

//         let amount = 100_000_000;
//         let order_key = OrderKey {
//             token0: token0.contract_address, token1: token1.contract_address, time_intervals: 10
//         };

//         token0.increase_balance(core.contract_address, amount);
//         let token_id = ITWAMMDispatcher { contract_address: twamm.contract_address }
//             .place_order(order_key, amount);

//         let order = ITWAMMDispatcher { contract_address: twamm.contract_address }
//             .get_order_state(order_key, token_id,);

//         set_block_timestamp(order.expiry_time + 1);

//         ITWAMMDispatcher { contract_address: twamm.contract_address }
//             .cancel_order(order_key, token_id);
//     }

//     #[test]
//     #[available_gas(3000000000)]
//     fn test_place_order_and_withdraw() {
//         let timestamp = 1_000_000;
//         set_block_timestamp(get_block_timestamp() + timestamp);

//         let core = deploy_core();
//         let twamm = deploy_twamm(core, 1_000_u64);
//         let (token0, token1) = deploy_two_mock_tokens();

//         let amount = 100_000_000;
//         let order_key = OrderKey {
//             token0: token0.contract_address, token1: token1.contract_address, time_intervals: 10
//         };

//         token0.increase_balance(core.contract_address, amount);
//         let token_id = ITWAMMDispatcher { contract_address: twamm.contract_address }
//             .place_order(order_key, amount);

//         let order = ITWAMMDispatcher { contract_address: twamm.contract_address }
//             .get_order_state(order_key, token_id,);

//         set_block_timestamp(order.expiry_time + 1);

//         // No trades were executed 
//         ITWAMMDispatcher { contract_address: twamm.contract_address }
//             .withdraw_from_order(order_key, token_id,);
//     }

//     #[test]
//     #[available_gas(3000000000)]
//     fn test_place_order_and_cancel_before_oti_passes_at_execution_time() {
//         let timestamp = 1_000_000_000;
//         set_block_timestamp(get_block_timestamp() + timestamp);

//         let core = deploy_core();
//         let twamm = deploy_twamm(core, 1_000_u64);
//         let (token0, token1) = deploy_two_mock_tokens();

//         let amount = 1_000;
//         let order_key = OrderKey {
//             token0: token0.contract_address, token1: token1.contract_address, time_intervals: 50
//         };

//         token0.increase_balance(core.contract_address, amount);
//         let token_id = ITWAMMDispatcher { contract_address: twamm.contract_address }
//             .place_order(order_key, amount);

//         let order = ITWAMMDispatcher { contract_address: twamm.contract_address }
//             .get_order_state(order_key, token_id,);

//         set_block_timestamp(get_block_timestamp() + 100);

//         ITWAMMDispatcher { contract_address: twamm.contract_address }
//             .cancel_order(order_key, token_id);

//         let token_balance = token0.balanceOf(get_contract_address());

//         assert(
//             amount.into() - token_balance == 1 || token_balance == amount.into(), 'token0.balance'
//         );
//     }

//     #[test]
//     #[available_gas(3000000000)]
//     fn test_place_order_and_cancel_before_oti_passes_before_execution_time() {
//         let timestamp = 999_999_999;
//         set_block_timestamp(get_block_timestamp() + timestamp);

//         let core = deploy_core();
//         let twamm = deploy_twamm(core, 1_000_u64);
//         let (token0, token1) = deploy_two_mock_tokens();

//         let amount = 1_000;
//         let order_key = OrderKey {
//             token0: token0.contract_address, token1: token1.contract_address, time_intervals: 50
//         };

//         token0.increase_balance(core.contract_address, amount);
//         let token_id = ITWAMMDispatcher { contract_address: twamm.contract_address }
//             .place_order(order_key, amount);

//         let order = ITWAMMDispatcher { contract_address: twamm.contract_address }
//             .get_order_state(order_key, token_id,);

//         set_block_timestamp(get_block_timestamp() + 100);

//         ITWAMMDispatcher { contract_address: twamm.contract_address }
//             .cancel_order(order_key, token_id);

//         let token_balance = token0.balanceOf(get_contract_address());

//         assert(
//             amount.into() - token_balance == 1 || token_balance == amount.into(), 'token0.balance'
//         );
//     }
// }

// mod PlaceOrderWithSwapsTests {
//     use super::{
//         PrintTrait, deploy_core, deploy_twamm, deploy_two_mock_tokens, ICoreDispatcher,
//         ICoreDispatcherTrait, PoolKey, MAX_TICK_SPACING, ITWAMMDispatcher, ITWAMMDispatcherTrait,
//         OrderKey, get_block_timestamp, set_block_timestamp, pop_log, to_token_key,
//         IMockERC20Dispatcher, IMockERC20DispatcherTrait, contract_address_const,
//         set_contract_address, setup_pool_with_core, deploy_positions, max_bounds, update_position,
//         max_liquidity, Bounds, tick_to_sqrt_ratio, i129, TICKS_IN_ONE_PERCENT, IPositionsDispatcher,
//         IPositionsDispatcherTrait, get_contract_address
//     };

//     #[test]
//     #[available_gas(3000000000)]
//     fn test_place_order_and_withdraw() {
//         let timestamp = 1_000_000;
//         set_block_timestamp(get_block_timestamp() + timestamp);

//         let core = deploy_core();
//         let twamm = deploy_twamm(core, 1_000_u64);

//         let liquidity_provider = contract_address_const::<42>();
//         let twamm_caller = contract_address_const::<43>();
//         set_contract_address(liquidity_provider);

//         let initial_tick = i129 { mag: 1386294, sign: false };
//         let setup = setup_pool_with_core(
//             core,
//             fee: 0,
//             tick_spacing: MAX_TICK_SPACING,
//             // 2:1 price
//             initial_tick: initial_tick,
//             extension: twamm.contract_address,
//         );
//         let positions = deploy_positions(setup.core);
//         let bounds = max_bounds(MAX_TICK_SPACING);

//         let price = core.get_pool_price(pool_key: setup.pool_key);
//         let token0_liquidity = 200_000_000 * 0x100000000;
//         let token1_liquidity = 100_000_000 * 0x100000000;
//         let max_liquidity = max_liquidity(
//             u256 { low: initial_tick.mag, high: 0 },
//             tick_to_sqrt_ratio(bounds.lower),
//             tick_to_sqrt_ratio(bounds.upper),
//             token0_liquidity,
//             token1_liquidity,
//         );

//         setup.token0.increase_balance(positions.contract_address, token0_liquidity);
//         setup.token1.increase_balance(positions.contract_address, token1_liquidity);
//         let (token_id, liquidity, amount0, amount1) = positions
//             .mint_and_deposit_and_clear_both(
//                 pool_key: setup.pool_key, bounds: bounds, min_liquidity: max_liquidity
//             );

//         // 'max liquidity'.print();
//         // max_liquidity.print();

//         // 'core token 0 balance'.print();
//         // setup.token0.balanceOf(core.contract_address).print();
//         // 'core token 1 balance'.print();
//         // setup.token1.balanceOf(core.contract_address).print();

//         // place order
//         set_contract_address(twamm_caller);
//         let amount = 100_000 * 0x100000000;
//         let order_key = OrderKey {
//             token0: setup.token0.contract_address,
//             token1: setup.token1.contract_address,
//             time_intervals: 10_000
//         };

//         setup.token0.increase_balance(core.contract_address, amount);
//         let token_id = ITWAMMDispatcher { contract_address: twamm.contract_address }
//             .place_order(order_key, amount);

//         // 'twamm token 0 balance'.print();
//         // setup.token0.balanceOf(twamm.contract_address).print();

//         set_block_timestamp(get_block_timestamp() + 1_001);

//         setup.token0.increase_balance(core.contract_address, amount);
//         ITWAMMDispatcher { contract_address: twamm.contract_address }
//             .place_order(order_key, amount);
//     // let order = ITWAMMDispatcher { contract_address: twamm.contract_address }
//     //     .get_order_state(order_key, token_id,);
//     }
// }


