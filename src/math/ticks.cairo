use core::integer::{u256_overflow_mul, u256_overflowing_add, u128_wide_mul};
use core::option::{OptionTrait, Option};
use core::traits::{Into, TryInto};
use ekubo::math::bits::{msb};
use ekubo::math::exp2::{exp2};
use ekubo::types::i129::{i129};

mod constants {
    // price may not exceed 2**128 or 2**-128
    // floor(log base 1.000001 of (2**128))
    const MAX_TICK_MAGNITUDE: u128 = 88722883;

    // rationale for this value is 2 251-bit tick bitmaps can contain initialized ticks for the entire price range
    // 2 is the minimum number of bitmaps because the 0 tick is always a bitmap boundary. any tick tick_spacing
    // larger than this does not offer any gas performance benefit to swappers
    // ceil(log base 1.000001 of 2)
    // also == ceil(MAX_TICK_MAGNITUDE / 251)
    // note that because the 0 tick is in the first bitmap, we actually do ceil(MAX_TICK_MAGNITUDE / 250) to meet this requirement
    // that the entire tick spacing fits in 2 bitmaps
    const MAX_TICK_SPACING: u128 = 354892;

    const MAX_SQRT_RATIO: u256 = 6277100250585753475930931601400621808602321654880405518632;
    const MIN_SQRT_RATIO: u256 = 18446748437148339061;
}


// Each step in the approximation performs a multiplication and a shift
// We assume the mul is safe in this function
#[inline(always)]
fn unsafe_mul_shift(x: u256, mul: u128) -> u256 {
    let (res, _) = u256_overflow_mul(x, u256 { high: 0, low: mul });
    return u256 { low: res.high, high: 0 };
}

// 56234808244317829948461091929465028608 = 0x3ffffffffff (the remaining log2 bits) * 25572630076711825471857579 (the conversion rate);
const MAX_ERROR_MAGNITUDE: u128 = 112469616488610087266845472033458199637;

#[inline(always)]
fn max(x: u256, y: u256) -> u256 {
    if (x > y) {
        x
    } else {
        y
    }
}

#[inline(always)]
fn unsafe_mul(x: u128, y: u128) -> u128 {
    let (_, low) = u128_wide_mul(x, y);
    return low;
}

#[inline(always)]
pub(crate) fn by_2_127(x: u256) -> u256 {
    let (sum, overflow) = u256_overflowing_add(x, x);
    u256 { low: sum.high, high: if overflow {
        1
    } else {
        0
    } }
}

pub(crate) fn log2(x: u256) -> (u128, bool) {
    // negative result, compute log 2 of reciprocal
    if (x.high == 0) {
        let (mag, sign) = log2(
            u256 {
                high: 0xffffffffffffffffffffffffffffffff, low: 0xffffffffffffffffffffffffffffffff
            }
                / x
        );
        return (mag, !sign);
    }

    // high is always non-zero because we inverse it above
    let msb_high = msb(x.high);

    let (mut r, mut log_2) = (
        x / u256 { low: exp2(msb_high + 1), high: 0 }, msb_high.into() * 0x10000000000000000
    );

    // 63
    r = by_2_127(r * r);
    let mut f = r.high;
    if f != 0 {
        log_2 = log_2 + 0x8000000000000000;
        r = r / 2;
    }

    // 62
    r = by_2_127(r * r);
    f = r.high;
    if f != 0 {
        log_2 = log_2 + 0x4000000000000000;
        r = r / 2;
    }

    // 61
    r = by_2_127(r * r);
    f = r.high;
    if f != 0 {
        log_2 = log_2 + 0x2000000000000000;
        r = r / 2;
    }

    // 60
    r = by_2_127(r * r);
    f = r.high;
    if f != 0 {
        log_2 = log_2 + 0x1000000000000000;
        r = r / 2;
    }

    // 59
    r = by_2_127(r * r);
    f = r.high;
    if f != 0 {
        log_2 = log_2 + 0x800000000000000;
        r = r / 2;
    }

    // 58
    r = by_2_127(r * r);
    f = r.high;
    if f != 0 {
        log_2 = log_2 + 0x400000000000000;
        r = r / 2;
    }

    // 57
    r = by_2_127(r * r);
    f = r.high;
    if f != 0 {
        log_2 = log_2 + 0x200000000000000;
        r = r / 2;
    }

    // 56
    r = by_2_127(r * r);
    f = r.high;
    if f != 0 {
        log_2 = log_2 + 0x100000000000000;
        r = r / 2;
    }

    // 55
    r = by_2_127(r * r);
    f = r.high;
    if f != 0 {
        log_2 = log_2 + 0x80000000000000;
        r = r / 2;
    }

    // 54
    r = by_2_127(r * r);
    f = r.high;
    if f != 0 {
        log_2 = log_2 + 0x40000000000000;
        r = r / 2;
    }

    // 53
    r = by_2_127(r * r);
    f = r.high;
    if f != 0 {
        log_2 = log_2 + 0x20000000000000;
        r = r / 2;
    }

    // 52
    r = by_2_127(r * r);
    f = r.high;
    if f != 0 {
        log_2 = log_2 + 0x10000000000000;
        r = r / 2;
    }

    // 51
    r = by_2_127(r * r);
    f = r.high;
    if f != 0 {
        log_2 = log_2 + 0x8000000000000;
        r = r / 2;
    }

    // 50
    r = by_2_127(r * r);
    f = r.high;
    if f != 0 {
        log_2 = log_2 + 0x4000000000000;
        r = r / 2;
    }

    // 49
    r = by_2_127(r * r);
    f = r.high;
    if f != 0 {
        log_2 = log_2 + 0x2000000000000;
        r = r / 2;
    }

    // 48
    r = by_2_127(r * r);
    f = r.high;
    if f != 0 {
        log_2 = log_2 + 0x1000000000000;
        r = r / 2;
    }

    // 47
    r = by_2_127(r * r);
    f = r.high;
    if f != 0 {
        log_2 = log_2 + 0x800000000000;
        r = r / 2;
    }

    // 46
    r = by_2_127(r * r);
    f = r.high;
    if f != 0 {
        log_2 = log_2 + 0x400000000000;
        r = r / 2;
    }

    // 45
    r = by_2_127(r * r);
    f = r.high;
    if f != 0 {
        log_2 = log_2 + 0x200000000000;
        r = r / 2;
    }

    // 44
    r = by_2_127(r * r);
    f = r.high;
    if f != 0 {
        log_2 = log_2 + 0x100000000000;
        r = r / 2;
    }

    // 43
    r = by_2_127(r * r);
    f = r.high;
    if f != 0 {
        log_2 = log_2 + 0x80000000000;
        r = r / 2;
    }

    // 42
    r = by_2_127(r * r);
    f = r.high;
    if f != 0 {
        log_2 = log_2 + 0x40000000000;
    }

    (log_2, false)
}

#[inline(always)]
fn min_tick() -> i129 {
    i129 { mag: constants::MAX_TICK_MAGNITUDE, sign: true }
}

#[inline(always)]
fn max_tick() -> i129 {
    i129 { mag: constants::MAX_TICK_MAGNITUDE, sign: false }
}

#[inline(always)]
fn max_sqrt_ratio() -> u256 {
    constants::MAX_SQRT_RATIO
}

#[inline(always)]
fn min_sqrt_ratio() -> u256 {
    constants::MIN_SQRT_RATIO
}

// Computes the value sqrt(1.000001)^tick as a binary fixed point 128.128 number
fn tick_to_sqrt_ratio(tick: i129) -> u256 {
    assert(tick.mag <= constants::MAX_TICK_MAGNITUDE, 'TICK_MAGNITUDE');

    let mut ratio = 0x100000000000000000000000000000000_u256;
    if ((tick.mag & 0x1) != 0) {
        ratio = u256 { high: 0, low: 0xfffff79c8499329c7cbb2510d893283b };
    }
    if ((tick.mag & 0x2) != 0) {
        ratio = unsafe_mul_shift(ratio, 0xffffef390978c398134b4ff3764fe410);
    }
    if ((tick.mag & 0x4) != 0) {
        ratio = unsafe_mul_shift(ratio, 0xffffde72140b00a354bd3dc828e976c9);
    }
    if ((tick.mag & 0x8) != 0) {
        ratio = unsafe_mul_shift(ratio, 0xffffbce42c7be6c998ad6318193c0b18);
    }
    if ((tick.mag & 0x10) != 0) {
        ratio = unsafe_mul_shift(ratio, 0xffff79c86a8f6150a32d9778eceef97c);
    }
    if ((tick.mag & 0x20) != 0) {
        ratio = unsafe_mul_shift(ratio, 0xfffef3911b7cff24ba1b3dbb5f8f5974);
    }
    if ((tick.mag & 0x40) != 0) {
        ratio = unsafe_mul_shift(ratio, 0xfffde72350725cc4ea8feece3b5f13c8);
    }
    if ((tick.mag & 0x80) != 0) {
        ratio = unsafe_mul_shift(ratio, 0xfffbce4b06c196e9247ac87695d53c60);
    }
    if ((tick.mag & 0x100) != 0) {
        ratio = unsafe_mul_shift(ratio, 0xfff79ca7a4d1bf1ee8556cea23cdbaa5);
    }
    if ((tick.mag & 0x200) != 0) {
        ratio = unsafe_mul_shift(ratio, 0xffef3995a5b6a6267530f207142a5764);
    }
    if ((tick.mag & 0x400) != 0) {
        ratio = unsafe_mul_shift(ratio, 0xffde7444b28145508125d10077ba83b8);
    }
    if ((tick.mag & 0x800) != 0) {
        ratio = unsafe_mul_shift(ratio, 0xffbceceeb791747f10df216f2e53ec57);
    }
    if ((tick.mag & 0x1000) != 0) {
        ratio = unsafe_mul_shift(ratio, 0xff79eb706b9a64c6431d76e63531e929);
    }
    if ((tick.mag & 0x2000) != 0) {
        ratio = unsafe_mul_shift(ratio, 0xfef41d1a5f2ae3a20676bec6f7f9459a);
    }
    if ((tick.mag & 0x4000) != 0) {
        ratio = unsafe_mul_shift(ratio, 0xfde95287d26d81bea159c37073122c73);
    }
    if ((tick.mag & 0x8000) != 0) {
        ratio = unsafe_mul_shift(ratio, 0xfbd701c7cbc4c8a6bb81efd232d1e4e7);
    }
    if ((tick.mag & 0x10000) != 0) {
        ratio = unsafe_mul_shift(ratio, 0xf7bf5211c72f5185f372aeb1d48f937e);
    }
    if ((tick.mag & 0x20000) != 0) {
        ratio = unsafe_mul_shift(ratio, 0xefc2bf59df33ecc28125cf78ec4f167f);
    }
    if ((tick.mag & 0x40000) != 0) {
        ratio = unsafe_mul_shift(ratio, 0xe08d35706200796273f0b3a981d90cfd);
    }
    if ((tick.mag & 0x80000) != 0) {
        ratio = unsafe_mul_shift(ratio, 0xc4f76b68947482dc198a48a54348c4ed);
    }
    if ((tick.mag & 0x100000) != 0) {
        ratio = unsafe_mul_shift(ratio, 0x978bcb9894317807e5fa4498eee7c0fa);
    }
    if ((tick.mag & 0x200000) != 0) {
        ratio = unsafe_mul_shift(ratio, 0x59b63684b86e9f486ec54727371ba6ca);
    }
    if ((tick.mag & 0x400000) != 0) {
        ratio = unsafe_mul_shift(ratio, 0x1f703399d88f6aa83a28b22d4a1f56e3);
    }
    if ((tick.mag & 0x800000) != 0) {
        ratio = unsafe_mul_shift(ratio, 0x3dc5dac7376e20fc8679758d1bcdcfc);
    }
    if ((tick.mag & 0x1000000) != 0) {
        ratio = unsafe_mul_shift(ratio, 0xee7e32d61fdb0a5e622b820f681d0);
    }
    if ((tick.mag & 0x2000000) != 0) {
        ratio = unsafe_mul_shift(ratio, 0xde2ee4bc381afa7089aa84bb66);
    }
    if ((tick.mag & 0x4000000) != 0) {
        ratio = unsafe_mul_shift(ratio, 0xc0d55d4d7152c25fb139);
    }

    // if positive and non-zero, invert, because we were computng a negative value
    if (!tick.sign) {
        if (tick.mag != 0) {
            ratio = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff_u256 / ratio;
        }
    }

    return ratio;
}

// Computes the tick corresponding to the price, i.e. log base sqrt(1.000001) of the ratio aligned with the above function s.t. sqrt_ratio_to_tick(tick_to_sqrt_ratio(tick)) == tick
fn sqrt_ratio_to_tick(sqrt_ratio: u256) -> i129 {
    // max price from max tick, exclusive check because this function should never be called on a price equal to max price
    assert(sqrt_ratio < max_sqrt_ratio(), 'SQRT_RATIO_TOO_HIGH');
    // min price from min tick
    assert(sqrt_ratio >= min_sqrt_ratio(), 'SQRT_RATIO_TOO_LOW');

    let (log2_sqrt_ratio, sign) = log2(sqrt_ratio);

    // == 2**64/(log base 2 of tick size)
    // https://www.wolframalpha.com/input?i=floor%28%281%2F+log+base+2+of+%28sqrt%281.000001%29%29%29*2**64%29
    let (high, low) = u128_wide_mul(25572630076711825471857579, log2_sqrt_ratio);

    let tick_mag_x128 = u256 { high, low };

    let error = u256 { low: MAX_ERROR_MAGNITUDE, high: 0 };

    let (tick_low, tick_high) = if (sign) {
        // rounds towards negative infinity and includes error
        (
            i129 {
                mag: (tick_mag_x128
                    + error
                    + u256 { low: 0xffffffffffffffffffffffffffffffff, high: 0 })
                    .high,
                sign
            },
            i129 {
                mag: (tick_mag_x128 + u256 { low: 0xffffffffffffffffffffffffffffffff, high: 0 })
                    .high,
                sign
            }
        )
    } else {
        (i129 { mag: tick_mag_x128.high, sign }, i129 { mag: (tick_mag_x128 + error).high, sign })
    };

    if (tick_low == tick_high) {
        return tick_low;
    }

    if (tick_to_sqrt_ratio(tick_high) <= sqrt_ratio) {
        return tick_high;
    }
    return tick_low;
}
