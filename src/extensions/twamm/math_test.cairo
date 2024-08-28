use ekubo::extensions::twamm::math::{
    calculate_sale_rate, calculate_reward_amount, calculate_c, constants, calculate_next_sqrt_ratio,
    calculate_amount_from_sale_rate, time::{to_duration}
};
use ekubo::math::ticks::constants::{MAX_TICK_SPACING};
use ekubo::math::ticks::{tick_to_sqrt_ratio};
use ekubo::types::bounds::{max_bounds};
use ekubo::types::i129::{i129};


const SIXTEEN_POW_ZERO: u64 = 0x1;
const SIXTEEN_POW_ONE: u64 = 0x10;
const SIXTEEN_POW_TWO: u64 = 0x100;
const SIXTEEN_POW_THREE: u64 = 0x1000;
const SIXTEEN_POW_FOUR: u64 = 0x10000;
const SIXTEEN_POW_FIVE: u64 = 0x100000;
const SIXTEEN_POW_SIX: u64 = 0x1000000;
const SIXTEEN_POW_SEVEN: u64 = 0x10000000;
const SIXTEEN_POW_EIGHT: u64 = 0x100000000; // 2**32


mod SaleRateTest {
    use super::{
        calculate_sale_rate, calculate_amount_from_sale_rate, SIXTEEN_POW_ONE, SIXTEEN_POW_TWO,
        SIXTEEN_POW_THREE, SIXTEEN_POW_FOUR, SIXTEEN_POW_FIVE, SIXTEEN_POW_SIX, SIXTEEN_POW_SEVEN,
        SIXTEEN_POW_EIGHT, constants, to_duration
    };

    #[test]
    fn test_sale_rates_smallest_amount() {
        assert_eq!(
            calculate_sale_rate(amount: 1, duration: to_duration(start: 0, end: SIXTEEN_POW_ONE)),
            0x10000000
        );
        assert_eq!(
            calculate_sale_rate(amount: 1, duration: to_duration(start: 0, end: SIXTEEN_POW_TWO)),
            0x1000000
        );
        assert_eq!(
            calculate_sale_rate(amount: 1, duration: to_duration(start: 0, end: SIXTEEN_POW_THREE)),
            0x100000
        );
        assert_eq!(
            calculate_sale_rate(amount: 1, duration: to_duration(start: 0, end: SIXTEEN_POW_FOUR)),
            0x10000
        );
        assert_eq!(
            calculate_sale_rate(amount: 1, duration: to_duration(start: 0, end: SIXTEEN_POW_FIVE)),
            0x1000
        );
        assert_eq!(
            calculate_sale_rate(amount: 1, duration: to_duration(start: 0, end: SIXTEEN_POW_SIX)),
            0x100
        );
        assert_eq!(
            calculate_sale_rate(amount: 1, duration: to_duration(start: 0, end: SIXTEEN_POW_SEVEN)),
            0x10
        );
        assert_eq!(
            calculate_sale_rate(
                amount: 1, duration: to_duration(start: 0, end: SIXTEEN_POW_EIGHT - 1)
            ),
            0x1
        );
    }

    #[test]
    #[should_panic(expected: ('SALE_RATE_OVERFLOW',))]
    fn test_sale_rates_overflow() {
        calculate_sale_rate(amount: 0xffffffffffffffffffffffffffffffff, duration: 0xffffffff);
    }

    #[test]
    fn test_calculate_amount_from_sale_rate() {
        assert_eq!(calculate_amount_from_sale_rate(0, 100, false), 0);
        assert_eq!(calculate_amount_from_sale_rate(1 * constants::X32_u128, 100, false), 100);
        assert_eq!(calculate_amount_from_sale_rate(2 * constants::X32_u128, 100, false), 200);

        assert_eq!(calculate_amount_from_sale_rate(0, 100, true), 0);
        assert_eq!(calculate_amount_from_sale_rate(1 * constants::X32_u128, 100, true), 100);
        assert_eq!(calculate_amount_from_sale_rate(2 * constants::X32_u128, 100, true), 200);

        // 0.5 sale rate
        assert_eq!(calculate_amount_from_sale_rate(2147483648, 3, false), 1);
        assert_eq!(calculate_amount_from_sale_rate(2147483648, 3, true), 2);
    }

    #[test]
    fn test_place_order_sale_rate() {
        run_place_order_and_validate_sale_rate(
            amount: 100_000_000,
            start_time: 0,
            end_time: SIXTEEN_POW_ONE,
            expected_sale_rate: 0x5f5e1000000000 // 6,250,000 * 2**32
        );
        run_place_order_and_validate_sale_rate(
            amount: 100_000_000,
            start_time: 0,
            end_time: SIXTEEN_POW_TWO,
            expected_sale_rate: 0x5f5e100000000 // ~ 390,625 * 2**32
        );
        run_place_order_and_validate_sale_rate(
            amount: 100_000_000,
            start_time: 0,
            end_time: SIXTEEN_POW_THREE,
            // scaled by 2**32
            expected_sale_rate: 0x5f5e10000000 // ~ 24,414.0625 * 2**32
        );
        run_place_order_and_validate_sale_rate(
            amount: 100_000_000,
            start_time: 0,
            end_time: SIXTEEN_POW_FOUR,
            // scaled by 2**32
            expected_sale_rate: 0x5f5e1000000 // ~ 1,525.87890625 * 2**32
        );
        run_place_order_and_validate_sale_rate(
            amount: 100_000_000,
            start_time: 0,
            end_time: SIXTEEN_POW_FIVE,
            // scaled by 2**32
            expected_sale_rate: 0x5f5e100000 // ~ 95.3674316406 * 2**32
        );
        run_place_order_and_validate_sale_rate(
            amount: 100_000_000,
            start_time: 0,
            end_time: SIXTEEN_POW_SIX,
            // scaled by 2**32
            expected_sale_rate: 0x5f5e10000 // ~ 5.9604644775 * 2**32
        );
    }

    fn run_place_order_and_validate_sale_rate(
        amount: u128, start_time: u64, end_time: u64, expected_sale_rate: u128
    ) {
        assert_eq!(
            calculate_sale_rate(amount, duration: to_duration(start: start_time, end: end_time)),
            expected_sale_rate
        );
    }
}

mod RewardRateTest {
    use super::{calculate_reward_amount, SIXTEEN_POW_EIGHT};

    #[test]
    fn test_largest_reward_amount_no_overflow() {
        // 2**256 - 2**128
        let reward_rate = 0xffffffffffffffffffffffffffffffff000000000000000000000000;
        // only way to get largest reward amount is with the smallest sale rate
        let sale_rate = SIXTEEN_POW_EIGHT.into();
        // 2**128 - 1
        let expected_amount = 0xffffffffffffffffffffffffffffffff;

        let amount = calculate_reward_amount(reward_rate: reward_rate, sale_rate: sale_rate);

        assert_eq!(expected_amount, amount);
    }
}

mod TWAMMMathTest {
    use ekubo::math::delta::{amount0_delta, amount1_delta};

    use ekubo::math::muldiv::{muldiv};
    use super::{calculate_c, constants, calculate_next_sqrt_ratio};


    fn assert_case_c(sqrt_ratio: u256, sqrt_sell_ratio: u256, expected: (u256, bool)) {
        let (val, sign) = calculate_c(sqrt_ratio, sqrt_sell_ratio, false);
        let (expected_val, expected_sign) = expected;

        assert_eq!(val, expected_val);
        assert_eq!(sign, expected_sign);
    }

    #[test]
    fn test_zero_c() {
        assert_case_c(sqrt_ratio: 0, sqrt_sell_ratio: 0, expected: (0, false));
        assert_case_c(sqrt_ratio: 1, sqrt_sell_ratio: 1, expected: (0, false));
        assert_case_c(sqrt_ratio: 0, sqrt_sell_ratio: 1, expected: (constants::X128, false));
    }

    #[test]
    fn test_c_min_values() {
        assert_case_c(sqrt_ratio: 0, sqrt_sell_ratio: 0, expected: (0, false));
        assert_case_c(
            sqrt_ratio: 0, sqrt_sell_ratio: 1, expected: (u256 { low: 0, high: 0x1 }, false)
        );
        assert_case_c(
            sqrt_ratio: 1, sqrt_sell_ratio: 0, expected: (u256 { low: 0, high: 0x1 }, true)
        );
        assert_case_c(sqrt_ratio: 1, sqrt_sell_ratio: 1, expected: (0, false));
    }

    #[test]
    fn test_production_issue() {
        let sqrt_ratio = 286363514177267035440548892163466107483369185;
        let liquidity = 130385243018985227;
        let token0_sale_rate = 1917585044284;
        let token1_sale_rate = 893194653345642013054241177;
        let fee = 0xccccccccccccccccccccccccccccccc;
        let time_elapsed = 360;
        let two_pow_32 = 0x100000000;

        let sqrt_ratio_next = calculate_next_sqrt_ratio(
            sqrt_ratio: sqrt_ratio,
            liquidity: liquidity,
            token0_sale_rate: token0_sale_rate,
            token1_sale_rate: token1_sale_rate,
            time_elapsed: time_elapsed,
            fee: fee,
        );
        assert_gt!(sqrt_ratio_next, 286363514177267035440548892163466107483369185);

        let token0_sold_amount = muldiv(
            token0_sale_rate.into(), time_elapsed.into(), two_pow_32, false
        )
            .unwrap();
        let token1_sold_amount = muldiv(
            token1_sale_rate.into(), time_elapsed.into(), two_pow_32, false
        )
            .unwrap();

        assert_eq!(
            (
                token0_sold_amount,
                token1_sold_amount,
                amount0_delta(sqrt_ratio_next, sqrt_ratio, liquidity, false).into(),
                amount1_delta(sqrt_ratio_next, sqrt_ratio, liquidity, false).into(),
            ),
            // 0.16073 USDC for 74866710976797883561 - (71015167668577728143/0.95) =
            // 0.113902904610801 EKUBO price ~= 1.411114146291565 USDC/EKUBO
            // other side gets 100371327 USDC for 74866710976797883561 EKUBO, for a price of
            // approximately 1.3406669759
            (160730, 74866710976797883561, 100210597, 71015167668577728143)
        );
    }

    #[test]
    fn test_c_max_values() {
        // max sqrt ratio is 2**192
        let max_sqrt_ratio = 0x1000000000000000000000000000000000000000000000000_u256;
        // max sqrt sell ratio is 2**128
        let max_sqrt_sell_ratio = 0xffffffffffffffffffffffffffffffff_u256;

        assert_case_c(
            sqrt_ratio: max_sqrt_ratio,
            sqrt_sell_ratio: max_sqrt_sell_ratio,
            expected: (u256 { low: 0xfffffffffffffffe0000000000000001, high: 0 }, true)
        );
    }

    #[test]
    fn test_c_range() {
        // positive
        assert_case_c(
            sqrt_ratio: 10,
            sqrt_sell_ratio: 15,
            expected: (u256 { low: 0x33333333333333333333333333333333, high: 0 }, false)
        );
        assert_case_c(
            sqrt_ratio: 10,
            sqrt_sell_ratio: 20,
            expected: (u256 { low: 0x55555555555555555555555555555555, high: 0 }, false)
        );
        assert_case_c(
            sqrt_ratio: 10,
            sqrt_sell_ratio: 30,
            expected: (u256 { low: 0x80000000000000000000000000000000, high: 0 }, false)
        );
        assert_case_c(
            sqrt_ratio: 10,
            sqrt_sell_ratio: 40,
            expected: (u256 { low: 0x99999999999999999999999999999999, high: 0 }, false)
        );
        assert_case_c(
            sqrt_ratio: 10,
            sqrt_sell_ratio: 50,
            expected: (u256 { low: 0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa, high: 0 }, false)
        );
        assert_case_c(
            sqrt_ratio: 10,
            sqrt_sell_ratio: 60,
            expected: (u256 { low: 0xb6db6db6db6db6db6db6db6db6db6db6, high: 0 }, false)
        );
        assert_case_c(
            sqrt_ratio: 10,
            sqrt_sell_ratio: 90,
            expected: (u256 { low: 0xcccccccccccccccccccccccccccccccc, high: 0 }, false)
        );
        assert_case_c(
            sqrt_ratio: 10,
            sqrt_sell_ratio: 150,
            expected: (u256 { low: 0xe0000000000000000000000000000000, high: 0 }, false)
        );
        assert_case_c(
            sqrt_ratio: 10,
            sqrt_sell_ratio: 190,
            expected: (u256 { low: 0xe6666666666666666666666666666666, high: 0 }, false)
        );
        // negative
        assert_case_c(
            sqrt_ratio: 15,
            sqrt_sell_ratio: 10,
            expected: (u256 { low: 0x33333333333333333333333333333333, high: 0 }, true)
        );
        assert_case_c(
            sqrt_ratio: 20,
            sqrt_sell_ratio: 10,
            expected: (u256 { low: 0x55555555555555555555555555555555, high: 0 }, true)
        );
        assert_case_c(
            sqrt_ratio: 30,
            sqrt_sell_ratio: 10,
            expected: (u256 { low: 0x80000000000000000000000000000000, high: 0 }, true)
        );
        assert_case_c(
            sqrt_ratio: 40,
            sqrt_sell_ratio: 10,
            expected: (u256 { low: 0x99999999999999999999999999999999, high: 0 }, true)
        );
        assert_case_c(
            sqrt_ratio: 50,
            sqrt_sell_ratio: 10,
            expected: (u256 { low: 0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa, high: 0 }, true)
        );
        assert_case_c(
            sqrt_ratio: 60,
            sqrt_sell_ratio: 10,
            expected: (u256 { low: 0xb6db6db6db6db6db6db6db6db6db6db6, high: 0 }, true)
        );
        assert_case_c(
            sqrt_ratio: 90,
            sqrt_sell_ratio: 10,
            expected: (u256 { low: 0xcccccccccccccccccccccccccccccccc, high: 0 }, true)
        );
        assert_case_c(
            sqrt_ratio: 150,
            sqrt_sell_ratio: 10,
            expected: (u256 { low: 0xe0000000000000000000000000000000, high: 0 }, true)
        );
        assert_case_c(
            sqrt_ratio: 190,
            sqrt_sell_ratio: 10,
            expected: (u256 { low: 0xe6666666666666666666666666666666, high: 0 }, true)
        );
    }

    #[test]
    fn test_calculate_next_sqrt_ratio() {
        // token0_sale_rate and token1_sale_rate are always non-zero.
        // liquidity is zero, price is sqrt_sale_ratio
        let next_sqrt_ratio = calculate_next_sqrt_ratio(
            sqrt_ratio: 0x0,
            liquidity: 0x0,
            token0_sale_rate: constants::X32_u128,
            token1_sale_rate: constants::X32_u128,
            time_elapsed: 1,
            fee: 0,
        );
        // sqrt_ratio = 1
        assert_eq!(next_sqrt_ratio, constants::X128);

        // c is zero since sqrt_ratio == sqrt_sale_ratio, price is sqrt_sale_ratio
        let next_sqrt_ratio = calculate_next_sqrt_ratio(
            sqrt_ratio: constants::X128,
            liquidity: constants::X64_u128,
            token0_sale_rate: constants::X32_u128,
            token1_sale_rate: constants::X32_u128,
            time_elapsed: 1,
            fee: 0,
        );
        // sqrt_ratio = 1
        assert_eq!(next_sqrt_ratio, constants::X128);

        let next_sqrt_ratio = calculate_next_sqrt_ratio(
            sqrt_ratio: constants::X128,
            liquidity: 10_000 * 1000000000000000000,
            token0_sale_rate: 5000 * constants::X32_u128,
            token1_sale_rate: 500 * constants::X32_u128,
            time_elapsed: 1,
            fee: 0,
        );
        // sqrt_ratio ~= .99
        assert_eq!(next_sqrt_ratio, 340282366920938463305873545376503282647);

        // very low liquidity
        let next_sqrt_ratio = calculate_next_sqrt_ratio(
            sqrt_ratio: constants::X128,
            liquidity: 10,
            token0_sale_rate: 5000 * constants::X32_u128,
            token1_sale_rate: 500 * constants::X32_u128,
            time_elapsed: 1,
            fee: 0,
        );
        // sqrt_ratio will be sqrt_sale_ratio
        assert_eq!(next_sqrt_ratio, 107606732706330320687810575726449262521);
    }
}

mod MaxPrices {
    use super::{i129, constants, max_bounds, MAX_TICK_SPACING, tick_to_sqrt_ratio};

    #[test]
    fn test_max_min_tick() {
        let bounds = max_bounds(MAX_TICK_SPACING);
        assert_eq!(bounds.lower, i129 { mag: constants::MAX_USABLE_TICK_MAGNITUDE, sign: true },);
        assert_eq!(bounds.upper, i129 { mag: constants::MAX_USABLE_TICK_MAGNITUDE, sign: false },);
    }

    #[test]
    fn test_max_min_sqrt_ratio() {
        let bounds = max_bounds(MAX_TICK_SPACING);
        let (min_sqrt_ratio, max_sqrt_ratio) = (
            tick_to_sqrt_ratio(bounds.lower), tick_to_sqrt_ratio(bounds.upper)
        );

        assert_eq!(min_sqrt_ratio, constants::MAX_BOUNDS_MIN_SQRT_RATIO);
        assert_eq!(max_sqrt_ratio, constants::MAX_BOUNDS_MAX_SQRT_RATIO);
    }
}
