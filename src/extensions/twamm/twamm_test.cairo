use core::debug::PrintTrait;
use core::num::traits::{Zero};
use core::option::{OptionTrait};
use core::traits::{TryInto, Into};
use ekubo::core::Core::{PoolInitialized, PositionUpdated, Swapped, LoadedBalance, SavedBalance};
use ekubo::extensions::twamm::TWAMM::{
    OrderPlaced, VirtualOrdersExecuted, OrderWithdrawn, time_to_word_and_bit_index,
    word_and_bit_index_to_time,
};
use ekubo::extensions::twamm::math::{
    calculate_sale_rate, calculate_reward_rate_deltas, calculate_reward_amount, calculate_c,
    constants, exp_fractional, calculate_next_sqrt_ratio
};

use ekubo::extensions::twamm::{ITWAMMDispatcher, ITWAMMDispatcherTrait, OrderState};
use ekubo::extensions::twamm::{OrderKey, TWAMMPoolKey};
use ekubo::interfaces::core::{
    ICoreDispatcherTrait, ICoreDispatcher, SwapParameters, IExtensionDispatcher, Delta
};
use ekubo::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
use ekubo::interfaces::erc721::{IERC721Dispatcher, IERC721DispatcherTrait};
use ekubo::interfaces::positions::{
    IPositionsDispatcher, IPositionsDispatcherTrait, GetTokenInfoResult, GetTokenInfoRequest
};
use ekubo::interfaces::upgradeable::{IUpgradeableDispatcher, IUpgradeableDispatcherTrait};
use ekubo::math::bitmap::{Bitmap, BitmapTrait};
use ekubo::math::max_liquidity::{max_liquidity};
use ekubo::math::ticks::constants::{MAX_TICK_SPACING, TICKS_IN_ONE_PERCENT};
use ekubo::math::ticks::{min_tick, max_tick};
use ekubo::math::ticks::{tick_to_sqrt_ratio};
use ekubo::mock_erc20::{IMockERC20, IMockERC20Dispatcher, IMockERC20DispatcherTrait};
use ekubo::tests::helper::{
    Deployer, DeployerTrait, update_position, SetupPoolResult, default_owner
};
use ekubo::tests::mocks::locker::{UpdatePositionParameters};
use ekubo::tests::mocks::mock_upgradeable::{MockUpgradeable};
use ekubo::types::bounds::{Bounds, max_bounds};
use ekubo::types::call_points::{CallPoints};
use ekubo::types::i129::{i129, i129Trait, AddDeltaTrait};
use ekubo::types::keys::{PoolKey};
use starknet::testing::{set_contract_address, set_block_timestamp, pop_log};
use starknet::{get_contract_address, get_block_timestamp, contract_address_const, ClassHash};

const SIXTEEN_POW_ZERO: u64 = 0x1;
const SIXTEEN_POW_ONE: u64 = 0x10;
const SIXTEEN_POW_TWO: u64 = 0x100;
const SIXTEEN_POW_THREE: u64 = 0x1000;
const SIXTEEN_POW_FOUR: u64 = 0x10000;
const SIXTEEN_POW_FIVE: u64 = 0x100000;
const SIXTEEN_POW_SIX: u64 = 0x1000000;
const SIXTEEN_POW_SEVEN: u64 = 0x10000000;
const SIXTEEN_POW_EIGHT: u64 = 0x100000000; // 2**32


mod UpgradableTest {
    use ekubo::extensions::twamm::TWAMM;
    use super::{
        Deployer, DeployerTrait, update_position, ClassHash, MockUpgradeable, set_contract_address,
        pop_log, IUpgradeableDispatcher, IUpgradeableDispatcherTrait, default_owner
    };

    #[test]
    fn test_replace_class_hash_can_be_called_by_owner() {
        let mut d: Deployer = Default::default();
        let core = d.deploy_core();
        let twamm = d.deploy_twamm(core);
        let _event: ekubo::components::owned::Owned::OwnershipTransferred = pop_log(
            twamm.contract_address
        )
            .unwrap();

        let class_hash: ClassHash = TWAMM::TEST_CLASS_HASH.try_into().unwrap();

        set_contract_address(default_owner());
        IUpgradeableDispatcher { contract_address: twamm.contract_address }
            .replace_class_hash(class_hash);

        let event: ekubo::components::upgradeable::Upgradeable::ClassHashReplaced = pop_log(
            twamm.contract_address
        )
            .unwrap();
        assert(event.new_class_hash == class_hash, 'event.class_hash');
    }
}

mod BitmapTest {
    use super::{time_to_word_and_bit_index, word_and_bit_index_to_time, Bitmap, BitmapTrait};

    fn assert_case_time(time: u64, location: (u128, u8)) {
        let (word, bit) = time_to_word_and_bit_index(time);
        let (expected_word, expected_bit) = location;
        assert_eq!(word, expected_word);
        assert_eq!(bit, expected_bit);
        let prev = word_and_bit_index_to_time(location);
        assert((time - prev) < 16, 'reverse');
    }

    #[test]
    fn test_time_spacing_sixteen() {
        assert_case_time(0, location: (0, 250));
        assert_case_time(16, location: (0, 249));
        assert_case_time(4000, location: (0, 0));
        assert_case_time(4016, location: (1, 250));
        assert_case_time(8016, location: (1, 0));
    }
}

mod PoolTests {
    use super::{
        Deployer, DeployerTrait, update_position, ClassHash, set_contract_address, pop_log,
        IPositionsDispatcher, IPositionsDispatcherTrait, ICoreDispatcher, ICoreDispatcherTrait,
        PoolKey, MAX_TICK_SPACING, max_bounds, max_liquidity, contract_address_const,
        tick_to_sqrt_ratio, Bounds, i129, TICKS_IN_ONE_PERCENT, Zero, IMockERC20,
        IMockERC20Dispatcher, IMockERC20DispatcherTrait
    };

    #[test]
    #[should_panic(expected: ('TICK_SPACING', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED'))]
    fn test_before_initialize_pool_invalid_tick_spacing() {
        let mut d: Deployer = Default::default();
        let core = d.deploy_core();
        let twamm = d.deploy_twamm(core);
        let (token0, token1) = d.deploy_two_mock_tokens();

        core
            .initialize_pool(
                PoolKey {
                    token0: token0.contract_address,
                    token1: token1.contract_address,
                    fee: 0,
                    tick_spacing: 1,
                    extension: twamm.contract_address,
                },
                Zero::zero()
            );
    }

    #[test]
    fn test_before_initialize_pool_valid_tick_spacing() {
        let mut d: Deployer = Default::default();
        let core = d.deploy_core();
        let twamm = d.deploy_twamm(core);
        let (token0, token1) = d.deploy_two_mock_tokens();

        core
            .initialize_pool(
                PoolKey {
                    token0: token0.contract_address,
                    token1: token1.contract_address,
                    fee: 0,
                    tick_spacing: MAX_TICK_SPACING,
                    extension: twamm.contract_address,
                },
                Zero::zero()
            );
    }

    #[test]
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
        let mut d: Deployer = Default::default();
        let core = d.deploy_core();
        let twamm = d.deploy_twamm(core);

        let caller = contract_address_const::<42>();
        set_contract_address(caller);

        let setup = d
            .setup_pool_with_core(
                core,
                fee: 0,
                tick_spacing: MAX_TICK_SPACING,
                initial_tick: Zero::zero(),
                extension: twamm.contract_address,
            );
        let positions = d.deploy_positions(setup.core);
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

        positions
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
    fn test_before_update_position_valid_bounds() {
        let mut d: Deployer = Default::default();
        let core = d.deploy_core();
        let twamm = d.deploy_twamm(core);

        let caller = contract_address_const::<42>();
        set_contract_address(caller);

        let setup = d
            .setup_pool_with_core(
                core,
                fee: 0,
                tick_spacing: MAX_TICK_SPACING,
                initial_tick: Zero::zero(),
                extension: twamm.contract_address,
            );
        let positions = d.deploy_positions(setup.core);
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

        positions
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

mod PlaceOrderTestsValidateTime {
    use super::{
        PrintTrait, Deployer, DeployerTrait, ICoreDispatcher, ICoreDispatcherTrait, PoolKey,
        MAX_TICK_SPACING, ITWAMMDispatcher, ITWAMMDispatcherTrait, OrderKey, get_block_timestamp,
        set_block_timestamp, pop_log, IMockERC20, IMockERC20Dispatcher, IMockERC20DispatcherTrait,
        SIXTEEN_POW_ZERO, SIXTEEN_POW_ONE, SIXTEEN_POW_TWO, SIXTEEN_POW_THREE, SIXTEEN_POW_FOUR,
        SIXTEEN_POW_FIVE, SIXTEEN_POW_SIX, SIXTEEN_POW_SEVEN, TWAMMPoolKey, Zero
    };

    #[test]
    #[should_panic(expected: ('INVALID_END_TIME', 'ENTRYPOINT_FAILED'))]
    fn test_place_order_at_timestamp() {
        let mut d: Deployer = Default::default();
        let core = d.deploy_core();
        let twamm = d.deploy_twamm(core);
        let (token0, token1) = d.deploy_two_mock_tokens();

        let twamm_pool_key = TWAMMPoolKey {
            token0: token0.contract_address, token1: token1.contract_address, fee: 0,
        };

        let order_key = OrderKey {
            // current timestamp is 0
            twamm_pool_key: twamm_pool_key, is_sell_token1: false, start_time: 0, end_time: 0
        };

        let amount = 100_000_000;
        token0.increase_balance(twamm.contract_address, amount);
        ITWAMMDispatcher { contract_address: twamm.contract_address }
            .place_order(order_key, amount);
    }

    #[test]
    fn test_place_order_time_validation() {
        // the tests take too long so we don't run them all
        // however, they are all valid/passing

        // timestamp is multiple of 16**N

        // _test_place_order_time_validation(timestamp: SIXTEEN_POW_ONE);
        // _test_place_order_time_validation(timestamp: SIXTEEN_POW_TWO);
        // _test_place_order_time_validation(timestamp: SIXTEEN_POW_THREE);
        // _test_place_order_time_validation(timestamp: SIXTEEN_POW_FOUR);
        // _test_place_order_time_validation(timestamp: SIXTEEN_POW_FIVE);
        // _test_place_order_time_validation(timestamp: SIXTEEN_POW_SIX);
        // _test_place_order_time_validation(timestamp: SIXTEEN_POW_SEVEN);

        // timestamp is _not_ multiple of 16**N

        // _test_place_order_time_validation(timestamp: 1);
        // _test_place_order_time_validation(timestamp: 100);
        // _test_place_order_time_validation(timestamp: 1_000);
        // _test_place_order_time_validation(timestamp: 1_000_000);
        // _test_place_order_time_validation(timestamp: 1_000_000_000);
        // _test_place_order_time_validation(timestamp: 1_000_000_000_000);
        // _test_place_order_time_validation(timestamp: 1_000_000_000_000_000);

        _test_place_order_time_validation(timestamp: 0);
    }

    fn _test_place_order_time_validation(timestamp: u64) {
        // Do not allow orders to be placed in the smallest interval
        // orders expire in <= 16**1 seconds 
        // do not allow 16**0 = 1 second precision

        // orders expire in <= 16**2 = 256 seconds (~4.2min),
        // allow 16**1 = 16 seconds precision
        assert_place_order_and_validate_time(
            timestamp: timestamp,
            prev_interval: SIXTEEN_POW_ONE,
            interval: SIXTEEN_POW_TWO,
            step: SIXTEEN_POW_ONE
        );

        // orders expire in <= 16**3 = 4,096 seconds (~1hr),
        // allow 16**2 = 256 seconds (~4.2min) precision
        assert_place_order_and_validate_time(
            timestamp: timestamp,
            prev_interval: SIXTEEN_POW_TWO,
            interval: SIXTEEN_POW_THREE,
            step: SIXTEEN_POW_TWO
        );

        // orders expire in <= 16**4 = 65,536 seconds (~18hrs),
        // allow 16**3 = 4,096 seconds (~1hr) precision
        assert_place_order_and_validate_time(
            timestamp: timestamp,
            prev_interval: SIXTEEN_POW_THREE,
            interval: SIXTEEN_POW_FOUR,
            step: SIXTEEN_POW_THREE
        );

        // orders expire in <= 16**5 = 1,048,576 seconds (~12 days),
        // allow 16**4 = 65,536 seconds (~18hrs) precision
        assert_place_order_and_validate_time(
            timestamp: timestamp,
            prev_interval: SIXTEEN_POW_FOUR,
            interval: SIXTEEN_POW_FIVE,
            step: SIXTEEN_POW_FOUR
        );

        // orders expire in <= 16**6 = 16,777,216 seconds (~6.4 months),
        // allow 16**5 = 1,048,576 seconds (~12 days) precision
        assert_place_order_and_validate_time(
            timestamp: timestamp,
            prev_interval: SIXTEEN_POW_FIVE,
            interval: SIXTEEN_POW_SIX,
            step: SIXTEEN_POW_FIVE
        );

        // orders expire in <= 16**7 = 268,435,456 seconds (~8.5 years),
        // allow 16**6 = 16,777,216 (~6.4 month) precision
        assert_place_order_and_validate_time(
            timestamp: timestamp,
            prev_interval: SIXTEEN_POW_SIX,
            interval: SIXTEEN_POW_SEVEN,
            step: SIXTEEN_POW_SIX
        );
    }

    fn assert_place_order_and_validate_time(
        timestamp: u64, prev_interval: u64, interval: u64, step: u64
    ) {
        set_block_timestamp(timestamp);

        let mut d: Deployer = Default::default();
        let core = d.deploy_core();
        let twamm = d.deploy_twamm(core);
        let (token0, token1) = d.deploy_two_mock_tokens();

        let amount = 100_000_000;

        let twamm_pool_key = TWAMMPoolKey {
            token0: token0.contract_address, token1: token1.contract_address, fee: 0,
        };

        // end time at the interval time
        let mut order_key = OrderKey {
            twamm_pool_key: twamm_pool_key,
            is_sell_token1: false,
            start_time: 0,
            end_time: timestamp + prev_interval
        };
        token0.increase_balance(twamm.contract_address, amount);
        let mut token_id = ITWAMMDispatcher { contract_address: twamm.contract_address }
            .place_order(order_key, amount);
        let mut order = ITWAMMDispatcher { contract_address: twamm.contract_address }
            .get_order_state(order_key, token_id,);
        assert_eq!(token_id, 1);
        // assert_eq!(
        //     order.end_time == order_key.end_time
        //         || order.end_time == (order_key.end_time - (order_key.end_time % step)),
        //     'end_TIME'
        // );

        // first valid end time in interval
        order_key =
            OrderKey {
                twamm_pool_key: twamm_pool_key,
                is_sell_token1: false,
                start_time: 0,
                end_time: timestamp + prev_interval + step
            };
        token0.increase_balance(twamm.contract_address, amount);
        token_id = ITWAMMDispatcher { contract_address: twamm.contract_address }
            .place_order(order_key, amount);
        order = ITWAMMDispatcher { contract_address: twamm.contract_address }
            .get_order_state(order_key, token_id,);
        assert_eq!(token_id, 2);
        // assert_eq!(
        //     order.end_time == order_key.end_time
        //         || order.end_time == (order_key.end_time - (order_key.end_time % step)),
        //     'end_TIME'
        // );

        // last valid end time in interval
        order_key =
            OrderKey {
                twamm_pool_key: twamm_pool_key,
                is_sell_token1: false,
                start_time: 0,
                end_time: timestamp + interval - step
            };
        token0.increase_balance(twamm.contract_address, amount);
        token_id = ITWAMMDispatcher { contract_address: twamm.contract_address }
            .place_order(order_key, amount);
        order = ITWAMMDispatcher { contract_address: twamm.contract_address }
            .get_order_state(order_key, token_id,);
        assert_eq!(token_id, 3);
    // assert_eq!(
    //     order.end_time == order_key.end_time
    //         || order.end_time == (order_key.end_time - (order_key.end_time % step)),
    //     'end_TIME'
    // );
    }
}

mod PlaceOrderTests {
    use super::{
        PrintTrait, Deployer, DeployerTrait, ICoreDispatcher, ICoreDispatcherTrait, PoolKey,
        MAX_TICK_SPACING, ITWAMMDispatcher, ITWAMMDispatcherTrait, OrderKey, get_block_timestamp,
        set_block_timestamp, pop_log, IMockERC20, IMockERC20Dispatcher, IMockERC20DispatcherTrait,
        TWAMMPoolKey, SIXTEEN_POW_ZERO, SIXTEEN_POW_ONE, SIXTEEN_POW_TWO, SIXTEEN_POW_THREE,
        SIXTEEN_POW_FOUR, SIXTEEN_POW_FIVE, SIXTEEN_POW_SIX, SIXTEEN_POW_SEVEN, OrderPlaced, Zero
    };

    #[test]
    #[should_panic(expected: ('INVALID_SPACING', 'ENTRYPOINT_FAILED'))]
    fn test_place_order_end_time_too_small() {
        run_place_order_and_validate_sale_rate(
            amount: 100_000_000,
            timestamp: 0,
            end_time: 15,
            expected_sale_rate: 0x5f5e1000000000 // 6,250,000 * 2**32
        );
    }

    #[test]
    fn test_place_order_sale_rate() {
        run_place_order_and_validate_sale_rate(
            amount: 100_000_000,
            timestamp: 0,
            end_time: SIXTEEN_POW_ONE,
            expected_sale_rate: 0x5f5e1000000000 // 6,250,000 * 2**32
        );
        run_place_order_and_validate_sale_rate(
            amount: 100_000_000,
            timestamp: 0,
            end_time: SIXTEEN_POW_TWO,
            expected_sale_rate: 0x5f5e100000000 // ~ 390,625 * 2**32
        );
        run_place_order_and_validate_sale_rate(
            amount: 100_000_000,
            timestamp: 0,
            end_time: SIXTEEN_POW_THREE,
            // scaled by 2**32
            expected_sale_rate: 0x5f5e10000000 // ~ 24,414.0625 * 2**32
        );
        run_place_order_and_validate_sale_rate(
            amount: 100_000_000,
            timestamp: 0,
            end_time: SIXTEEN_POW_FOUR,
            // scaled by 2**32
            expected_sale_rate: 0x5f5e1000000 // ~ 1,525.87890625 * 2**32
        );
        run_place_order_and_validate_sale_rate(
            amount: 100_000_000,
            timestamp: 0,
            end_time: SIXTEEN_POW_FIVE,
            // scaled by 2**32
            expected_sale_rate: 0x5f5e100000 // ~ 95.3674316406 * 2**32
        );
        run_place_order_and_validate_sale_rate(
            amount: 100_000_000,
            timestamp: 0,
            end_time: SIXTEEN_POW_SIX,
            // scaled by 2**32
            expected_sale_rate: 0x5f5e10000 // ~ 5.9604644775 * 2**32
        );
        run_place_order_and_validate_sale_rate(
            amount: 100_000_000,
            timestamp: 0,
            end_time: SIXTEEN_POW_SEVEN,
            // scaled by 2**32
            expected_sale_rate: 0x5f5e1000 // ~ 0.3725290298 * 2**32
        );
    }

    fn run_place_order_and_validate_sale_rate(
        amount: u128, timestamp: u64, end_time: u64, expected_sale_rate: u128
    ) {
        set_block_timestamp(timestamp);

        let mut d: Deployer = Default::default();
        let core = d.deploy_core();
        let twamm = d.deploy_twamm(core);
        let (token0, token1) = d.deploy_two_mock_tokens();

        let twamm_pool_key = TWAMMPoolKey {
            token0: token0.contract_address, token1: token1.contract_address, fee: 0,
        };

        let order_key = OrderKey {
            twamm_pool_key: twamm_pool_key, is_sell_token1: false, start_time: 0, end_time,
        };

        token0.increase_balance(twamm.contract_address, amount);
        let token_id = ITWAMMDispatcher { contract_address: twamm.contract_address }
            .place_order(order_key, amount);

        let order = ITWAMMDispatcher { contract_address: twamm.contract_address }
            .get_order_state(order_key, token_id,);

        assert_eq!(order.sale_rate, expected_sale_rate);
    }

    #[test]
    fn test_two_orders_and_global_rate_no_virtual_orders_executed() {
        let mut d: Deployer = Default::default();
        let core = d.deploy_core();
        let twamm = d.deploy_twamm(core);
        let _event: ekubo::components::owned::Owned::OwnershipTransferred = pop_log(
            twamm.contract_address
        )
            .unwrap();
        let (token0, token1) = d.deploy_two_mock_tokens();

        let amount = 100_000_000;

        let twamm_pool_key = TWAMMPoolKey {
            token0: token0.contract_address, token1: token1.contract_address, fee: 0,
        };

        // order 0
        let order_key_1 = OrderKey {
            twamm_pool_key: twamm_pool_key, is_sell_token1: false, start_time: 0, end_time: 16 * 16,
        };
        token0.increase_balance(twamm.contract_address, amount);
        ITWAMMDispatcher { contract_address: twamm.contract_address }
            .place_order(order_key_1, amount);

        let event: OrderPlaced = pop_log(twamm.contract_address).unwrap();

        assert_eq!(event.id, 1);
        assert(
            event.order_key.twamm_pool_key.token0 == order_key_1.twamm_pool_key.token0, 'token0'
        );
        assert(
            event.order_key.twamm_pool_key.token1 == order_key_1.twamm_pool_key.token1, 'token1'
        );
        assert_eq!(event.amount, amount);
        assert_eq!(event.sale_rate, 0x5f5e100000000);

        // order 1
        let order_key_2 = OrderKey {
            twamm_pool_key: twamm_pool_key,
            is_sell_token1: false,
            start_time: 0,
            end_time: 16 * 16 * 16,
        };
        token0.increase_balance(twamm.contract_address, amount);
        ITWAMMDispatcher { contract_address: twamm.contract_address }
            .place_order(order_key_2, amount);

        let event: OrderPlaced = pop_log(twamm.contract_address).unwrap();

        assert_eq!(event.id, 2);
        assert(
            event.order_key.twamm_pool_key.token0 == order_key_2.twamm_pool_key.token0, 'token0'
        );
        assert(
            event.order_key.twamm_pool_key.token1 == order_key_2.twamm_pool_key.token1, 'token1'
        );
        assert_eq!(event.amount, amount);
        assert_eq!(event.sale_rate, 0x5f5e10000000);

        // global rate
        let global_sale_rate = ITWAMMDispatcher { contract_address: twamm.contract_address }
            .get_sale_rate(
                TWAMMPoolKey {
                    token0: token0.contract_address, token1: token1.contract_address, fee: 0
                }
            );

        let (gsr0, _) = global_sale_rate;
        assert_eq!(gsr0, 0x5f5e100000000 + 0x5f5e10000000);
    }

    #[test]
    #[should_panic(
        expected: (
            'INSUFFICIENT_TF_BALANCE',
            'ENTRYPOINT_FAILED',
            'ENTRYPOINT_FAILED',
            'ENTRYPOINT_FAILED',
            'ENTRYPOINT_FAILED',
            'ENTRYPOINT_FAILED'
        )
    )]
    fn test_place_order_no_token_transfer() {
        let mut d: Deployer = Default::default();
        let core = d.deploy_core();
        let twamm = d.deploy_twamm(core);
        let (token0, token1) = d.deploy_two_mock_tokens();

        let amount = 100_000_000;
        let twamm_pool_key = TWAMMPoolKey {
            token0: token0.contract_address, token1: token1.contract_address, fee: 0,
        };
        let order_key = OrderKey {
            twamm_pool_key: twamm_pool_key, is_sell_token1: false, start_time: 0, end_time: 16 * 16,
        };

        ITWAMMDispatcher { contract_address: twamm.contract_address }
            .place_order(order_key, amount);
    }
}

mod CancelOrderTests {
    use super::{
        PrintTrait, Deployer, DeployerTrait, ICoreDispatcher, ICoreDispatcherTrait, PoolKey,
        MAX_TICK_SPACING, ITWAMMDispatcher, ITWAMMDispatcherTrait, OrderKey, get_block_timestamp,
        set_block_timestamp, pop_log, get_contract_address, IMockERC20, IMockERC20Dispatcher,
        IMockERC20DispatcherTrait, SIXTEEN_POW_TWO, SIXTEEN_POW_THREE, TWAMMPoolKey,
        IERC20Dispatcher, IERC20DispatcherTrait, place_order, set_up_twamm_with_default_liquidity,
        i129
    };

    #[test]
    #[should_panic(expected: ('ORDER_ENDED', 'ENTRYPOINT_FAILED'))]
    fn test_place_order_and_cancel_after_end_time() {
        let mut d: Deployer = Default::default();
        let core = d.deploy_core();
        let twamm = d.deploy_twamm(core);
        let (token0, token1) = d.deploy_two_mock_tokens();

        let amount = 100_000_000;
        let twamm_pool_key = TWAMMPoolKey {
            token0: token0.contract_address, token1: token1.contract_address, fee: 0,
        };
        let order_key = OrderKey {
            twamm_pool_key: twamm_pool_key,
            is_sell_token1: false,
            start_time: 0,
            end_time: SIXTEEN_POW_THREE
        };

        token0.increase_balance(twamm.contract_address, amount);
        let token_id = ITWAMMDispatcher { contract_address: twamm.contract_address }
            .place_order(order_key, amount);

        set_block_timestamp(order_key.end_time + 1);

        ITWAMMDispatcher { contract_address: twamm.contract_address }
            .cancel_order(order_key, token_id);
    }

    #[test]
    fn test_place_order_and_cancel_before_order_execution() {
        let mut d: Deployer = Default::default();
        let core = d.deploy_core();
        let fee = 0;
        let initial_tick = i129 { mag: 693147, sign: false };
        let (twamm, setup) = set_up_twamm_with_default_liquidity(ref d, core, fee, initial_tick);

        let timestamp = SIXTEEN_POW_TWO;
        set_block_timestamp(timestamp);

        let twamm_pool_key = TWAMMPoolKey {
            token0: setup.token0.contract_address, token1: setup.token1.contract_address, fee
        };

        let amount = 1_000 * 1000000000000000000;
        let (order1_id, order1_key, _) = place_order(
            twamm,
            setup.token0,
            setup.token1,
            twamm_pool_key,
            false,
            SIXTEEN_POW_TWO,
            SIXTEEN_POW_THREE,
            amount
        );

        twamm.cancel_order(order1_key, order1_id);

        let token_balance = IERC20Dispatcher { contract_address: setup.token0.contract_address }
            .balanceOf(get_contract_address());

        assert(token_balance == 0x3635c9adc5de9fffff, 'token0.balance');
    }

    #[test]
    #[should_panic(expected: ('MUST_WITHDRAW_PROCEEDS', 'ENTRYPOINT_FAILED'))]
    fn test_place_order_and_cancel_during_order_execution_without_withdrawing_proceeds() {
        let mut d: Deployer = Default::default();
        let core = d.deploy_core();
        let fee = 0;
        let initial_tick = i129 { mag: 693147, sign: false };
        let (twamm, setup) = set_up_twamm_with_default_liquidity(ref d, core, fee, initial_tick);

        let timestamp = SIXTEEN_POW_TWO;
        set_block_timestamp(timestamp);

        let twamm_pool_key = TWAMMPoolKey {
            token0: setup.token0.contract_address, token1: setup.token1.contract_address, fee
        };

        let amount = 1_000 * 1000000000000000000;
        let (order1_id, order1_key, _) = place_order(
            twamm,
            setup.token0,
            setup.token1,
            twamm_pool_key,
            false,
            SIXTEEN_POW_TWO,
            SIXTEEN_POW_THREE,
            amount
        );

        set_block_timestamp(SIXTEEN_POW_THREE - 1);

        twamm.cancel_order(order1_key, order1_id);
    }

    #[test]
    fn test_place_order_and_cancel_during_before_full_order_execution() {
        let mut d: Deployer = Default::default();
        let core = d.deploy_core();
        let fee = 0;
        let initial_tick = i129 { mag: 693147, sign: false };
        let (twamm, setup) = set_up_twamm_with_default_liquidity(ref d, core, fee, initial_tick);

        let timestamp = SIXTEEN_POW_TWO;
        set_block_timestamp(timestamp);

        let twamm_pool_key = TWAMMPoolKey {
            token0: setup.token0.contract_address, token1: setup.token1.contract_address, fee
        };

        let amount = 1_000 * 1000000000000000000;
        let (order1_id, order1_key, _) = place_order(
            twamm,
            setup.token0,
            setup.token1,
            twamm_pool_key,
            false,
            SIXTEEN_POW_TWO,
            SIXTEEN_POW_THREE,
            amount
        );

        set_block_timestamp(SIXTEEN_POW_THREE - 1);

        twamm.withdraw_from_order(order1_key, order1_id);
        twamm.cancel_order(order1_key, order1_id);
    }
}

mod PlaceOrderAndCheckExecutionTimesAndRates {
    use super::{
        PrintTrait, Deployer, DeployerTrait, ICoreDispatcher, ICoreDispatcherTrait, PoolKey,
        MAX_TICK_SPACING, ITWAMMDispatcher, ITWAMMDispatcherTrait, OrderKey, get_block_timestamp,
        set_block_timestamp, pop_log, IMockERC20, IMockERC20Dispatcher, IMockERC20DispatcherTrait,
        contract_address_const, set_contract_address, max_bounds, update_position, max_liquidity,
        Bounds, tick_to_sqrt_ratio, i129, TICKS_IN_ONE_PERCENT, IPositionsDispatcher,
        IPositionsDispatcherTrait, get_contract_address, IExtensionDispatcher, SetupPoolResult,
        SIXTEEN_POW_ZERO, SIXTEEN_POW_ONE, SIXTEEN_POW_TWO, SIXTEEN_POW_THREE, SIXTEEN_POW_FOUR,
        SIXTEEN_POW_FIVE, SIXTEEN_POW_SIX, SIXTEEN_POW_SEVEN, OrderPlaced, VirtualOrdersExecuted,
        OrderState, TWAMMPoolKey, set_up_twamm_with_default_liquidity,
        place_order_with_default_start_time
    };

    #[test]
    fn test_place_orders_0() {
        // Both order expiries are after the current time
        // l = last virtual order time
        // t = current time
        // 0 = order for token0
        // 1 = order for token1
        // l---------------------t----0--1----------> time
        // trade from l->t

        let mut d: Deployer = Default::default();
        let core = d.deploy_core();
        let fee = 0;
        let initial_tick = i129 { mag: 693147, sign: false };
        let (twamm, setup) = set_up_twamm_with_default_liquidity(ref d, core, fee, initial_tick);

        let timestamp = SIXTEEN_POW_ONE;
        set_block_timestamp(timestamp);

        let twamm_pool_key = TWAMMPoolKey {
            token0: setup.token0.contract_address, token1: setup.token1.contract_address, fee
        };

        let amount = 10_000 * 1000000000000000000;

        let order1_timestamp = timestamp;
        let order1_end_time = timestamp + SIXTEEN_POW_THREE - SIXTEEN_POW_ONE;
        place_order_with_default_start_time(
            twamm, setup.token0, setup.token1, twamm_pool_key, false, order1_end_time, amount
        );

        let _event: OrderPlaced = pop_log(twamm.contract_address).unwrap();

        let order2_timestamp = timestamp + SIXTEEN_POW_ONE;
        set_block_timestamp(order2_timestamp);
        let order2_end_time = order2_timestamp + SIXTEEN_POW_THREE - 2 * SIXTEEN_POW_ONE;
        place_order_with_default_start_time(
            twamm, setup.token0, setup.token1, twamm_pool_key, true, order2_end_time, amount
        );

        let event: VirtualOrdersExecuted = pop_log(twamm.contract_address).unwrap();

        assert_eq!(event.last_virtual_order_time, order1_timestamp);
        assert_eq!(event.next_virtual_order_time, order2_timestamp);
    }

    #[test]
    fn test_place_orders_1() {
        // Order 0 expiries before current time
        // Order 1 expiries after current time
        // l = last virtual order time
        // t = current time
        // 1 = order for token0
        // 2 = order for token1
        // l---------------0-----t-------1----------> time
        // execute from l->0 and from 0->t

        let mut d: Deployer = Default::default();
        let core = d.deploy_core();
        let fee = 0;
        let initial_tick = i129 { mag: 693147, sign: false };
        let (twamm, setup) = set_up_twamm_with_default_liquidity(ref d, core, fee, initial_tick);

        let timestamp = SIXTEEN_POW_ONE;
        set_block_timestamp(timestamp);

        let twamm_pool_key = TWAMMPoolKey {
            token0: setup.token0.contract_address, token1: setup.token1.contract_address, fee
        };

        let amount = 10_000 * 1000000000000000000;
        let order1_timestamp = timestamp;
        let order1_end_time = timestamp + SIXTEEN_POW_ONE;
        let (_, _, order1) = place_order_with_default_start_time(
            twamm, setup.token0, setup.token1, twamm_pool_key, false, order1_end_time, amount
        );

        let _event: OrderPlaced = pop_log(twamm.contract_address).unwrap();

        let order2_timestamp = order1_end_time + SIXTEEN_POW_ONE;
        set_block_timestamp(order2_timestamp);
        let order2_end_time = order2_timestamp + SIXTEEN_POW_THREE - 3 * SIXTEEN_POW_ONE;
        place_order_with_default_start_time(
            twamm, setup.token0, setup.token1, twamm_pool_key, true, order2_end_time, amount
        );

        // first order execution
        let event: VirtualOrdersExecuted = pop_log(twamm.contract_address).unwrap();

        assert_eq!(event.last_virtual_order_time, order1_timestamp);
        assert_eq!(event.next_virtual_order_time, order1_end_time);
        assert_eq!(event.token0_sale_rate, order1.sale_rate);
        assert_eq!(event.token1_sale_rate, 0);
    // second order execution
    // no event is emitted since both sale rates are 0
    }

    #[test]
    fn test_place_orders_2() {
        // Order 0 expiries before current time
        // Order 1 expiries before current time
        // l = last virtual order time
        // t = current time
        // 1 = order for token0
        // 2 = order for token1
        // l---------------0--1--t------------------> time
        // execute from l->0, 0->1, 1->t

        let mut d: Deployer = Default::default();
        let core = d.deploy_core();
        let fee = 0;
        let initial_tick = i129 { mag: 693147, sign: false };
        let (twamm, setup) = set_up_twamm_with_default_liquidity(ref d, core, fee, initial_tick);

        let timestamp = 1_000_000;
        set_block_timestamp(timestamp);

        let twamm_pool_key = TWAMMPoolKey {
            token0: setup.token0.contract_address, token1: setup.token1.contract_address, fee
        };

        let amount = 100_000 * 1000000000000000000;
        let order1_timestamp = timestamp;
        let order1_end_time = timestamp + SIXTEEN_POW_ONE;
        let (_, _, order1) = place_order_with_default_start_time(
            twamm, setup.token0, setup.token1, twamm_pool_key, false, order1_end_time, amount
        );
        let _event: OrderPlaced = pop_log(twamm.contract_address).unwrap();

        let order2_end_time = timestamp + SIXTEEN_POW_ONE * 2;
        let (_, _, order2) = place_order_with_default_start_time(
            twamm, setup.token0, setup.token1, twamm_pool_key, true, order2_end_time, amount
        );
        let _event: OrderPlaced = pop_log(twamm.contract_address).unwrap();

        // after order2 expires
        let order_execution_timestamp = order2_end_time + SIXTEEN_POW_ONE;
        set_block_timestamp(order_execution_timestamp);

        // manually trigger virtual order execution
        twamm.execute_virtual_orders(setup.pool_key);

        // first order execution
        let event: VirtualOrdersExecuted = pop_log(twamm.contract_address).unwrap();

        assert_eq!(event.last_virtual_order_time, order1_timestamp);
        assert_eq!(event.next_virtual_order_time, order1_end_time);
        assert_eq!(event.token0_sale_rate, order1.sale_rate);
        assert_eq!(event.token1_sale_rate, order2.sale_rate);

        // second order execution
        let event: VirtualOrdersExecuted = pop_log(twamm.contract_address).unwrap();
        assert_eq!(event.last_virtual_order_time, order1_end_time);
        assert_eq!(event.next_virtual_order_time, order2_end_time);

        assert_eq!(event.token0_sale_rate, 0);
        assert_eq!(event.token1_sale_rate, order2.sale_rate);
    // third order execution
    // no event is emitted since both sale rates are 0
    }

    #[test]
    fn test_place_orders_3() {
        // Order 0 expiries before current time
        // Order 1 expiries before current time
        // l = last virtual order time
        // t = current time
        // 1 = order for token0
        // 2 = order for token1
        // l---------------0--1--t------------------> time
        // execute from l->0, 0->1, 1->t

        let mut d: Deployer = Default::default();
        let core = d.deploy_core();
        let fee = 0;
        let initial_tick = i129 { mag: 693147, sign: false };
        let (twamm, setup) = set_up_twamm_with_default_liquidity(ref d, core, fee, initial_tick);

        let timestamp = 1_000_000;
        set_block_timestamp(timestamp);

        let twamm_pool_key = TWAMMPoolKey {
            token0: setup.token0.contract_address, token1: setup.token1.contract_address, fee
        };
        let amount = 10_000 * 1000000000000000000;
        let order1_timestamp = timestamp;
        let order1_end_time = timestamp + SIXTEEN_POW_ONE;
        let (_, _, order1) = place_order_with_default_start_time(
            twamm, setup.token0, setup.token1, twamm_pool_key, false, order1_end_time, amount
        );

        let _event: OrderPlaced = pop_log(twamm.contract_address).unwrap();

        let order2_end_time = timestamp
            + SIXTEEN_POW_THREE
            - 0x240; // ensure end time is valid and in a diff word
        let (_, _, order2) = place_order_with_default_start_time(
            twamm, setup.token0, setup.token1, twamm_pool_key, true, order2_end_time, amount
        );
        let _event: OrderPlaced = pop_log(twamm.contract_address).unwrap();

        // after order2 expires
        let order_execution_timestamp = order2_end_time + SIXTEEN_POW_THREE;
        set_block_timestamp(order_execution_timestamp);

        // manually trigger virtual order execution
        twamm.execute_virtual_orders(setup.pool_key);

        // first order execution
        let event: VirtualOrdersExecuted = pop_log(twamm.contract_address).unwrap();

        assert_eq!(event.last_virtual_order_time, order1_timestamp);
        assert_eq!(event.next_virtual_order_time, order1_end_time);
        assert_eq!(event.token0_sale_rate, order1.sale_rate);
        assert_eq!(event.token1_sale_rate, order2.sale_rate);

        // second order execution
        let event: VirtualOrdersExecuted = pop_log(twamm.contract_address).unwrap();
        assert_eq!(event.last_virtual_order_time, order1_end_time);
        assert_eq!(event.next_virtual_order_time, order2_end_time);

        assert_eq!(event.token0_sale_rate, 0);
        assert_eq!(event.token1_sale_rate, order2.sale_rate);
    // third order execution
    // no event is emitted since both sale rates are 0
    }
}

mod PlaceOrdersCheckDeltaAndNet {
    use super::{
        PrintTrait, Deployer, DeployerTrait, ICoreDispatcher, ICoreDispatcherTrait, PoolKey,
        MAX_TICK_SPACING, ITWAMMDispatcher, ITWAMMDispatcherTrait, OrderKey, get_block_timestamp,
        set_block_timestamp, pop_log, IMockERC20, IMockERC20Dispatcher, IMockERC20DispatcherTrait,
        contract_address_const, set_contract_address, max_bounds, update_position, max_liquidity,
        Bounds, tick_to_sqrt_ratio, i129, i129Trait, AddDeltaTrait, TICKS_IN_ONE_PERCENT,
        IPositionsDispatcher, IPositionsDispatcherTrait, get_contract_address, IExtensionDispatcher,
        SetupPoolResult, SIXTEEN_POW_ZERO, SIXTEEN_POW_ONE, SIXTEEN_POW_TWO, SIXTEEN_POW_THREE,
        SIXTEEN_POW_FOUR, SIXTEEN_POW_FIVE, SIXTEEN_POW_SIX, SIXTEEN_POW_SEVEN, OrderPlaced,
        VirtualOrdersExecuted, OrderState, TWAMMPoolKey, set_up_twamm_with_default_liquidity,
        place_order_with_default_start_time, place_order, calculate_sale_rate
    };

    #[test]
    fn test_place_orders_0() {
        // Both order expiries are after the current time
        // l = last virtual order time
        // t = current time
        // 1 = first order for token0
        // 2 = second order for token0
        // l---------------------t----1/2-----------> time
        // place orders and check sale rate nets

        let mut d: Deployer = Default::default();
        let core = d.deploy_core();
        let fee = 0;
        let initial_tick = i129 { mag: 693147, sign: false };
        let (twamm, setup) = set_up_twamm_with_default_liquidity(ref d, core, fee, initial_tick);

        let timestamp = SIXTEEN_POW_TWO;
        set_block_timestamp(timestamp);

        let twamm_pool_key = TWAMMPoolKey {
            token0: setup.token0.contract_address, token1: setup.token1.contract_address, fee
        };

        let amount = 10_000 * 1000000000000000000;
        let duration = 2 * SIXTEEN_POW_TWO;
        let order1_end_time = timestamp + duration;
        let expected_sale_rate_net = calculate_sale_rate(amount, order1_end_time, timestamp);

        let (_, _, _) = place_order_with_default_start_time(
            twamm, setup.token0, setup.token1, twamm_pool_key, false, order1_end_time, amount
        );

        let _event: OrderPlaced = pop_log(twamm.contract_address).unwrap();

        let (token0_sale_rate_net, _) = twamm.get_sale_rate_net(twamm_pool_key, order1_end_time);
        assert_eq!(token0_sale_rate_net, expected_sale_rate_net);

        let order2_start_time = order1_end_time; // start time is order1 end time
        let order2_end_time = order1_end_time + 2 * SIXTEEN_POW_TWO;
        place_order(
            twamm,
            setup.token0,
            setup.token1,
            twamm_pool_key,
            false,
            order2_start_time,
            order2_end_time,
            amount
        );

        let _event: OrderPlaced = pop_log(twamm.contract_address).unwrap();

        let (token0_sale_rate_net, _) = twamm.get_sale_rate_net(twamm_pool_key, order1_end_time);
        assert_eq!(token0_sale_rate_net, expected_sale_rate_net * 2);

        set_block_timestamp(order2_end_time + 1);
        twamm.execute_virtual_orders(setup.pool_key);

        let event: VirtualOrdersExecuted = pop_log(twamm.contract_address).unwrap();

        assert_eq!(event.last_virtual_order_time, timestamp);
        assert_eq!(event.next_virtual_order_time, order1_end_time);

        let event: VirtualOrdersExecuted = pop_log(twamm.contract_address).unwrap();

        assert_eq!(event.last_virtual_order_time, order1_end_time);
        assert_eq!(event.next_virtual_order_time, order2_end_time);
    }

    #[test]
    fn test_place_orders_1() {
        // Both order expiries are after the current time
        // l = last virtual order time
        // t = current time
        // 1 = first order for token1
        // 2 = second order for token1
        // l---------------------t----1/2-----------> time
        // place orders and check sale rate nets

        let mut d: Deployer = Default::default();
        let core = d.deploy_core();
        let fee = 0;
        let initial_tick = i129 { mag: 693147, sign: false };
        let (twamm, setup) = set_up_twamm_with_default_liquidity(ref d, core, fee, initial_tick);

        let timestamp = SIXTEEN_POW_TWO;
        set_block_timestamp(timestamp);

        let twamm_pool_key = TWAMMPoolKey {
            token0: setup.token0.contract_address, token1: setup.token1.contract_address, fee
        };

        let amount = 10_000 * 1000000000000000000;
        let duration = 2 * SIXTEEN_POW_TWO;
        let order1_end_time = timestamp + duration;
        let expected_sale_rate_net = calculate_sale_rate(amount, order1_end_time, timestamp);

        let (_, _, _) = place_order_with_default_start_time(
            twamm, setup.token0, setup.token1, twamm_pool_key, true, order1_end_time, amount
        );

        let _event: OrderPlaced = pop_log(twamm.contract_address).unwrap();

        let (_, token1_sale_rate_net) = twamm.get_sale_rate_net(twamm_pool_key, order1_end_time);
        assert_eq!(token1_sale_rate_net, expected_sale_rate_net);

        let order2_start_time = order1_end_time; // start time is order1 end time
        let order2_end_time = order1_end_time + 2 * SIXTEEN_POW_TWO;
        place_order(
            twamm,
            setup.token0,
            setup.token1,
            twamm_pool_key,
            true,
            order2_start_time,
            order2_end_time,
            amount
        );

        let _event: OrderPlaced = pop_log(twamm.contract_address).unwrap();

        let (_, token1_sale_rate_net) = twamm.get_sale_rate_net(twamm_pool_key, order1_end_time);
        assert_eq!(token1_sale_rate_net, expected_sale_rate_net * 2);

        set_block_timestamp(order2_end_time + 1);
        twamm.execute_virtual_orders(setup.pool_key);

        let event: VirtualOrdersExecuted = pop_log(twamm.contract_address).unwrap();

        assert_eq!(event.last_virtual_order_time, timestamp);
        assert_eq!(event.next_virtual_order_time, order1_end_time);

        let event: VirtualOrdersExecuted = pop_log(twamm.contract_address).unwrap();

        assert_eq!(event.last_virtual_order_time, order1_end_time);
        assert_eq!(event.next_virtual_order_time, order2_end_time);
    }

    #[test]
    fn test_place_orders_2() {
        // Both order expiries are after the current time
        // l = last virtual order time
        // t = current time
        // 0 = first order for token0
        // 1 = second order for token0
        // l---------------------t----0/1-----------> time

        // place orders and cancel before execution, check sale rate nets

        let mut d: Deployer = Default::default();
        let core = d.deploy_core();
        let fee = 0;
        let initial_tick = i129 { mag: 693147, sign: false };
        let (twamm, setup) = set_up_twamm_with_default_liquidity(ref d, core, fee, initial_tick);

        let timestamp = SIXTEEN_POW_TWO;
        set_block_timestamp(timestamp);

        let twamm_pool_key = TWAMMPoolKey {
            token0: setup.token0.contract_address, token1: setup.token1.contract_address, fee
        };

        let amount = 10_000 * 1000000000000000000;
        let duration = 2 * SIXTEEN_POW_TWO;
        let order1_end_time = timestamp + duration;
        let expected_sale_rate_net = calculate_sale_rate(amount, order1_end_time, timestamp);

        let (order1_id, order1_key, _) = place_order_with_default_start_time(
            twamm, setup.token0, setup.token1, twamm_pool_key, false, order1_end_time, amount
        );

        let _event: OrderPlaced = pop_log(twamm.contract_address).unwrap();

        let (token0_sale_rate_net, _) = twamm.get_sale_rate_net(twamm_pool_key, order1_end_time);
        assert_eq!(token0_sale_rate_net, expected_sale_rate_net);

        let order2_start_time = order1_end_time; // start time is order1 end time
        let order2_end_time = order1_end_time + 2 * SIXTEEN_POW_TWO;
        let (order2_id, order2_key, _) = place_order(
            twamm,
            setup.token0,
            setup.token1,
            twamm_pool_key,
            false,
            order2_start_time,
            order2_end_time,
            amount
        );

        let _event: OrderPlaced = pop_log(twamm.contract_address).unwrap();

        let (token0_sale_rate_net, _) = twamm.get_sale_rate_net(twamm_pool_key, order1_end_time);
        assert_eq!(token0_sale_rate_net, expected_sale_rate_net * 2);

        // cancel both orders

        twamm.cancel_order(order1_key, order1_id);

        let (token0_sale_rate_net, _) = twamm.get_sale_rate_net(twamm_pool_key, order1_end_time);
        assert_eq!(token0_sale_rate_net, expected_sale_rate_net);

        twamm.cancel_order(order2_key, order2_id);

        let (token0_sale_rate_net, _) = twamm.get_sale_rate_net(twamm_pool_key, order1_end_time);
        assert_eq!(token0_sale_rate_net, 0);
    }

    #[test]
    fn test_place_orders_3() {
        // Both order expiries are after the current time
        // l = last virtual order time
        // t = current time
        // 0 = first order for token0
        // 1 = second order for token0
        // l---------------------t----0/1-----------> time

        // place orders and cancel before execution, check sale rate nets

        let mut d: Deployer = Default::default();
        let core = d.deploy_core();
        let fee = 0;
        let initial_tick = i129 { mag: 693147, sign: false };
        let (twamm, setup) = set_up_twamm_with_default_liquidity(ref d, core, fee, initial_tick);

        let timestamp = SIXTEEN_POW_TWO;
        set_block_timestamp(timestamp);

        let twamm_pool_key = TWAMMPoolKey {
            token0: setup.token0.contract_address, token1: setup.token1.contract_address, fee
        };

        let amount = 10_000 * 1000000000000000000;
        let duration = 2 * SIXTEEN_POW_TWO;
        let order1_end_time = timestamp + duration;
        let expected_sale_rate_net = calculate_sale_rate(amount, order1_end_time, timestamp);

        let (order1_id, order1_key, _) = place_order_with_default_start_time(
            twamm, setup.token0, setup.token1, twamm_pool_key, true, order1_end_time, amount
        );

        let _event: OrderPlaced = pop_log(twamm.contract_address).unwrap();

        let (_, token1_sale_rate_net) = twamm.get_sale_rate_net(twamm_pool_key, order1_end_time);
        assert_eq!(token1_sale_rate_net, expected_sale_rate_net);

        let order2_start_time = order1_end_time; // start time is order1 end time
        let order2_end_time = order1_end_time + 2 * SIXTEEN_POW_TWO;
        let (order2_id, order2_key, _) = place_order(
            twamm,
            setup.token0,
            setup.token1,
            twamm_pool_key,
            true,
            order2_start_time,
            order2_end_time,
            amount
        );

        let _event: OrderPlaced = pop_log(twamm.contract_address).unwrap();

        let (_, token1_sale_rate_net) = twamm.get_sale_rate_net(twamm_pool_key, order1_end_time);
        assert_eq!(token1_sale_rate_net, expected_sale_rate_net * 2);

        // cancel both orders

        twamm.cancel_order(order1_key, order1_id);

        let (_, token1_sale_rate_net) = twamm.get_sale_rate_net(twamm_pool_key, order1_end_time);
        assert_eq!(token1_sale_rate_net, expected_sale_rate_net);

        twamm.cancel_order(order2_key, order2_id);

        let (_, token1_sale_rate_net) = twamm.get_sale_rate_net(twamm_pool_key, order1_end_time);
        assert_eq!(token1_sale_rate_net, 0);
    }
}

mod PlaceOrderOnOneSideAndWithdrawProceeds {
    use super::{
        PrintTrait, Deployer, DeployerTrait, ICoreDispatcher, ICoreDispatcherTrait, PoolKey,
        MAX_TICK_SPACING, ITWAMMDispatcher, ITWAMMDispatcherTrait, OrderKey, get_block_timestamp,
        set_block_timestamp, pop_log, IMockERC20, IMockERC20Dispatcher, IMockERC20DispatcherTrait,
        contract_address_const, set_contract_address, max_bounds, update_position, max_liquidity,
        Bounds, tick_to_sqrt_ratio, i129, TICKS_IN_ONE_PERCENT, IPositionsDispatcher,
        IPositionsDispatcherTrait, get_contract_address, IExtensionDispatcher, SetupPoolResult,
        SIXTEEN_POW_ZERO, SIXTEEN_POW_ONE, SIXTEEN_POW_TWO, SIXTEEN_POW_THREE, SIXTEEN_POW_FOUR,
        SIXTEEN_POW_FIVE, SIXTEEN_POW_SIX, SIXTEEN_POW_SEVEN, OrderPlaced, VirtualOrdersExecuted,
        OrderState, TWAMMPoolKey, set_up_twamm_with_default_liquidity,
        place_order_with_default_start_time, OrderWithdrawn, Swapped, LoadedBalance, SavedBalance,
        PoolInitialized, PositionUpdated
    };

    #[test]
    fn test_place_orders_0() {
        // place one order to sell token0
        // withdraw once before it expires then again at end time

        let mut d: Deployer = Default::default();
        let core = d.deploy_core();
        let _event: ekubo::components::owned::Owned::OwnershipTransferred = pop_log(
            core.contract_address
        )
            .unwrap();

        let fee = 0;
        let initial_tick = i129 { mag: 693147, sign: false }; // ~ 2:1 price
        let (twamm, setup) = set_up_twamm_with_default_liquidity(ref d, core, fee, initial_tick);
        let twamm_pool_key = TWAMMPoolKey {
            token0: setup.token0.contract_address, token1: setup.token1.contract_address, fee
        };
        let _event: PoolInitialized = pop_log(core.contract_address).unwrap();
        let _event: PositionUpdated = pop_log(core.contract_address).unwrap();

        let timestamp = SIXTEEN_POW_ONE;
        set_block_timestamp(timestamp);

        let order1_timestamp = timestamp;
        let order1_end_time = timestamp + SIXTEEN_POW_THREE - SIXTEEN_POW_ONE;
        let amount = 10_000 * 1000000000000000000;
        let (token_id1, order1_key, _) = place_order_with_default_start_time(
            twamm, setup.token0, setup.token1, twamm_pool_key, false, order1_end_time, amount
        );

        let (_, token1_reward_rate) = twamm.get_reward_rate(twamm_pool_key);

        // no trades have been executed
        assert_eq!(token1_reward_rate, 0x0);

        let _event: SavedBalance = pop_log(core.contract_address).unwrap();
        let _event: OrderPlaced = pop_log(twamm.contract_address).unwrap();

        // halfway through the order duration
        let execution_timestamp = timestamp + 2040;
        set_block_timestamp(execution_timestamp);
        twamm.execute_virtual_orders(setup.pool_key);

        let virtual_orders_executed_event: VirtualOrdersExecuted = pop_log(twamm.contract_address)
            .unwrap();

        assert_eq!(virtual_orders_executed_event.last_virtual_order_time, order1_timestamp);
        assert_eq!(virtual_orders_executed_event.next_virtual_order_time, execution_timestamp);

        let swapped_event: Swapped = pop_log(core.contract_address).unwrap();
        let _event: LoadedBalance = pop_log(core.contract_address).unwrap();
        let _event: SavedBalance = pop_log(core.contract_address).unwrap();

        // price 2:1
        // time window    = 2,040 sec
        // sale rate      = 10,000 / 4,080 ~= 2.4509803922 per sec
        // sold amount   ~= 2,040 * 2.4509803922 ~= 5,000 tokens
        // bought amount ~= 9,998.994829713355494901 tokens
        assert_eq!(swapped_event.delta.amount0.sign, false);
        assert_eq!(swapped_event.delta.amount0.mag, 0x10f0cf064dd591fffff);
        assert_eq!(swapped_event.delta.amount1.sign, true);
        assert_eq!(swapped_event.delta.amount1.mag, 0x21e0bedb4ade006d5f5);

        // reward rate  = 9,998.994829713355494901 / 2.4509803922
        //               ~= 4,079.5898895263671875 (then scaled by 2**96)
        assert_eq!(virtual_orders_executed_event.token1_reward_rate, 0xfef970310b8b749c2bcbffcbb3e);

        // Withdraw proceeds
        twamm.withdraw_from_order(order1_key, token_id1);
        let _event: LoadedBalance = pop_log(core.contract_address).unwrap();
        let event: OrderWithdrawn = pop_log(twamm.contract_address).unwrap();

        // amount  = reward_rate * sale_rate
        //         = 4,079.5898895263671875 * 2.4509803922
        //        ~= 9,998.994827270507812499 tokens
        assert_eq!(event.amount, 0x21e0bedb4ade006d5f4);

        // withdraw the remaining proceeds after order expires

        set_block_timestamp(order1_end_time + 1);
        twamm.execute_virtual_orders(setup.pool_key);

        let virtual_orders_executed_event: VirtualOrdersExecuted = pop_log(twamm.contract_address)
            .unwrap();

        assert_eq!(virtual_orders_executed_event.last_virtual_order_time, execution_timestamp);
        assert_eq!(virtual_orders_executed_event.next_virtual_order_time, order1_end_time);

        let swapped_event: Swapped = pop_log(core.contract_address).unwrap();
        let _event: LoadedBalance = pop_log(core.contract_address).unwrap();
        let _event: SavedBalance = pop_log(core.contract_address).unwrap();

        // price 1.9996:1
        // time window    = 2,040 sec
        // sale rate      = 10,000 / 4,080 ~= 2.4509803922 per sec
        // sold amount   ~= 2,048 * 2.4509803922 = 5,000 tokens
        // bought amount ~= 9,996.995431680968690346 tokens
        assert_eq!(swapped_event.delta.amount0.sign, false);
        assert_eq!(swapped_event.delta.amount0.mag, 0x10f0cf064dd591fffff);
        assert_eq!(swapped_event.delta.amount1.sign, true);
        assert_eq!(swapped_event.delta.amount1.mag, 0x21df02e6ac312ff0aaa);

        // reward rate  = prev_rewards_rate + (9,996.995431680968690346 / 2.4509803922)
        //               ~= 4,079.5898895263671875 + 4,078.774136054 
        //               ~= 8,158.364013671875 (then scaled by 2**96)
        assert_eq!(
            virtual_orders_executed_event.token1_reward_rate, 0x1fde5d30d9b7d4955dc39bced5bf
        );

        // withdraw proceeds
        twamm.withdraw_from_order(order1_key, token_id1);
        let _event: LoadedBalance = pop_log(core.contract_address).unwrap();
        let event: OrderWithdrawn = pop_log(twamm.contract_address).unwrap();
        // amount  = reward_rate * sale_rate
        //         = 4,078.774136054 * 2.4509803922
        //        ~= 9,996.9954316808 tokens
        assert_eq!(event.amount, 0x21df02e6ac312ff0aa9);
    }

    #[test]
    fn test_place_orders_1() {
        // place one order to sell token0
        // withdraw afer end time

        let mut d: Deployer = Default::default();
        let core = d.deploy_core();
        let _event: ekubo::components::owned::Owned::OwnershipTransferred = pop_log(
            core.contract_address
        )
            .unwrap();
        let fee = 0;
        let initial_tick = i129 { mag: 693147, sign: false }; // ~ 2:1 price
        let (twamm, setup) = set_up_twamm_with_default_liquidity(ref d, core, fee, initial_tick);
        let twamm_pool_key = TWAMMPoolKey {
            token0: setup.token0.contract_address, token1: setup.token1.contract_address, fee
        };
        let _event: PoolInitialized = pop_log(core.contract_address).unwrap();
        let _event: PositionUpdated = pop_log(core.contract_address).unwrap();

        let timestamp = SIXTEEN_POW_ONE;
        set_block_timestamp(timestamp);

        let order1_timestamp = timestamp;
        let order1_end_time = timestamp + SIXTEEN_POW_THREE - SIXTEEN_POW_ONE;
        let amount = 10_000 * 1000000000000000000;
        let (token_id1, order1_key, _) = place_order_with_default_start_time(
            twamm, setup.token0, setup.token1, twamm_pool_key, false, order1_end_time, amount
        );

        let (_, token1_reward_rate) = twamm.get_reward_rate(twamm_pool_key);

        // no trades have been executed
        assert_eq!(token1_reward_rate, 0x0);

        let _event: SavedBalance = pop_log(core.contract_address).unwrap();
        let _event: OrderPlaced = pop_log(twamm.contract_address).unwrap();

        // halfway through the order duration
        let execution_timestamp = timestamp + 2040;
        set_block_timestamp(execution_timestamp);
        twamm.execute_virtual_orders(setup.pool_key);

        let virtual_orders_executed_event: VirtualOrdersExecuted = pop_log(twamm.contract_address)
            .unwrap();

        assert_eq!(virtual_orders_executed_event.last_virtual_order_time, order1_timestamp);
        assert_eq!(virtual_orders_executed_event.next_virtual_order_time, execution_timestamp);

        let swapped_event: Swapped = pop_log(core.contract_address).unwrap();
        let _event: LoadedBalance = pop_log(core.contract_address).unwrap();
        let _event: SavedBalance = pop_log(core.contract_address).unwrap();

        // price 2:1
        // time window    = 2,040 sec
        // sale rate      = 10,000 / 4,080 ~= 2.4509803922 per sec
        // sold amount   ~= 2,040 * 2.4509803922 ~= 5,000 tokens
        // bought amount ~= 9,998.994829713355494901 tokens
        assert_eq!(swapped_event.delta.amount0.sign, false);
        assert_eq!(swapped_event.delta.amount0.mag, 0x10f0cf064dd591fffff);
        assert_eq!(swapped_event.delta.amount1.sign, true);
        assert_eq!(swapped_event.delta.amount1.mag, 0x21e0bedb4ade006d5f5);

        // reward rate  = 9998.994829713355494901 / 2.4509803922
        //               ~= 4079.5898895263671875 (then scaled by 2**96)
        assert_eq!(virtual_orders_executed_event.token1_reward_rate, 0xfef970310b8b749c2bcbffcbb3e);

        set_block_timestamp(order1_end_time + 1);
        twamm.execute_virtual_orders(setup.pool_key);

        let virtual_orders_executed_event: VirtualOrdersExecuted = pop_log(twamm.contract_address)
            .unwrap();

        assert_eq!(virtual_orders_executed_event.last_virtual_order_time, execution_timestamp);
        assert_eq!(virtual_orders_executed_event.next_virtual_order_time, order1_end_time);

        let swapped_event: Swapped = pop_log(core.contract_address).unwrap();
        let _event: LoadedBalance = pop_log(core.contract_address).unwrap();
        let _event: SavedBalance = pop_log(core.contract_address).unwrap();

        // price 1.9996:1
        // time window    = 2,040 sec
        // sale rate      = 10,000 / 4,080 ~= 2.4509803922 per sec
        // sold amount   ~= 2,048 * 2.4509803922 = 5,000 tokens
        // bought amount ~= 9,996.995431680968690346 tokens
        assert_eq!(swapped_event.delta.amount0.sign, false);
        assert_eq!(swapped_event.delta.amount0.mag, 0x10f0cf064dd591fffff);
        assert_eq!(swapped_event.delta.amount1.sign, true);
        assert_eq!(swapped_event.delta.amount1.mag, 0x21df02e6ac312ff0aaa);

        // reward rate  = prev_rewards_rate + (9,996.995431680968690346 / 2.4509803922)
        //               ~= 4,079.5898895263671875 + 4,078.774136054 
        //               ~= 8,158.364013671875 (then scaled by 2**96)
        assert_eq!(
            virtual_orders_executed_event.token1_reward_rate, 0x1fde5d30d9b7d4955dc39bced5bf
        );

        // withdraw proceeds
        twamm.withdraw_from_order(order1_key, token_id1);
        let _event: LoadedBalance = pop_log(core.contract_address).unwrap();
        let event: OrderWithdrawn = pop_log(twamm.contract_address).unwrap();
        // amount  = reward_rate * sale_rate
        //         = 8,158.364013671875 * 2.4509803922
        //        ~= 9,996.9954316808 tokens
        assert_eq!(event.amount, 0x43bfc1c1f70f305e09e);
    }

    #[test]
    fn test_place_orders_2() {
        // Place one order to sell token1
        // withdraw once before it expires then again at end time

        let mut d: Deployer = Default::default();
        let core = d.deploy_core();
        let _event: ekubo::components::owned::Owned::OwnershipTransferred = pop_log(
            core.contract_address
        )
            .unwrap();
        let fee = 0;
        let initial_tick = i129 { mag: 693147, sign: false }; // ~ 2:1 price
        let (twamm, setup) = set_up_twamm_with_default_liquidity(ref d, core, fee, initial_tick);
        let twamm_pool_key = TWAMMPoolKey {
            token0: setup.token0.contract_address, token1: setup.token1.contract_address, fee
        };
        let _event: PoolInitialized = pop_log(core.contract_address).unwrap();
        let _event: PositionUpdated = pop_log(core.contract_address).unwrap();

        let timestamp = SIXTEEN_POW_ONE;
        set_block_timestamp(timestamp);

        let order1_timestamp = timestamp;
        let order1_end_time = timestamp + SIXTEEN_POW_THREE - SIXTEEN_POW_ONE;
        let amount = 10_000 * 1000000000000000000;
        let (token_id1, order1_key, _) = place_order_with_default_start_time(
            twamm, setup.token0, setup.token1, twamm_pool_key, true, order1_end_time, amount
        );

        let (token0_reward_rate, _) = twamm.get_reward_rate(twamm_pool_key);

        // no trades have been executed
        assert_eq!(token0_reward_rate, 0x0);

        let _event: SavedBalance = pop_log(core.contract_address).unwrap();
        let _event: OrderPlaced = pop_log(twamm.contract_address).unwrap();

        // halfway through the order duration
        let execution_timestamp = timestamp + 2040;
        set_block_timestamp(execution_timestamp);
        twamm.execute_virtual_orders(setup.pool_key);

        let virtual_orders_executed_event: VirtualOrdersExecuted = pop_log(twamm.contract_address)
            .unwrap();

        assert_eq!(virtual_orders_executed_event.last_virtual_order_time, order1_timestamp);
        assert_eq!(virtual_orders_executed_event.next_virtual_order_time, execution_timestamp);

        let swapped_event: Swapped = pop_log(core.contract_address).unwrap();
        let _event: LoadedBalance = pop_log(core.contract_address).unwrap();
        let _event: SavedBalance = pop_log(core.contract_address).unwrap();

        // price 2:1
        // time window    = 2,040 sec
        // sale rate      = 10,000 / 4,080 ~= 2.4509803922 per sec
        // sold amount   ~= 2,040 * 2.4509803922 ~= 5,000 tokens
        // bought amount ~= 2,499.876324017182129212 tokens
        assert_eq!(swapped_event.delta.amount0.sign, true);
        assert_eq!(swapped_event.delta.amount0.mag, 0x8784c0cfc7fd74bc3c);
        assert_eq!(swapped_event.delta.amount1.sign, false);
        assert_eq!(swapped_event.delta.amount1.mag, 0x10f0cf064dd591fffff);

        // reward rate  = 2,499.876324017182129212 / 2.4509803922
        //               ~= 1,019.9495391845703125 (then scaled by 2**96)
        assert_eq!(virtual_orders_executed_event.token0_reward_rate, 0x3fbf3151104fc924f597b256ca6);

        // Withdraw proceeds
        twamm.withdraw_from_order(order1_key, token_id1);
        let _event: LoadedBalance = pop_log(core.contract_address).unwrap();
        let event: OrderWithdrawn = pop_log(twamm.contract_address).unwrap();

        // amount  = reward_rate * sale_rate
        //         = 1,019.9495391845703125 * 2.4509803922
        //        ~= 2,499.87632153080958946 tokens
        assert_eq!(event.amount, 0x8784c0cfc7fd74bc3b);

        // withdraw the remaining proceeds after order expires

        set_block_timestamp(order1_end_time + 1);
        twamm.execute_virtual_orders(setup.pool_key);

        let virtual_orders_executed_event: VirtualOrdersExecuted = pop_log(twamm.contract_address)
            .unwrap();

        assert_eq!(virtual_orders_executed_event.last_virtual_order_time, execution_timestamp);
        assert_eq!(virtual_orders_executed_event.next_virtual_order_time, order1_end_time);

        let swapped_event: Swapped = pop_log(core.contract_address).unwrap();
        let _event: LoadedBalance = pop_log(core.contract_address).unwrap();
        let _event: SavedBalance = pop_log(core.contract_address).unwrap();

        // price 2.0002:1
        // time window    = 2,040 sec
        // sale rate      = 10,000 / 4,080 ~= 2.4509803922 per sec
        // sold amount   ~= 2,048 * 2.4509803922 = 5,000 tokens
        // bought amount ~= 2,499.626361381044024809 tokens
        assert_eq!(swapped_event.delta.amount0.sign, true);
        assert_eq!(swapped_event.delta.amount0.mag, 0x878148c4168752f5e9);
        assert_eq!(swapped_event.delta.amount1.sign, false);
        assert_eq!(swapped_event.delta.amount1.mag, 0x10f0cf064dd591fffff);

        // reward rate  = prev_rewards_rate + (2,499.626361381044024809 / 2.4509803922)
        //               ~= 1,019.9495391845703125 + 1,019.8475554255
        //               ~= 2,039.797088623046875 (then scaled by 2**96)
        assert_eq!(virtual_orders_executed_event.token0_reward_rate, 0x7f7cc0e75c4383db7609db75268);

        // withdraw proceeds
        twamm.withdraw_from_order(order1_key, token_id1);
        let _event: LoadedBalance = pop_log(core.contract_address).unwrap();
        let event: OrderWithdrawn = pop_log(twamm.contract_address).unwrap();
        // amount  = reward_rate * sale_rate
        //         = 1,019.8475554255 * 2.4509803922
        //        ~= 2,499.626346662932751225 tokens
        assert_eq!(event.amount, 0x878148c4168752f5e8);
    }

    #[test]
    fn test_place_orders_3() {
        // place one order to sell token1
        // withdraw afer end

        let mut d: Deployer = Default::default();
        let core = d.deploy_core();
        let _event: ekubo::components::owned::Owned::OwnershipTransferred = pop_log(
            core.contract_address
        )
            .unwrap();
        let fee = 0;
        let initial_tick = i129 { mag: 693147, sign: false }; // ~ 2:1 price
        let (twamm, setup) = set_up_twamm_with_default_liquidity(ref d, core, fee, initial_tick);
        let twamm_pool_key = TWAMMPoolKey {
            token0: setup.token0.contract_address, token1: setup.token1.contract_address, fee
        };
        let _event: PoolInitialized = pop_log(core.contract_address).unwrap();
        let _event: PositionUpdated = pop_log(core.contract_address).unwrap();

        let timestamp = SIXTEEN_POW_ONE;
        set_block_timestamp(timestamp);

        let order1_timestamp = timestamp;
        let order1_end_time = timestamp + SIXTEEN_POW_THREE - SIXTEEN_POW_ONE;
        let amount = 10_000 * 1000000000000000000;
        let (token_id1, order1_key, _) = place_order_with_default_start_time(
            twamm, setup.token0, setup.token1, twamm_pool_key, true, order1_end_time, amount
        );

        let (token0_reward_rate, _) = twamm.get_reward_rate(twamm_pool_key);

        // no trades have been executed
        assert_eq!(token0_reward_rate, 0x0);

        let _event: SavedBalance = pop_log(core.contract_address).unwrap();
        let _event: OrderPlaced = pop_log(twamm.contract_address).unwrap();

        // halfway through the order duration
        let execution_timestamp = timestamp + 2040;
        set_block_timestamp(execution_timestamp);
        twamm.execute_virtual_orders(setup.pool_key);

        let virtual_orders_executed_event: VirtualOrdersExecuted = pop_log(twamm.contract_address)
            .unwrap();

        assert_eq!(virtual_orders_executed_event.last_virtual_order_time, order1_timestamp);
        assert_eq!(virtual_orders_executed_event.next_virtual_order_time, execution_timestamp);

        let swapped_event: Swapped = pop_log(core.contract_address).unwrap();
        let _event: LoadedBalance = pop_log(core.contract_address).unwrap();
        let _event: SavedBalance = pop_log(core.contract_address).unwrap();

        // price 2:1
        // time window    = 2,040 sec
        // sale rate      = 10,000 / 4,080 ~= 2.4509803922 per sec
        // sold amount   ~= 2,040 * 2.4509803922 ~= 5,000 tokens
        // bought amount ~= 2,499.876324017182129212 tokens
        assert_eq!(swapped_event.delta.amount0.sign, true);
        assert_eq!(swapped_event.delta.amount0.mag, 0x8784c0cfc7fd74bc3c);
        assert_eq!(swapped_event.delta.amount1.sign, false);
        assert_eq!(swapped_event.delta.amount1.mag, 0x10f0cf064dd591fffff);

        // reward rate  = 2,499.876324017182129212 / 2.4509803922
        //               ~= 1,019.9495391845703125 (then scaled by 2**96)
        assert_eq!(virtual_orders_executed_event.token0_reward_rate, 0x3fbf3151104fc924f597b256ca6);

        set_block_timestamp(order1_end_time + 1);
        twamm.execute_virtual_orders(setup.pool_key);
        let virtual_orders_executed_event: VirtualOrdersExecuted = pop_log(twamm.contract_address)
            .unwrap();

        assert_eq!(virtual_orders_executed_event.last_virtual_order_time, execution_timestamp);
        assert_eq!(virtual_orders_executed_event.next_virtual_order_time, order1_end_time);

        let swapped_event: Swapped = pop_log(core.contract_address).unwrap();
        let _event: LoadedBalance = pop_log(core.contract_address).unwrap();
        let _event: SavedBalance = pop_log(core.contract_address).unwrap();

        // price 2.0002:1
        // time window    = 2,040 sec
        // sale rate      = 10,000 / 4,080 ~= 2.4509803922 per sec
        // sold amount   ~= 2,048 * 2.4509803922 = 5,000 tokens
        // bought amount ~= 2,499.626361381044024809 tokens
        assert_eq!(swapped_event.delta.amount0.sign, true);
        assert_eq!(swapped_event.delta.amount0.mag, 0x878148c4168752f5e9);
        assert_eq!(swapped_event.delta.amount1.sign, false);
        assert_eq!(swapped_event.delta.amount1.mag, 0x10f0cf064dd591fffff);

        // reward rate  = prev_rewards_rate + (2,499.626361381044024809 / 2.4509803922)
        //               ~= 1,019.9495391845703125 + 1,019.8475554255
        //               ~= 2,039.797088623046875 (then scaled by 2*96)
        assert_eq!(
            virtual_orders_executed_event.token0_reward_rate, 0x7f7cc0e75c4383db7609db75268,
        );

        // withdraw proceeds
        twamm.withdraw_from_order(order1_key, token_id1);
        let _event: LoadedBalance = pop_log(core.contract_address).unwrap();
        let event: OrderWithdrawn = pop_log(twamm.contract_address).unwrap();
        // amount  = reward_rate * sale_rate
        //         = 2,039.797088623046875 * 2.4509803922
        //        ~= 4,999.5026682817 tokens
        assert_eq!(event.amount, 0x10f060993de84c7b224);
    }
}

mod PlaceOrderOnBothSides {
    use super::{
        PrintTrait, Deployer, DeployerTrait, ICoreDispatcher, ICoreDispatcherTrait, PoolKey,
        MAX_TICK_SPACING, ITWAMMDispatcher, ITWAMMDispatcherTrait, OrderKey, get_block_timestamp,
        set_block_timestamp, pop_log, IMockERC20Dispatcher, IMockERC20DispatcherTrait,
        contract_address_const, set_contract_address, max_bounds, update_position, max_liquidity,
        Bounds, tick_to_sqrt_ratio, i129, TICKS_IN_ONE_PERCENT, IPositionsDispatcher,
        IPositionsDispatcherTrait, get_contract_address, IExtensionDispatcher, SetupPoolResult,
        SIXTEEN_POW_ZERO, SIXTEEN_POW_ONE, SIXTEEN_POW_TWO, SIXTEEN_POW_THREE, SIXTEEN_POW_FOUR,
        SIXTEEN_POW_FIVE, SIXTEEN_POW_SIX, SIXTEEN_POW_SEVEN, OrderPlaced, VirtualOrdersExecuted,
        OrderState, TWAMMPoolKey, set_up_twamm_with_default_liquidity, set_up_twamm_with_liquidity,
        place_order_with_default_start_time, OrderWithdrawn, PoolInitialized, PositionUpdated,
        SavedBalance, Swapped, LoadedBalance,
    };

    #[test]
    fn test_place_orders_0() {
        // place one order on both sides expiring at the same time.

        let mut d: Deployer = Default::default();
        let core = d.deploy_core();
        let _event: ekubo::components::owned::Owned::OwnershipTransferred = pop_log(
            core.contract_address
        )
            .unwrap();
        let fee = 0;
        let initial_tick = i129 { mag: 693147, sign: false }; // ~ 2:1 price
        let (twamm, setup) = set_up_twamm_with_default_liquidity(ref d, core, fee, initial_tick);
        let twamm_pool_key = TWAMMPoolKey {
            token0: setup.token0.contract_address, token1: setup.token1.contract_address, fee
        };
        let _event: PoolInitialized = pop_log(core.contract_address).unwrap();
        let _event: PositionUpdated = pop_log(core.contract_address).unwrap();

        let timestamp = SIXTEEN_POW_ONE;
        set_block_timestamp(timestamp);

        let order_end_time = timestamp + SIXTEEN_POW_THREE - SIXTEEN_POW_ONE;

        let amount = 10_000 * 1000000000000000000;
        let (token_id1, order1_key, _) = place_order_with_default_start_time(
            twamm, setup.token0, setup.token1, twamm_pool_key, false, order_end_time, amount
        );
        let _event: SavedBalance = pop_log(core.contract_address).unwrap();
        let _event: OrderPlaced = pop_log(twamm.contract_address).unwrap();

        let (token_id2, order2_key, _) = place_order_with_default_start_time(
            twamm, setup.token0, setup.token1, twamm_pool_key, true, order_end_time, amount
        );
        let _event: SavedBalance = pop_log(core.contract_address).unwrap();
        let _event: OrderPlaced = pop_log(twamm.contract_address).unwrap();

        let (token0_reward_rate, token1_reward_rate) = twamm.get_reward_rate(twamm_pool_key);

        // no trades have been executed
        assert_eq!(token0_reward_rate, 0x0);
        assert_eq!(token1_reward_rate, 0x0);

        // halfway through the order duration
        let execution_timestamp = timestamp + 2040;
        set_block_timestamp(execution_timestamp);
        twamm.execute_virtual_orders(setup.pool_key);
        let virtual_orders_executed_event: VirtualOrdersExecuted = pop_log(twamm.contract_address)
            .unwrap();

        assert_eq!(virtual_orders_executed_event.last_virtual_order_time, timestamp);
        assert_eq!(virtual_orders_executed_event.next_virtual_order_time, execution_timestamp);

        let swapped_event: Swapped = pop_log(core.contract_address).unwrap();
        let _event: LoadedBalance = pop_log(core.contract_address).unwrap();
        let _event: SavedBalance = pop_log(core.contract_address).unwrap();

        // price 2:1 (sqrt_ratio ~= 1.414213)
        // time window           = 2,040 sec
        // token0 sale-rate      = 10,000 / 4,080 ~= 2.4509803922 per sec
        // token0 sold-amount   ~= 2,040 * 2.4509803922 = 5,000.000000088 tokens
        // token1 sale-rate      = 10,000 / 4,080 ~= 5,019.6078432256 per sec
        // token1 sold-amount   ~= 2,040 * 2.4509803922 = 5,000.000000088 tokens
        // Using twamm math to calculate the next price based on sell-rates:
        // next price 1.999798971:1 (sqrt_ratio ~= 1.414142)
        // trade token1 for token0 up to the next price
        // token0 spent amount ~= 2499.873684315946883792
        // token1 bought amount ~= 4999.494771123186662264
        // token0 reward rate = (5,000 + 4999.494771123186662264) / 2.4509803922 = 4,079.7938665465
        // token1 reward rate = (5,000 - 2499.873684315946883792) / 2.4509803922 = 1,020.05153678114
        assert_eq!(swapped_event.delta.amount0.sign, false);
        assert_eq!(swapped_event.delta.amount0.mag, 2499873684315946883792);
        assert_eq!(swapped_event.delta.amount1.sign, true);
        assert_eq!(swapped_event.delta.amount1.mag, 4999494771123186662264);
        assert_eq!(virtual_orders_executed_event.token0_reward_rate, 0x3fc0d318402a5d8eb069cd5df58);
        assert_eq!(virtual_orders_executed_event.token1_reward_rate, 0xfefcb3ad7bad041447ab720a895);

        // Withdraw proceeds for order1
        twamm.withdraw_from_order(order1_key, token_id1);
        let _event: LoadedBalance = pop_log(core.contract_address).unwrap();
        let event: OrderWithdrawn = pop_log(twamm.contract_address).unwrap();

        // amount  = reward_rate * sale_rate
        //         = 4,079.7938665465 * 2.4509803922
        //        ~= 9,999.4947711233 tokens
        assert_eq!(event.amount, 0x21e12dddabe1d857b76);

        // Withdraw proceeds for order2
        twamm.withdraw_from_order(order2_key, token_id2);
        let _event: LoadedBalance = pop_log(core.contract_address).unwrap();
        let event: OrderWithdrawn = pop_log(twamm.contract_address).unwrap();

        // amount  = reward_rate * sale_rate
        //         = 1,020.05153678114 * 2.4509803922
        //        ~= 2,500.1263156841 tokens
        assert_eq!(event.amount, 2500126315684053116206);

        // withdraw the remaining proceeds after order expires

        set_block_timestamp(order_end_time + 1);
        twamm.execute_virtual_orders(setup.pool_key);
        let virtual_orders_executed_event: VirtualOrdersExecuted = pop_log(twamm.contract_address)
            .unwrap();

        assert_eq!(virtual_orders_executed_event.last_virtual_order_time, execution_timestamp);
        assert_eq!(virtual_orders_executed_event.next_virtual_order_time, order_end_time);

        let swapped_event: Swapped = pop_log(core.contract_address).unwrap();
        let _event: LoadedBalance = pop_log(core.contract_address).unwrap();
        let _event: SavedBalance = pop_log(core.contract_address).unwrap();

        // price 1.999798971:1 (sqrt_ratio ~= 1.414142)
        // time window           = 2,040 sec
        // token0 sale-rate      = 10,000 / 4,080 ~= 2.4509803922 per sec
        // token0 sold-amount   ~= 2,040 * 2.4509803922 = 5,000.000000088 tokens
        // token1 sale-rate      = 10,000 / 4,080 ~= 5,019.6078432256 per sec
        // token1 sold-amount   ~= 2,040 * 2.4509803922 = 5,000.000000088 tokens
        // Using twamm math to calculate the next price based on sell-rates:
        // next price 1.999599046:1 (sqrt_ratio ~= 1.414071)
        // trade token1 for token0 up to the next price
        // token0 spent amount ~= 2499.623696949194922069
        // token1 bought amount ~= 4998.495022657373310749
        // token0 reward rate = (5,000 + 4998.495022657373310749) / 2.4509803922 = 4,079.3859691724
        // token1 reward rate = (5,000 - 2499.623696949194922069) / 2.4509803922 = 1,020.1535316268

        assert_eq!(swapped_event.delta.amount0.sign, false);
        assert_eq!(swapped_event.delta.amount0.mag, 2499623696949194922069);
        assert_eq!(swapped_event.delta.amount1.sign, true);
        assert_eq!(swapped_event.delta.amount1.mag, 4998495022657373310749);
        assert_eq!(
            virtual_orders_executed_event.token0_reward_rate,
            0x3fc0d318402a5d8eb069cd5df58 + 0x3fc274dd99102874f458134e9db
        );
        assert_eq!(
            virtual_orders_executed_event.token1_reward_rate,
            0xfefcb3ad7bad041447ab720a895 + 0xfef62cee16122f3c6c6e3a4ded6
        );

        // Withdraw proceeds for order1
        twamm.withdraw_from_order(order1_key, token_id1);
        let _event: LoadedBalance = pop_log(core.contract_address).unwrap();
        let event: OrderWithdrawn = pop_log(twamm.contract_address).unwrap();

        // amount  = reward_rate * sale_rate
        //         = 4,079.3859691724 * 2.4509803922
        //        ~= 9,998.4950226573 tokens
        assert_eq!(event.amount, 9998495022657373310747);

        // Withdraw proceeds for order2
        twamm.withdraw_from_order(order2_key, token_id2);
        let _event: LoadedBalance = pop_log(core.contract_address).unwrap();
        let event: OrderWithdrawn = pop_log(twamm.contract_address).unwrap();

        // amount  = reward_rate * sale_rate
        //         = 1,020.1535316268 * 2.4509803922
        //        ~= 2,500.3763030509 tokens
        assert_eq!(event.amount, 2500376303050805077929);
    }

    #[test]
    fn test_place_orders_1() {
        // place two orders on both sides expiring at the same time.
        // sale rate is the same for both orders but smaller than the previous test
        // since it loses 1 wei of precision.

        let mut d: Deployer = Default::default();
        let core = d.deploy_core();
        let _event: ekubo::components::owned::Owned::OwnershipTransferred = pop_log(
            core.contract_address
        )
            .unwrap();
        let fee = 0;
        let initial_tick = i129 { mag: 693147, sign: false }; // ~ 2:1 price
        let (twamm, setup) = set_up_twamm_with_default_liquidity(ref d, core, fee, initial_tick);
        let twamm_pool_key = TWAMMPoolKey {
            token0: setup.token0.contract_address, token1: setup.token1.contract_address, fee
        };
        let _event: PoolInitialized = pop_log(core.contract_address).unwrap();
        let _event: PositionUpdated = pop_log(core.contract_address).unwrap();

        let timestamp = SIXTEEN_POW_ONE;
        set_block_timestamp(timestamp);

        let order_end_time = timestamp + SIXTEEN_POW_THREE - SIXTEEN_POW_ONE;

        let amount = 5_000 * 1000000000000000000;
        let (token_id1, order1_key, _) = place_order_with_default_start_time(
            twamm, setup.token0, setup.token1, twamm_pool_key, false, order_end_time, amount
        );
        let _event: OrderPlaced = pop_log(twamm.contract_address).unwrap();
        let _event: SavedBalance = pop_log(core.contract_address).unwrap();

        let (token_id2, order2_key, _) = place_order_with_default_start_time(
            twamm, setup.token0, setup.token1, twamm_pool_key, false, order_end_time, amount
        );
        let _event: OrderPlaced = pop_log(twamm.contract_address).unwrap();
        let _event: SavedBalance = pop_log(core.contract_address).unwrap();

        let (token_id3, order3_key, _) = place_order_with_default_start_time(
            twamm, setup.token0, setup.token1, twamm_pool_key, true, order_end_time, amount
        );
        let _event: OrderPlaced = pop_log(twamm.contract_address).unwrap();
        let _event: SavedBalance = pop_log(core.contract_address).unwrap();

        let (token_id4, order4_key, _) = place_order_with_default_start_time(
            twamm, setup.token0, setup.token1, twamm_pool_key, true, order_end_time, amount
        );
        let _event: OrderPlaced = pop_log(twamm.contract_address).unwrap();
        let _event: SavedBalance = pop_log(core.contract_address).unwrap();

        let (token0_reward_rate, token1_reward_rate) = twamm.get_reward_rate(twamm_pool_key);

        // no trades have been executed
        assert_eq!(token0_reward_rate, 0x0);
        assert_eq!(token1_reward_rate, 0x0);

        // halfway through the order duration
        let execution_timestamp = timestamp + 2040;
        set_block_timestamp(execution_timestamp);
        twamm.execute_virtual_orders(setup.pool_key);
        let virtual_orders_executed_event: VirtualOrdersExecuted = pop_log(twamm.contract_address)
            .unwrap();

        assert_eq!(virtual_orders_executed_event.last_virtual_order_time, timestamp);
        assert_eq!(virtual_orders_executed_event.next_virtual_order_time, execution_timestamp);

        let swapped_event: Swapped = pop_log(core.contract_address).unwrap();
        let _event: LoadedBalance = pop_log(core.contract_address).unwrap();
        let _event: SavedBalance = pop_log(core.contract_address).unwrap();

        // price 2:1 (sqrt_ratio ~= 1.414213)
        // time window           = 2,040 sec
        // token0 sale-rate      = (5,000 / 4,080) + (5,000 / 4,080) ~= 2.4509803921 per sec
        // token0 sold-amount   ~= 2,040 * 2.4509803921 = 4,999.999999884 tokens
        // token1 sale-rate      = 10,000 / 4,080 ~= 5,019.6078432256 per sec
        // token1 sold-amount   ~= 2,040 * 2.4509803921 = 4,999.999999884 tokens
        // Using twamm math to calculate the next price based on sell-rates:
        // next price 1.999798971:1 (sqrt_ratio ~= 1.414142)
        // trade token1 for token0 up to the next price
        // token0 spent amount ~= 2499.873684315946883792
        // token1 bought amount ~= 4999.494771123186662264
        // token0 reward rate = (4,999.999999884 + 4999.494771123186662264) / 2.4509803921 ~= 4,079.7938666656
        // token1 reward rate = (4,999.999999884 - 2499.873684315946883792) / 2.4509803921 ~= 1,020.05153677543
        assert_eq!(swapped_event.delta.amount0.sign, false);
        assert_eq!(swapped_event.delta.amount0.mag, 2499873684315946883792);
        assert_eq!(swapped_event.delta.amount1.sign, true);
        assert_eq!(swapped_event.delta.amount1.mag, 4999494771123186662264);
        assert_eq!(virtual_orders_executed_event.token0_reward_rate, 0x3fc0d318402a5d8eb069cd5fd56);
        assert_eq!(virtual_orders_executed_event.token1_reward_rate, 0xfefcb3ad7bad041447ab7212087);

        set_block_timestamp(order_end_time + 1);
        twamm.execute_virtual_orders(setup.pool_key);
        let virtual_orders_executed_event: VirtualOrdersExecuted = pop_log(twamm.contract_address)
            .unwrap();

        assert_eq!(virtual_orders_executed_event.last_virtual_order_time, execution_timestamp);
        assert_eq!(virtual_orders_executed_event.next_virtual_order_time, order_end_time);

        let swapped_event: Swapped = pop_log(core.contract_address).unwrap();
        let _event: LoadedBalance = pop_log(core.contract_address).unwrap();
        let _event: SavedBalance = pop_log(core.contract_address).unwrap();

        // price 1.999798971:1 (sqrt_ratio ~= 1.414142)
        // time window           = 2,040 sec
        // token0 sale-rate      = 10,000 / 4,080 ~= 2.4509803921 per sec
        // token0 sold-amount   ~= 2,040 * 2.4509803921 = 4,999.999999884 tokens
        // token1 sale-rate      = 10,000 / 4,080 ~= 5,019.6078432256 per sec
        // token1 sold-amount   ~= 2,040 * 2.4509803921 = 4,999.999999884 tokens
        // Using twamm math to calculate the next price based on sell-rates:
        // next price 1.999599046:1 (sqrt_ratio ~= 1.414071)
        // trade token1 for token0 up to the next price
        // token0 spent amount ~= 2499.623696949194922069
        // token1 bought amount ~= 4998.495022657373310749
        // token0 reward rate = (4,999.999999884 + 4998.495022657373310749) / 2.4509803921 ~= 4,079.3859692915
        // token1 reward rate = (4,999.999999884 - 2499.623696949194922069) / 2.4509803921 ~= 1,020.1535316211

        assert_eq!(swapped_event.delta.amount0.sign, false);
        assert_eq!(swapped_event.delta.amount0.mag, 2499623696949194922069);
        assert_eq!(swapped_event.delta.amount1.sign, true);
        assert_eq!(swapped_event.delta.amount1.mag, 4998495022657373310749);
        assert_eq!(
            virtual_orders_executed_event.token0_reward_rate,
            0x3fc0d318402a5d8eb069cd5fd56 + 0x3fc274dd99102874f45813507d9
        );
        assert_eq!(
            virtual_orders_executed_event.token1_reward_rate,
            0xfefcb3ad7bad041447ab7212087 + 0xfef62cee16122f3c6c6e3a556c4
        );

        // Withdraw proceeds for order1
        twamm.withdraw_from_order(order1_key, token_id1);
        let _event: LoadedBalance = pop_log(core.contract_address).unwrap();
        let event: OrderWithdrawn = pop_log(twamm.contract_address).unwrap();

        // amount  = reward_rate * sale_rate
        //         = (4,079.7938666656 + 4,079.3859692915) * 1.225490196
        //        ~= 9,998.9948963663 tokens
        assert_eq!(event.amount, 9998994896890279986505);

        // Withdraw proceeds for order2
        twamm.withdraw_from_order(order2_key, token_id2);
        let _event: LoadedBalance = pop_log(core.contract_address).unwrap();
        let event: OrderWithdrawn = pop_log(twamm.contract_address).unwrap();

        // amount  = reward_rate * sale_rate
        //         = (4,079.7938666656 + 4,079.3859692915) * 1.225490196
        //        ~= 9,998.9948963663 tokens
        assert_eq!(event.amount, 9998994896890279986505);

        // Withdraw proceeds for order3
        twamm.withdraw_from_order(order3_key, token_id3);
        let _event: LoadedBalance = pop_log(core.contract_address).unwrap();
        let event: OrderWithdrawn = pop_log(twamm.contract_address).unwrap();

        // amount  = reward_rate * sale_rate
        //         = (1,020.05153677543 + 1,020.1535316211) * 1.225490196
        //        ~= 2,500.2513091495 tokens
        assert_eq!(event.amount, 2500251309367429097068);

        // Withdraw proceeds for order4
        twamm.withdraw_from_order(order4_key, token_id4);
        let _event: LoadedBalance = pop_log(core.contract_address).unwrap();
        let event: OrderWithdrawn = pop_log(twamm.contract_address).unwrap();

        // amount  = reward_rate * sale_rate
        //         = (1,020.05153677543 + 1,020.1535316211) * 1.225490196
        //        ~= 2,500.2513091495 tokens
        assert_eq!(event.amount, 2500251309367429097068);
    }

    #[test]
    fn test_place_orders_2() {
        // place one order on both sides expiring at the same time.
        // price is 100_000_000:1

        let mut d: Deployer = Default::default();
        let core = d.deploy_core();
        let _event: ekubo::components::owned::Owned::OwnershipTransferred = pop_log(
            core.contract_address
        )
            .unwrap();
        let fee = 0;
        let initial_tick = i129 { mag: 18420685, sign: false }; // ~ 100_000_000:1 price
        let token0_liquidity = 2 * 1000000000000000000;
        let token1_liquidity = 100_000_000 * 1000000000000000000;
        let (twamm, setup) = set_up_twamm_with_liquidity(
            ref d, core, fee, initial_tick, token0_liquidity, token1_liquidity
        );
        let twamm_pool_key = TWAMMPoolKey {
            token0: setup.token0.contract_address, token1: setup.token1.contract_address, fee
        };
        let _event: PoolInitialized = pop_log(core.contract_address).unwrap();
        let _event: PositionUpdated = pop_log(core.contract_address).unwrap();

        let timestamp = SIXTEEN_POW_ONE;
        set_block_timestamp(timestamp);

        let order_end_time = timestamp + SIXTEEN_POW_THREE - SIXTEEN_POW_ONE;

        let amount = 1 * 1000000000000000000;
        let (token_id1, order1_key, _) = place_order_with_default_start_time(
            twamm, setup.token0, setup.token1, twamm_pool_key, false, order_end_time, amount
        );
        let _event: SavedBalance = pop_log(core.contract_address).unwrap();
        let _event: OrderPlaced = pop_log(twamm.contract_address).unwrap();

        let amount = 1_000_000 * 1000000000000000000;
        let (token_id2, order2_key, _) = place_order_with_default_start_time(
            twamm, setup.token0, setup.token1, twamm_pool_key, true, order_end_time, amount
        );
        let _event: SavedBalance = pop_log(core.contract_address).unwrap();
        let _event: OrderPlaced = pop_log(twamm.contract_address).unwrap();

        // halfway through the order duration
        let execution_timestamp = timestamp + 2040;
        set_block_timestamp(execution_timestamp);
        twamm.execute_virtual_orders(setup.pool_key);
        let virtual_orders_executed_event: VirtualOrdersExecuted = pop_log(twamm.contract_address)
            .unwrap();

        assert_eq!(virtual_orders_executed_event.last_virtual_order_time, timestamp);
        assert_eq!(virtual_orders_executed_event.next_virtual_order_time, execution_timestamp);

        let swapped_event: Swapped = pop_log(core.contract_address).unwrap();
        let _event: LoadedBalance = pop_log(core.contract_address).unwrap();
        let _event: SavedBalance = pop_log(core.contract_address).unwrap();

        // price 100_000_000:1 (sqrt_ratio ~= 9999.97522858)
        // time window           = 2,040 sec
        // token0 sale-rate      = 1 / 4,080 ~= 0.0002450980392 per sec
        // token0 sold-amount   ~= 2,040 * 0.0002450980392 = 0.5 tokens
        // token1 sale-rate      = 1,000,000 / 4,080 ~= 245.09803921569 per sec
        // token1 sold-amount   ~= 2,040 * 245.09803921569 = 0.0000000001 tokens
        // Using twamm math to calculate the next price based on sell-rates:
        // next price 44,914,477,916.10660784:1 (sqrt_ratio ~= 6701.826461)
        // trade token1 for token0 up to the next price
        // token0 spent amount ~= 0.492129291394822418
        // token1 bought amount ~= 32,981,569.373828693521176462
        // token0 reward rate = (0.5 - 0.492129291394822418) / 245.09803921569 = 0.00003211249111
        // token1 reward rate = (500,000 + 32,981,569.373828693521176462) / 0.0002450980392 = 136,604,803,053.9637769619
        assert_eq!(swapped_event.delta.amount0.sign, false);
        assert_eq!(swapped_event.delta.amount0.mag, 492129291394822418);
        assert_eq!(swapped_event.delta.amount1.sign, true);
        assert_eq!(swapped_event.delta.amount1.mag, 32981569373828693521176462);
        assert_eq!(virtual_orders_executed_event.token0_reward_rate, 0x21ac2195f0fdd994baf61);
        assert_eq!(
            virtual_orders_executed_event.token1_reward_rate, 0x1fce47dfe5389803ddd431d5f1667b413e,
        );

        // Withdraw proceeds for order1
        twamm.withdraw_from_order(order1_key, token_id1);
        let _event: LoadedBalance = pop_log(core.contract_address).unwrap();
        let event: OrderWithdrawn = pop_log(twamm.contract_address).unwrap();

        // amount  = reward_rate * sale_rate
        //         = 136,604,803,053.9637769619 * 0.0002450980392
        //        ~= 33,481,569.3738286935 tokens
        assert_eq!(event.amount, 33481569373828693521176460);

        // Withdraw proceeds for order2
        twamm.withdraw_from_order(order2_key, token_id2);
        let _event: LoadedBalance = pop_log(core.contract_address).unwrap();
        let event: OrderWithdrawn = pop_log(twamm.contract_address).unwrap();

        // amount  = reward_rate * sale_rate
        //         = 0.00003211249111 * 245.09803921569
        //        ~= 0.007870708605 tokens
        assert_eq!(event.amount, 7870708605177580);

        // withdraw the remaining proceeds after order expires

        set_block_timestamp(order_end_time + 1);
        twamm.execute_virtual_orders(setup.pool_key);
        let virtual_orders_executed_event: VirtualOrdersExecuted = pop_log(twamm.contract_address)
            .unwrap();

        assert_eq!(virtual_orders_executed_event.last_virtual_order_time, execution_timestamp);
        assert_eq!(virtual_orders_executed_event.next_virtual_order_time, order_end_time);

        let swapped_event: Swapped = pop_log(core.contract_address).unwrap();
        let _event: LoadedBalance = pop_log(core.contract_address).unwrap();
        let _event: SavedBalance = pop_log(core.contract_address).unwrap();

        // price 44,914,477,916.10660784:1 (sqrt_ratio ~= 6701.826461)
        // time window           = 2,040 sec
        // token0 sale-rate      = 1 / 4,080 ~= 0.0002450980392 per sec
        // token0 sold-amount   ~= 2,040 * 0.0002450980392 = 0.5 tokens
        // token1 sale-rate      = 1,000,000 / 4,080 ~= 245.09803921569 per sec
        // token1 sold-amount   ~= 2,040 * 245.09803921569 = 0.0000000001 tokens
        // Using twamm math to calculate the next price based on sell-rates:
        // next price 25,585,698.166907:1 (sqrt_ratio ~= 5058.230735)
        // trade token1 for token0 up to the next price
        // token0 spent amount ~= 0.484846500277456573
        // token1 bought amount ~= 16,435,997.977911462045022653
        // token0 reward rate = (0.5 - 0.484846500277456573) / 245.09803921569 = 0.00006182627887
        // token1 reward rate = (500,000 + 16,435,997.977911462045022653) / 0.0002450980392 = 69,098,871,754.301092936
        assert_eq!(swapped_event.delta.amount0.sign, false);
        assert_eq!(swapped_event.delta.amount0.mag, 484846500277456573);
        assert_eq!(swapped_event.delta.amount1.sign, true);
        assert_eq!(swapped_event.delta.amount1.mag, 16435997977911462045022653);
        assert_eq!(
            virtual_orders_executed_event.token0_reward_rate,
            0x21ac2195f0fdd994baf61 + 0x40d45d884786c18677398
        );
        assert_eq!(
            virtual_orders_executed_event.token1_reward_rate,
            0x1fce47dfe5389803ddd431d5f1667b413e + 0x10169d1bc5e0f6c0a106154f4bfa93eba0
        );

        // Withdraw proceeds for order1
        twamm.withdraw_from_order(order1_key, token_id1);
        let _event: LoadedBalance = pop_log(core.contract_address).unwrap();
        let event: OrderWithdrawn = pop_log(twamm.contract_address).unwrap();

        // amount  = reward_rate * sale_rate
        //         = 69,098,871,754.301092936 * 0.0002450980392
        //        ~= 16,935,997.977911462 tokens
        assert_eq!(event.amount, 16935997977911462045022651);

        // Withdraw proceeds for order2
        twamm.withdraw_from_order(order2_key, token_id2);
        let _event: LoadedBalance = pop_log(core.contract_address).unwrap();
        let event: OrderWithdrawn = pop_log(twamm.contract_address).unwrap();

        // amount  = reward_rate * sale_rate
        //         = 0.00006182627887 * 245.09803921569
        //        ~= 0.01515349972 tokens
        assert_eq!(event.amount, 15153499722543425);
    }

    #[test]
    fn test_place_orders_3() {
        // place one order on both sides expiring at different
        // price is 0.5:1

        let mut d: Deployer = Default::default();
        let core = d.deploy_core();
        let _event: ekubo::components::owned::Owned::OwnershipTransferred = pop_log(
            core.contract_address
        )
            .unwrap();
        let fee = 0;
        let initial_tick = i129 { mag: 693148, sign: true }; // ~ 0.5:1 price
        let token0_liquidity = 10_000_000 * 1000000000000000000;
        let token1_liquidity = 10_000_000 * 1000000000000000000;
        let (twamm, setup) = set_up_twamm_with_liquidity(
            ref d, core, fee, initial_tick, token0_liquidity, token1_liquidity
        );
        let twamm_pool_key = TWAMMPoolKey {
            token0: setup.token0.contract_address, token1: setup.token1.contract_address, fee
        };
        let _event: PoolInitialized = pop_log(core.contract_address).unwrap();
        let _event: PositionUpdated = pop_log(core.contract_address).unwrap();

        let timestamp = SIXTEEN_POW_ONE;
        set_block_timestamp(timestamp);

        let order_end_time = timestamp + SIXTEEN_POW_THREE - SIXTEEN_POW_ONE;
        let order2_end_time = order_end_time - SIXTEEN_POW_TWO;

        let amount = 10_000 * 1000000000000000000;
        let (token_id1, order1_key, _) = place_order_with_default_start_time(
            twamm, setup.token0, setup.token1, twamm_pool_key, false, order_end_time, amount
        );
        let _event: SavedBalance = pop_log(core.contract_address).unwrap();
        let _event: OrderPlaced = pop_log(twamm.contract_address).unwrap();

        let amount = 10_000 * 1000000000000000000;
        let (token_id2, order2_key, _) = place_order_with_default_start_time(
            twamm, setup.token0, setup.token1, twamm_pool_key, true, order2_end_time, amount
        );
        let _event: SavedBalance = pop_log(core.contract_address).unwrap();
        let _event: OrderPlaced = pop_log(twamm.contract_address).unwrap();

        // // halfway through the first order duration
        let execution_timestamp = timestamp + 2040;
        set_block_timestamp(execution_timestamp);
        twamm.execute_virtual_orders(setup.pool_key);
        let virtual_orders_executed_event: VirtualOrdersExecuted = pop_log(twamm.contract_address)
            .unwrap();

        assert_eq!(virtual_orders_executed_event.last_virtual_order_time, timestamp);
        assert_eq!(virtual_orders_executed_event.next_virtual_order_time, execution_timestamp);

        let swapped_event: Swapped = pop_log(core.contract_address).unwrap();
        let _event: LoadedBalance = pop_log(core.contract_address).unwrap();
        let _event: SavedBalance = pop_log(core.contract_address).unwrap();

        // price 0.5:1 (sqrt_ratio ~= 0.707106)
        // token0 time window    = 2,040 sec
        // token0 sale-rate      = 10,000 / 4,080 ~= 2.4509803922 per sec
        // token0 sold-amount   ~= 2,040 * 2.4509803922 = 5,000.000000088 tokens
        // token0 time window    = 2,040 sec
        // token1 sale-rate      = 10,000 / 3,824 ~= 2.6150627615 per sec
        // token1 sold-amount   ~= 2,040 * 2.6150627615 = 5,334.72803346 tokens
        // Using twamm math to calculate the next price based on sell-rates:
        // next price 0.500566586:1 (sqrt_ratio ~= 0.707507304931)
        // trade token1 for token0 up to the next price
        // token0 bought amount ~= 5663.417543754833543103
        // token1 spent amount  ~= 2833.312055778486901416
        // token0 reward rate = (5,334.72803346 - 2833.312055778486901416) / 2.4509803922 = 1,020.5777188761
        // token1 reward rate = (5663.417543754833543103 + 5,000.000000088) / 2.6150627615 = 4,077.6908687753
        assert_eq!(swapped_event.delta.amount0.sign, true);
        assert_eq!(swapped_event.delta.amount0.mag, 5663417543754833543103);
        assert_eq!(swapped_event.delta.amount1.sign, false);
        assert_eq!(swapped_event.delta.amount1.mag, 2833312055778486901416);
        assert_eq!(virtual_orders_executed_event.token0_reward_rate, 0xfedb0dcc5f11e1de241494a3cc0);
        assert_eq!(virtual_orders_executed_event.token1_reward_rate, 0x3fc93e562c2b1883b621228f5a6);

        // Two swaps are executed since order2 expires before order1
        set_block_timestamp(order_end_time + 1);
        twamm.execute_virtual_orders(setup.pool_key);

        let virtual_orders_executed_event: VirtualOrdersExecuted = pop_log(twamm.contract_address)
            .unwrap();
        assert_eq!(virtual_orders_executed_event.last_virtual_order_time, execution_timestamp);
        assert_eq!(virtual_orders_executed_event.next_virtual_order_time, order2_end_time);

        let swapped_event: Swapped = pop_log(core.contract_address).unwrap();

        // price 0.5005665865:1 (sqrt_ratio ~= 0.707507304931)
        // token0 time window    = 1,784 sec
        // token0 sale-rate      = 10,000 / 4,080 ~= 2.4509803922 per sec
        // token0 sold-amount   ~= 1,784 * 2.4509803922 = 4,372.5490196848 tokens
        // token0 time window    = 1,784 sec
        // token1 sale-rate      = 10,000 / 3,824 ~= 2.6150627615 per sec
        // token1 sold-amount   ~= 1,784 * 2.6150627615 = 4,665.271966516 tokens
        // Using twamm math to calculate the next price based on sell-rates:
        // next price 0.500566586:1 (sqrt_ratio ~= 0.707857)
        // trade token1 for token0 up to the next price
        // token0 bought amount ~= 4942.823774128753304972
        // token1 spent amount  ~= 2475.436682518369242249
        // token0 reward rate = (4,665.271966516 - 2475.436682518369242249) / 2.4509803922 = 893.4527958553
        // token1 reward rate = (4,942.823774128753304972 + 4,372.5490196848) / 2.6150627615 = 3,562.1985563629
        assert_eq!(swapped_event.delta.amount0.sign, true);
        assert_eq!(swapped_event.delta.amount0.mag, 4942823774128753304972);
        assert_eq!(swapped_event.delta.amount1.sign, false);
        assert_eq!(swapped_event.delta.amount1.mag, 2475436682518369242249);
        assert_eq!(
            virtual_orders_executed_event.token0_reward_rate,
            0xfedb0dcc5f11e1de241494a3cc0 + 0xdea32d49659bff590dfff190dd7
        );
        assert_eq!(
            virtual_orders_executed_event.token1_reward_rate,
            0x3fc93e562c2b1883b621228f5a6 + 0x37d73ea6e3578f4cc8e5ad2f6ce
        );

        // check second swap 

        let virtual_orders_executed_event: VirtualOrdersExecuted = pop_log(twamm.contract_address)
            .unwrap();

        assert_eq!(virtual_orders_executed_event.last_virtual_order_time, order2_end_time);
        assert_eq!(virtual_orders_executed_event.next_virtual_order_time, order_end_time);

        let swapped_event: Swapped = pop_log(core.contract_address).unwrap();
        let _event: LoadedBalance = pop_log(core.contract_address).unwrap();
        let _event: SavedBalance = pop_log(core.contract_address).unwrap();

        // price 0.501062076:1 (sqrt_ratio ~= 0.707857)
        // token0 time window    = 256 sec (difference between order1 and order2 end times)
        // token0 sale-rate      = 10,000 / 4,080 ~= 2.4509803922 per sec
        // token0 sold-amount   ~= 256 * 2.4509803922 = 627.450980392156862745 tokens
        // token1 bought amount ~= 314.372145178424505739
        // token1 reward rate = (314.372145178424505739 + 0) / 2.4509803922 = 128.2638352305
        assert_eq!(swapped_event.delta.amount0.sign, false);
        assert_eq!(swapped_event.delta.amount0.mag, 627450980392156862745);
        assert_eq!(swapped_event.delta.amount1.sign, true);
        assert_eq!(swapped_event.delta.amount1.mag, 314372145178424505739);
        assert_eq!(
            virtual_orders_executed_event.token0_reward_rate,
            0xfedb0dcc5f11e1de241494a3cc0 + 0xdea32d49659bff590dfff190dd7
        );
        assert_eq!(
            virtual_orders_executed_event.token1_reward_rate,
            0x3fc93e562c2b1883b621228f5a6
                + 0x37d73ea6e3578f4cc8e5ad2f6ce
                + 0x80438ab4b06581e84114b622a2
        );

        // // Withdraw proceeds for order1
        twamm.withdraw_from_order(order1_key, token_id1);
        let _event: LoadedBalance = pop_log(core.contract_address).unwrap();
        let event: OrderWithdrawn = pop_log(twamm.contract_address).unwrap();

        // amount  = reward_rate * sale_rate
        //         = (1,020.5777188761 + 893.4527958553 + 128.2638352305) * 2.4509803922
        //        ~= 5,005.6234068575 tokens
        assert_eq!(event.amount, 5005623406881568362072);

        // Withdraw proceeds for order2
        twamm.withdraw_from_order(order2_key, token_id2);
        let _event: LoadedBalance = pop_log(core.contract_address).unwrap();
        let event: OrderWithdrawn = pop_log(twamm.contract_address).unwrap();

        // amount  = reward_rate * sale_rate
        //         = (4,077.6908687753 + 3,562.1985563629) * 2.6150627615
        //        ~= 19,978.790293548 tokens
        assert_eq!(event.amount, 19978790337491429985327);
    }
}

fn set_up_twamm_with_default_liquidity(
    ref d: Deployer, core: ICoreDispatcher, fee: u128, initial_tick: i129
) -> (ITWAMMDispatcher, SetupPoolResult) {
    let token0_liquidity = 100_000_000 * 1000000000000000000;
    let token1_liquidity = 100_000_000 * 1000000000000000000;
    set_up_twamm_with_liquidity(ref d, core, fee, initial_tick, token0_liquidity, token1_liquidity)
}

fn set_up_twamm_with_liquidity(
    ref d: Deployer,
    core: ICoreDispatcher,
    fee: u128,
    initial_tick: i129,
    token0_liquidity: u128,
    token1_liquidity: u128
) -> (ITWAMMDispatcher, SetupPoolResult) {
    set_block_timestamp(1);

    let twamm = d.deploy_twamm(core);
    let _event: ekubo::components::owned::Owned::OwnershipTransferred = pop_log(
        twamm.contract_address
    )
        .unwrap();

    let liquidity_provider = contract_address_const::<42>();
    set_contract_address(liquidity_provider);

    let setup = d
        .setup_pool_with_core(
            core,
            fee: fee,
            tick_spacing: MAX_TICK_SPACING,
            initial_tick: initial_tick,
            extension: twamm.contract_address,
        );
    let positions = d.deploy_positions(setup.core);
    let bounds = max_bounds(MAX_TICK_SPACING);

    let max_liquidity = max_liquidity(
        tick_to_sqrt_ratio(initial_tick),
        tick_to_sqrt_ratio(bounds.lower),
        tick_to_sqrt_ratio(bounds.upper),
        token0_liquidity,
        token1_liquidity,
    );

    setup.token0.increase_balance(positions.contract_address, token0_liquidity);
    setup.token1.increase_balance(positions.contract_address, token1_liquidity);
    positions
        .mint_and_deposit_and_clear_both(
            pool_key: setup.pool_key, bounds: bounds, min_liquidity: max_liquidity
        );

    (ITWAMMDispatcher { contract_address: twamm.contract_address }, setup)
}

fn place_order_with_default_start_time(
    twamm: ITWAMMDispatcher,
    token0: IMockERC20Dispatcher,
    token1: IMockERC20Dispatcher,
    twamm_pool_key: TWAMMPoolKey,
    is_sell_token1: bool,
    end_time: u64,
    amount: u128
) -> (u64, OrderKey, OrderState) {
    place_order(twamm, token0, token1, twamm_pool_key, is_sell_token1, 0, end_time, amount)
}


fn place_order(
    twamm: ITWAMMDispatcher,
    token0: IMockERC20Dispatcher,
    token1: IMockERC20Dispatcher,
    twamm_pool_key: TWAMMPoolKey,
    is_sell_token1: bool,
    start_time: u64,
    end_time: u64,
    amount: u128
) -> (u64, OrderKey, OrderState) {
    let twamm_caller = contract_address_const::<43>();

    // place order
    set_contract_address(twamm_caller);
    let order_key = OrderKey {
        twamm_pool_key, is_sell_token1: is_sell_token1, start_time, end_time
    };

    if (is_sell_token1) {
        token1.increase_balance(twamm.contract_address, amount);
    } else {
        token0.increase_balance(twamm.contract_address, amount);
    }

    let token_id = twamm.place_order(order_key, amount);

    // return token id, order key, and order state
    (
        token_id,
        order_key,
        ITWAMMDispatcher { contract_address: twamm.contract_address }
            .get_order_state(order_key, token_id)
    )
}

