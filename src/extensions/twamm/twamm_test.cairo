use core::num::traits::{Zero};
use core::option::{OptionTrait};
use core::traits::{TryInto, Into};
use ekubo::components::clear::{IClearDispatcher, IClearDispatcherTrait};
use ekubo::core::Core::{PoolInitialized, PositionUpdated, Swapped, LoadedBalance, SavedBalance};

use ekubo::extensions::interfaces::twamm::{
    ITWAMMDispatcher, ITWAMMDispatcherTrait, OrderInfo, OrderKey, StateKey
};
use ekubo::extensions::twamm::TWAMM::{
    OrderUpdated, VirtualOrdersExecuted, OrderProceedsWithdrawn, time_to_word_and_bit_index,
    word_and_bit_index_to_time
};
use ekubo::extensions::twamm::math::{
    calculate_sale_rate, calculate_reward_amount, calculate_c, constants, calculate_next_sqrt_ratio,
    calculate_amount_from_sale_rate, time::{to_duration}
};
use ekubo::interfaces::core::{
    ICoreDispatcherTrait, ICoreDispatcher, SwapParameters, IExtensionDispatcher
};
use ekubo::interfaces::core::{UpdatePositionParameters};
use ekubo::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
use ekubo::interfaces::erc721::{IERC721Dispatcher, IERC721DispatcherTrait};
use ekubo::interfaces::positions::{
    IPositionsDispatcher, IPositionsDispatcherTrait, GetTokenInfoResult, GetTokenInfoRequest
};
use ekubo::interfaces::upgradeable::{IUpgradeableDispatcher, IUpgradeableDispatcherTrait};
use ekubo::math::bitmap::{Bitmap, BitmapTrait};
use ekubo::math::max_liquidity::{max_liquidity};
use ekubo::math::ticks::constants::{MAX_TICK_SPACING};
use ekubo::math::ticks::{min_tick, max_tick};
use ekubo::math::ticks::{tick_to_sqrt_ratio};
use ekubo::mock_erc20::{IMockERC20, IMockERC20Dispatcher, IMockERC20DispatcherTrait};
use ekubo::tests::helper::{
    Deployer, DeployerTrait, update_position, SetupPoolResult, default_owner, FEE_ONE_PERCENT
};
use ekubo::tests::mocks::mock_upgradeable::{MockUpgradeable};
use ekubo::types::bounds::{Bounds, max_bounds};
use ekubo::types::call_points::{CallPoints};
use ekubo::types::delta::{Delta};
use ekubo::types::i129::{i129, i129Trait, AddDeltaTrait};
use ekubo::types::keys::{PoolKey};
use starknet::testing::{set_contract_address, set_block_timestamp, pop_log};
use starknet::{
    get_contract_address, get_block_timestamp, contract_address_const, ClassHash, ContractAddress
};

const SIXTEEN_POW_ZERO: u64 = 0x1;
const SIXTEEN_POW_ONE: u64 = 0x10;
const SIXTEEN_POW_TWO: u64 = 0x100;
const SIXTEEN_POW_THREE: u64 = 0x1000;
const SIXTEEN_POW_FOUR: u64 = 0x10000;
const SIXTEEN_POW_FIVE: u64 = 0x100000;
const SIXTEEN_POW_SIX: u64 = 0x1000000;
const SIXTEEN_POW_SEVEN: u64 = 0x10000000;
const SIXTEEN_POW_EIGHT: u64 = 0x100000000; // 2**32

// floor(log base 1.000001 of 1.01)
const TICKS_IN_ONE_PERCENT: u128 = 9950;


impl PoolKeyIntoStateKey of Into<PoolKey, StateKey> {
    fn into(self: PoolKey) -> StateKey {
        StateKey { token0: self.token0, token1: self.token1, fee: self.fee }
    }
}

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
    use super::{
        time_to_word_and_bit_index, word_and_bit_index_to_time, Bitmap, BitmapTrait, Deployer,
        DeployerTrait, set_up_twamm, i129, contract_address_const, calculate_sale_rate,
        SIXTEEN_POW_TWO, SIXTEEN_POW_THREE, place_order, set_block_timestamp, StateKey,
        ITWAMMDispatcher, ITWAMMDispatcherTrait, get_block_timestamp
    };

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

    #[test]
    fn test_next_initialized_time() {
        let mut d: Deployer = Default::default();
        let core = d.deploy_core();
        let fee = 0;
        let initial_tick = i129 { mag: 693147, sign: false };
        let (twamm, setup, positions) = set_up_twamm(
            ref d,
            core,
            fee,
            initial_tick,
            amount0: 100_000_000 * 1000000000000000000,
            amount1: 100_000_000 * 1000000000000000000
        );

        let timestamp = SIXTEEN_POW_TWO;
        set_block_timestamp(timestamp);

        let owner = contract_address_const::<42>();
        let amount = 10_000 * 1000000000000000000;
        let order1_start_time = 2 * SIXTEEN_POW_TWO;
        let order1_end_time = SIXTEEN_POW_THREE;

        let state_key: StateKey = StateKey {
            token0: setup.token0.contract_address, token1: setup.token1.contract_address, fee
        };

        place_order(
            positions,
            owner,
            setup.token0,
            setup.token1,
            fee,
            order1_start_time,
            order1_end_time,
            amount
        );

        assert_eq!(
            twamm.next_initialized_time(state_key, from: 0, max_time: timestamp), (timestamp, false)
        );

        assert_eq!(
            twamm.next_initialized_time(state_key, from: timestamp, max_time: order1_end_time),
            (order1_start_time, true)
        );

        assert_eq!(
            twamm.next_initialized_time(state_key, from: timestamp, max_time: order1_start_time),
            (order1_start_time, true)
        );

        assert_eq!(
            twamm
                .next_initialized_time(
                    state_key, from: order1_start_time, max_time: order1_start_time + 16
                ),
            (order1_start_time + 16, false)
        );

        assert_eq!(
            twamm
                .next_initialized_time(
                    state_key, from: order1_start_time, max_time: order1_end_time
                ),
            (order1_end_time, true)
        );
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

mod PlaceOrdersCheckDeltaAndNet {
    use super::{
        Deployer, DeployerTrait, ICoreDispatcher, ICoreDispatcherTrait, PoolKey, MAX_TICK_SPACING,
        ITWAMMDispatcher, ITWAMMDispatcherTrait, OrderKey, get_block_timestamp, set_block_timestamp,
        pop_log, IMockERC20, IMockERC20Dispatcher, IMockERC20DispatcherTrait,
        contract_address_const, set_contract_address, max_bounds, update_position, max_liquidity,
        Bounds, tick_to_sqrt_ratio, i129, i129Trait, AddDeltaTrait, TICKS_IN_ONE_PERCENT,
        IPositionsDispatcher, IPositionsDispatcherTrait, get_contract_address, IExtensionDispatcher,
        SetupPoolResult, SIXTEEN_POW_ZERO, SIXTEEN_POW_ONE, SIXTEEN_POW_TWO, SIXTEEN_POW_THREE,
        SIXTEEN_POW_FOUR, SIXTEEN_POW_FIVE, SIXTEEN_POW_SIX, SIXTEEN_POW_SEVEN, OrderUpdated,
        VirtualOrdersExecuted, set_up_twamm, place_order, calculate_sale_rate, PoolKeyIntoStateKey,
        to_duration
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
        let (twamm, setup, positions) = set_up_twamm(
            ref d,
            core,
            fee,
            initial_tick,
            amount0: 100_000_000 * 1000000000000000000,
            amount1: 100_000_000 * 1000000000000000000
        );

        let timestamp = SIXTEEN_POW_TWO;
        set_block_timestamp(timestamp);

        let owner = contract_address_const::<42>();
        let amount = 10_000 * 1000000000000000000;
        let duration = 2 * SIXTEEN_POW_TWO;
        let order1_end_time = timestamp + duration;
        let expected_sale_rate_net = calculate_sale_rate(
            amount: amount, duration: to_duration(start: timestamp, end: order1_end_time)
        );

        place_order(positions, owner, setup.token0, setup.token1, fee, 0, order1_end_time, amount);

        let _event: OrderUpdated = pop_log(twamm.contract_address).unwrap();

        let sale_rate_net = twamm.get_sale_rate_net(setup.pool_key.into(), order1_end_time);
        assert_eq!(sale_rate_net, expected_sale_rate_net);

        let order2_start_time = order1_end_time; // start time is order1 end time
        let order2_end_time = order1_end_time + 2 * SIXTEEN_POW_TWO;
        place_order(
            positions,
            owner,
            setup.token0,
            setup.token1,
            fee,
            order2_start_time,
            order2_end_time,
            amount
        );

        let _event: OrderUpdated = pop_log(twamm.contract_address).unwrap();

        let sale_rate_net = twamm.get_sale_rate_net(setup.pool_key.into(), order1_end_time);
        assert_eq!(sale_rate_net, expected_sale_rate_net * 2);

        set_block_timestamp(order2_end_time + 1);
        twamm.execute_virtual_orders(setup.pool_key.into());

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
        let (twamm, setup, positions) = set_up_twamm(
            ref d,
            core,
            fee,
            initial_tick,
            amount0: 100_000_000 * 1000000000000000000,
            amount1: 100_000_000 * 1000000000000000000
        );

        let timestamp = SIXTEEN_POW_TWO;
        set_block_timestamp(timestamp);

        let owner = contract_address_const::<42>();
        let amount = 10_000 * 1000000000000000000;
        let duration = 2 * SIXTEEN_POW_TWO;
        let order1_end_time = timestamp + duration;
        let expected_sale_rate_net = calculate_sale_rate(
            amount, duration: to_duration(start: timestamp, end: order1_end_time)
        );

        place_order(positions, owner, setup.token1, setup.token0, fee, 0, order1_end_time, amount);

        let _event: OrderUpdated = pop_log(twamm.contract_address).unwrap();

        let sale_rate_net = twamm.get_sale_rate_net(setup.pool_key.into(), order1_end_time);
        assert_eq!(sale_rate_net, expected_sale_rate_net);

        let order2_start_time = order1_end_time; // start time is order1 end time
        let order2_end_time = order1_end_time + 2 * SIXTEEN_POW_TWO;
        place_order(
            positions,
            owner,
            setup.token1,
            setup.token0,
            fee,
            order2_start_time,
            order2_end_time,
            amount
        );

        let _event: OrderUpdated = pop_log(twamm.contract_address).unwrap();

        let sale_rate_net = twamm.get_sale_rate_net(setup.pool_key.into(), order1_end_time);
        assert_eq!(sale_rate_net, expected_sale_rate_net * 2);

        set_block_timestamp(order2_end_time + 1);
        twamm.execute_virtual_orders(setup.pool_key.into());

        let event: VirtualOrdersExecuted = pop_log(twamm.contract_address).unwrap();

        assert_eq!(event.last_virtual_order_time, timestamp);
        assert_eq!(event.next_virtual_order_time, order1_end_time);

        let event: VirtualOrdersExecuted = pop_log(twamm.contract_address).unwrap();

        assert_eq!(event.last_virtual_order_time, order1_end_time);
        assert_eq!(event.next_virtual_order_time, order2_end_time);
    }

    #[test]
    fn test_place_orders_2() {
        // Both order start after the current time
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
        let (twamm, setup, positions) = set_up_twamm(
            ref d,
            core,
            fee,
            initial_tick,
            amount0: 100_000_000 * 1000000000000000000,
            amount1: 100_000_000 * 1000000000000000000
        );

        let timestamp = SIXTEEN_POW_TWO;
        set_block_timestamp(timestamp);

        let owner = contract_address_const::<42>();
        let amount = 10_000 * 1000000000000000000;
        let duration = 2 * SIXTEEN_POW_TWO;
        let order1_end_time = timestamp + duration;
        let expected_sale_rate_net = calculate_sale_rate(
            amount, duration: to_duration(start: timestamp, end: order1_end_time)
        );

        let (order1_id, order1_key, order1_state) = place_order(
            positions, owner, setup.token0, setup.token1, fee, 0, order1_end_time, amount
        );

        let _event: OrderUpdated = pop_log(twamm.contract_address).unwrap();

        let sale_rate_net = twamm.get_sale_rate_net(setup.pool_key.into(), order1_end_time);
        assert_eq!(sale_rate_net, expected_sale_rate_net);

        let order2_start_time = order1_end_time; // start time is order1 end time
        let order2_end_time = order1_end_time + 2 * SIXTEEN_POW_TWO;
        let (order2_id, order2_key, order2_state) = place_order(
            positions,
            owner,
            setup.token0,
            setup.token1,
            fee,
            order2_start_time,
            order2_end_time,
            amount
        );

        let _event: OrderUpdated = pop_log(twamm.contract_address).unwrap();

        let sale_rate_net = twamm.get_sale_rate_net(setup.pool_key.into(), order1_end_time);
        assert_eq!(sale_rate_net, expected_sale_rate_net * 2);

        // cancel both orders

        set_contract_address(owner);
        positions.decrease_sale_rate(order1_id, order1_key, order1_state.sale_rate);

        let sale_rate_net = twamm.get_sale_rate_net(setup.pool_key.into(), order1_end_time);
        assert_eq!(sale_rate_net, expected_sale_rate_net);

        positions.decrease_sale_rate(order2_id, order2_key, order2_state.sale_rate,);

        let sale_rate_net = twamm.get_sale_rate_net(setup.pool_key.into(), order1_end_time);
        assert_eq!(sale_rate_net, 0);
    }

    #[test]
    fn test_place_orders_3() {
        // Both order expiries after the current time
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
        let (twamm, setup, positions) = set_up_twamm(
            ref d,
            core,
            fee,
            initial_tick,
            amount0: 100_000_000 * 1000000000000000000,
            amount1: 100_000_000 * 1000000000000000000
        );

        let timestamp = SIXTEEN_POW_TWO;
        set_block_timestamp(timestamp);

        let owner = contract_address_const::<42>();
        let amount = 10_000 * 1000000000000000000;
        let duration = 2 * SIXTEEN_POW_TWO;
        let order1_end_time = timestamp + duration;
        let expected_sale_rate_net = calculate_sale_rate(
            amount, duration: to_duration(start: timestamp, end: order1_end_time)
        );

        let (order1_id, order1_key, order1_state) = place_order(
            positions, owner, setup.token1, setup.token0, fee, 0, order1_end_time, amount
        );

        let _event: OrderUpdated = pop_log(twamm.contract_address).unwrap();

        let sale_rate_net = twamm.get_sale_rate_net(setup.pool_key.into(), order1_end_time);
        assert_eq!(sale_rate_net, expected_sale_rate_net);

        let order2_start_time = order1_end_time; // start time is order1 end time
        let order2_end_time = order1_end_time + 2 * SIXTEEN_POW_TWO;
        let (order2_id, order2_key, order2_state) = place_order(
            positions,
            owner,
            setup.token1,
            setup.token0,
            fee,
            order2_start_time,
            order2_end_time,
            amount
        );

        let _event: OrderUpdated = pop_log(twamm.contract_address).unwrap();

        let sale_rate_net = twamm.get_sale_rate_net(setup.pool_key.into(), order1_end_time);
        assert_eq!(sale_rate_net, expected_sale_rate_net * 2);

        // cancel both orders

        set_contract_address(owner);
        positions.decrease_sale_rate(order1_id, order1_key, order1_state.sale_rate);

        let sale_rate_net = twamm.get_sale_rate_net(setup.pool_key.into(), order1_end_time);
        assert_eq!(sale_rate_net, expected_sale_rate_net);

        positions.decrease_sale_rate(order2_id, order2_key, order2_state.sale_rate);

        let sale_rate_net = twamm.get_sale_rate_net(setup.pool_key.into(), order1_end_time);
        assert_eq!(sale_rate_net, 0);
    }
}

mod PlaceOrderAndCheckExecutionTimesAndRates {
    use super::{
        Deployer, DeployerTrait, ICoreDispatcher, ICoreDispatcherTrait, PoolKey, MAX_TICK_SPACING,
        ITWAMMDispatcher, ITWAMMDispatcherTrait, OrderKey, get_block_timestamp, set_block_timestamp,
        pop_log, IMockERC20, IMockERC20Dispatcher, IMockERC20DispatcherTrait,
        contract_address_const, set_contract_address, max_bounds, update_position, max_liquidity,
        Bounds, tick_to_sqrt_ratio, i129, TICKS_IN_ONE_PERCENT, IPositionsDispatcher,
        IPositionsDispatcherTrait, get_contract_address, IExtensionDispatcher, SetupPoolResult,
        SIXTEEN_POW_ZERO, SIXTEEN_POW_ONE, SIXTEEN_POW_TWO, SIXTEEN_POW_THREE, SIXTEEN_POW_FOUR,
        SIXTEEN_POW_FIVE, SIXTEEN_POW_SIX, SIXTEEN_POW_SEVEN, OrderUpdated, VirtualOrdersExecuted,
        OrderInfo, set_up_twamm, place_order, PoolKeyIntoStateKey
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
        let (twamm, setup, positions) = set_up_twamm(
            ref d,
            core,
            fee,
            initial_tick,
            amount0: 100_000_000 * 1000000000000000000,
            amount1: 100_000_000 * 1000000000000000000
        );

        let timestamp = SIXTEEN_POW_ONE;
        set_block_timestamp(timestamp);

        let owner = contract_address_const::<42>();
        let amount = 10_000 * 1000000000000000000;
        let order1_timestamp = timestamp;
        let order1_end_time = timestamp + SIXTEEN_POW_THREE - SIXTEEN_POW_ONE;
        place_order(positions, owner, setup.token0, setup.token1, fee, 0, order1_end_time, amount);

        let _event: OrderUpdated = pop_log(twamm.contract_address).unwrap();

        let order2_timestamp = timestamp + SIXTEEN_POW_ONE;
        set_block_timestamp(order2_timestamp);
        let order2_end_time = order2_timestamp + SIXTEEN_POW_THREE - 2 * SIXTEEN_POW_ONE;
        place_order(positions, owner, setup.token1, setup.token0, fee, 0, order2_end_time, amount);

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
        let (twamm, setup, positions) = set_up_twamm(
            ref d,
            core,
            fee,
            initial_tick,
            amount0: 100_000_000 * 1000000000000000000,
            amount1: 100_000_000 * 1000000000000000000
        );

        let timestamp = SIXTEEN_POW_ONE;
        set_block_timestamp(timestamp);

        let owner = contract_address_const::<42>();
        let amount = 10_000 * 1000000000000000000;
        let order1_timestamp = timestamp;
        let order1_end_time = timestamp + SIXTEEN_POW_ONE;
        let (_, _, order1_state) = place_order(
            positions, owner, setup.token0, setup.token1, fee, 0, order1_end_time, amount
        );

        let _event: OrderUpdated = pop_log(twamm.contract_address).unwrap();

        let order2_timestamp = order1_end_time + SIXTEEN_POW_ONE;
        set_block_timestamp(order2_timestamp);
        let order2_end_time = order2_timestamp + SIXTEEN_POW_THREE - 3 * SIXTEEN_POW_ONE;
        place_order(positions, owner, setup.token1, setup.token0, fee, 0, order2_end_time, amount);

        // first order execution
        let event: VirtualOrdersExecuted = pop_log(twamm.contract_address).unwrap();

        assert_eq!(event.last_virtual_order_time, order1_timestamp);
        assert_eq!(event.next_virtual_order_time, order1_end_time);
        assert_eq!(event.token0_sale_rate, order1_state.sale_rate);
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
        let (twamm, setup, positions) = set_up_twamm(
            ref d,
            core,
            fee,
            initial_tick,
            amount0: 100_000_000 * 1000000000000000000,
            amount1: 100_000_000 * 1000000000000000000
        );

        let timestamp = 1_000_000;
        set_block_timestamp(timestamp);

        let owner = contract_address_const::<42>();
        let amount = 100_000 * 1000000000000000000;
        let order1_timestamp = timestamp;
        let order1_end_time = timestamp + SIXTEEN_POW_ONE;
        let (_, _, order1_state) = place_order(
            positions, owner, setup.token0, setup.token1, fee, 0, order1_end_time, amount
        );
        let _event: OrderUpdated = pop_log(twamm.contract_address).unwrap();

        let order2_end_time = timestamp + SIXTEEN_POW_ONE * 2;
        let (_, _, order2_state) = place_order(
            positions, owner, setup.token1, setup.token0, fee, 0, order2_end_time, amount
        );
        let _event: OrderUpdated = pop_log(twamm.contract_address).unwrap();

        // after order2 expires
        let order_execution_timestamp = order2_end_time + SIXTEEN_POW_ONE;
        set_block_timestamp(order_execution_timestamp);

        // manually trigger virtual order execution
        twamm.execute_virtual_orders(setup.pool_key.into());

        // first order execution
        let event: VirtualOrdersExecuted = pop_log(twamm.contract_address).unwrap();

        assert_eq!(event.last_virtual_order_time, order1_timestamp);
        assert_eq!(event.next_virtual_order_time, order1_end_time);
        assert_eq!(event.token0_sale_rate, order1_state.sale_rate);
        assert_eq!(event.token1_sale_rate, order2_state.sale_rate);

        // second order execution
        let event: VirtualOrdersExecuted = pop_log(twamm.contract_address).unwrap();
        assert_eq!(event.last_virtual_order_time, order1_end_time);
        assert_eq!(event.next_virtual_order_time, order2_end_time);

        assert_eq!(event.token0_sale_rate, 0);
        assert_eq!(event.token1_sale_rate, order2_state.sale_rate);
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
        let (twamm, setup, positions) = set_up_twamm(
            ref d,
            core,
            fee,
            initial_tick,
            amount0: 100_000_000 * 1000000000000000000,
            amount1: 100_000_000 * 1000000000000000000
        );

        let timestamp = 1_000_000;
        set_block_timestamp(timestamp);

        let owner = contract_address_const::<42>();
        let amount = 10_000 * 1000000000000000000;
        let order1_timestamp = timestamp;
        let order1_end_time = timestamp + SIXTEEN_POW_ONE;
        let (_, _, order1_state) = place_order(
            positions, owner, setup.token0, setup.token1, fee, 0, order1_end_time, amount
        );

        let _event: OrderUpdated = pop_log(twamm.contract_address).unwrap();

        let order2_end_time = timestamp
            + SIXTEEN_POW_THREE
            - 0x240; // ensure end time is valid and in a diff word
        let (_, _, order2_state) = place_order(
            positions, owner, setup.token1, setup.token0, fee, 0, order2_end_time, amount
        );
        let _event: OrderUpdated = pop_log(twamm.contract_address).unwrap();

        // after order2 expires
        let order_execution_timestamp = order2_end_time + SIXTEEN_POW_THREE;
        set_block_timestamp(order_execution_timestamp);

        // manually trigger virtual order execution
        twamm.execute_virtual_orders(setup.pool_key.into());

        // first order execution
        let event: VirtualOrdersExecuted = pop_log(twamm.contract_address).unwrap();

        assert_eq!(event.last_virtual_order_time, order1_timestamp);
        assert_eq!(event.next_virtual_order_time, order1_end_time);
        assert_eq!(event.token0_sale_rate, order1_state.sale_rate);
        assert_eq!(event.token1_sale_rate, order2_state.sale_rate);

        // second order execution
        let event: VirtualOrdersExecuted = pop_log(twamm.contract_address).unwrap();
        assert_eq!(event.last_virtual_order_time, order1_end_time);
        assert_eq!(event.next_virtual_order_time, order2_end_time);

        assert_eq!(event.token0_sale_rate, 0);
        assert_eq!(event.token1_sale_rate, order2_state.sale_rate);
    // third order execution
    // no event is emitted since both sale rates are 0
    }
}

mod CancelOrderTests {
    use super::{
        Deployer, DeployerTrait, ICoreDispatcher, ICoreDispatcherTrait, PoolKey, MAX_TICK_SPACING,
        ITWAMMDispatcher, ITWAMMDispatcherTrait, OrderKey, get_block_timestamp, set_block_timestamp,
        pop_log, get_contract_address, IMockERC20, IMockERC20Dispatcher, IMockERC20DispatcherTrait,
        SIXTEEN_POW_TWO, SIXTEEN_POW_THREE, IERC20Dispatcher, IERC20DispatcherTrait, place_order,
        i129, contract_address_const, set_contract_address, IPositionsDispatcher,
        IPositionsDispatcherTrait, IClearDispatcher, IClearDispatcherTrait, set_up_twamm
    };

    #[test]
    #[should_panic(
        expected: (
            'ORDER_ENDED',
            'ENTRYPOINT_FAILED',
            'ENTRYPOINT_FAILED',
            'ENTRYPOINT_FAILED',
            'ENTRYPOINT_FAILED'
        )
    )]
    fn test_place_order_and_cancel_after_end_time() {
        let mut d: Deployer = Default::default();
        let core = d.deploy_core();
        let fee = 0;
        let initial_tick = i129 { mag: 693147, sign: false };
        let (_, setup, positions) = set_up_twamm(
            ref d,
            core,
            fee,
            initial_tick,
            amount0: 100_000_000 * 1000000000000000000,
            amount1: 100_000_000 * 1000000000000000000
        );

        let timestamp = SIXTEEN_POW_TWO;
        set_block_timestamp(timestamp);

        let owner = contract_address_const::<42>();
        let amount = 1_000 * 1000000000000000000;
        let (order1_id, order1_key, order1_state) = place_order(
            positions,
            owner,
            setup.token0,
            setup.token1,
            fee,
            SIXTEEN_POW_TWO,
            SIXTEEN_POW_THREE,
            amount
        );

        set_block_timestamp(order1_key.end_time + 1);

        set_contract_address(owner);
        positions.decrease_sale_rate(order1_id, order1_key, order1_state.sale_rate);
    }

    #[test]
    fn test_place_order_and_cancel_before_order_execution() {
        let mut d: Deployer = Default::default();
        let core = d.deploy_core();
        let fee = 0;
        let initial_tick = i129 { mag: 693147, sign: false };
        let (twamm, setup, positions) = set_up_twamm(
            ref d,
            core,
            fee,
            initial_tick,
            amount0: 100_000_000 * 1000000000000000000,
            amount1: 100_000_000 * 1000000000000000000
        );

        let timestamp = SIXTEEN_POW_TWO;
        set_block_timestamp(timestamp);

        let owner = contract_address_const::<42>();
        let amount = 1_000 * 1000000000000000000;
        let (order1_id, order1_key, order1_state) = place_order(
            positions,
            owner,
            setup.token0,
            setup.token1,
            fee,
            SIXTEEN_POW_TWO,
            SIXTEEN_POW_THREE,
            amount
        );

        let token_balance_before = IERC20Dispatcher {
            contract_address: setup.token0.contract_address
        }
            .balanceOf(owner);

        set_contract_address(owner);
        positions.decrease_sale_rate(order1_id, order1_key, order1_state.sale_rate);
        IClearDispatcher { contract_address: twamm.contract_address }
            .clear(IERC20Dispatcher { contract_address: setup.token0.contract_address });

        let token_balance_after = IERC20Dispatcher {
            contract_address: setup.token0.contract_address
        }
            .balanceOf(owner);

        assert_eq!(token_balance_after - token_balance_before, 999999999999999999999);
    }

    #[test]
    #[should_panic(
        expected: (
            'MUST_WITHDRAW_PROCEEDS',
            'ENTRYPOINT_FAILED',
            'ENTRYPOINT_FAILED',
            'ENTRYPOINT_FAILED',
            'ENTRYPOINT_FAILED'
        )
    )]
    fn test_place_order_and_cancel_during_order_execution_without_withdrawing_proceeds() {
        let mut d: Deployer = Default::default();
        let core = d.deploy_core();
        let fee = 0;
        let initial_tick = i129 { mag: 693147, sign: false };
        let (_, setup, positions) = set_up_twamm(
            ref d,
            core,
            fee,
            initial_tick,
            amount0: 100_000_000 * 1000000000000000000,
            amount1: 100_000_000 * 1000000000000000000
        );

        let timestamp = SIXTEEN_POW_TWO;
        set_block_timestamp(timestamp);

        let owner = contract_address_const::<42>();
        let amount = 1_000 * 1000000000000000000;
        let (order1_id, order1_key, order1_state) = place_order(
            positions,
            owner,
            setup.token0,
            setup.token1,
            fee,
            SIXTEEN_POW_TWO,
            SIXTEEN_POW_THREE,
            amount
        );

        set_block_timestamp(SIXTEEN_POW_THREE - 1);

        set_contract_address(owner);
        positions.decrease_sale_rate(order1_id, order1_key, order1_state.sale_rate);
    }

    #[test]
    fn test_place_order_and_cancel_before_full_order_execution() {
        let mut d: Deployer = Default::default();
        let core = d.deploy_core();
        let fee = 0;
        let initial_tick = i129 { mag: 693147, sign: false };
        let (_, setup, positions) = set_up_twamm(
            ref d,
            core,
            fee,
            initial_tick,
            amount0: 100_000_000 * 1000000000000000000,
            amount1: 100_000_000 * 1000000000000000000
        );

        let timestamp = SIXTEEN_POW_TWO;
        set_block_timestamp(timestamp);

        let owner = contract_address_const::<42>();
        let amount = 1_000 * 1000000000000000000;
        let (order1_id, order1_key, order1_state) = place_order(
            positions,
            owner,
            setup.token0,
            setup.token1,
            fee,
            SIXTEEN_POW_TWO,
            SIXTEEN_POW_THREE,
            amount
        );

        set_block_timestamp(SIXTEEN_POW_THREE - 1);

        set_contract_address(owner);
        positions.withdraw_proceeds_from_sale(order1_id, order1_key);
        positions.decrease_sale_rate(order1_id, order1_key, order1_state.sale_rate);
    }
}

mod PlaceOrdersAndUpdateSaleRate {
    use super::{
        Deployer, DeployerTrait, ICoreDispatcher, ICoreDispatcherTrait, PoolKey, MAX_TICK_SPACING,
        ITWAMMDispatcher, ITWAMMDispatcherTrait, OrderKey, get_block_timestamp, set_block_timestamp,
        pop_log, IMockERC20, IMockERC20Dispatcher, IMockERC20DispatcherTrait,
        contract_address_const, set_contract_address, max_bounds, update_position, max_liquidity,
        Bounds, tick_to_sqrt_ratio, i129, i129Trait, AddDeltaTrait, TICKS_IN_ONE_PERCENT,
        IPositionsDispatcher, IPositionsDispatcherTrait, get_contract_address, IExtensionDispatcher,
        SetupPoolResult, SIXTEEN_POW_ZERO, SIXTEEN_POW_ONE, SIXTEEN_POW_TWO, SIXTEEN_POW_THREE,
        SIXTEEN_POW_FOUR, SIXTEEN_POW_FIVE, SIXTEEN_POW_SIX, SIXTEEN_POW_SEVEN, SIXTEEN_POW_EIGHT,
        OrderUpdated, VirtualOrdersExecuted, OrderInfo, set_up_twamm, place_order,
        calculate_sale_rate, OrderProceedsWithdrawn, Swapped, LoadedBalance, SavedBalance,
        PoolInitialized, PositionUpdated, calculate_amount_from_sale_rate, FEE_ONE_PERCENT,
        IERC20Dispatcher, IERC20DispatcherTrait, IClearDispatcher, IClearDispatcherTrait,
        PoolKeyIntoStateKey, constants, max_tick, to_duration
    };

    #[test]
    #[should_panic(
        expected: (
            'ORDER_ENDED',
            'ENTRYPOINT_FAILED',
            'ENTRYPOINT_FAILED',
            'ENTRYPOINT_FAILED',
            'ENTRYPOINT_FAILED'
        )
    )]
    fn test_update_at_order_expiry() {
        let mut d: Deployer = Default::default();
        let core = d.deploy_core();
        let fee = 0;
        let initial_tick = i129 { mag: 693147, sign: false };
        let (twamm, setup, positions) = set_up_twamm(
            ref d,
            core,
            fee,
            initial_tick,
            amount0: 100_000_000 * 1000000000000000000,
            amount1: 100_000_000 * 1000000000000000000
        );

        let timestamp = SIXTEEN_POW_TWO;
        set_block_timestamp(timestamp);

        let owner = contract_address_const::<42>();

        let amount = 10_000 * 1000000000000000000;
        let duration = 2 * SIXTEEN_POW_TWO;
        let order1_end_time = timestamp + duration;

        let (order1_id, order1_key, order1_state) = place_order(
            positions, owner, setup.token0, setup.token1, fee, 0, order1_end_time, amount
        );

        let _event: OrderUpdated = pop_log(twamm.contract_address).unwrap();

        set_block_timestamp(order1_end_time);

        set_contract_address(owner);
        positions.decrease_sale_rate(order1_id, order1_key, order1_state.sale_rate);
    }

    #[test]
    #[should_panic(
        expected: (
            'ORDER_ENDED',
            'ENTRYPOINT_FAILED',
            'ENTRYPOINT_FAILED',
            'ENTRYPOINT_FAILED',
            'ENTRYPOINT_FAILED'
        )
    )]
    fn test_update_after_order_expiry() {
        let mut d: Deployer = Default::default();
        let core = d.deploy_core();
        let fee = 0;
        let initial_tick = i129 { mag: 693147, sign: false };
        let (twamm, setup, positions) = set_up_twamm(
            ref d,
            core,
            fee,
            initial_tick,
            amount0: 100_000_000 * 1000000000000000000,
            amount1: 100_000_000 * 1000000000000000000
        );

        let timestamp = SIXTEEN_POW_TWO;
        set_block_timestamp(timestamp);

        let owner = contract_address_const::<42>();

        let amount = 10_000 * 1000000000000000000;
        let duration = 2 * SIXTEEN_POW_TWO;
        let order1_end_time = timestamp + duration;

        let (order1_id, order1_key, order1_state) = place_order(
            positions, owner, setup.token0, setup.token1, fee, 0, order1_end_time, amount
        );

        let _event: OrderUpdated = pop_log(twamm.contract_address).unwrap();

        set_block_timestamp(order1_end_time + 1);

        set_contract_address(owner);
        positions.decrease_sale_rate(order1_id, order1_key, order1_state.sale_rate * 2);
    }

    #[test]
    #[should_panic(
        expected: (
            'ADD_DELTA',
            'ENTRYPOINT_FAILED',
            'ENTRYPOINT_FAILED',
            'ENTRYPOINT_FAILED',
            'ENTRYPOINT_FAILED'
        )
    )]
    fn test_update_invalid_sale_rate() {
        let mut d: Deployer = Default::default();
        let core = d.deploy_core();
        let fee = 0;
        let initial_tick = i129 { mag: 693147, sign: false };
        let (twamm, setup, positions) = set_up_twamm(
            ref d,
            core,
            fee,
            initial_tick,
            amount0: 100_000_000 * 1000000000000000000,
            amount1: 100_000_000 * 1000000000000000000
        );

        let timestamp = SIXTEEN_POW_TWO;
        set_block_timestamp(timestamp);

        let owner = contract_address_const::<42>();

        let amount = 10_000 * 1000000000000000000;
        let duration = 2 * SIXTEEN_POW_TWO;
        let order1_end_time = timestamp + duration;

        let (order1_id, order1_key, order1_state) = place_order(
            positions, owner, setup.token0, setup.token1, fee, 0, order1_end_time, amount
        );

        let _event: OrderUpdated = pop_log(twamm.contract_address).unwrap();

        set_contract_address(owner);
        positions.decrease_sale_rate(order1_id, order1_key, order1_state.sale_rate * 2);
    }

    #[test]
    fn test_decrease_order_sale_rate_before_order_starts_token0() {
        let mut d: Deployer = Default::default();
        let core = d.deploy_core();
        let _event: ekubo::components::owned::Owned::OwnershipTransferred = pop_log(
            core.contract_address
        )
            .unwrap();
        let fee = 0;
        let initial_tick = i129 { mag: 693147, sign: false };
        let (twamm, setup, positions) = set_up_twamm(
            ref d,
            core,
            fee,
            initial_tick,
            amount0: 100_000_000 * 1000000000000000000,
            amount1: 100_000_000 * 1000000000000000000
        );
        let _event: PoolInitialized = pop_log(core.contract_address).unwrap();
        let _event: PositionUpdated = pop_log(core.contract_address).unwrap();

        let timestamp = SIXTEEN_POW_TWO;
        set_block_timestamp(timestamp);

        let owner = contract_address_const::<42>();

        let amount = 10_000 * 1000000000000000000;
        let order1_start_time = timestamp + 2 * SIXTEEN_POW_TWO;
        let order1_end_time = order1_start_time + SIXTEEN_POW_TWO;
        let expected_sale_rate = calculate_sale_rate(
            amount, duration: to_duration(start: order1_start_time, end: order1_end_time)
        );

        let (order1_id, order1_key, order1_state) = place_order(
            positions,
            owner,
            setup.token0,
            setup.token1,
            fee,
            order1_start_time,
            order1_end_time,
            amount
        );

        let _event: SavedBalance = pop_log(core.contract_address).unwrap();
        let _event: OrderUpdated = pop_log(twamm.contract_address).unwrap();

        // start sale rate net
        let sale_rate_net = twamm.get_sale_rate_net(setup.pool_key.into(), order1_start_time);
        assert_eq!(sale_rate_net, expected_sale_rate);
        // end sale rate net
        let sale_rate_net = twamm.get_sale_rate_net(setup.pool_key.into(), order1_end_time);
        assert_eq!(sale_rate_net, expected_sale_rate);

        // start sale rate delta
        let (token0_start_sale_rate_delta, _) = twamm
            .get_sale_rate_delta(setup.pool_key.into(), order1_start_time);
        assert_eq!(token0_start_sale_rate_delta, i129 { mag: expected_sale_rate, sign: false });
        // end sale rate delta
        let (token0_end_sale_rate_delta, _) = twamm
            .get_sale_rate_delta(setup.pool_key.into(), order1_end_time);
        assert_eq!(token0_end_sale_rate_delta, i129 { mag: expected_sale_rate, sign: true });

        // set time to just before order start
        set_block_timestamp(order1_start_time - 1);

        // decrease sale rate
        set_contract_address(owner);
        positions.decrease_sale_rate(order1_id, order1_key, order1_state.sale_rate / 2);

        let event: LoadedBalance = pop_log(core.contract_address).unwrap();
        assert_eq!(event.key.owner, twamm.contract_address);
        assert_eq!(event.key.token, setup.token0.contract_address);
        assert_eq!(event.key.salt, 0);
        assert_eq!(event.amount, amount / 2);

        // order sale rate
        let order1_state = twamm
            .get_order_info(positions.contract_address, order1_id.into(), order1_key);
        assert_eq!(order1_state.sale_rate, expected_sale_rate / 2);

        // start sale rate net
        let sale_rate_net = twamm.get_sale_rate_net(setup.pool_key.into(), order1_start_time);
        assert_eq!(sale_rate_net, expected_sale_rate / 2);
        // end sale rate net
        let sale_rate_net = twamm.get_sale_rate_net(setup.pool_key.into(), order1_end_time);
        assert_eq!(sale_rate_net, expected_sale_rate / 2);

        // start sale rate delta
        let (token0_start_sale_rate_delta, _) = twamm
            .get_sale_rate_delta(setup.pool_key.into(), order1_start_time);
        assert_eq!(token0_start_sale_rate_delta, i129 { mag: expected_sale_rate / 2, sign: false });
        // end sale rate delta
        let (token0_end_sale_rate_delta, _) = twamm
            .get_sale_rate_delta(setup.pool_key.into(), order1_end_time);
        assert_eq!(token0_end_sale_rate_delta, i129 { mag: expected_sale_rate / 2, sign: true });
    }

    #[test]
    fn test_decrease_order_sale_rate_before_order_starts_token1() {
        let mut d: Deployer = Default::default();
        let core = d.deploy_core();
        let _event: ekubo::components::owned::Owned::OwnershipTransferred = pop_log(
            core.contract_address
        )
            .unwrap();
        let fee = 0;
        let initial_tick = i129 { mag: 693147, sign: false };
        let (twamm, setup, positions) = set_up_twamm(
            ref d,
            core,
            fee,
            initial_tick,
            amount0: 100_000_000 * 1000000000000000000,
            amount1: 100_000_000 * 1000000000000000000
        );
        let _event: PoolInitialized = pop_log(core.contract_address).unwrap();
        let _event: PositionUpdated = pop_log(core.contract_address).unwrap();

        let timestamp = SIXTEEN_POW_TWO;
        set_block_timestamp(timestamp);

        let owner = contract_address_const::<42>();

        let amount = 10_000 * 1000000000000000000;
        let order1_start_time = timestamp + 2 * SIXTEEN_POW_TWO;
        let order1_end_time = order1_start_time + SIXTEEN_POW_TWO;
        let expected_sale_rate = calculate_sale_rate(
            amount, duration: to_duration(start: order1_start_time, end: order1_end_time)
        );

        let (order1_id, order1_key, order1_state) = place_order(
            positions,
            owner,
            setup.token1,
            setup.token0,
            fee,
            order1_start_time,
            order1_end_time,
            amount
        );

        let _event: SavedBalance = pop_log(core.contract_address).unwrap();
        let _event: OrderUpdated = pop_log(twamm.contract_address).unwrap();

        // start sale rate net
        let sale_rate_net = twamm.get_sale_rate_net(setup.pool_key.into(), order1_start_time);
        assert_eq!(sale_rate_net, expected_sale_rate);
        // end sale rate net
        let sale_rate_net = twamm.get_sale_rate_net(setup.pool_key.into(), order1_end_time);
        assert_eq!(sale_rate_net, expected_sale_rate);

        // start sale rate delta
        let (_, token1_start_sale_rate_delta) = twamm
            .get_sale_rate_delta(setup.pool_key.into(), order1_start_time);
        assert_eq!(token1_start_sale_rate_delta, i129 { mag: expected_sale_rate, sign: false });
        // end sale rate delta
        let (_, token1_end_sale_rate_delta) = twamm
            .get_sale_rate_delta(setup.pool_key.into(), order1_end_time);
        assert_eq!(token1_end_sale_rate_delta, i129 { mag: expected_sale_rate, sign: true });

        // set time to just before order start
        set_block_timestamp(order1_start_time - 1);

        // decrease sale rate
        set_contract_address(owner);
        positions.decrease_sale_rate(order1_id, order1_key, order1_state.sale_rate / 2);

        let event: LoadedBalance = pop_log(core.contract_address).unwrap();
        assert_eq!(event.key.owner, twamm.contract_address);
        assert_eq!(event.key.token, setup.token1.contract_address);
        assert_eq!(event.key.salt, 0);
        assert_eq!(event.amount, amount / 2);

        // order sale rate
        let order1_state = twamm
            .get_order_info(positions.contract_address, order1_id.into(), order1_key);
        assert_eq!(order1_state.sale_rate, expected_sale_rate / 2);

        // start sale rate net
        let sale_rate_net = twamm.get_sale_rate_net(setup.pool_key.into(), order1_start_time);
        assert_eq!(sale_rate_net, expected_sale_rate / 2);
        // end sale rate net
        let sale_rate_net = twamm.get_sale_rate_net(setup.pool_key.into(), order1_end_time);
        assert_eq!(sale_rate_net, expected_sale_rate / 2);

        // start sale rate delta
        let (_, token1_start_sale_rate_delta) = twamm
            .get_sale_rate_delta(setup.pool_key.into(), order1_start_time);
        assert_eq!(token1_start_sale_rate_delta, i129 { mag: expected_sale_rate / 2, sign: false });
        // end sale rate delta
        let (_, token1_end_sale_rate_delta) = twamm
            .get_sale_rate_delta(setup.pool_key.into(), order1_end_time);
        assert_eq!(token1_end_sale_rate_delta, i129 { mag: expected_sale_rate / 2, sign: true });
    }

    #[test]
    fn test_increase_order_sale_rate_before_order_starts_token0() {
        let mut d: Deployer = Default::default();
        let core = d.deploy_core();
        let _event: ekubo::components::owned::Owned::OwnershipTransferred = pop_log(
            core.contract_address
        )
            .unwrap();
        let fee = 0;
        let initial_tick = i129 { mag: 693147, sign: false };
        let (twamm, setup, positions) = set_up_twamm(
            ref d,
            core,
            fee,
            initial_tick,
            amount0: 100_000_000 * 1000000000000000000,
            amount1: 100_000_000 * 1000000000000000000
        );
        let _event: PoolInitialized = pop_log(core.contract_address).unwrap();
        let _event: PositionUpdated = pop_log(core.contract_address).unwrap();

        let timestamp = SIXTEEN_POW_TWO;
        set_block_timestamp(timestamp);

        let owner = contract_address_const::<42>();

        let amount = 10_000 * 1000000000000000000;
        let order1_start_time = timestamp + 2 * SIXTEEN_POW_TWO;
        let order1_end_time = order1_start_time + SIXTEEN_POW_TWO;
        let expected_sale_rate = calculate_sale_rate(
            amount, duration: to_duration(start: order1_start_time, end: order1_end_time)
        );

        let (order1_id, order1_key, order1_state) = place_order(
            positions,
            owner,
            setup.token0,
            setup.token1,
            fee,
            order1_start_time,
            order1_end_time,
            amount
        );

        let _event: SavedBalance = pop_log(core.contract_address).unwrap();
        let _event: OrderUpdated = pop_log(twamm.contract_address).unwrap();

        // start sale rate net
        let sale_rate_net = twamm.get_sale_rate_net(setup.pool_key.into(), order1_start_time);
        assert_eq!(sale_rate_net, expected_sale_rate);
        // end sale rate net
        let sale_rate_net = twamm.get_sale_rate_net(setup.pool_key.into(), order1_end_time);
        assert_eq!(sale_rate_net, expected_sale_rate);

        // start sale rate delta
        let (token0_start_sale_rate_delta, _) = twamm
            .get_sale_rate_delta(setup.pool_key.into(), order1_start_time);
        assert_eq!(token0_start_sale_rate_delta, i129 { mag: expected_sale_rate, sign: false });
        // end sale rate delta
        let (token0_end_sale_rate_delta, _) = twamm
            .get_sale_rate_delta(setup.pool_key.into(), order1_end_time);
        assert_eq!(token0_end_sale_rate_delta, i129 { mag: expected_sale_rate, sign: true });

        // set time to just before order start
        set_block_timestamp(order1_start_time - 1);

        let sale_rate_delta = i129 { mag: order1_state.sale_rate / 2, sign: false };

        // transfer funds to twamm
        let sale_rate_delta_amount = calculate_amount_from_sale_rate(
            sale_rate_delta.mag,
            duration: to_duration(start: order1_start_time, end: order1_end_time),
            round_up: false
        );

        setup
            .token0
            .increase_balance(positions.contract_address, sale_rate_delta_amount.into() + 1);
        // increase sale rate
        set_contract_address(owner);
        positions.increase_sell_amount(order1_id, order1_key, sale_rate_delta_amount);

        let expected_updated_sale_rate = expected_sale_rate + expected_sale_rate / 2;

        let event: SavedBalance = pop_log(core.contract_address).unwrap();
        assert_eq!(event.key.owner, twamm.contract_address);
        assert_eq!(event.key.token, setup.token0.contract_address);
        assert_eq!(event.key.salt, 0);
        assert_eq!(event.amount, amount / 2);

        // order sale rate
        let order1_state = twamm
            .get_order_info(positions.contract_address, order1_id.into(), order1_key);
        assert_eq!(order1_state.sale_rate, expected_updated_sale_rate);

        // start sale rate net
        let sale_rate_net = twamm.get_sale_rate_net(setup.pool_key.into(), order1_start_time);
        assert_eq!(sale_rate_net, expected_updated_sale_rate);
        // end sale rate net
        let sale_rate_net = twamm.get_sale_rate_net(setup.pool_key.into(), order1_end_time);
        assert_eq!(sale_rate_net, expected_updated_sale_rate);

        // start sale rate delta
        let (token0_start_sale_rate_delta, _) = twamm
            .get_sale_rate_delta(setup.pool_key.into(), order1_start_time);
        assert_eq!(
            token0_start_sale_rate_delta, i129 { mag: expected_updated_sale_rate, sign: false }
        );
        // end sale rate delta
        let (token0_end_sale_rate_delta, _) = twamm
            .get_sale_rate_delta(setup.pool_key.into(), order1_end_time);
        assert_eq!(
            token0_end_sale_rate_delta, i129 { mag: expected_updated_sale_rate, sign: true }
        );
    }

    #[test]
    fn test_increase_order_sale_rate_before_order_starts_token1() {
        let mut d: Deployer = Default::default();
        let core = d.deploy_core();
        let _event: ekubo::components::owned::Owned::OwnershipTransferred = pop_log(
            core.contract_address
        )
            .unwrap();
        let fee = 0;
        let initial_tick = i129 { mag: 693147, sign: false };
        let (twamm, setup, positions) = set_up_twamm(
            ref d,
            core,
            fee,
            initial_tick,
            amount0: 100_000_000 * 1000000000000000000,
            amount1: 100_000_000 * 1000000000000000000
        );
        let _event: PoolInitialized = pop_log(core.contract_address).unwrap();
        let _event: PositionUpdated = pop_log(core.contract_address).unwrap();

        let timestamp = SIXTEEN_POW_TWO;
        set_block_timestamp(timestamp);

        let owner = contract_address_const::<42>();

        let amount = 10_000 * 1000000000000000000;
        let order1_start_time = timestamp + 2 * SIXTEEN_POW_TWO;
        let order1_end_time = order1_start_time + SIXTEEN_POW_TWO;
        let expected_sale_rate = calculate_sale_rate(
            amount, duration: to_duration(start: order1_start_time, end: order1_end_time)
        );

        let (order1_id, order1_key, order1_state) = place_order(
            positions,
            owner,
            setup.token1,
            setup.token0,
            fee,
            order1_start_time,
            order1_end_time,
            amount
        );

        let _event: SavedBalance = pop_log(core.contract_address).unwrap();
        let _event: OrderUpdated = pop_log(twamm.contract_address).unwrap();

        // start sale rate net
        let sale_rate_net = twamm.get_sale_rate_net(setup.pool_key.into(), order1_start_time);
        assert_eq!(sale_rate_net, expected_sale_rate);
        // end sale rate net
        let sale_rate_net = twamm.get_sale_rate_net(setup.pool_key.into(), order1_end_time);
        assert_eq!(sale_rate_net, expected_sale_rate);

        // start sale rate delta
        let (_, token1_start_sale_rate_delta) = twamm
            .get_sale_rate_delta(setup.pool_key.into(), order1_start_time);
        assert_eq!(token1_start_sale_rate_delta, i129 { mag: expected_sale_rate, sign: false });
        // end sale rate delta
        let (_, token1_end_sale_rate_delta) = twamm
            .get_sale_rate_delta(setup.pool_key.into(), order1_end_time);
        assert_eq!(token1_end_sale_rate_delta, i129 { mag: expected_sale_rate, sign: true });

        // set time to just before order start
        set_block_timestamp(order1_start_time - 1);

        let sale_rate_delta = i129 { mag: order1_state.sale_rate / 2, sign: false };

        // transfer funds to twamm
        let sale_rate_delta_amount = calculate_amount_from_sale_rate(
            sale_rate_delta.mag,
            duration: to_duration(start: order1_start_time, end: order1_end_time),
            round_up: false
        );
        setup
            .token1
            .increase_balance(positions.contract_address, sale_rate_delta_amount.into() + 1);
        // increase sale rate
        set_contract_address(owner);
        positions.increase_sell_amount(order1_id, order1_key, sale_rate_delta_amount);

        let expected_updated_sale_rate = expected_sale_rate + expected_sale_rate / 2;

        let event: SavedBalance = pop_log(core.contract_address).unwrap();
        assert_eq!(event.key.owner, twamm.contract_address);
        assert_eq!(event.key.token, setup.token1.contract_address);
        assert_eq!(event.key.salt, 0);
        assert_eq!(event.amount, amount / 2);

        // order sale rate
        let order1_state = twamm
            .get_order_info(positions.contract_address, order1_id.into(), order1_key);
        assert_eq!(order1_state.sale_rate, expected_updated_sale_rate);

        // start sale rate net
        let sale_rate_net = twamm.get_sale_rate_net(setup.pool_key.into(), order1_start_time);
        assert_eq!(sale_rate_net, expected_updated_sale_rate);
        // end sale rate net
        let sale_rate_net = twamm.get_sale_rate_net(setup.pool_key.into(), order1_end_time);
        assert_eq!(sale_rate_net, expected_updated_sale_rate);

        // start sale rate delta
        let (_, token1_start_sale_rate_delta) = twamm
            .get_sale_rate_delta(setup.pool_key.into(), order1_start_time);
        assert_eq!(
            token1_start_sale_rate_delta, i129 { mag: expected_updated_sale_rate, sign: false }
        );
        // end sale rate delta
        let (_, token1_end_sale_rate_delta) = twamm
            .get_sale_rate_delta(setup.pool_key.into(), order1_end_time);
        assert_eq!(
            token1_end_sale_rate_delta, i129 { mag: expected_updated_sale_rate, sign: true }
        );
    }

    #[test]
    fn test_decrease_order_sale_rate_after_order_starts_token0() {
        let mut d: Deployer = Default::default();
        let core = d.deploy_core();
        let _event: ekubo::components::owned::Owned::OwnershipTransferred = pop_log(
            core.contract_address
        )
            .unwrap();
        let fee = 0;
        let initial_tick = i129 { mag: 693147, sign: false };
        let (twamm, setup, positions) = set_up_twamm(
            ref d,
            core,
            fee,
            initial_tick,
            amount0: 100_000_000 * 1000000000000000000,
            amount1: 100_000_000 * 1000000000000000000
        );
        let _event: PoolInitialized = pop_log(core.contract_address).unwrap();
        let _event: PositionUpdated = pop_log(core.contract_address).unwrap();

        let timestamp = SIXTEEN_POW_TWO;
        set_block_timestamp(timestamp);

        let owner = contract_address_const::<42>();

        let amount = 10_000 * 1000000000000000000;
        let order1_start_time = timestamp + 2 * SIXTEEN_POW_TWO;
        let order1_end_time = order1_start_time + SIXTEEN_POW_TWO;
        let expected_sale_rate = calculate_sale_rate(
            amount, duration: to_duration(start: order1_start_time, end: order1_end_time)
        );

        let (order1_id, order1_key, order1_state) = place_order(
            positions,
            owner,
            setup.token0,
            setup.token1,
            fee,
            order1_start_time,
            order1_end_time,
            amount
        );

        let _event: SavedBalance = pop_log(core.contract_address).unwrap();
        let _event: OrderUpdated = pop_log(twamm.contract_address).unwrap();

        // start sale rate net
        let sale_rate_net = twamm.get_sale_rate_net(setup.pool_key.into(), order1_start_time);
        assert_eq!(sale_rate_net, expected_sale_rate);
        // end sale rate net
        let sale_rate_net = twamm.get_sale_rate_net(setup.pool_key.into(), order1_end_time);
        assert_eq!(sale_rate_net, expected_sale_rate);

        // start sale rate delta
        let (token0_start_sale_rate_delta, _) = twamm
            .get_sale_rate_delta(setup.pool_key.into(), order1_start_time);
        assert_eq!(token0_start_sale_rate_delta, i129 { mag: expected_sale_rate, sign: false });
        // end sale rate delta
        let (token0_end_sale_rate_delta, _) = twamm
            .get_sale_rate_delta(setup.pool_key.into(), order1_end_time);
        assert_eq!(token0_end_sale_rate_delta, i129 { mag: expected_sale_rate, sign: true });

        // set time halfway through order execution
        set_block_timestamp(order1_start_time + (order1_end_time - order1_start_time) / 2);

        // decrease sale rate by half
        set_contract_address(owner);
        positions.decrease_sale_rate(order1_id, order1_key, order1_state.sale_rate / 2);

        // virtual orders are executed
        let virtual_orders_executed_event: VirtualOrdersExecuted = pop_log(twamm.contract_address)
            .unwrap();
        let _event: OrderUpdated = pop_log(twamm.contract_address).unwrap();

        assert_eq!(virtual_orders_executed_event.last_virtual_order_time, order1_start_time);
        assert_eq!(
            virtual_orders_executed_event.next_virtual_order_time,
            order1_start_time + (order1_end_time - order1_start_time) / 2
        );

        let swapped_event: Swapped = pop_log(core.contract_address).unwrap();
        let _event: LoadedBalance = pop_log(core.contract_address).unwrap();
        let _event: SavedBalance = pop_log(core.contract_address).unwrap();

        // price 2:1
        // time window    = 256 sec
        // sale rate      = 10,000 / 256 ~= 39.0625 per sec
        // sold amount   ~= 128 * 39.0625 ~= 5,000 tokens
        // bought amount ~= 9,9989.94829713355494903 tokens
        assert_eq!(swapped_event.delta.amount0.sign, false);
        assert_eq!(swapped_event.delta.amount0.mag, 5000000000000000000000);
        assert_eq!(swapped_event.delta.amount1.sign, true);
        assert_eq!(swapped_event.delta.amount1.mag, 9998994829713355494903);

        let event: LoadedBalance = pop_log(core.contract_address).unwrap();
        assert_eq!(event.key.owner, twamm.contract_address);
        assert_eq!(event.key.token, setup.token0.contract_address);
        assert_eq!(event.key.salt, 0);
        // half the order has been executed, half of the remaining is removed
        assert_eq!(event.amount, amount / 4);

        // order sale rate
        let order1_state = twamm
            .get_order_info(positions.contract_address, order1_id.into(), order1_key);
        assert_eq!(order1_state.sale_rate, expected_sale_rate / 2);

        // start sale rate net, if start_time is in the past, do not update
        let sale_rate_net = twamm.get_sale_rate_net(setup.pool_key.into(), order1_start_time);
        assert_eq!(sale_rate_net, expected_sale_rate);
        // end sale rate net
        let sale_rate_net = twamm.get_sale_rate_net(setup.pool_key.into(), order1_end_time);
        assert_eq!(sale_rate_net, expected_sale_rate / 2);

        // start sale rate delta, if start_time is in the past, do not update
        let (token0_start_sale_rate_delta, _) = twamm
            .get_sale_rate_delta(setup.pool_key.into(), order1_start_time);
        assert_eq!(token0_start_sale_rate_delta, i129 { mag: expected_sale_rate, sign: false });

        // end sale rate delta
        let (token0_end_sale_rate_delta, _) = twamm
            .get_sale_rate_delta(setup.pool_key.into(), order1_end_time);
        assert_eq!(token0_end_sale_rate_delta, i129 { mag: expected_sale_rate / 2, sign: true });

        // withdraw proceeds (same transaction)
        positions.withdraw_proceeds_from_sale(order1_id, order1_key);
        let event: OrderProceedsWithdrawn = pop_log(twamm.contract_address).unwrap();

        // amount  = updated reward_rate * updated sale_rate
        //         = 511.948535281 * 19.53125
        //        ~= 9,998.994829713355494901 tokens
        assert_eq!(event.amount, 9998994829713355494901);
    }

    #[test]
    fn test_decrease_order_sale_rate_before_order_starts_and_pay_fee_token0() {
        let mut d: Deployer = Default::default();
        let core = d.deploy_core();
        let _event: ekubo::components::owned::Owned::OwnershipTransferred = pop_log(
            core.contract_address
        )
            .unwrap();
        let fee = FEE_ONE_PERCENT;
        let initial_tick = i129 { mag: 693147, sign: false };
        let (twamm, setup, positions) = set_up_twamm(
            ref d,
            core,
            fee,
            initial_tick,
            amount0: 100_000_000 * 1000000000000000000,
            amount1: 100_000_000 * 1000000000000000000
        );
        let _event: PoolInitialized = pop_log(core.contract_address).unwrap();
        let _event: PositionUpdated = pop_log(core.contract_address).unwrap();

        let timestamp = SIXTEEN_POW_TWO;
        set_block_timestamp(timestamp);

        let owner = contract_address_const::<42>();

        let amount = 10_000 * 1000000000000000000;
        let order1_start_time = timestamp + 2 * SIXTEEN_POW_TWO;
        let order1_end_time = order1_start_time + SIXTEEN_POW_TWO;

        let (order1_id, order1_key, order1_state) = place_order(
            positions,
            owner,
            setup.token0,
            setup.token1,
            fee,
            order1_start_time,
            order1_end_time,
            amount
        );

        let _event: SavedBalance = pop_log(core.contract_address).unwrap();
        let _event: OrderUpdated = pop_log(twamm.contract_address).unwrap();

        // set time to just before order start
        set_block_timestamp(order1_start_time - 1);

        let token_balance_before = IERC20Dispatcher {
            contract_address: setup.token0.contract_address
        }
            .balanceOf(owner);

        // decrease sale rate
        set_contract_address(owner);
        positions.decrease_sale_rate(order1_id, order1_key, order1_state.sale_rate / 2);
        IClearDispatcher { contract_address: twamm.contract_address }
            .clear(IERC20Dispatcher { contract_address: setup.token0.contract_address });

        let token_balance_after = IERC20Dispatcher {
            contract_address: setup.token0.contract_address
        }
            .balanceOf(owner);

        // pays 1% fee of 5000
        assert_eq!(token_balance_after - token_balance_before, 4950000000000000000000);
    }

    #[test]
    fn test_decrease_order_sale_rate_before_order_starts_and_pay_fee_token1() {
        let mut d: Deployer = Default::default();
        let core = d.deploy_core();
        let _event: ekubo::components::owned::Owned::OwnershipTransferred = pop_log(
            core.contract_address
        )
            .unwrap();
        let fee = FEE_ONE_PERCENT;
        let initial_tick = i129 { mag: 693147, sign: false };
        let (twamm, setup, positions) = set_up_twamm(
            ref d,
            core,
            fee,
            initial_tick,
            amount0: 100_000_000 * 1000000000000000000,
            amount1: 100_000_000 * 1000000000000000000
        );
        let _event: PoolInitialized = pop_log(core.contract_address).unwrap();
        let _event: PositionUpdated = pop_log(core.contract_address).unwrap();

        let timestamp = SIXTEEN_POW_TWO;
        set_block_timestamp(timestamp);

        let owner = contract_address_const::<42>();

        let amount = 10_000 * 1000000000000000000;
        let order1_start_time = timestamp + 2 * SIXTEEN_POW_TWO;
        let order1_end_time = order1_start_time + SIXTEEN_POW_TWO;

        let (order1_id, order1_key, order1_state) = place_order(
            positions,
            owner,
            setup.token1,
            setup.token0,
            fee,
            order1_start_time,
            order1_end_time,
            amount
        );

        let _event: SavedBalance = pop_log(core.contract_address).unwrap();
        let _event: OrderUpdated = pop_log(twamm.contract_address).unwrap();

        // set time to just before order start
        set_block_timestamp(order1_start_time - 1);

        let token_balance_before = IERC20Dispatcher {
            contract_address: setup.token1.contract_address
        }
            .balanceOf(owner);

        // decrease sale rate
        set_contract_address(owner);
        positions.decrease_sale_rate(order1_id, order1_key, order1_state.sale_rate / 2);
        IClearDispatcher { contract_address: twamm.contract_address }
            .clear(IERC20Dispatcher { contract_address: setup.token1.contract_address });

        let token_balance_after = IERC20Dispatcher {
            contract_address: setup.token1.contract_address
        }
            .balanceOf(owner);

        // pays 1% fee of 5000
        assert_eq!(token_balance_after - token_balance_before, 4950000000000000000000);
    }
}

mod PlaceOrderOnOneSideAndWithdrawProceeds {
    use super::{
        Deployer, DeployerTrait, ICoreDispatcher, ICoreDispatcherTrait, PoolKey, MAX_TICK_SPACING,
        ITWAMMDispatcher, ITWAMMDispatcherTrait, OrderKey, get_block_timestamp, set_block_timestamp,
        pop_log, IMockERC20, IMockERC20Dispatcher, IMockERC20DispatcherTrait,
        contract_address_const, set_contract_address, max_bounds, update_position, max_liquidity,
        Bounds, tick_to_sqrt_ratio, i129, TICKS_IN_ONE_PERCENT, IPositionsDispatcher,
        IPositionsDispatcherTrait, get_contract_address, IExtensionDispatcher, SetupPoolResult,
        SIXTEEN_POW_ZERO, SIXTEEN_POW_ONE, SIXTEEN_POW_TWO, SIXTEEN_POW_THREE, SIXTEEN_POW_FOUR,
        SIXTEEN_POW_FIVE, SIXTEEN_POW_SIX, SIXTEEN_POW_SEVEN, OrderUpdated, VirtualOrdersExecuted,
        OrderInfo, OrderProceedsWithdrawn, Swapped, LoadedBalance, SavedBalance, PoolInitialized,
        PositionUpdated, place_order, set_up_twamm, PoolKeyIntoStateKey
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
        let (twamm, setup, positions) = set_up_twamm(
            ref d,
            core,
            fee,
            initial_tick,
            amount0: 100_000_000 * 1000000000000000000,
            amount1: 100_000_000 * 1000000000000000000
        );
        let _event: PoolInitialized = pop_log(core.contract_address).unwrap();
        let _event: PositionUpdated = pop_log(core.contract_address).unwrap();

        let timestamp = SIXTEEN_POW_ONE;
        set_block_timestamp(timestamp);

        let owner = contract_address_const::<42>();

        let order1_timestamp = timestamp;
        let order1_end_time = timestamp + SIXTEEN_POW_THREE - SIXTEEN_POW_ONE;
        let amount = 10_000 * 1000000000000000000;
        let (order1_id, order1_key, _) = place_order(
            positions, owner, setup.token0, setup.token1, fee, 0, order1_end_time, amount
        );

        let (_, token1_reward_rate) = twamm.get_reward_rate(setup.pool_key.into());

        // no trades have been executed
        assert_eq!(token1_reward_rate, 0x0);

        let _event: SavedBalance = pop_log(core.contract_address).unwrap();
        let _event: OrderUpdated = pop_log(twamm.contract_address).unwrap();

        // halfway through the order duration
        let execution_timestamp = timestamp + 2040;
        set_block_timestamp(execution_timestamp);
        twamm.execute_virtual_orders(setup.pool_key.into());

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
        set_contract_address(owner);
        positions.withdraw_proceeds_from_sale(order1_id, order1_key);

        let _event: LoadedBalance = pop_log(core.contract_address).unwrap();
        let event: OrderProceedsWithdrawn = pop_log(twamm.contract_address).unwrap();

        // amount  = reward_rate * sale_rate
        //         = 4,079.5898895263671875 * 2.4509803922
        //        ~= 9,998.994827270507812499 tokens
        assert_eq!(event.amount, 0x21e0bedb4ade006d5f4);

        // withdraw the remaining proceeds after order expires

        set_block_timestamp(order1_end_time + 1);
        twamm.execute_virtual_orders(setup.pool_key.into());

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
        set_contract_address(owner);
        positions.withdraw_proceeds_from_sale(order1_id, order1_key);
        let _event: LoadedBalance = pop_log(core.contract_address).unwrap();
        let event: OrderProceedsWithdrawn = pop_log(twamm.contract_address).unwrap();
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
        let (twamm, setup, positions) = set_up_twamm(
            ref d,
            core,
            fee,
            initial_tick,
            amount0: 100_000_000 * 1000000000000000000,
            amount1: 100_000_000 * 1000000000000000000
        );
        let _event: PoolInitialized = pop_log(core.contract_address).unwrap();
        let _event: PositionUpdated = pop_log(core.contract_address).unwrap();

        let timestamp = SIXTEEN_POW_ONE;
        set_block_timestamp(timestamp);

        let owner = contract_address_const::<42>();

        let order1_timestamp = timestamp;
        let order1_end_time = timestamp + SIXTEEN_POW_THREE - SIXTEEN_POW_ONE;
        let amount = 10_000 * 1000000000000000000;
        let (order1_id, order1_key, _) = place_order(
            positions, owner, setup.token0, setup.token1, fee, 0, order1_end_time, amount
        );

        let (_, token1_reward_rate) = twamm.get_reward_rate(setup.pool_key.into());

        // no trades have been executed
        assert_eq!(token1_reward_rate, 0x0);

        let _event: SavedBalance = pop_log(core.contract_address).unwrap();
        let _event: OrderUpdated = pop_log(twamm.contract_address).unwrap();

        // halfway through the order duration
        let execution_timestamp = timestamp + 2040;
        set_block_timestamp(execution_timestamp);
        twamm.execute_virtual_orders(setup.pool_key.into());

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
        twamm.execute_virtual_orders(setup.pool_key.into());

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
        set_contract_address(owner);
        positions.withdraw_proceeds_from_sale(order1_id, order1_key);
        let _event: LoadedBalance = pop_log(core.contract_address).unwrap();
        let event: OrderProceedsWithdrawn = pop_log(twamm.contract_address).unwrap();
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
        let (twamm, setup, positions) = set_up_twamm(
            ref d,
            core,
            fee,
            initial_tick,
            amount0: 100_000_000 * 1000000000000000000,
            amount1: 100_000_000 * 1000000000000000000
        );
        let _event: PoolInitialized = pop_log(core.contract_address).unwrap();
        let _event: PositionUpdated = pop_log(core.contract_address).unwrap();

        let timestamp = SIXTEEN_POW_ONE;
        set_block_timestamp(timestamp);

        let owner = contract_address_const::<42>();

        let order1_timestamp = timestamp;
        let order1_end_time = timestamp + SIXTEEN_POW_THREE - SIXTEEN_POW_ONE;
        let amount = 10_000 * 1000000000000000000;
        let (order1_id, order1_key, _) = place_order(
            positions, owner, setup.token1, setup.token0, fee, 0, order1_end_time, amount
        );

        let (token0_reward_rate, _) = twamm.get_reward_rate(setup.pool_key.into());

        // no trades have been executed
        assert_eq!(token0_reward_rate, 0x0);

        let _event: SavedBalance = pop_log(core.contract_address).unwrap();
        let _event: OrderUpdated = pop_log(twamm.contract_address).unwrap();

        // halfway through the order duration
        let execution_timestamp = timestamp + 2040;
        set_block_timestamp(execution_timestamp);
        twamm.execute_virtual_orders(setup.pool_key.into());

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
        set_contract_address(owner);
        positions.withdraw_proceeds_from_sale(order1_id, order1_key);
        let _event: LoadedBalance = pop_log(core.contract_address).unwrap();
        let event: OrderProceedsWithdrawn = pop_log(twamm.contract_address).unwrap();

        // amount  = reward_rate * sale_rate
        //         = 1,019.9495391845703125 * 2.4509803922
        //        ~= 2,499.87632153080958946 tokens
        assert_eq!(event.amount, 0x8784c0cfc7fd74bc3b);

        // withdraw the remaining proceeds after order expires

        set_block_timestamp(order1_end_time + 1);
        twamm.execute_virtual_orders(setup.pool_key.into());

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
        set_contract_address(owner);
        positions.withdraw_proceeds_from_sale(order1_id, order1_key);
        let _event: LoadedBalance = pop_log(core.contract_address).unwrap();
        let event: OrderProceedsWithdrawn = pop_log(twamm.contract_address).unwrap();
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
        let (twamm, setup, positions) = set_up_twamm(
            ref d,
            core,
            fee,
            initial_tick,
            amount0: 100_000_000 * 1000000000000000000,
            amount1: 100_000_000 * 1000000000000000000
        );
        let _event: PoolInitialized = pop_log(core.contract_address).unwrap();
        let _event: PositionUpdated = pop_log(core.contract_address).unwrap();

        let timestamp = SIXTEEN_POW_ONE;
        set_block_timestamp(timestamp);

        let owner = contract_address_const::<42>();

        let order1_timestamp = timestamp;
        let order1_end_time = timestamp + SIXTEEN_POW_THREE - SIXTEEN_POW_ONE;
        let amount = 10_000 * 1000000000000000000;
        let (order1_id, order1_key, _) = place_order(
            positions, owner, setup.token1, setup.token0, fee, 0, order1_end_time, amount
        );

        let (token0_reward_rate, _) = twamm.get_reward_rate(setup.pool_key.into());

        // no trades have been executed
        assert_eq!(token0_reward_rate, 0x0);

        let _event: SavedBalance = pop_log(core.contract_address).unwrap();
        let _event: OrderUpdated = pop_log(twamm.contract_address).unwrap();

        // halfway through the order duration
        let execution_timestamp = timestamp + 2040;
        set_block_timestamp(execution_timestamp);
        twamm.execute_virtual_orders(setup.pool_key.into());

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
        twamm.execute_virtual_orders(setup.pool_key.into());
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
        set_contract_address(owner);
        positions.withdraw_proceeds_from_sale(order1_id, order1_key);
        let _event: LoadedBalance = pop_log(core.contract_address).unwrap();
        let event: OrderProceedsWithdrawn = pop_log(twamm.contract_address).unwrap();
        // amount  = reward_rate * sale_rate
        //         = 2,039.797088623046875 * 2.4509803922
        //        ~= 4,999.5026682817 tokens
        assert_eq!(event.amount, 0x10f060993de84c7b224);
    }
}

mod PlaceOrderOnBothSides {
    use super::{
        Deployer, DeployerTrait, ICoreDispatcher, ICoreDispatcherTrait, PoolKey, MAX_TICK_SPACING,
        ITWAMMDispatcher, ITWAMMDispatcherTrait, OrderKey, get_block_timestamp, set_block_timestamp,
        pop_log, IMockERC20Dispatcher, IMockERC20DispatcherTrait, contract_address_const,
        set_contract_address, max_bounds, update_position, max_liquidity, Bounds,
        tick_to_sqrt_ratio, i129, TICKS_IN_ONE_PERCENT, IPositionsDispatcher,
        IPositionsDispatcherTrait, get_contract_address, IExtensionDispatcher, SetupPoolResult,
        SIXTEEN_POW_ZERO, SIXTEEN_POW_ONE, SIXTEEN_POW_TWO, SIXTEEN_POW_THREE, SIXTEEN_POW_FOUR,
        SIXTEEN_POW_FIVE, SIXTEEN_POW_SIX, SIXTEEN_POW_SEVEN, OrderUpdated, VirtualOrdersExecuted,
        OrderInfo, set_up_twamm, place_order, OrderProceedsWithdrawn, PoolInitialized,
        PositionUpdated, SavedBalance, Swapped, LoadedBalance, PoolKeyIntoStateKey
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
        let (twamm, setup, positions) = set_up_twamm(
            ref d,
            core,
            fee,
            initial_tick,
            amount0: 100_000_000 * 1000000000000000000,
            amount1: 100_000_000 * 1000000000000000000
        );
        let _event: PoolInitialized = pop_log(core.contract_address).unwrap();
        let _event: PositionUpdated = pop_log(core.contract_address).unwrap();

        let timestamp = SIXTEEN_POW_ONE;
        set_block_timestamp(timestamp);

        let order_end_time = timestamp + SIXTEEN_POW_THREE - SIXTEEN_POW_ONE;

        let amount = 10_000 * 1000000000000000000;
        let (order1_id, order1_key, _) = place_order(
            positions,
            get_contract_address(),
            setup.token0,
            setup.token1,
            fee,
            0,
            order_end_time,
            amount
        );
        let _event: SavedBalance = pop_log(core.contract_address).unwrap();
        let _event: OrderUpdated = pop_log(twamm.contract_address).unwrap();

        let (order2_id, order2_key, _) = place_order(
            positions,
            get_contract_address(),
            setup.token1,
            setup.token0,
            fee,
            0,
            order_end_time,
            amount
        );
        let _event: SavedBalance = pop_log(core.contract_address).unwrap();
        let _event: OrderUpdated = pop_log(twamm.contract_address).unwrap();

        let (token0_reward_rate, token1_reward_rate) = twamm.get_reward_rate(setup.pool_key.into());

        // no trades have been executed
        assert_eq!(token0_reward_rate, 0x0);
        assert_eq!(token1_reward_rate, 0x0);

        // halfway through the order duration
        let execution_timestamp = timestamp + 2040;
        set_block_timestamp(execution_timestamp);
        twamm.execute_virtual_orders(setup.pool_key.into());
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
        positions.withdraw_proceeds_from_sale(order1_id, order1_key);
        let _event: LoadedBalance = pop_log(core.contract_address).unwrap();
        let event: OrderProceedsWithdrawn = pop_log(twamm.contract_address).unwrap();

        // amount  = reward_rate * sale_rate
        //         = 4,079.7938665465 * 2.4509803922
        //        ~= 9,999.4947711233 tokens
        assert_eq!(event.amount, 0x21e12dddabe1d857b76);

        // Withdraw proceeds for order2
        positions.withdraw_proceeds_from_sale(order2_id, order2_key);
        let _event: LoadedBalance = pop_log(core.contract_address).unwrap();
        let event: OrderProceedsWithdrawn = pop_log(twamm.contract_address).unwrap();

        // amount  = reward_rate * sale_rate
        //         = 1,020.05153678114 * 2.4509803922
        //        ~= 2,500.1263156841 tokens
        assert_eq!(event.amount, 2500126315684053116206);

        // withdraw the remaining proceeds after order expires

        set_block_timestamp(order_end_time + 1);
        twamm.execute_virtual_orders(setup.pool_key.into());
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
        positions.withdraw_proceeds_from_sale(order1_id, order1_key);
        let _event: LoadedBalance = pop_log(core.contract_address).unwrap();
        let event: OrderProceedsWithdrawn = pop_log(twamm.contract_address).unwrap();

        // amount  = reward_rate * sale_rate
        //         = 4,079.3859691724 * 2.4509803922
        //        ~= 9,998.4950226573 tokens
        assert_eq!(event.amount, 9998495022657373310747);

        // Withdraw proceeds for order2
        positions.withdraw_proceeds_from_sale(order2_id, order2_key);
        let _event: LoadedBalance = pop_log(core.contract_address).unwrap();
        let event: OrderProceedsWithdrawn = pop_log(twamm.contract_address).unwrap();

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
        let (twamm, setup, positions) = set_up_twamm(
            ref d,
            core,
            fee,
            initial_tick,
            amount0: 100_000_000 * 1000000000000000000,
            amount1: 100_000_000 * 1000000000000000000
        );
        let _event: PoolInitialized = pop_log(core.contract_address).unwrap();
        let _event: PositionUpdated = pop_log(core.contract_address).unwrap();

        let owner0 = get_contract_address();
        let owner1 = contract_address_const::<32>();

        let timestamp = SIXTEEN_POW_ONE;
        set_block_timestamp(timestamp);

        let order_end_time = timestamp + SIXTEEN_POW_THREE - SIXTEEN_POW_ONE;

        let amount = 5_000 * 1000000000000000000;
        let (order1_id, order1_key, _) = place_order(
            positions, owner0, setup.token0, setup.token1, fee, 0, order_end_time, amount
        );
        let _event: OrderUpdated = pop_log(twamm.contract_address).unwrap();
        let _event: SavedBalance = pop_log(core.contract_address).unwrap();

        let (order2_id, order2_key, _) = place_order(
            positions, owner1, setup.token0, setup.token1, fee, 0, order_end_time, amount
        );
        let _event: OrderUpdated = pop_log(twamm.contract_address).unwrap();
        let _event: SavedBalance = pop_log(core.contract_address).unwrap();

        let (order3_id, order3_key, _) = place_order(
            positions, owner0, setup.token1, setup.token0, fee, 0, order_end_time, amount
        );
        let _event: OrderUpdated = pop_log(twamm.contract_address).unwrap();
        let _event: SavedBalance = pop_log(core.contract_address).unwrap();

        let (order4_id, order4_key, _) = place_order(
            positions, owner1, setup.token1, setup.token0, fee, 0, order_end_time, amount
        );
        let _event: OrderUpdated = pop_log(twamm.contract_address).unwrap();
        let _event: SavedBalance = pop_log(core.contract_address).unwrap();

        let (token0_reward_rate, token1_reward_rate) = twamm.get_reward_rate(setup.pool_key.into());

        // no trades have been executed
        assert_eq!(token0_reward_rate, 0x0);
        assert_eq!(token1_reward_rate, 0x0);

        // halfway through the order duration
        let execution_timestamp = timestamp + 2040;
        set_block_timestamp(execution_timestamp);
        twamm.execute_virtual_orders(setup.pool_key.into());
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
        twamm.execute_virtual_orders(setup.pool_key.into());
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
        set_contract_address(owner0);
        positions.withdraw_proceeds_from_sale(order1_id, order1_key);
        let _event: LoadedBalance = pop_log(core.contract_address).unwrap();
        let event: OrderProceedsWithdrawn = pop_log(twamm.contract_address).unwrap();

        // amount  = reward_rate * sale_rate
        //         = (4,079.7938666656 + 4,079.3859692915) * 1.225490196
        //        ~= 9,998.9948963663 tokens
        assert_eq!(event.amount, 9998994896890279986505);

        // Withdraw proceeds for order2
        set_contract_address(owner1);
        positions.withdraw_proceeds_from_sale(order2_id, order2_key);
        let _event: LoadedBalance = pop_log(core.contract_address).unwrap();
        let event: OrderProceedsWithdrawn = pop_log(twamm.contract_address).unwrap();

        // amount  = reward_rate * sale_rate
        //         = (4,079.7938666656 + 4,079.3859692915) * 1.225490196
        //        ~= 9,998.9948963663 tokens
        assert_eq!(event.amount, 9998994896890279986505);

        // Withdraw proceeds for order3
        set_contract_address(owner0);
        positions.withdraw_proceeds_from_sale(order3_id, order3_key);
        let _event: LoadedBalance = pop_log(core.contract_address).unwrap();
        let event: OrderProceedsWithdrawn = pop_log(twamm.contract_address).unwrap();

        // amount  = reward_rate * sale_rate
        //         = (1,020.05153677543 + 1,020.1535316211) * 1.225490196
        //        ~= 2,500.2513091495 tokens
        assert_eq!(event.amount, 2500251309367429097068);

        // Withdraw proceeds for order4
        set_contract_address(owner1);
        positions.withdraw_proceeds_from_sale(order4_id, order4_key);
        let _event: LoadedBalance = pop_log(core.contract_address).unwrap();
        let event: OrderProceedsWithdrawn = pop_log(twamm.contract_address).unwrap();

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
        let (twamm, setup, positions) = set_up_twamm(
            ref d,
            core,
            fee,
            initial_tick,
            amount0: 2 * 1000000000000000000,
            amount1: 100_000_000 * 1000000000000000000
        );
        let _event: PoolInitialized = pop_log(core.contract_address).unwrap();
        let _event: PositionUpdated = pop_log(core.contract_address).unwrap();

        let timestamp = SIXTEEN_POW_ONE;
        set_block_timestamp(timestamp);

        let order_end_time = timestamp + SIXTEEN_POW_THREE - SIXTEEN_POW_ONE;

        let amount = 1 * 1000000000000000000;
        let (order1_id, order1_key, _) = place_order(
            positions,
            get_contract_address(),
            setup.token0,
            setup.token1,
            fee,
            0,
            order_end_time,
            amount
        );
        let _event: SavedBalance = pop_log(core.contract_address).unwrap();
        let _event: OrderUpdated = pop_log(twamm.contract_address).unwrap();

        let amount = 1_000_000 * 1000000000000000000;
        let (order2_id, order2_key, _) = place_order(
            positions,
            get_contract_address(),
            setup.token1,
            setup.token0,
            fee,
            0,
            order_end_time,
            amount
        );
        let _event: SavedBalance = pop_log(core.contract_address).unwrap();
        let _event: OrderUpdated = pop_log(twamm.contract_address).unwrap();

        // halfway through the order duration
        let execution_timestamp = timestamp + 2040;
        set_block_timestamp(execution_timestamp);
        twamm.execute_virtual_orders(setup.pool_key.into());
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
        positions.withdraw_proceeds_from_sale(order1_id, order1_key);
        let _event: LoadedBalance = pop_log(core.contract_address).unwrap();
        let event: OrderProceedsWithdrawn = pop_log(twamm.contract_address).unwrap();

        // amount  = reward_rate * sale_rate
        //         = 136,604,803,053.9637769619 * 0.0002450980392
        //        ~= 33,481,569.3738286935 tokens
        assert_eq!(event.amount, 33481569373828693521176460);

        // Withdraw proceeds for order2
        positions.withdraw_proceeds_from_sale(order2_id, order2_key);
        let _event: LoadedBalance = pop_log(core.contract_address).unwrap();
        let event: OrderProceedsWithdrawn = pop_log(twamm.contract_address).unwrap();

        // amount  = reward_rate * sale_rate
        //         = 0.00003211249111 * 245.09803921569
        //        ~= 0.007870708605 tokens
        assert_eq!(event.amount, 7870708605177580);

        // withdraw the remaining proceeds after order expires

        set_block_timestamp(order_end_time + 1);
        twamm.execute_virtual_orders(setup.pool_key.into());
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
        positions.withdraw_proceeds_from_sale(order1_id, order1_key);
        let _event: LoadedBalance = pop_log(core.contract_address).unwrap();
        let event: OrderProceedsWithdrawn = pop_log(twamm.contract_address).unwrap();

        // amount  = reward_rate * sale_rate
        //         = 69,098,871,754.301092936 * 0.0002450980392
        //        ~= 16,935,997.977911462 tokens
        assert_eq!(event.amount, 16935997977911462045022651);

        // Withdraw proceeds for order2
        positions.withdraw_proceeds_from_sale(order2_id, order2_key);
        let _event: LoadedBalance = pop_log(core.contract_address).unwrap();
        let event: OrderProceedsWithdrawn = pop_log(twamm.contract_address).unwrap();

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
        let amount0 = 10_000_000 * 1000000000000000000;
        let amount1 = 10_000_000 * 1000000000000000000;
        let (twamm, setup, positions) = set_up_twamm(
            ref d, core, fee, initial_tick, amount0, amount1
        );
        let _event: PoolInitialized = pop_log(core.contract_address).unwrap();
        let _event: PositionUpdated = pop_log(core.contract_address).unwrap();

        let timestamp = SIXTEEN_POW_ONE;
        set_block_timestamp(timestamp);

        let order_end_time = timestamp + SIXTEEN_POW_THREE - SIXTEEN_POW_ONE;
        let order2_end_time = order_end_time - SIXTEEN_POW_TWO;

        let amount = 10_000 * 1000000000000000000;
        let (order1_id, order1_key, _) = place_order(
            positions,
            get_contract_address(),
            setup.token0,
            setup.token1,
            fee,
            0,
            order_end_time,
            amount
        );
        let _event: SavedBalance = pop_log(core.contract_address).unwrap();
        let _event: OrderUpdated = pop_log(twamm.contract_address).unwrap();

        let amount = 10_000 * 1000000000000000000;
        let (order2_id, order2_key, _) = place_order(
            positions,
            get_contract_address(),
            setup.token1,
            setup.token0,
            fee,
            0,
            order2_end_time,
            amount
        );
        let _event: SavedBalance = pop_log(core.contract_address).unwrap();
        let _event: OrderUpdated = pop_log(twamm.contract_address).unwrap();

        // // halfway through the first order duration
        let execution_timestamp = timestamp + 2040;
        set_block_timestamp(execution_timestamp);
        twamm.execute_virtual_orders(setup.pool_key.into());
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
        twamm.execute_virtual_orders(setup.pool_key.into());

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
        positions.withdraw_proceeds_from_sale(order1_id, order1_key);
        let _event: LoadedBalance = pop_log(core.contract_address).unwrap();
        let event: OrderProceedsWithdrawn = pop_log(twamm.contract_address).unwrap();

        // amount  = reward_rate * sale_rate
        //         = (1,020.5777188761 + 893.4527958553 + 128.2638352305) * 2.4509803922
        //        ~= 5,005.6234068575 tokens
        assert_eq!(event.amount, 5005623406881568362072);

        // Withdraw proceeds for order2
        positions.withdraw_proceeds_from_sale(order2_id, order2_key);
        let _event: LoadedBalance = pop_log(core.contract_address).unwrap();
        let event: OrderProceedsWithdrawn = pop_log(twamm.contract_address).unwrap();

        // amount  = reward_rate * sale_rate
        //         = (4,077.6908687753 + 3,562.1985563629) * 2.6150627615
        //        ~= 19,978.790293548 tokens
        assert_eq!(event.amount, 19978790337491429985327);
    }
}

mod PlaceOrderDurationTooLong {
    use super::{
        Deployer, DeployerTrait, i129, set_up_twamm, pop_log, PoolInitialized, PositionUpdated,
        SIXTEEN_POW_ONE, set_block_timestamp, place_order, get_contract_address, constants,
        OrderKey, ITWAMMDispatcher, ITWAMMDispatcherTrait
    };

    #[test]
    #[should_panic(expected: ('DURATION_EXCEEDS_MAX_U32', 'ENTRYPOINT_FAILED'))]
    fn test_order_duration_too_long_positions() {
        let mut d: Deployer = Default::default();
        let core = d.deploy_core();
        let _event: ekubo::components::owned::Owned::OwnershipTransferred = pop_log(
            core.contract_address
        )
            .unwrap();
        let fee = 0;
        let initial_tick = i129 { mag: 693148, sign: true }; // ~ 0.5:1 price
        let amount0 = 10_000_000 * 1000000000000000000;
        let amount1 = 10_000_000 * 1000000000000000000;
        let (_, setup, positions) = set_up_twamm(ref d, core, fee, initial_tick, amount0, amount1);
        let _event: PoolInitialized = pop_log(core.contract_address).unwrap();
        let _event: PositionUpdated = pop_log(core.contract_address).unwrap();

        let timestamp = SIXTEEN_POW_ONE;
        set_block_timestamp(timestamp);

        place_order(
            positions,
            get_contract_address(),
            setup.token0,
            setup.token1,
            fee,
            timestamp,
            0x100000000 + timestamp,
            1
        );
    }

    #[test]
    #[should_panic(
        expected: (
            'DURATION_EXCEEDS_MAX_U32',
            'ENTRYPOINT_FAILED',
            'ENTRYPOINT_FAILED',
            'ENTRYPOINT_FAILED'
        )
    )]
    fn test_order_duration_too_long_twamm() {
        let mut d: Deployer = Default::default();
        let core = d.deploy_core();
        let _event: ekubo::components::owned::Owned::OwnershipTransferred = pop_log(
            core.contract_address
        )
            .unwrap();
        let fee = 0;
        let initial_tick = i129 { mag: 693148, sign: true }; // ~ 0.5:1 price
        let amount0 = 10_000_000 * 1000000000000000000;
        let amount1 = 10_000_000 * 1000000000000000000;
        let (twamm, setup, _) = set_up_twamm(ref d, core, fee, initial_tick, amount0, amount1);
        let _event: PoolInitialized = pop_log(core.contract_address).unwrap();
        let _event: PositionUpdated = pop_log(core.contract_address).unwrap();

        let timestamp = SIXTEEN_POW_ONE;
        set_block_timestamp(timestamp);

        let order_key = OrderKey {
            sell_token: setup.token0.contract_address,
            buy_token: setup.token1.contract_address,
            fee,
            start_time: timestamp,
            end_time: 0x100000000 + timestamp // 2**32
        };

        twamm.update_order(0, order_key, i129 { mag: 1, sign: false });
    }
}

fn set_up_twamm(
    ref d: Deployer,
    core: ICoreDispatcher,
    fee: u128,
    initial_tick: i129,
    amount0: u128,
    amount1: u128
) -> (ITWAMMDispatcher, SetupPoolResult, IPositionsDispatcher) {
    set_block_timestamp(1);

    let twamm = d.deploy_twamm(core);
    let _event: ekubo::components::owned::Owned::OwnershipTransferred = pop_log(
        twamm.contract_address
    )
        .unwrap();

    let setup = d
        .setup_pool_with_core(
            core,
            fee: fee,
            tick_spacing: MAX_TICK_SPACING,
            initial_tick: initial_tick,
            extension: twamm.contract_address,
        );
    let positions = d.deploy_positions(setup.core);
    set_contract_address(default_owner());
    positions.set_twamm(twamm.contract_address);

    let liquidity_provider = contract_address_const::<42>();
    set_contract_address(liquidity_provider);

    let bounds = max_bounds(MAX_TICK_SPACING);
    let max_liquidity = max_liquidity(
        tick_to_sqrt_ratio(initial_tick),
        tick_to_sqrt_ratio(bounds.lower),
        tick_to_sqrt_ratio(bounds.upper),
        amount0,
        amount1,
    );

    setup.token0.increase_balance(positions.contract_address, amount0);
    setup.token1.increase_balance(positions.contract_address, amount1);
    positions
        .mint_and_deposit_and_clear_both(
            pool_key: setup.pool_key, bounds: bounds, min_liquidity: max_liquidity
        );

    (
        ITWAMMDispatcher { contract_address: twamm.contract_address },
        setup,
        IPositionsDispatcher { contract_address: positions.contract_address }
    )
}

fn place_order(
    positions: IPositionsDispatcher,
    owner: ContractAddress,
    sell_token: IMockERC20Dispatcher,
    buy_token: IMockERC20Dispatcher,
    fee: u128,
    start_time: u64,
    end_time: u64,
    amount: u128
) -> (u64, OrderKey, OrderInfo) {
    // place order
    let twamm = positions.get_twamm_address();

    sell_token.increase_balance(positions.contract_address, amount);

    let current_contract_address = get_contract_address();

    let order_key = OrderKey {
        sell_token: sell_token.contract_address,
        buy_token: buy_token.contract_address,
        fee,
        start_time,
        end_time
    };

    let (id, _) = if (owner != current_contract_address) {
        set_contract_address(owner);
        let (id, sale_rate) = positions.mint_and_increase_sell_amount(order_key, amount);
        set_contract_address(current_contract_address);
        (id, sale_rate)
    } else {
        positions.mint_and_increase_sell_amount(order_key, amount)
    };

    // return token id, order key, and order state
    (
        id,
        order_key,
        ITWAMMDispatcher { contract_address: twamm }
            .get_order_info(positions.contract_address, id.into(), order_key)
    )
}
