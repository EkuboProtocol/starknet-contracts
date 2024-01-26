use core::integer::{
    u512, u256_wide_mul, u512_safe_div_rem_by_u256, u256_as_non_zero, u256_safe_div_rem,
    u128_wide_mul, u256_sqrt
};
use core::num::traits::{Zero};
use core::traits::{Into, TryInto};
use ekubo::interfaces::core::{Delta};
use ekubo::math::bits::{msb};
use ekubo::math::exp2::{exp2};
use ekubo::math::muldiv::{muldiv};

mod constants {
    const LOG_SCALE_FACTOR: u8 = 4;
    const BITMAP_SPACING: u64 = 16;

    // 2**32
    const X32_u128: u128 = 0x100000000_u128;
    const X32_u256: u256 = 0x100000000_u256;

    // 2**64
    const X64_u128: u128 = 0x10000000000000000_u128;
    const X64_u256: u256 = 0x10000000000000000_u256;

    // 2**128
    const X128: u256 = 0x100000000000000000000000000000000_u256;

    // ~ ln(2**128) * 2**64
    const EXPONENT_LIMIT: u128 = 1623313478486440542208;
}

fn calculate_sale_rate(amount: u128, end_time: u64, start_time: u64) -> u128 {
    let sale_rate: u128 = ((amount.into() * constants::X32_u256) / (end_time - start_time).into())
        .try_into()
        .expect('SALE_RATE_OVERFLOW');

    assert(sale_rate > 0, 'SALE_RATE_ZERO');

    sale_rate
}

fn calculate_reward_rate_deltas(sale_rates: (u128, u128), delta: Delta) -> (felt252, felt252) {
    let (token0_sale_rate, token1_sale_rate) = sale_rates;

    let token0_reward_delta: felt252 = if (delta.amount0.mag > 0) {
        if (!delta.amount0.sign || token1_sale_rate.is_zero()) {
            0
        } else {
            (u256 { high: delta.amount0.mag, low: 0 } / token1_sale_rate.into())
                .try_into()
                .expect('REWARD_DELTA_OVERFLOW')
        }
    } else {
        0
    };

    let token1_reward_delta: felt252 = if (delta.amount1.mag > 0) {
        if (!delta.amount1.sign || token0_sale_rate.is_zero()) {
            0
        } else {
            (u256 { high: delta.amount1.mag, low: 0 } / token0_sale_rate.into())
                .try_into()
                .expect('REWARD_DELTA_OVERFLOW')
        }
    } else {
        0
    };

    (token0_reward_delta, token1_reward_delta)
}

fn calculate_reward_amount(reward_rate: felt252, sale_rate: u128) -> u128 {
    // this should never overflow since total_sale_rate <= sale_rate 
    ((reward_rate.into() * sale_rate.into()) / constants::X128)
        .try_into()
        .expect('REWARD_AMOUNT_OVERFLOW')
}

fn validate_time(start_time: u64, end_time: u64) {
    assert(end_time > start_time, 'INVALID_END_TIME');

    // calculate the closest timestamp at which an order can expire
    // based on the step of the interval that the order expires in using
    // an approximation of
    // = 16**(floor(log_16(end_time-start_time)))
    // = 2**(4 * (floor(log_2(end_time-start_time)) / 4))
    let step = exp2(
        constants::LOG_SCALE_FACTOR
            * (msb((end_time - start_time).into()) / constants::LOG_SCALE_FACTOR)
    );

    assert(step >= constants::BITMAP_SPACING.into(), 'INVALID_SPACING');
    assert((end_time.into() % step).is_zero(), 'INVALID_TIME');
}

fn calculate_next_sqrt_ratio(
    sqrt_ratio: u256,
    liquidity: u128,
    token0_sale_rate: u128,
    token1_sale_rate: u128,
    time_window: u64
) -> u256 {
    let sale_ratio = (u256 { high: token1_sale_rate, low: 0 } / token0_sale_rate.into());
    let sqrt_sale_ratio: u256 = u256_sqrt(sale_ratio).into() * constants::X64_u256;

    let (c, sign) = calculate_c(sqrt_ratio, sqrt_sale_ratio);

    let sqrt_ratio_next = if (c.is_zero() || liquidity.is_zero()) {
        // current sale ratio is the price
        sqrt_sale_ratio
    } else {
        let sqrt_sale_rate = u256_sqrt(token0_sale_rate.into() * token1_sale_rate.into());

        // calculate e
        // sqrt_sale_rate * 2 * t
        let (high, low) = u128_wide_mul(sqrt_sale_rate, (0x200000000 * time_window.into()));

        let (exponent, _) = u256_safe_div_rem(
            u256 { high: high, low: low }, u256_as_non_zero(liquidity.into())
        );
        // validate high is 0, integer piece should be < 128
        assert(exponent.high.is_zero(), 'E_MUL_OVERFLOW');

        if (exponent.low > constants::EXPONENT_LIMIT) {
            // sale_rate * t >> liquidity
            sqrt_sale_ratio
        } else {
            let e = exp_fractional(exponent.low);

            let term1 = e - c;
            let term2 = e + c;

            let scale: u256 = if (sign) {
                muldiv(term2, constants::X128, term1, false)
                    .expect('NEXT_SQRT_RATIO_TERM2_OVERFLOW')
            } else {
                muldiv(term1, constants::X128, term2, false)
                    .expect('NEXT_SQRT_RATIO_TERM1_OVERFLOW')
            };

            muldiv(sqrt_sale_ratio, scale, constants::X128, false)
                .expect('NEXT_SQRT_RATIO_OVERFLOW')
        }
    };

    sqrt_ratio_next
}

// c = (sqrt_sale_ratio - sqrt_ratio) / (sqrt_sale_ratio + sqrt_ratio)
fn calculate_c(sqrt_ratio: u256, sqrt_sale_ratio: u256) -> (u256, bool) {
    if (sqrt_ratio == sqrt_sale_ratio) {
        (0, false)
    } else if (sqrt_ratio.is_zero()) {
        // early return 1, if current price is zero
        (constants::X128, false)
    } else {
        let (numerator, sign) = if (sqrt_ratio > sqrt_sale_ratio) {
            (sqrt_ratio - sqrt_sale_ratio, true)
        } else {
            (sqrt_sale_ratio - sqrt_ratio, false)
        };

        (
            muldiv(numerator, constants::X128, sqrt_sale_ratio + sqrt_ratio, false)
                .expect('C_MULDIV_OVERFLOW'),
            sign
        )
    }
}

fn exp_fractional(x: u128) -> u256 {
    let res = if (x >= 0x20000000000000000) {
        let half = exp_fractional(x / 2);
        muldiv(half, half, constants::X128, false).expect('EXP_FRACTIONAL_OVERFLOW')
    } else {
        internal::exp_fractional(x)
    };

    res
}

mod internal {
    use core::integer::{u256_overflow_mul};

    fn exp_fractional(x: u128) -> u256 {
        assert(x < 0x20000000000000000, 'EXP_X_MAGNITUDE');

        let mut ratio = 0x100000000000000000000000000000000_u256;
        if ((x & 0x1) != 0) {
            ratio = u256 { high: 0, low: 0xffffffffffffffff0000000000000000 };
        }
        if ((x & 0x2) != 0) {
            ratio = unsafe_mul_shift(ratio, 0xfffffffffffffffe0000000000000002);
        }
        if ((x & 0x4) != 0) {
            ratio = unsafe_mul_shift(ratio, 0xfffffffffffffffc0000000000000008);
        }
        if ((x & 0x8) != 0) {
            ratio = unsafe_mul_shift(ratio, 0xfffffffffffffff80000000000000020);
        }
        if ((x & 0x10) != 0) {
            ratio = unsafe_mul_shift(ratio, 0xfffffffffffffff00000000000000080);
        }
        if ((x & 0x20) != 0) {
            ratio = unsafe_mul_shift(ratio, 0xffffffffffffffe00000000000000200);
        }
        if ((x & 0x40) != 0) {
            ratio = unsafe_mul_shift(ratio, 0xffffffffffffffc00000000000000800);
        }
        if ((x & 0x80) != 0) {
            ratio = unsafe_mul_shift(ratio, 0xffffffffffffff800000000000002000);
        }
        if ((x & 0x100) != 0) {
            ratio = unsafe_mul_shift(ratio, 0xffffffffffffff000000000000008000);
        }
        if ((x & 0x200) != 0) {
            ratio = unsafe_mul_shift(ratio, 0xfffffffffffffe000000000000020000);
        }
        if ((x & 0x400) != 0) {
            ratio = unsafe_mul_shift(ratio, 0xfffffffffffffc000000000000080000);
        }
        if ((x & 0x800) != 0) {
            ratio = unsafe_mul_shift(ratio, 0xfffffffffffff8000000000000200000);
        }
        if ((x & 0x1000) != 0) {
            ratio = unsafe_mul_shift(ratio, 0xfffffffffffff0000000000000800000);
        }
        if ((x & 0x2000) != 0) {
            ratio = unsafe_mul_shift(ratio, 0xffffffffffffe0000000000002000000);
        }
        if ((x & 0x4000) != 0) {
            ratio = unsafe_mul_shift(ratio, 0xffffffffffffc0000000000008000000);
        }
        if ((x & 0x8000) != 0) {
            ratio = unsafe_mul_shift(ratio, 0xffffffffffff80000000000020000000);
        }
        if ((x & 0x10000) != 0) {
            ratio = unsafe_mul_shift(ratio, 0xffffffffffff00000000000080000000);
        }
        if ((x & 0x20000) != 0) {
            ratio = unsafe_mul_shift(ratio, 0xfffffffffffe00000000000200000000);
        }
        if ((x & 0x40000) != 0) {
            ratio = unsafe_mul_shift(ratio, 0xfffffffffffc00000000000800000000);
        }
        if ((x & 0x80000) != 0) {
            ratio = unsafe_mul_shift(ratio, 0xfffffffffff800000000002000000000);
        }
        if ((x & 0x100000) != 0) {
            ratio = unsafe_mul_shift(ratio, 0xfffffffffff000000000008000000000);
        }
        if ((x & 0x200000) != 0) {
            ratio = unsafe_mul_shift(ratio, 0xffffffffffe000000000020000000000);
        }
        if ((x & 0x400000) != 0) {
            ratio = unsafe_mul_shift(ratio, 0xffffffffffc00000000007ffffffffff);
        }
        if ((x & 0x800000) != 0) {
            ratio = unsafe_mul_shift(ratio, 0xffffffffff80000000001ffffffffffb);
        }
        if ((x & 0x1000000) != 0) {
            ratio = unsafe_mul_shift(ratio, 0xffffffffff00000000007fffffffffd5);
        }
        if ((x & 0x2000000) != 0) {
            ratio = unsafe_mul_shift(ratio, 0xfffffffffe0000000001fffffffffeab);
        }
        if ((x & 0x4000000) != 0) {
            ratio = unsafe_mul_shift(ratio, 0xfffffffffc0000000007fffffffff555);
        }
        if ((x & 0x8000000) != 0) {
            ratio = unsafe_mul_shift(ratio, 0xfffffffff8000000001fffffffffaaab);
        }
        if ((x & 0x10000000) != 0) {
            ratio = unsafe_mul_shift(ratio, 0xfffffffff0000000007ffffffffd5555);
        }
        if ((x & 0x20000000) != 0) {
            ratio = unsafe_mul_shift(ratio, 0xffffffffe000000001ffffffffeaaaab);
        }
        if ((x & 0x40000000) != 0) {
            ratio = unsafe_mul_shift(ratio, 0xffffffffc000000007ffffffff555555);
        }
        if ((x & 0x80000000) != 0) {
            ratio = unsafe_mul_shift(ratio, 0xffffffff800000001ffffffffaaaaaab);
        }
        if ((x & 0x100000000) != 0) {
            ratio = unsafe_mul_shift(ratio, 0xffffffff000000007fffffffd5555555);
        }
        if ((x & 0x200000000) != 0) {
            ratio = unsafe_mul_shift(ratio, 0xfffffffe00000001fffffffeaaaaaaab);
        }
        if ((x & 0x400000000) != 0) {
            ratio = unsafe_mul_shift(ratio, 0xfffffffc00000007fffffff555555560);
        }
        if ((x & 0x800000000) != 0) {
            ratio = unsafe_mul_shift(ratio, 0xfffffff80000001fffffffaaaaaaab55);
        }
        if ((x & 0x1000000000) != 0) {
            ratio = unsafe_mul_shift(ratio, 0xfffffff00000007ffffffd5555556000);
        }
        if ((x & 0x2000000000) != 0) {
            ratio = unsafe_mul_shift(ratio, 0xffffffe0000001ffffffeaaaaaab5555);
        }
        if ((x & 0x4000000000) != 0) {
            ratio = unsafe_mul_shift(ratio, 0xffffffc0000007ffffff555555600000);
        }
        if ((x & 0x8000000000) != 0) {
            ratio = unsafe_mul_shift(ratio, 0xffffff8000001ffffffaaaaaab555555);
        }
        if ((x & 0x10000000000) != 0) {
            ratio = unsafe_mul_shift(ratio, 0xffffff0000007fffffd555555ffffffe);
        }
        if ((x & 0x20000000000) != 0) {
            ratio = unsafe_mul_shift(ratio, 0xfffffe000001fffffeaaaaab55555511);
        }
        if ((x & 0x40000000000) != 0) {
            ratio = unsafe_mul_shift(ratio, 0xfffffc000007fffff555555ffffff777);
        }
        if ((x & 0x80000000000) != 0) {
            ratio = unsafe_mul_shift(ratio, 0xfffff800001fffffaaaaab5555544444);
        }
        if ((x & 0x100000000000) != 0) {
            ratio = unsafe_mul_shift(ratio, 0xfffff000007ffffd55555fffffddddde);
        }
        if ((x & 0x200000000000) != 0) {
            ratio = unsafe_mul_shift(ratio, 0xffffe00001ffffeaaaab555551111128);
        }
        if ((x & 0x400000000000) != 0) {
            ratio = unsafe_mul_shift(ratio, 0xffffc00007ffff55555fffff77777d28);
        }
        if ((x & 0x800000000000) != 0) {
            ratio = unsafe_mul_shift(ratio, 0xffff80001ffffaaaab5555444445b05b);
        }
        if ((x & 0x1000000000000) != 0) {
            ratio = unsafe_mul_shift(ratio, 0xffff00007fffd5555ffffdddde38e381);
        }
        if ((x & 0x2000000000000) != 0) {
            ratio = unsafe_mul_shift(ratio, 0xfffe0001fffeaaab5555111127d276a7);
        }
        if ((x & 0x4000000000000) != 0) {
            ratio = unsafe_mul_shift(ratio, 0xfffc0007fff5555ffff7777d27cf3cf5);
        }
        if ((x & 0x8000000000000) != 0) {
            ratio = unsafe_mul_shift(ratio, 0xfff8001fffaaab55544445b0596597f9);
        }
        if ((x & 0x10000000000000) != 0) {
            ratio = unsafe_mul_shift(ratio, 0xfff0007ffd555fffddde38e2be2d82d5);
        }
        if ((x & 0x20000000000000) != 0) {
            ratio = unsafe_mul_shift(ratio, 0xffe001ffeaab55511127d21522f2295c);
        }
        if ((x & 0x40000000000000) != 0) {
            ratio = unsafe_mul_shift(ratio, 0xffc007ff555fff777d279e7b87acece0);
        }
        if ((x & 0x80000000000000) != 0) {
            ratio = unsafe_mul_shift(ratio, 0xff801ffaab554445b04105b043e8f48d);
        }
        if ((x & 0x100000000000000) != 0) {
            ratio = unsafe_mul_shift(ratio, 0xff007fd55ffdde38d68f08c257e0ce3f);
        }
        if ((x & 0x200000000000000) != 0) {
            ratio = unsafe_mul_shift(ratio, 0xfe01feab551127cbfe5f89994c44216f);
        }
        if ((x & 0x400000000000000) != 0) {
            ratio = unsafe_mul_shift(ratio, 0xfc07f55ff77d2493e885eeaa756ad523);
        }
        if ((x & 0x800000000000000) != 0) {
            ratio = unsafe_mul_shift(ratio, 0xf81fab5445aebc8a58055fcbbb139ae9);
        }
        if ((x & 0x1000000000000000) != 0) {
            ratio = unsafe_mul_shift(ratio, 0xf07d5fde38151e72f18ff03049ac5d7f);
        }
        if ((x & 0x2000000000000000) != 0) {
            ratio = unsafe_mul_shift(ratio, 0xe1eb51276c110c3c3eb1269f2f5d4afb);
        }
        if ((x & 0x4000000000000000) != 0) {
            ratio = unsafe_mul_shift(ratio, 0xc75f7cf564105743415cbc9d6368f3b9);
        }
        if ((x & 0x8000000000000000) != 0) {
            ratio = unsafe_mul_shift(ratio, 0x9b4597e37cb04ff3d675a35530cdd768);
        }
        if ((x & 0x10000000000000000) != 0) {
            ratio = unsafe_mul_shift(ratio, 0x5e2d58d8b3bcdf1abadec7829054f90e);
        }

        if (x != 0) {
            ratio =
                u256 {
                    high: 0xffffffffffffffffffffffffffffffff,
                    low: 0xffffffffffffffffffffffffffffffff
                }
                / ratio;
        }

        ratio
    }

    fn unsafe_mul_shift(x: u256, mul: u128) -> u256 {
        let (res, _) = u256_overflow_mul(x, u256 { high: 0, low: mul });
        u256 { high: 0, low: res.high }
    }
}
