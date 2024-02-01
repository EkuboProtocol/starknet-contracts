use ekubo::extensions::twamm::math::{
    calculate_sale_rate, calculate_reward_rate_deltas, calculate_reward_amount, calculate_c,
    constants, exp_fractional, calculate_next_sqrt_ratio
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
        assert_case_sale_rate(amount: 1, end_time: SIXTEEN_POW_SIX, start_time: 0, expected: 0x100);
        assert_case_sale_rate(
            amount: 1, end_time: SIXTEEN_POW_SEVEN, start_time: 0, expected: 0x10
        );
        assert_case_sale_rate(amount: 1, end_time: SIXTEEN_POW_EIGHT, start_time: 0, expected: 0x1);
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
    use super::{
        calculate_c, i129, constants, SIXTEEN_POW_SEVEN, exp_fractional, calculate_next_sqrt_ratio
    };


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
    fn test_exp_fractional() {
        // e^0 = 1
        assert_eq!(exp_fractional(0), 0x100000000000000000000000000000000);
        // e^(0.0000000000000000000542101086242752217003726400434970855712890625), error -1
        assert_eq!(exp_fractional(0x1), 340282366920938463481821351505477763073);
        // e^(0.000000000000000000867361737988403547205962240695953369140625), error 1
        assert_eq!(exp_fractional(0x10), 340282366920938463758522512611121037439);
        // e^(0.00000000000000001387778780781445675529539585113525390625), error 1
        assert_eq!(exp_fractional(0x100), 340282366920938468185741090301413457919);
        // e^(0.0000000000000002220446049250313080847263336181640625), error 1
        assert_eq!(exp_fractional(0x1000), 340282366920938539021238333346100019199);
        // e^(0.000000000000003552713678800500929355621337890625), error 1
        assert_eq!(exp_fractional(0x10000), 340282366920939672389194222063090401279);
        // e^(0.00000000000005684341886080801486968994140625), error 1
        assert_eq!(exp_fractional(0x100000), 340282366920957806276488442048319324159);
        // e^(0.0000000000009094947017729282379150390625), error -1
        assert_eq!(exp_fractional(0x1000000), 340282366921247948473196093237981347883);
        // e^(0.000000000014551915228366851806640625), error -1
        assert_eq!(exp_fractional(0x10000000), 340282366925890223620552157328383847083);
        // e^(0.00000000023283064365386962890625), error -1
        assert_eq!(exp_fractional(0x100000000), 340282367000166625986862317062882765483);
        // e^(0.0000000037252902984619140625), error 0
        assert_eq!(exp_fractional(0x1000000000), 340282368188589066052787253295325033813);
        // e^(0.000000059604644775390625), error 0
        assert_eq!(exp_fractional(0x10000000000), 340282387203348671577966848292792128855);
        // e^(0.00000095367431640625), error -1
        assert_eq!(exp_fractional(0x100000000000), 340282691439646864444203392380169582456);
        // e^(0.0000152587890625), error -1
        assert_eq!(exp_fractional(0x1000000000000), 340287559257411281036540525845100526901);
        // e^(0.000244140625), error -1
        assert_eq!(exp_fractional(0x10000000000000), 340365453812705166265158710766120017429);
        // e^(0.00390625), error 0
        assert_eq!(exp_fractional(0x100000000000000), 341614194448858001518548349210986147431);
        // e^(0.0625), error 0
        assert_eq!(exp_fractional(0x1000000000000000), 362228694054792897708330706853750745425);
        // e^(0.125), error 0
        assert_eq!(exp_fractional(0x2000000000000000), 385590437682379610444903081021111242050);
        // e^(0.1875), error 1
        assert_eq!(exp_fractional(0x3000000000000000), 410458884324605278747045302672787018564);
        // e^(0.25), error -1
        assert_eq!(exp_fractional(0x4000000000000000), 436931207977148949689182835287359640399);
        // e^(0.3125), error -1
        assert_eq!(exp_fractional(0x5000000000000000), 465110849819961876897005063802066305987);
        // e^(0.375), error -2
        assert_eq!(exp_fractional(0x6000000000000000), 495107922415926095027634166600617428423);
        // e^(0.4375), error -1
        assert_eq!(exp_fractional(0x7000000000000000), 527039639978086774335495300108384275440);
        // e^(0.5), error 0
        assert_eq!(exp_fractional(0x8000000000000000), 561030776386736916030812855022080227761);
        // e^(0.5625), error -1
        assert_eq!(exp_fractional(0x9000000000000000), 597214152746066100200648133048910480876);
        // e^(0.625), error -1
        assert_eq!(exp_fractional(0xa000000000000000), 635731156385511486531950475009791253446);
        // e^(0.6875), error -2
        assert_eq!(exp_fractional(0xb000000000000000), 676732293333820125464283151708592742980);
        // e^(0.75), error -2
        assert_eq!(exp_fractional(0xc000000000000000), 720377776424626984252099347839312863015);
        // e^(0.8521), error -2
        assert_eq!(exp_fractional(0xd000000000000000), 766838151331584014392864879771379942747);
        // e^(0.875), error -6
        assert_eq!(exp_fractional(0xe000000000000000), 816294962979286131831249594449188333552);
        // e^(0.9375), error -3
        assert_eq!(exp_fractional(0xf000000000000000), 868941464934009285206259196893053646191);
        // e^1, error 1
        assert_eq!(exp_fractional(0x10000000000000000), 924983374546220337150911035843336795078);
        // e^2, error 8
        assert_eq!(
            exp_fractional(2 * constants::X64_u128), 2514365498655717699434277416465328696985
        );
        // e^3, error -86
        assert_eq!(
            exp_fractional(3 * constants::X64_u128), 6834754045100203352782362684486003079515
        );
        // e^4, error 120
        assert_eq!(
            exp_fractional(4 * constants::X64_u128), 18578787722782836492235669422995900914061
        );
        // e^5, error -1150
        assert_eq!(
            exp_fractional(5 * constants::X64_u128), 50502381061638590010053149766929220245932
        );
        // e^6, error -3433
        assert_eq!(
            exp_fractional(6 * constants::X64_u128), 137279704733766404528564625531825993812898
        );
        // e^7, error -27603
        assert_eq!(
            exp_fractional(7 * constants::X64_u128), 373164926794020389796596697795276277152463
        );
        // e^8, error 13167
        assert_eq!(
            exp_fractional(8 * constants::X64_u128), 1014367439522435506293930954162796520996787
        );
        // e^9, error 10252
        assert_eq!(
            exp_fractional(9 * constants::X64_u128), 2757336578234365975078160713954485341829012
        );
        // e^(10), error -341285
        assert_eq!(
            exp_fractional(10 * constants::X64_u128), 7495217915559919573679589385952004519747242
        );

        // last valid input
        // e^(88), error -28250270430280119449491910663393939268384
        assert_eq!(
            exp_fractional(88 * constants::X64_u128),
            56202269414179362208214868742863362868341779313762687677660940959816606662721
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
            time_window: 1
        );
        // sqrt_ratio = 1
        assert_eq!(next_sqrt_ratio, constants::X128);

        // c is zero since sqrt_ratio == sqrt_sale_ratio, price is sqrt_sale_ratio
        let next_sqrt_ratio = calculate_next_sqrt_ratio(
            sqrt_ratio: constants::X128,
            liquidity: constants::X64_u128,
            token0_sale_rate: constants::X32_u128,
            token1_sale_rate: constants::X32_u128,
            time_window: 1
        );
        // sqrt_ratio = 1
        assert_eq!(next_sqrt_ratio, constants::X128);

        let next_sqrt_ratio = calculate_next_sqrt_ratio(
            sqrt_ratio: constants::X128,
            liquidity: 10_000 * 1000000000000000000,
            token0_sale_rate: 5000 * constants::X32_u128,
            token1_sale_rate: 500 * constants::X32_u128,
            time_window: 1
        );
        // sqrt_ratio ~= .99
        assert_eq!(next_sqrt_ratio, 340282366920938463332123722385714104074);

        // very low liquidity
        let next_sqrt_ratio = calculate_next_sqrt_ratio(
            sqrt_ratio: constants::X128,
            liquidity: 10,
            token0_sale_rate: 5000 * constants::X32_u128,
            token1_sale_rate: 500 * constants::X32_u128,
            time_window: 1
        );
        // sqrt_ratio will be sqrt_sale_ratio
        assert_eq!(next_sqrt_ratio, 107606732706330320671984263368533868544);
    }
}
