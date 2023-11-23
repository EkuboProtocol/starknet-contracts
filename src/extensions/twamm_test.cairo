use debug::PrintTrait;
use ekubo::owner::owner;
use ekubo::extensions::twamm::{ITWAMMDispatcher, ITWAMMDispatcherTrait, OrderState};
use ekubo::interfaces::core::{
    ICoreDispatcherTrait, ICoreDispatcher, SwapParameters, IExtensionDispatcher
};
use ekubo::interfaces::erc721::{IERC721Dispatcher, IERC721DispatcherTrait};
use ekubo::simple_swapper::{ISimpleSwapperDispatcherTrait};
use ekubo::tests::helper::{
    deploy_core, deploy_twamm, deploy_two_mock_tokens, deploy_positions, setup_pool_with_core,
    update_position, SetupPoolResult
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
use ekubo::extensions::twamm::TWAMM::{to_token_key, OrderPlaced, VirtualOrdersExecuted};
use option::{OptionTrait};
use starknet::testing::{set_contract_address, set_block_timestamp, pop_log};
use starknet::{get_contract_address, get_block_timestamp, contract_address_const, ClassHash};
use traits::{TryInto, Into};
use zeroable::{Zeroable};

const SIXTEEN_POW_ZERO: u64 = 0x1;
const SIXTEEN_POW_ONE: u64 = 0x10;
const SIXTEEN_POW_TWO: u64 = 0x100;
const SIXTEEN_POW_THREE: u64 = 0x1000;
const SIXTEEN_POW_FOUR: u64 = 0x10000;
const SIXTEEN_POW_FIVE: u64 = 0x100000;
const SIXTEEN_POW_SIX: u64 = 0x1000000;
const SIXTEEN_POW_SEVEN: u64 = 0x10000000;

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
        IMockERC20Dispatcher, IMockERC20DispatcherTrait, SIXTEEN_POW_ZERO, SIXTEEN_POW_ONE,
        SIXTEEN_POW_TWO, SIXTEEN_POW_THREE, SIXTEEN_POW_FOUR, SIXTEEN_POW_FIVE, SIXTEEN_POW_SIX,
        SIXTEEN_POW_SEVEN
    };


    #[test]
    #[available_gas(3000000000)]
    #[should_panic(expected: ('INVALID_EXPIRY_TIME', 'ENTRYPOINT_FAILED'))]
    fn test_place_order_at_timestamp() {
        let core = deploy_core();
        let twamm = deploy_twamm(core);
        let (token0, token1) = deploy_two_mock_tokens();

        let pool_key = PoolKey {
            token0: token0.contract_address,
            token1: token1.contract_address,
            fee: 0,
            tick_spacing: MAX_TICK_SPACING,
            extension: twamm.contract_address,
        };

        let order_key = OrderKey {
            // current timestamp is 0
            token0: token0.contract_address,
            token1: token1.contract_address,
            pool_key,
            expiry_time: 0
        };

        let amount = 100_000_000;
        token0.increase_balance(core.contract_address, amount);
        let token_id = ITWAMMDispatcher { contract_address: twamm.contract_address }
            .place_order(order_key, amount);
    }

    #[test]
    #[available_gas(3000000000)]
    fn test_place_order_expiry_validation() {
        // the tests take too long so we don't run them all
        // however, they are all valid/passing

        // timestamp is multiple of 16**N

        // _test_place_order_expiry_validation(timestamp: SIXTEEN_POW_ONE);
        // _test_place_order_expiry_validation(timestamp: SIXTEEN_POW_TWO);
        // _test_place_order_expiry_validation(timestamp: SIXTEEN_POW_THREE);
        // _test_place_order_expiry_validation(timestamp: SIXTEEN_POW_FOUR);
        // _test_place_order_expiry_validation(timestamp: SIXTEEN_POW_FIVE);
        // _test_place_order_expiry_validation(timestamp: SIXTEEN_POW_SIX);
        // _test_place_order_expiry_validation(timestamp: SIXTEEN_POW_SEVEN);

        // timestamp is _not_ multiple of 16**N

        // _test_place_order_expiry_validation(timestamp: 1);
        // _test_place_order_expiry_validation(timestamp: 100);
        // _test_place_order_expiry_validation(timestamp: 1_000);
        // _test_place_order_expiry_validation(timestamp: 1_000_000);
        // _test_place_order_expiry_validation(timestamp: 1_000_000_000);
        // _test_place_order_expiry_validation(timestamp: 1_000_000_000_000);
        // _test_place_order_expiry_validation(timestamp: 1_000_000_000_000_000);

        _test_place_order_expiry_validation(timestamp: 0);
    }

    fn _test_place_order_expiry_validation(timestamp: u64) {
        // Do not allow orders to be placed in the smallest interval
        // orders expire in <= 16**1 seconds 
        // do not allow 16**0 = 1 second precision

        // orders expire in <= 16**2 = 256 seconds (~4.2min),
        // allow 16**1 = 16 seconds precision
        assert_place_order_and_validate_expiry(
            timestamp: timestamp,
            prev_interval: SIXTEEN_POW_ONE,
            interval: SIXTEEN_POW_TWO,
            step: SIXTEEN_POW_ONE
        );

        // orders expire in <= 16**3 = 4,096 seconds (~1hr),
        // allow 16**2 = 256 seconds (~4.2min) precision
        assert_place_order_and_validate_expiry(
            timestamp: timestamp,
            prev_interval: SIXTEEN_POW_TWO,
            interval: SIXTEEN_POW_THREE,
            step: SIXTEEN_POW_TWO
        );

        // orders expire in <= 16**4 = 65,536 seconds (~18hrs),
        // allow 16**3 = 4,096 seconds (~1hr) precision
        assert_place_order_and_validate_expiry(
            timestamp: timestamp,
            prev_interval: SIXTEEN_POW_THREE,
            interval: SIXTEEN_POW_FOUR,
            step: SIXTEEN_POW_THREE
        );

        // orders expire in <= 16**5 = 1,048,576 seconds (~12 days),
        // allow 16**4 = 65,536 seconds (~18hrs) precision
        assert_place_order_and_validate_expiry(
            timestamp: timestamp,
            prev_interval: SIXTEEN_POW_FOUR,
            interval: SIXTEEN_POW_FIVE,
            step: SIXTEEN_POW_FOUR
        );

        // orders expire in <= 16**6 = 16,777,216 seconds (~6.4 months),
        // allow 16**5 = 1,048,576 seconds (~12 days) precision
        assert_place_order_and_validate_expiry(
            timestamp: timestamp,
            prev_interval: SIXTEEN_POW_FIVE,
            interval: SIXTEEN_POW_SIX,
            step: SIXTEEN_POW_FIVE
        );

        // orders expire in <= 16**7 = 268,435,456 seconds (~8.5 years),
        // allow 16**6 = 16,777,216 (~6.4 month) precision
        // unlikely to be used in practice
        assert_place_order_and_validate_expiry(
            timestamp: timestamp,
            prev_interval: SIXTEEN_POW_SIX,
            interval: SIXTEEN_POW_SEVEN,
            step: SIXTEEN_POW_SIX
        );
    }

    fn assert_place_order_and_validate_expiry(
        timestamp: u64, prev_interval: u64, interval: u64, step: u64
    ) {
        set_block_timestamp(timestamp);

        let core = deploy_core();
        let twamm = deploy_twamm(core);
        let (token0, token1) = deploy_two_mock_tokens();

        let amount = 100_000_000;

        let pool_key = PoolKey {
            token0: token0.contract_address,
            token1: token1.contract_address,
            fee: 0,
            tick_spacing: MAX_TICK_SPACING,
            extension: twamm.contract_address,
        };

        // expiry time at the interval time
        let mut order_key = OrderKey {
            token0: token0.contract_address,
            token1: token1.contract_address,
            pool_key,
            expiry_time: timestamp + prev_interval
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

        // first valid expiry time in interval
        order_key =
            OrderKey {
                token0: token0.contract_address,
                token1: token1.contract_address,
                pool_key,
                expiry_time: timestamp + prev_interval + step
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

        // last valid expiry time in interval
        order_key =
            OrderKey {
                token0: token0.contract_address,
                token1: token1.contract_address,
                pool_key,
                expiry_time: timestamp + interval - step
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
        IMockERC20Dispatcher, IMockERC20DispatcherTrait, TokenKey, SIXTEEN_POW_ZERO,
        SIXTEEN_POW_ONE, SIXTEEN_POW_TWO, SIXTEEN_POW_THREE, SIXTEEN_POW_FOUR, SIXTEEN_POW_FIVE,
        SIXTEEN_POW_SIX, SIXTEEN_POW_SEVEN, OrderPlaced,
    };

    #[test]
    #[available_gas(3000000000)]
    #[should_panic(expected: ('INVALID_SPACING', 'ENTRYPOINT_FAILED'))]
    fn test_place_order_expiry_too_small() {
        run_place_order_and_validate_sale_rate(
            amount: 100_000_000,
            timestamp: 0,
            expiry_time: 15,
            expected_sale_rate: 0x5f5e1000000000 // 6,250,000 * 2**32
        );
    }

    #[test]
    #[available_gas(3000000000)]
    fn test_place_order_sale_rate() {
        run_place_order_and_validate_sale_rate(
            amount: 100_000_000,
            timestamp: 0,
            expiry_time: SIXTEEN_POW_ONE + 1,
            expected_sale_rate: 0x5f5e1000000000 // 6,250,000 * 2**32
        );
        run_place_order_and_validate_sale_rate(
            amount: 100_000_000,
            timestamp: 0,
            expiry_time: SIXTEEN_POW_TWO + 1,
            expected_sale_rate: 0x5f5e100000000 // ~ 390,625 * 2**32
        );
        run_place_order_and_validate_sale_rate(
            amount: 100_000_000,
            timestamp: 0,
            expiry_time: SIXTEEN_POW_THREE + 1,
            // scaled by 2**32
            expected_sale_rate: 0x5f5e10000000 // ~ 24,414.0625 * 2**32
        );
        run_place_order_and_validate_sale_rate(
            amount: 100_000_000,
            timestamp: 0,
            expiry_time: SIXTEEN_POW_FOUR + 1,
            // scaled by 2**32
            expected_sale_rate: 0x5f5e1000000 // ~ 1,525.87890625 * 2**32
        );
        run_place_order_and_validate_sale_rate(
            amount: 100_000_000,
            timestamp: 0,
            expiry_time: SIXTEEN_POW_FIVE + 1,
            // scaled by 2**32
            expected_sale_rate: 0x5f5e100000 // ~ 95.3674316406 * 2**32
        );
        run_place_order_and_validate_sale_rate(
            amount: 100_000_000,
            timestamp: 0,
            expiry_time: SIXTEEN_POW_SIX + 1,
            // scaled by 2**32
            expected_sale_rate: 0x5f5e10000 // ~ 5.9604644775 * 2**32
        );
        run_place_order_and_validate_sale_rate(
            amount: 100_000_000,
            timestamp: 0,
            expiry_time: SIXTEEN_POW_SEVEN + 1,
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

        let pool_key = PoolKey {
            token0: token0.contract_address,
            token1: token1.contract_address,
            fee: 0,
            tick_spacing: MAX_TICK_SPACING,
            extension: twamm.contract_address,
        };

        let order_key = OrderKey {
            token0: token0.contract_address, token1: token1.contract_address, pool_key, expiry_time,
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

        let pool_key = PoolKey {
            token0: token0.contract_address,
            token1: token1.contract_address,
            fee: 0,
            tick_spacing: MAX_TICK_SPACING,
            extension: twamm.contract_address,
        };

        // order 0
        let order_key_1 = OrderKey {
            token0: token0.contract_address,
            token1: token1.contract_address,
            pool_key,
            expiry_time: 16 * 16,
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
            pool_key,
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
        let pool_key = PoolKey {
            token0: token0.contract_address,
            token1: token1.contract_address,
            fee: 0,
            tick_spacing: MAX_TICK_SPACING,
            extension: twamm.contract_address,
        };
        let order_key = OrderKey {
            token0: token0.contract_address,
            token1: token1.contract_address,
            pool_key,
            expiry_time: 16 * 16,
        };

        ITWAMMDispatcher { contract_address: twamm.contract_address }
            .place_order(order_key, amount);
    }
}
mod CancelOrderTests {
    use super::{
        PrintTrait, deploy_core, deploy_twamm, deploy_two_mock_tokens, ICoreDispatcher,
        ICoreDispatcherTrait, PoolKey, MAX_TICK_SPACING, ITWAMMDispatcher, ITWAMMDispatcherTrait,
        OrderKey, get_block_timestamp, set_block_timestamp, pop_log, to_token_key,
        get_contract_address, IMockERC20Dispatcher, IMockERC20DispatcherTrait, SIXTEEN_POW_THREE
    };

    #[test]
    #[available_gas(3000000000)]
    #[should_panic(expected: ('ORDER_EXPIRED', 'ENTRYPOINT_FAILED'))]
    fn test_place_order_and_cancel_after_expiry() {
        let core = deploy_core();
        let twamm = deploy_twamm(core);
        let (token0, token1) = deploy_two_mock_tokens();

        let amount = 100_000_000;
        let pool_key = PoolKey {
            token0: token0.contract_address,
            token1: token1.contract_address,
            fee: 0,
            tick_spacing: MAX_TICK_SPACING,
            extension: twamm.contract_address,
        };
        let order_key = OrderKey {
            token0: token0.contract_address,
            token1: token1.contract_address,
            pool_key,
            expiry_time: SIXTEEN_POW_THREE
        };

        token0.increase_balance(core.contract_address, amount);
        let token_id = ITWAMMDispatcher { contract_address: twamm.contract_address }
            .place_order(order_key, amount);

        let order = ITWAMMDispatcher { contract_address: twamm.contract_address }
            .get_order_state(order_key, token_id,);

        set_block_timestamp(order_key.expiry_time + 1);

        ITWAMMDispatcher { contract_address: twamm.contract_address }
            .cancel_order(order_key, token_id);
    }
    #[test]
    #[available_gas(3000000000)]
    fn test_place_order_and_withdraw() {
        let core = deploy_core();
        let twamm = deploy_twamm(core);
        let (token0, token1) = deploy_two_mock_tokens();

        let amount = 100_000_000;
        let pool_key = PoolKey {
            token0: token0.contract_address,
            token1: token1.contract_address,
            fee: 0,
            tick_spacing: MAX_TICK_SPACING,
            extension: twamm.contract_address,
        };
        let order_key = OrderKey {
            token0: token0.contract_address,
            token1: token1.contract_address,
            pool_key,
            expiry_time: SIXTEEN_POW_THREE
        };

        token0.increase_balance(core.contract_address, amount);
        let token_id = ITWAMMDispatcher { contract_address: twamm.contract_address }
            .place_order(order_key, amount);

        set_block_timestamp(order_key.expiry_time + 1);

        // No swaps were executed 
        ITWAMMDispatcher { contract_address: twamm.contract_address }
            .withdraw_from_order(order_key, token_id);
    }
    #[test]
    #[available_gas(3000000000)]
    fn test_place_order_and_cancel_before_order_execution() {
        let core = deploy_core();
        let twamm = deploy_twamm(core);
        let (token0, token1) = deploy_two_mock_tokens();

        let amount = 1_000;
        let pool_key = PoolKey {
            token0: token0.contract_address,
            token1: token1.contract_address,
            fee: 0,
            tick_spacing: MAX_TICK_SPACING,
            extension: twamm.contract_address,
        };
        let order_key = OrderKey {
            token0: token0.contract_address,
            token1: token1.contract_address,
            pool_key,
            expiry_time: SIXTEEN_POW_THREE,
        };

        token0.increase_balance(core.contract_address, amount);
        let token_id = ITWAMMDispatcher { contract_address: twamm.contract_address }
            .place_order(order_key, amount);

        let order = ITWAMMDispatcher { contract_address: twamm.contract_address }
            .get_order_state(order_key, token_id,);

        set_block_timestamp(get_block_timestamp() + 1);

        ITWAMMDispatcher { contract_address: twamm.contract_address }
            .cancel_order(order_key, token_id);

        let token_balance = token0.balanceOf(get_contract_address());

        assert(
            amount.into() - token_balance == 1 || token_balance == amount.into(), 'token0.balance'
        );
    }
}


mod PlaceOrderAndCheckExpiryBitmapTests {
    use super::{
        PrintTrait, deploy_core, deploy_twamm, deploy_two_mock_tokens, ICoreDispatcher,
        ICoreDispatcherTrait, PoolKey, MAX_TICK_SPACING, ITWAMMDispatcher, ITWAMMDispatcherTrait,
        OrderKey, get_block_timestamp, set_block_timestamp, pop_log, to_token_key,
        IMockERC20Dispatcher, IMockERC20DispatcherTrait, contract_address_const,
        set_contract_address, setup_pool_with_core, deploy_positions, max_bounds, update_position,
        max_liquidity, Bounds, tick_to_sqrt_ratio, i129, TICKS_IN_ONE_PERCENT, IPositionsDispatcher,
        IPositionsDispatcherTrait, get_contract_address, IExtensionDispatcher, SetupPoolResult,
        SIXTEEN_POW_ZERO, SIXTEEN_POW_ONE, SIXTEEN_POW_TWO, SIXTEEN_POW_THREE, SIXTEEN_POW_FOUR,
        SIXTEEN_POW_FIVE, SIXTEEN_POW_SIX, SIXTEEN_POW_SEVEN, OrderPlaced, VirtualOrdersExecuted,
        OrderState
    };

    #[test]
    #[available_gas(3000000000)]
    fn test_place_orders_0() {
        // Both order expiries are after the current time
        // l = last virtual order time
        // t = current time
        // 0 = order for token0 expiry
        // 1 = order for token1 expiry
        // l---------------------t----0--1----------> time
        // trade from l->t

        let core = deploy_core();
        let (twamm, setup) = set_up_twamm_with_liquidity(core);

        let timestamp = 1_000_000;
        set_block_timestamp(timestamp);

        let order1_timestamp = timestamp;
        let (token_id1, _) = place_order(core, twamm, setup, timestamp + SIXTEEN_POW_THREE);

        let event: ekubo::extensions::twamm::TWAMM::OrderPlaced = pop_log(twamm.contract_address)
            .unwrap();

        let order2_timestamp = timestamp + 16;
        set_block_timestamp(order2_timestamp);
        let (token_id2, _) = place_order(
            core,
            twamm,
            SetupPoolResult {
                core: setup.core,
                locker: setup.locker,
                token0: setup.token1,
                token1: setup.token0,
                pool_key: setup.pool_key,
            },
            timestamp + SIXTEEN_POW_THREE + 1
        );

        let event: VirtualOrdersExecuted = pop_log(twamm.contract_address).unwrap();

        assert(event.last_virtual_order_time == order1_timestamp, 'event.last_virtual_order_time');
        assert(event.next_virtual_order_time == order2_timestamp, 'event.next_virtual_order_time');
    }

    #[test]
    #[available_gas(3000000000)]
    fn test_place_orders_1() {
        // Order 0 expiries before current time
        // Order 1 expiries after current time
        // l = last virtual order time
        // t = current time
        // 1 = order for token0 expiry
        // 2 = order for token1 expiry
        // l---------------0-----t-------1----------> time
        // execute from l->0 and from 0->t

        let core = deploy_core();
        let (twamm, setup) = set_up_twamm_with_liquidity(core);

        let timestamp = 1_000_000;
        set_block_timestamp(timestamp);

        let order1_timestamp = timestamp;
        let (token_id1, order1) = place_order(core, twamm, setup, timestamp + 16);

        let event: OrderPlaced = pop_log(twamm.contract_address).unwrap();

        let order2_timestamp = order1.expiry_time + 1;
        set_block_timestamp(order2_timestamp);
        let (token_id2, order2) = place_order(
            core,
            twamm,
            SetupPoolResult {
                core: setup.core,
                locker: setup.locker,
                token0: setup.token1,
                token1: setup.token0,
                pool_key: setup.pool_key,
            },
            timestamp + SIXTEEN_POW_THREE * 2
        );

        // first order execution
        let event: VirtualOrdersExecuted = pop_log(twamm.contract_address).unwrap();

        assert(event.last_virtual_order_time == order1_timestamp, 'event0.last_virtual_order_time');
        assert(
            event.next_virtual_order_time == order1.expiry_time, 'event0.next_virtual_order_time'
        );
        assert(event.token0_sale_rate == order1.sale_rate, 'event0.token0_sale_rate');
        assert(event.token1_sale_rate == 0, 'event0.token1_sale_rate');

        // second order execution
        let event: VirtualOrdersExecuted = pop_log(twamm.contract_address).unwrap();
        assert(
            event.last_virtual_order_time == order1.expiry_time, 'event1.last_virtual_order_time'
        );
        assert(event.next_virtual_order_time == order2_timestamp, 'event1.next_virtual_order_time');
        assert(event.token0_sale_rate == 0, 'event0.token0_sale_rate');
        assert(event.token1_sale_rate == 0, 'event0.token1_sale_rate');
    }

    #[test]
    #[available_gas(3000000000)]
    fn test_place_orders_2() {
        // Order 0 expiries before current time
        // Order 1 expiries before current time
        // l = last virtual order time
        // t = current time
        // 1 = order for token0 expiry
        // 2 = order for token1 expiry
        // l---------------0--1--t------------------> time
        // execute from l->0, 0->1, 1->t

        let core = deploy_core();
        let (twamm, setup) = set_up_twamm_with_liquidity(core);

        let timestamp = 1_000_000;
        set_block_timestamp(timestamp);

        let order1_timestamp = timestamp;
        let (token_id1, order1) = place_order(core, twamm, setup, timestamp + SIXTEEN_POW_ONE);
        let event: OrderPlaced = pop_log(twamm.contract_address).unwrap();

        let (token_id2, order2) = place_order(
            core,
            twamm,
            SetupPoolResult {
                core: setup.core,
                locker: setup.locker,
                token0: setup.token1,
                token1: setup.token0,
                pool_key: setup.pool_key,
            },
            timestamp + SIXTEEN_POW_ONE * 2
        );
        let event: OrderPlaced = pop_log(twamm.contract_address).unwrap();

        // after order2 expires
        let order_execution_timestamp = order2.expiry_time + SIXTEEN_POW_ONE;
        set_block_timestamp(order_execution_timestamp);

        // manually trigger virtual order execution
        twamm.execute_virtual_orders(setup.pool_key);

        // first order execution
        let event: VirtualOrdersExecuted = pop_log(twamm.contract_address).unwrap();

        assert(event.last_virtual_order_time == order1_timestamp, 'event0.last_virtual_order_time');
        assert(
            event.next_virtual_order_time == order1.expiry_time, 'event0.next_virtual_order_time'
        );
        assert(event.token0_sale_rate == order1.sale_rate, 'event0.token0_sale_rate');
        assert(event.token1_sale_rate == order2.sale_rate, 'event0.token1_sale_rate');

        // second order execution
        let event: VirtualOrdersExecuted = pop_log(twamm.contract_address).unwrap();
        assert(
            event.last_virtual_order_time == order1.expiry_time, 'event1.last_virtual_order_time'
        );
        assert(
            event.next_virtual_order_time == order2.expiry_time, 'event1.next_virtual_order_time'
        );
        assert(event.token0_sale_rate == 0, 'event0.token0_sale_rate');
        assert(event.token1_sale_rate == order2.sale_rate, 'event0.token1_sale_rate');

        // third order execution
        let event: VirtualOrdersExecuted = pop_log(twamm.contract_address).unwrap();
        assert(
            event.last_virtual_order_time == order2.expiry_time, 'event2.last_virtual_order_time'
        );
        assert(
            event.next_virtual_order_time == order_execution_timestamp,
            'event2.next_virtual_order_time'
        );
        assert(event.token0_sale_rate == 0, 'event0.token0_sale_rate');
        assert(event.token1_sale_rate == 0, 'event0.token1_sale_rate');
    }

    fn set_up_twamm_with_liquidity(core: ICoreDispatcher) -> (ITWAMMDispatcher, SetupPoolResult) {
        let twamm = deploy_twamm(core);

        let liquidity_provider = contract_address_const::<42>();
        set_contract_address(liquidity_provider);

        let initial_tick = i129 { mag: 1386294, sign: false };
        let setup = setup_pool_with_core(
            core,
            fee: 0,
            tick_spacing: MAX_TICK_SPACING,
            // 2:1 price
            initial_tick: initial_tick,
            extension: twamm.contract_address,
        );
        let positions = deploy_positions(setup.core);
        let bounds = max_bounds(MAX_TICK_SPACING);

        let price = core.get_pool_price(pool_key: setup.pool_key);
        let token0_liquidity = 200_000_000 * 0x100000000;
        let token1_liquidity = 100_000_000 * 0x100000000;
        let max_liquidity = max_liquidity(
            u256 { low: initial_tick.mag, high: 0 },
            tick_to_sqrt_ratio(bounds.lower),
            tick_to_sqrt_ratio(bounds.upper),
            token0_liquidity,
            token1_liquidity,
        );

        setup.token0.increase_balance(positions.contract_address, token0_liquidity);
        setup.token1.increase_balance(positions.contract_address, token1_liquidity);
        let (token_id, liquidity, amount0, amount1) = positions
            .mint_and_deposit_and_clear_both(
                pool_key: setup.pool_key, bounds: bounds, min_liquidity: max_liquidity
            );

        (ITWAMMDispatcher { contract_address: twamm.contract_address }, setup)
    }

    fn place_order(
        core: ICoreDispatcher, twamm: ITWAMMDispatcher, setup: SetupPoolResult, expiry_time: u64
    ) -> (u64, OrderState) {
        let twamm_caller = contract_address_const::<43>();
        // place order
        set_contract_address(twamm_caller);
        let amount = 100_000 * 0x100000000;
        let order_key = OrderKey {
            token0: setup.token0.contract_address,
            token1: setup.token1.contract_address,
            pool_key: setup.pool_key,
            expiry_time
        };

        setup.token0.increase_balance(core.contract_address, amount);

        let token_id = twamm.place_order(order_key, amount);

        let order = ITWAMMDispatcher { contract_address: twamm.contract_address }
            .get_order_state(order_key, token_id,);

        // return token_id and potentially snapped (rounded-down) expiry time
        (token_id, order)
    }
}

