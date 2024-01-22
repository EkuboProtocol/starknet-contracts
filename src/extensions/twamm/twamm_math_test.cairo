use core::debug::PrintTrait;
use ekubo::extensions::twamm::math::{
    calculate_sale_rate, calculate_reward_rate_deltas, calculate_reward_amount, calculate_c,
    constants, exp_fractional, calculate_e
};
use ekubo::interfaces::core::{Delta};
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


    fn assert_case_sale_rate(amount: u128, end_time: u64, start_time: u64, expected: u128) {
        let sale_rate = calculate_sale_rate(
            amount: amount, end_time: end_time, start_time: start_time
        );
        assert_eq!(sale_rate, expected);
    }

    #[test]
    fn test_sale_rates_smallest_amount() {
        assert_case_sale_rate(
            amount: 1, end_time: SIXTEEN_POW_ONE, start_time: 0, expected: 0x10000000
        );
        assert_case_sale_rate(
            amount: 1, end_time: SIXTEEN_POW_TWO, start_time: 0, expected: 0x1000000
        );
        assert_case_sale_rate(
            amount: 1, end_time: SIXTEEN_POW_THREE, start_time: 0, expected: 0x100000
        );
        assert_case_sale_rate(
            amount: 1, end_time: SIXTEEN_POW_FOUR, start_time: 0, expected: 0x10000
        );
        assert_case_sale_rate(
            amount: 1, end_time: SIXTEEN_POW_FIVE, start_time: 0, expected: 0x1000
        );
        assert_case_sale_rate(
            amount: 1, end_time: SIXTEEN_POW_SIX, start_time: 0, expected: 0x100
        );
        assert_case_sale_rate(
            amount: 1, end_time: SIXTEEN_POW_SEVEN, start_time: 0, expected: 0x10
        );
        assert_case_sale_rate(
            amount: 1, end_time: SIXTEEN_POW_EIGHT, start_time: 0, expected: 0x1
        );
    }

    #[test]
    #[should_panic(expected: ('SALE_RATE_ZERO',))]
    fn test_sale_rates_smallest_amount_underflow() {
        // sale window above 2**32 seconds (136.2 years) underflows to 0 sale rate.
        assert_case_sale_rate(
            amount: 1, end_time: SIXTEEN_POW_EIGHT + 1, start_time: 0, expected: 0x0
        );
    }

    #[test]
    #[should_panic(expected: ('SALE_RATE_OVERFLOW',))]
    fn test_sale_rates_overflow() {
        assert_case_sale_rate(
            // 2**128 - 1
            amount: 0xffffffffffffffffffffffffffffffff,
            // 2**32 - 1
            end_time: 0xffffffff,
            start_time: 0,
            expected: 0
        );
    }

    #[test]
    fn test_sale_rates_largest_amount() {
        assert_case_sale_rate(
            // 2**128 - 1
            amount: 0xffffffffffffffffffffffffffffffff,
            // 2**32
            end_time: 0x1000000000,
            start_time: 0,
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

        assert_eq!(reward_rate_0_delta, expected_0);
        assert_eq!(reward_rate_1_delta, expected_1);
    }

    #[test]
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
    use core::debug::PrintTrait;
    use super::{calculate_c, i129, constants, SIXTEEN_POW_SEVEN, exp_fractional, calculate_e};


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
    fn test_exp_fractional() {
        //     assert_eq!(exp_fractional(0), 0x100000000000000000000000000000000);
        //     // e^1 ~= 2.71828
        //     assert_eq!(
        //         exp_fractional(constants::X64),
        //         u256 { high: 0x2, low: 0xb7e151628aed2a6abf7158809cf4f3c6 }
        //     );
        // // e^0.5 ~= 1.64872
        // assert_eq!(
        //     exp_fractional(0x08000000000000000),
        //     u256 { high: 0x1, low: 0xa61298e1e069bc972dfefab6df33f9b1 }
        // );
        // // e^0.9 ~= 2.45960
        // assert_eq!(
        //     exp_fractional(16602069666338596454),
        //     u256 { high: 0x2, low: 0x75a88cab8f177288b8747b33886aad40 }
        // );
        // // e^0.09 ~= 1.09417
        // assert_eq!(
        //     exp_fractional(1660206966633859645),
        //     u256 { high: 0x1, low: 0x181bce4ca35acbdb046f24c2ae3f638f }
        // );
        // // e^0.08 ~= 1.08328
        // assert_eq!(
        //     exp_fractional(1475739525896764129),
        //     u256 { high: 0x1, low: 0x15524d1fd7fbca0db855628db68b61ca }
        // );
        // // e^0.07 ~= 1.07251
        // assert_eq!(
        //     exp_fractional(1291272085159668613),
        //     u256 { high: 0x1, low: 0x128fe56b2de69b7e490462b1192f78f8 }
        // );
        // // e^0.065 ~= 1.06783
        // assert_eq!(
        //     exp_fractional(1199038364791120855),
        //     u256 { high: 0x1, low: 0x113155755c82ff672e6342fca30adcf7 }
        // );
        // // e^0.064 ~= 1.06624
        // assert_eq!(
        //     exp_fractional(1180591620717411303),
        //     u256 { high: 0x1, low: 0x10eb6e7331e213f13432fca5237e3e63 }
        // );
        // // e^0.063 ~= 1.06465
        // assert_eq!(
        //     exp_fractional(1162144876643701751),
        //     u256 { high: 0x1, low: 0x10a59953dc574707aea915106603b7dd }
        // );
        // // e^0.062 ~= 1.063962
        // assert_eq!(
        //     exp_fractional(1143698132569992200),
        //     u256 { high: 0x1, low: 0x105fd612c84a3a38c6269b3d34a40ea2 }
        // );
        // // e^0.061 ~= 1.062899
        // assert_eq!(
        //     exp_fractional(1125251388496282648),
        //     u256 { high: 0x1, low: 0x101a24ab634e565840d674fd498c8543 }
        // );
        // e^0.06 ~= 1.061837
        assert_eq!(
            exp_fractional(1106804644422573096),
            u256 { high: 0x1, low: 0x101a24ab634e565840d674fd498c8543 }
        );
    // // e^0.02 ~= 1.02020
    // assert_eq!(
    //     exp_fractional(368934881474191032),
    //     u256 { high: 0x1, low: 0x181bce4ca35acbdb046f24c2ae3f638f }
    // );
    // // e^0.01 ~= 1.01005
    // assert_eq!(
    //     exp_fractional(184467440737095516),
    //     u256 { high: 0x1, low: 0x181bce4ca35acbdb046f24c2ae3f638f }
    // );
    // // e^0.009 ~= 1.00901
    // assert_eq!(
    //     exp_fractional(166020696663385964),
    //     u256 { high: 0x1, low: 0x181bce4ca35acbdb046f24c2ae3f638f }
    // );
    // // e^(0.00141421) ~= 1.001416
    // assert_eq!(
    //     exp_fractional(0x5cae926fa0cdac),
    //     u256 { high: 0x2, low: 0x75a88cab8f177288b8747b33886aad40 }
    // );
    }

    #[test]
    fn test_calculate_e_base() {
        // assert_eq!(calculate_e(0x0, 0x0, 0x1), u256 { high: 0x1, low: 0x0 });
        // assert_eq!(calculate_e(0x1, 0x0, 0x1), u256 { high: 0x1, low: 0x0 });
        // assert_eq!(calculate_e(0x0, 0x1, 0x1), u256 { high: 0x1, low: 0x0 });

        let sqrt_rate_sell = 0x2203a1ae49f5191919191919; // 2.45098 * 2**32
        let t = 2040;
        let liquidity = 7071066140030886677554057;
        // e ~= 1.00080032027
        assert_eq!(calculate_e(sqrt_rate_sell, t, liquidity), u256 { high: 0x1, low: 0x0 });
    }
}

