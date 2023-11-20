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
use ekubo::extensions::twamm::{OrderKey};
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
        let twamm = deploy_twamm(core, 1_000_u64);

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
        let twamm = deploy_twamm(core, 1_000_u64);

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
        let twamm = deploy_twamm(core, 1_000_u64);

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
        IMockERC20Dispatcher, IMockERC20DispatcherTrait,
    };

    #[test]
    #[available_gas(3000000000)]
    #[should_panic(expected: ('INVALID_EXPIRY_TIME', 'ENTRYPOINT_FAILED'))]
    fn test_place_order() {
        let timestamp = 1_000_000;
        set_block_timestamp(get_block_timestamp() + timestamp);

        let core = deploy_core();
        let twamm = deploy_twamm(core, 1_000_u64);
        let (token0, token1) = deploy_two_mock_tokens();

        let amount = 100_000_000;
        let order_key = OrderKey {
            token0: token0.contract_address,
            token1: token1.contract_address,
            time_intervals: 10_000,
            expiry_time: 0
        };

        token0.increase_balance(core.contract_address, amount);
        let token_id = ITWAMMDispatcher { contract_address: twamm.contract_address }
            .place_order(order_key, amount);
    }

    #[test]
    #[available_gas(3000000000)]
    #[should_panic(expected: ('INVALID_EXPIRY_TIME', 'ENTRYPOINT_FAILED'))]
    fn test_place_order_at_timestamp() {
        let timestamp = 1_000_000;
        set_block_timestamp(get_block_timestamp() + timestamp);

        let core = deploy_core();
        let twamm = deploy_twamm(core, 1_000_u64);
        let (token0, token1) = deploy_two_mock_tokens();

        let amount = 100_000_000;
        let order_key = OrderKey {
            token0: token0.contract_address,
            token1: token1.contract_address,
            time_intervals: 10_000,
            expiry_time: timestamp
        };

        token0.increase_balance(core.contract_address, amount);
        let token_id = ITWAMMDispatcher { contract_address: twamm.contract_address }
            .place_order(order_key, amount);
    }

    #[test]
    #[available_gas(3000000000)]
    fn test_place_order_at_intervals() {
        let current_time = get_block_timestamp();

        let core = deploy_core();
        let twamm = deploy_twamm(core, 1_000_u64);
        let (token0, token1) = deploy_two_mock_tokens();

        let amount = 100_000_000;

        // orders expire in <= 16**1 seconds 
        // allow 1 second precision
        token0.increase_balance(core.contract_address, amount);
        ITWAMMDispatcher { contract_address: twamm.contract_address }
            .place_order(
                OrderKey {
                    token0: token0.contract_address,
                    token1: token1.contract_address,
                    time_intervals: 10_000,
                    // first valid expiry time in interval
                    expiry_time: current_time + 1 // 16**0 + 1
                },
                amount
            );

        token0.increase_balance(core.contract_address, amount);
        ITWAMMDispatcher { contract_address: twamm.contract_address }
            .place_order(
                OrderKey {
                    token0: token0.contract_address,
                    token1: token1.contract_address,
                    time_intervals: 10_000,
                    expiry_time: current_time + 16
                },
                amount
            );

        // orders expire in <= 16**2 = 256 seconds (~4.2min),
        // allow 16 seconds precision
        token0.increase_balance(core.contract_address, amount);
        ITWAMMDispatcher { contract_address: twamm.contract_address }
            .place_order(
                OrderKey {
                    token0: token0.contract_address,
                    token1: token1.contract_address,
                    time_intervals: 10_000,
                    // first valid expiry time in interval
                    expiry_time: current_time + 16 + 16 // 16**1 + 16
                },
                amount
            );

        token0.increase_balance(core.contract_address, amount);
        ITWAMMDispatcher { contract_address: twamm.contract_address }
            .place_order(
                OrderKey {
                    token0: token0.contract_address,
                    token1: token1.contract_address,
                    time_intervals: 10_000,
                    expiry_time: current_time + 16 * 16 // 256
                },
                amount
            );

        // orders expire in <= 16**3 = 4,096 seconds (~1hr),
        // allow 256 seconds (~4.2min) precision
        token0.increase_balance(core.contract_address, amount);
        ITWAMMDispatcher { contract_address: twamm.contract_address }
            .place_order(
                OrderKey {
                    token0: token0.contract_address,
                    token1: token1.contract_address,
                    time_intervals: 10_000,
                    // first valid expiry time in interval
                    expiry_time: current_time + (16 * 16) + 256 // 16**2 + 256
                },
                amount
            );

        token0.increase_balance(core.contract_address, amount);
        ITWAMMDispatcher { contract_address: twamm.contract_address }
            .place_order(
                OrderKey {
                    token0: token0.contract_address,
                    token1: token1.contract_address,
                    time_intervals: 10_000,
                    expiry_time: current_time + (16 * 16 * 16) // 4,096
                },
                amount
            );

        // orders expire in <= 16**4 = 65,536 seconds (~18hrs),
        // allow 4,096 seconds (~1hr) precision
        token0.increase_balance(core.contract_address, amount);
        ITWAMMDispatcher { contract_address: twamm.contract_address }
            .place_order(
                OrderKey {
                    token0: token0.contract_address,
                    token1: token1.contract_address,
                    time_intervals: 10_000,
                    // first valid expiry time in interval
                    expiry_time: current_time + (16 * 16 * 16) + 4_096 // 16**3 + 4,096
                },
                amount
            );

        token0.increase_balance(core.contract_address, amount);
        ITWAMMDispatcher { contract_address: twamm.contract_address }
            .place_order(
                OrderKey {
                    token0: token0.contract_address,
                    token1: token1.contract_address,
                    time_intervals: 10_000,
                    expiry_time: current_time + (16 * 16 * 16 * 16) // 65,536
                },
                amount
            );

        // orders expire in <= 16**5 = 1,048,576 seconds (~12 days),
        // allow 65,536 seconds (~18hrs) precision
        token0.increase_balance(core.contract_address, amount);
        ITWAMMDispatcher { contract_address: twamm.contract_address }
            .place_order(
                OrderKey {
                    token0: token0.contract_address,
                    token1: token1.contract_address,
                    time_intervals: 10_000,
                    // first valid expiry time in interval
                    expiry_time: current_time + (16 * 16 * 16 * 16) + 65_536 // 16**4 + 65,536
                },
                amount
            );

        token0.increase_balance(core.contract_address, amount);
        ITWAMMDispatcher { contract_address: twamm.contract_address }
            .place_order(
                OrderKey {
                    token0: token0.contract_address,
                    token1: token1.contract_address,
                    time_intervals: 10_000,
                    expiry_time: current_time + (16 * 16 * 16 * 16 * 16) // 1,048,576
                },
                amount
            );

        // orders expire in <= 16**6 = 16,777,216 seconds (~6.4 months),
        // allow 1,048,576 seconds (~12 days) precision
        token0.increase_balance(core.contract_address, amount);
        ITWAMMDispatcher { contract_address: twamm.contract_address }
            .place_order(
                OrderKey {
                    token0: token0.contract_address,
                    token1: token1.contract_address,
                    time_intervals: 10_000,
                    // first valid expiry time in interval
                    expiry_time: current_time
                        + (16 * 16 * 16 * 16 * 16)
                        + 1_048_576 // 16**5 + 1,048,576
                },
                amount
            );

        token0.increase_balance(core.contract_address, amount);
        ITWAMMDispatcher { contract_address: twamm.contract_address }
            .place_order(
                OrderKey {
                    token0: token0.contract_address,
                    token1: token1.contract_address,
                    time_intervals: 10_000,
                    expiry_time: current_time + (16 * 16 * 16 * 16 * 16 * 16) // 16,777,216
                },
                amount
            );
    }
}
// mod PlaceOrderTests {
//     use super::{
//         PrintTrait, deploy_core, deploy_twamm, deploy_two_mock_tokens, ICoreDispatcher,
//         ICoreDispatcherTrait, PoolKey, MAX_TICK_SPACING, ITWAMMDispatcher, ITWAMMDispatcherTrait,
//         OrderKey, get_block_timestamp, set_block_timestamp, pop_log, to_token_key,
//         IMockERC20Dispatcher, IMockERC20DispatcherTrait,
//     };

//     #[test]
//     #[available_gas(3000000000)]
//     fn test_place_order_at_expiry_time() {
//         let timestamp = 1_000_000;
//         set_block_timestamp(get_block_timestamp() + timestamp);

//         let core = deploy_core();
//         let twamm = deploy_twamm(core, 1_000_u64);
//         let (token0, token1) = deploy_two_mock_tokens();

//         let amount = 100_000_000;
//         let order_key = OrderKey {
//             token0: token0.contract_address, token1: token1.contract_address, time_intervals: 10_000
//         };

//         token0.increase_balance(core.contract_address, amount);
//         let token_id = ITWAMMDispatcher { contract_address: twamm.contract_address }
//             .place_order(order_key, amount);

//         let order = ITWAMMDispatcher { contract_address: twamm.contract_address }
//             .get_order_state(order_key, token_id,);

//         // 1000000 - (1000001 % 1000) + (1000 * (10000 + 1)) = 11001000
//         assert(order.expiry_time == 11_001_000, 'EXPIRY_TIME');
//         // 100000000 * 2**32 / (11001000 - 1000000)
//         assert(order.sale_rate == 0x9ffbe7876, 'SALE_RATE');

//         let global_rate = ITWAMMDispatcher { contract_address: twamm.contract_address }
//             .get_sale_rate(to_token_key(order_key));

//         assert(global_rate == 0x9ffbe7876, 'GLOBAL_SALE_RATE');

//         // check event

//         let event: ekubo::extensions::twamm::TWAMM::OrderPlaced = pop_log(twamm.contract_address)
//             .unwrap();
//         assert(event.id == 1, 'event.id');
//         assert(event.amount == amount, 'event.amount');
//         assert(event.expiry_time == 11_001_000, 'event.expiry_time');
//         assert(event.sale_rate == 0x9ffbe7876, 'event.sale_rate');
//         assert(event.global_sale_rate == 0x9ffbe7876, 'event.global_sale_rate');
//     }

//     #[test]
//     #[available_gas(3000000000)]
//     fn test_place_order_just_after_expiry_time() {
//         set_block_timestamp(get_block_timestamp() + 1_000_001);

//         let core = deploy_core();
//         let twamm = deploy_twamm(core, 1_000_u64);
//         let (token0, token1) = deploy_two_mock_tokens();

//         let amount = 100_000_000;
//         let order_key = OrderKey {
//             token0: token0.contract_address, token1: token1.contract_address, time_intervals: 10_000
//         };

//         token0.increase_balance(core.contract_address, amount);
//         let token_id = ITWAMMDispatcher { contract_address: twamm.contract_address }
//             .place_order(order_key, amount);

//         let order = ITWAMMDispatcher { contract_address: twamm.contract_address }
//             .get_order_state(order_key, token_id,);

//         // 1000001 - (1000001 % 1000) + (1000 * (10000 + 1)) = 11001000
//         assert(order.expiry_time == 11_001_000, 'EXPIRY_TIME');
//         // 100000000 * 2**32 / (11001000 - 1000001)
//         assert(order.sale_rate == 0x9ffbe893c, 'SALE_RATE');

//         let global_rate = ITWAMMDispatcher { contract_address: twamm.contract_address }
//             .get_sale_rate(to_token_key(order_key));

//         assert(global_rate == 0x9ffbe893c, 'GLOBAL_SALE_RATE');

//         // check event

//         let event: ekubo::extensions::twamm::TWAMM::OrderPlaced = pop_log(twamm.contract_address)
//             .unwrap();
//         assert(event.id == 1, 'event.id');
//         assert(event.amount == amount, 'event.amount');
//         assert(event.expiry_time == 11_001_000, 'event.expiry_time');
//         assert(event.sale_rate == 0x9ffbe893c, 'event.sale_rate');
//         assert(event.global_sale_rate == 0x9ffbe893c, 'event.global_sale_rate');
//     }

//     #[test]
//     #[available_gas(3000000000)]
//     fn test_place_order_just_before_expiry_time() {
//         set_block_timestamp(get_block_timestamp() + 999_999);

//         let core = deploy_core();
//         let twamm = deploy_twamm(core, 1_000_u64);
//         let (token0, token1) = deploy_two_mock_tokens();

//         let amount = 100_000_000;
//         let order_key = OrderKey {
//             token0: token0.contract_address, token1: token1.contract_address, time_intervals: 10_000
//         };
//         token0.increase_balance(core.contract_address, amount);
//         let token_id = ITWAMMDispatcher { contract_address: twamm.contract_address }
//             .place_order(order_key, amount);

//         let order = ITWAMMDispatcher { contract_address: twamm.contract_address }
//             .get_order_state(
//                 OrderKey {
//                     token0: token0.contract_address,
//                     token1: token1.contract_address,
//                     time_intervals: 10_000
//                 },
//                 token_id,
//             );

//         // 999999 - (999999 % 1000) + (1000 * (10000 + 1)) = 11000000
//         assert(order.expiry_time == 11_000_000, 'EXPIRY_TIME');
//         // 100000000 * 2**32 / (11000000 - 999999)
//         assert(order.sale_rate == 0x9ffffef39, 'SALE_RATE');

//         let global_rate = ITWAMMDispatcher { contract_address: twamm.contract_address }
//             .get_sale_rate(to_token_key(order_key));

//         assert(global_rate == 0x9ffffef39, 'GLOBAL_SALE_RATE');

//         // check event

//         let event: ekubo::extensions::twamm::TWAMM::OrderPlaced = pop_log(twamm.contract_address)
//             .unwrap();
//         assert(event.id == 1, 'event.id');
//         assert(event.amount == amount, 'event.amount');
//         assert(event.expiry_time == 11_000_000, 'event.expiry_time');
//         assert(event.sale_rate == 0x9ffffef39, 'event.sale_rate');
//         assert(event.global_sale_rate == 0x9ffffef39, 'event.global_sale_rate');
//     }

//     #[test]
//     #[available_gas(3000000000)]
//     fn test_two_orders_and_global_rate_no_virtual_orders_executed() {
//         let timestamp = 1_000_000;
//         set_block_timestamp(get_block_timestamp() + timestamp);

//         let core = deploy_core();
//         let twamm = deploy_twamm(core, 100_u64);
//         let (token0, token1) = deploy_two_mock_tokens();

//         let amount = 100_000;
//         let order_key = OrderKey {
//             token0: token0.contract_address, token1: token1.contract_address, time_intervals: 100
//         };

//         token0.increase_balance(core.contract_address, amount);
//         let token_id_0 = ITWAMMDispatcher { contract_address: twamm.contract_address }
//             .place_order(order_key, amount);

//         let order_0 = ITWAMMDispatcher { contract_address: twamm.contract_address }
//             .get_order_state(order_key, token_id_0,);

//         // 1000000 + (100 * (100 + 1))  
//         assert(order_0.expiry_time == 1_010_100, 'EXPIRY_TIME');
//         // 100000 * 2**32 / (1010100 - 1000000)
//         assert(order_0.sale_rate == 0x9e6a74981, 'SALE_RATE');

//         // check event

//         let event: ekubo::extensions::twamm::TWAMM::OrderPlaced = pop_log(twamm.contract_address)
//             .unwrap();
//         assert(event.id == 1, 'event.id');
//         assert(event.amount == amount, 'event.amount');
//         assert(event.expiry_time == 1_010_100, 'event.expiry_time');
//         assert(event.sale_rate == 0x9e6a74981, 'event.sale_rate');
//         assert(event.global_sale_rate == 0x9e6a74981, 'event.global_sale_rate');

//         // increase timestamp
//         set_block_timestamp(get_block_timestamp() + 1);

//         token0.increase_balance(core.contract_address, amount);
//         let token_id_1 = ITWAMMDispatcher { contract_address: twamm.contract_address }
//             .place_order(order_key, amount);

//         let order_1 = ITWAMMDispatcher { contract_address: twamm.contract_address }
//             .get_order_state(order_key, token_id_1);

//         // 1000000 + (100 * (100 + 1))  
//         assert(order_1.expiry_time == 1_010_100, 'EXPIRY_TIME');
//         // 100000 * 2**32 / (1010100 - 1000001)
//         assert(order_1.sale_rate == 0x9e6e789c5, 'SALE_RATE');

//         // check event

//         let event: ekubo::extensions::twamm::TWAMM::OrderPlaced = pop_log(twamm.contract_address)
//             .unwrap();
//         assert(event.id == 2, 'event.id');
//         assert(event.amount == amount, 'event.amount');
//         assert(event.expiry_time == 1_010_100, 'event.expiry_time');
//         assert(event.sale_rate == 0x9e6e789c5, 'event.sale_rate');
//         assert(event.global_sale_rate == 0x9e6a74981 + 0x9e6e789c5, 'event.global_sale_rate');

//         let global_rate = ITWAMMDispatcher { contract_address: twamm.contract_address }
//             .get_sale_rate(to_token_key(order_key));

//         assert(global_rate == 0x9e6a74981 + 0x9e6e789c5, 'GLOBAL_SALE_RATE');
//     }

//     #[test]
//     #[available_gas(3000000000)]
//     #[should_panic(
//         expected: (
//             'DEPOSIT_AMOUNT_NE_AMOUNT',
//             'ENTRYPOINT_FAILED',
//             'ENTRYPOINT_FAILED',
//             'ENTRYPOINT_FAILED'
//         )
//     )]
//     fn test_place_order_no_token_transfer() {
//         let timestamp = 1_000_000;
//         set_block_timestamp(get_block_timestamp() + timestamp);

//         let core = deploy_core();
//         let twamm = deploy_twamm(core, 1_000_u64);
//         let (token0, token1) = deploy_two_mock_tokens();

//         let amount = 100_000_000;
//         let order_key = OrderKey {
//             token0: token0.contract_address, token1: token1.contract_address, time_intervals: 10_000
//         };

//         ITWAMMDispatcher { contract_address: twamm.contract_address }
//             .place_order(order_key, amount);
//     }
// }

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


