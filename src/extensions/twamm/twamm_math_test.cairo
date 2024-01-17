use core::debug::PrintTrait;
use ekubo::extensions::twamm::math::{
    calculate_sale_rate, calculate_reward_rate_deltas, calculate_reward_amount, exp, calculate_c,
    constants
};
use ekubo::interfaces::core::{Delta};
use ekubo::math::ticks::{tick_to_sqrt_ratio};
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
        calculate_sale_rate, SIXTEEN_POW_ONE, SIXTEEN_POW_TWO, SIXTEEN_POW_THREE, SIXTEEN_POW_FOUR,
        SIXTEEN_POW_FIVE, SIXTEEN_POW_SIX, SIXTEEN_POW_SEVEN, SIXTEEN_POW_EIGHT
    };


    fn assert_case_sale_rate(amount: u128, expiry_time: u64, current_time: u64, expected: u128) {
        let sale_rate = calculate_sale_rate(
            amount: amount, expiry_time: expiry_time, current_time: current_time
        );
        assert(sale_rate == expected, 'sale_rate');
    }

    #[test]
    #[available_gas(3000000000)]
    fn test_sale_rates_smallest_amount() {
        assert_case_sale_rate(
            amount: 1, expiry_time: SIXTEEN_POW_ONE, current_time: 0, expected: 0x10000000
        );
        assert_case_sale_rate(
            amount: 1, expiry_time: SIXTEEN_POW_TWO, current_time: 0, expected: 0x1000000
        );
        assert_case_sale_rate(
            amount: 1, expiry_time: SIXTEEN_POW_THREE, current_time: 0, expected: 0x100000
        );
        assert_case_sale_rate(
            amount: 1, expiry_time: SIXTEEN_POW_FOUR, current_time: 0, expected: 0x10000
        );
        assert_case_sale_rate(
            amount: 1, expiry_time: SIXTEEN_POW_FIVE, current_time: 0, expected: 0x1000
        );
        assert_case_sale_rate(
            amount: 1, expiry_time: SIXTEEN_POW_SIX, current_time: 0, expected: 0x100
        );
        assert_case_sale_rate(
            amount: 1, expiry_time: SIXTEEN_POW_SEVEN, current_time: 0, expected: 0x10
        );
        assert_case_sale_rate(
            amount: 1, expiry_time: SIXTEEN_POW_EIGHT, current_time: 0, expected: 0x1
        );
    }

    #[test]
    #[available_gas(3000000000)]
    #[should_panic(expected: ('SALE_RATE_ZERO',))]
    fn test_sale_rates_smallest_amount_underflow() {
        // sale window above 2**32 seconds (136.2 years) underflows to 0 sale rate.
        assert_case_sale_rate(
            amount: 1, expiry_time: SIXTEEN_POW_EIGHT + 1, current_time: 0, expected: 0x0
        );
    }

    #[test]
    #[available_gas(3000000000)]
    #[should_panic(expected: ('SALE_RATE_OVERFLOW',))]
    fn test_sale_rates_overflow() {
        assert_case_sale_rate(
            // 2**128 - 1
            amount: 0xffffffffffffffffffffffffffffffff,
            // 2**32 - 1
            expiry_time: 0xffffffff,
            current_time: 0,
            expected: 0
        );
    }

    #[test]
    #[available_gas(3000000000)]
    fn test_sale_rates_largest_amount() {
        assert_case_sale_rate(
            // 2**128 - 1
            amount: 0xffffffffffffffffffffffffffffffff,
            // 2**32
            expiry_time: 0x1000000000,
            current_time: 0,
            expected: 0xfffffffffffffffffffffffffffffff
        );
    }
}

mod RewardRateTest {
    use super::{
        Delta, calculate_reward_rate_deltas, calculate_reward_amount, SIXTEEN_POW_EIGHT, i129,
    };


    fn assert_case_reward_rate(
        sale_rates: (u128, u128), delta: Delta, expected: (felt252, felt252)
    ) {
        let (sale_rate_0, sale_rate_1) = sale_rates;

        let (reward_rate_0_delta, reward_rate_1_delta) = calculate_reward_rate_deltas(
            sale_rates: sale_rates, delta: delta
        );

        let (expected_0, expected_1) = expected;

        assert(reward_rate_0_delta == expected_0, 'reward_rate_0');
        assert(reward_rate_1_delta == expected_1, 'reward_rate_1');
    }

    #[test]
    #[available_gas(3000000000)]
    fn test_reward_rates_largest_amount() {
        // 2**128 - 1
        let amount = 0xffffffffffffffffffffffffffffffff;
        // (2**128 - 1) * (2**160 / 2**32) = 2**256 - 2**128
        let expected_reward_rate = 0xffffffffffffffffffffffffffffffff000000000000000000000000;

        assert_case_reward_rate(
            // smallest possible sale rate
            sale_rates: (SIXTEEN_POW_EIGHT.into(), SIXTEEN_POW_EIGHT.into()),
            delta: Delta {
                amount0: i129 { mag: amount, sign: true },
                amount1: i129 { mag: amount, sign: true },
            },
            expected: (expected_reward_rate, expected_reward_rate)
        );
    }

    #[test]
    #[available_gas(3000000000)]
    fn test_largest_reward_amount_no_overflow() {
        // 2**256 - 2**128
        let reward_rate = 0xffffffffffffffffffffffffffffffff000000000000000000000000;
        // only way to get largest reward amount is with the smallest sale rate
        let sale_rate = SIXTEEN_POW_EIGHT.into();
        // 2**128 - 1
        let expected_amount = 0xffffffffffffffffffffffffffffffff;

        let amount = calculate_reward_amount(reward_rate: reward_rate, sale_rate: sale_rate);

        assert(expected_amount == amount, 'amount');
    }
}

mod TWAMMMathTest {
    use core::debug::PrintTrait;
    use super::{calculate_c, exp, tick_to_sqrt_ratio, i129, constants, SIXTEEN_POW_SEVEN};


    fn assert_case_c(sqrt_ratio: u256, sqrt_sell_ratio: u256, expected: (u256, bool)) {
        let (val, sign) = calculate_c(sqrt_ratio, sqrt_sell_ratio);
        let (expected_val, expected_sign) = expected;

        assert(val == expected_val, 'val');
        assert(sign == expected_sign, 'sign');
    }

    #[test]
    #[available_gas(3000000000)]
    fn test_zero_c() {
        assert_case_c(sqrt_ratio: 0, sqrt_sell_ratio: 0, expected: (0, false));
        assert_case_c(sqrt_ratio: 1, sqrt_sell_ratio: 1, expected: (0, false));
    }

    #[test]
    #[available_gas(3000000000)]
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
    #[available_gas(3000000000)]
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
    #[available_gas(3000000000)]
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
    #[available_gas(3000000000)]
    fn test_exp() {
        assert(exp(2 * constants::X_64) == 0x763992e34a0de88b8, 'exp(2) invalid');
    }
}
