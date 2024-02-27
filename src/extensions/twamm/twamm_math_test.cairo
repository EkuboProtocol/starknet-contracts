use core::num::traits::{Zero};
use ekubo::extensions::twamm::math::{
    calculate_sale_rate, calculate_reward_amount, calculate_c, constants, calculate_next_sqrt_ratio,
    calculate_amount_from_sale_rate, is_time_valid, validate_time, calculate_reward_rate
};
use ekubo::math::bitmap::{Bitmap, BitmapTrait};
use ekubo::types::delta::{Delta};
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
        SIXTEEN_POW_EIGHT, constants, i129, Zero
    };


    fn assert_case_sale_rate(amount: u128, start_time: u64, end_time: u64, expected: u128) {
        let sale_rate = calculate_sale_rate(
            amount: amount, start_time: start_time, end_time: end_time
        );
        assert_eq!(sale_rate, expected);
    }

    #[test]
    fn test_sale_rates_smallest_amount() {
        assert_case_sale_rate(
            amount: 1, start_time: 0, end_time: SIXTEEN_POW_ONE, expected: 0x10000000,
        );
        assert_case_sale_rate(
            amount: 1, start_time: 0, end_time: SIXTEEN_POW_TWO, expected: 0x1000000,
        );
        assert_case_sale_rate(
            amount: 1, start_time: 0, end_time: SIXTEEN_POW_THREE, expected: 0x100000,
        );
        assert_case_sale_rate(
            amount: 1, start_time: 0, end_time: SIXTEEN_POW_FOUR, expected: 0x10000,
        );
        assert_case_sale_rate(
            amount: 1, start_time: 0, end_time: SIXTEEN_POW_FIVE, expected: 0x1000,
        );
        assert_case_sale_rate(amount: 1, start_time: 0, end_time: SIXTEEN_POW_SIX, expected: 0x100);
        assert_case_sale_rate(
            amount: 1, start_time: 0, end_time: SIXTEEN_POW_SEVEN, expected: 0x10,
        );
        assert_case_sale_rate(amount: 1, start_time: 0, end_time: SIXTEEN_POW_EIGHT, expected: 0x1);
    }

    #[test]
    #[should_panic(expected: ('SALE_RATE_ZERO',))]
    fn test_sale_rates_smallest_amount_underflow() {
        // sale window above 2**32 seconds (136.2 years) underflows to 0 sale rate.
        assert_case_sale_rate(
            amount: 1, start_time: 0, end_time: SIXTEEN_POW_EIGHT + 1, expected: 0x0
        );
    }

    #[test]
    #[should_panic(expected: ('SALE_RATE_OVERFLOW',))]
    fn test_sale_rates_overflow() {
        assert_case_sale_rate(
            // 2**128 - 1
            amount: 0xffffffffffffffffffffffffffffffff,
            // 2**32 - 1
            start_time: 0,
            end_time: 0xffffffff,
            expected: 0
        );
    }

    #[test]
    fn test_sale_rates_largest_amount() {
        assert_case_sale_rate(
            // 2**128 - 1
            amount: 0xffffffffffffffffffffffffffffffff,
            start_time: 0,
            // 2**32
            end_time: 0x1000000000,
            expected: 0xfffffffffffffffffffffffffffffff
        );
    }


    #[test]
    fn test_calculate_amount_from_sale_rate() {
        assert_eq!(calculate_amount_from_sale_rate(0, 0, 100, false), 0);
        assert_eq!(calculate_amount_from_sale_rate(1 * constants::X32_u128, 0, 100, false), 100);
        assert_eq!(calculate_amount_from_sale_rate(2 * constants::X32_u128, 0, 100, false), 200);

        assert_eq!(calculate_amount_from_sale_rate(0, 0, 100, true), 0);
        assert_eq!(calculate_amount_from_sale_rate(1 * constants::X32_u128, 0, 100, true), 100);
        assert_eq!(calculate_amount_from_sale_rate(2 * constants::X32_u128, 0, 100, true), 200);

        // 0.5 sale rate
        assert_eq!(calculate_amount_from_sale_rate(2147483648, 0, 3, false), 1);
        assert_eq!(calculate_amount_from_sale_rate(2147483648, 0, 3, true), 2);
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
        assert_eq!(calculate_sale_rate(amount, start_time, end_time), expected_sale_rate);
    }
}

mod RewardRateTest {
    use super::{Delta, calculate_reward_amount, SIXTEEN_POW_EIGHT, i129,};

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
    use super::{calculate_c, i129, constants, SIXTEEN_POW_SEVEN, calculate_next_sqrt_ratio};


    fn assert_case_c(sqrt_ratio: u256, sqrt_sell_ratio: u256, expected: (u256, bool)) {
        let (val, sign) = calculate_c(sqrt_ratio, sqrt_sell_ratio);
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
            time_elapsed: 1
        );
        // sqrt_ratio = 1
        assert_eq!(next_sqrt_ratio, constants::X128);

        // c is zero since sqrt_ratio == sqrt_sale_ratio, price is sqrt_sale_ratio
        let next_sqrt_ratio = calculate_next_sqrt_ratio(
            sqrt_ratio: constants::X128,
            liquidity: constants::X64_u128,
            token0_sale_rate: constants::X32_u128,
            token1_sale_rate: constants::X32_u128,
            time_elapsed: 1
        );
        // sqrt_ratio = 1
        assert_eq!(next_sqrt_ratio, constants::X128);

        let next_sqrt_ratio = calculate_next_sqrt_ratio(
            sqrt_ratio: constants::X128,
            liquidity: 10_000 * 1000000000000000000,
            token0_sale_rate: 5000 * constants::X32_u128,
            token1_sale_rate: 500 * constants::X32_u128,
            time_elapsed: 1
        );
        // sqrt_ratio ~= .99
        assert_eq!(next_sqrt_ratio, 340282366920938463332123722385714104100);

        // very low liquidity
        let next_sqrt_ratio = calculate_next_sqrt_ratio(
            sqrt_ratio: constants::X128,
            liquidity: 10,
            token0_sale_rate: 5000 * constants::X32_u128,
            token1_sale_rate: 500 * constants::X32_u128,
            time_elapsed: 1
        );
        // sqrt_ratio will be sqrt_sale_ratio
        assert_eq!(next_sqrt_ratio, 107606732706330320687810575726449262521);
    }
}

#[test]
fn test_is_time_valid_past_or_close_time() {
    assert_eq!(is_time_valid(now: 0, time: 16), true);
    assert_eq!(is_time_valid(now: 8, time: 16), true);
    assert_eq!(is_time_valid(now: 9, time: 16), true);
    assert_eq!(is_time_valid(now: 15, time: 16), true);
    assert_eq!(is_time_valid(now: 16, time: 16), true);
    assert_eq!(is_time_valid(now: 17, time: 16), true);
    assert_eq!(is_time_valid(now: 12345678, time: 16), true);
    assert_eq!(is_time_valid(now: 12345678, time: 32), true);
    assert_eq!(is_time_valid(now: 12345678, time: 0), true);
}

#[test]
fn test_is_time_valid_future_times_near() {
    assert_eq!(is_time_valid(now: 0, time: 16), true);
    assert_eq!(is_time_valid(now: 8, time: 16), true);
    assert_eq!(is_time_valid(now: 9, time: 16), true);
    assert_eq!(is_time_valid(now: 0, time: 32), true);
    assert_eq!(is_time_valid(now: 31, time: 32), true);

    assert_eq!(is_time_valid(now: 0, time: 256), true);
    assert_eq!(is_time_valid(now: 0, time: 240), true);
    assert_eq!(is_time_valid(now: 0, time: 272), false);
    assert_eq!(is_time_valid(now: 16, time: 256), true);
    assert_eq!(is_time_valid(now: 16, time: 240), true);
    assert_eq!(is_time_valid(now: 16, time: 272), false);

    assert_eq!(is_time_valid(now: 0, time: 512), true);
    assert_eq!(is_time_valid(now: 0, time: 496), false);
    assert_eq!(is_time_valid(now: 0, time: 528), false);
    assert_eq!(is_time_valid(now: 16, time: 512), true);
    assert_eq!(is_time_valid(now: 16, time: 496), false);
    assert_eq!(is_time_valid(now: 16, time: 528), false);
}

#[test]
fn test_is_time_valid_future_times_near_second_boundary() {
    assert_eq!(is_time_valid(now: 0, time: 4096), true);
    assert_eq!(is_time_valid(now: 0, time: 3840), true);
    assert_eq!(is_time_valid(now: 0, time: 4352), false);
    assert_eq!(is_time_valid(now: 16, time: 4096), true);
    assert_eq!(is_time_valid(now: 16, time: 3840), true);
    assert_eq!(is_time_valid(now: 16, time: 4352), false);

    assert_eq!(is_time_valid(now: 256, time: 4096), true);
    assert_eq!(is_time_valid(now: 256, time: 3840), true);
    assert_eq!(is_time_valid(now: 256, time: 4352), false);
    assert_eq!(is_time_valid(now: 257, time: 4352), true);
}

#[test]
fn test_calculate_reward_rate() {
    // largest reward possible
    assert_eq!(
        3618502788666131106986593281521497120404053196834988299249819043765042544640,
        calculate_reward_rate(0xffffffffffffffffffffffffffffffff, 32)
    );

    // overflow returns 0
    assert_eq!(0, calculate_reward_rate(0xffffffffffffffffffffffffffffffff, 31));
}
