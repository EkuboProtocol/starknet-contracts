use core::integer::u128_wide_mul;
use ekubo::types::i129::i129;

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

    // floor(log base 1.000001 of 1.01)
    const TICKS_IN_ONE_PERCENT: u128 = 9950;

    const MAX_SQRT_RATIO: u256 = 6277100250585753475930931601400621808602321654880405518632;
    const MIN_SQRT_RATIO: u256 = 18446748437148339061;
}

mod internal {
    use core::integer::{downcast};
    use core::integer::{u256_overflow_mul, u256_overflowing_add, u128_wide_mul};
    use core::option::{OptionTrait, Option};
    use core::traits::{Into, TryInto};
    use ekubo::math::bits::{msb};
    use ekubo::math::exp2::{exp2};
    use ekubo::types::i129::{i129};


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
    fn by_2_127(x: u256) -> u256 {
        let (sum, overflow) = u256_overflowing_add(x, x);
        u256 { low: sum.high, high: if overflow {
            1
        } else {
            0
        } }
    }

    fn log2(x: u256) -> (u128, bool) {
        // negative result, compute log 2 of reciprocal
        if (x.high == 0) {
            let (mag, sign) = log2(
                u256 {
                    high: 0xffffffffffffffffffffffffffffffff,
                    low: 0xffffffffffffffffffffffffffffffff
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
        ratio = internal::unsafe_mul_shift(ratio, 0xffffef390978c398134b4ff3764fe410);
    }
    if ((tick.mag & 0x4) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0xffffde72140b00a354bd3dc828e976c9);
    }
    if ((tick.mag & 0x8) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0xffffbce42c7be6c998ad6318193c0b18);
    }
    if ((tick.mag & 0x10) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0xffff79c86a8f6150a32d9778eceef97c);
    }
    if ((tick.mag & 0x20) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0xfffef3911b7cff24ba1b3dbb5f8f5974);
    }
    if ((tick.mag & 0x40) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0xfffde72350725cc4ea8feece3b5f13c8);
    }
    if ((tick.mag & 0x80) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0xfffbce4b06c196e9247ac87695d53c60);
    }
    if ((tick.mag & 0x100) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0xfff79ca7a4d1bf1ee8556cea23cdbaa5);
    }
    if ((tick.mag & 0x200) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0xffef3995a5b6a6267530f207142a5764);
    }
    if ((tick.mag & 0x400) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0xffde7444b28145508125d10077ba83b8);
    }
    if ((tick.mag & 0x800) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0xffbceceeb791747f10df216f2e53ec57);
    }
    if ((tick.mag & 0x1000) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0xff79eb706b9a64c6431d76e63531e929);
    }
    if ((tick.mag & 0x2000) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0xfef41d1a5f2ae3a20676bec6f7f9459a);
    }
    if ((tick.mag & 0x4000) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0xfde95287d26d81bea159c37073122c73);
    }
    if ((tick.mag & 0x8000) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0xfbd701c7cbc4c8a6bb81efd232d1e4e7);
    }
    if ((tick.mag & 0x10000) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0xf7bf5211c72f5185f372aeb1d48f937e);
    }
    if ((tick.mag & 0x20000) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0xefc2bf59df33ecc28125cf78ec4f167f);
    }
    if ((tick.mag & 0x40000) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0xe08d35706200796273f0b3a981d90cfd);
    }
    if ((tick.mag & 0x80000) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0xc4f76b68947482dc198a48a54348c4ed);
    }
    if ((tick.mag & 0x100000) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0x978bcb9894317807e5fa4498eee7c0fa);
    }
    if ((tick.mag & 0x200000) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0x59b63684b86e9f486ec54727371ba6ca);
    }
    if ((tick.mag & 0x400000) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0x1f703399d88f6aa83a28b22d4a1f56e3);
    }
    if ((tick.mag & 0x800000) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0x3dc5dac7376e20fc8679758d1bcdcfc);
    }
    if ((tick.mag & 0x1000000) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0xee7e32d61fdb0a5e622b820f681d0);
    }
    if ((tick.mag & 0x2000000) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0xde2ee4bc381afa7089aa84bb66);
    }
    if ((tick.mag & 0x4000000) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0xc0d55d4d7152c25fb139);
    }

    // if positive and non-zero, invert, because we were computng a negative value
    if (!tick.sign) {
        if (tick.mag != 0) {
            ratio = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff_u256 / ratio;
        }
    }

    return ratio;
}


fn exp2_fractional(x: u128) -> u256 {
    let mut ratio = 0x100000000000000000000000000000000_u256;
    if ((x & 0x1) != 0) {
        ratio = u256 { high: 0, low: 0xffffffffffffffff4e8de8082e308654 };
    }
    if ((x & 0x2) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0xfffffffffffffffe9d1bd0105c610ca9);
    }
    if ((x & 0x4) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0xfffffffffffffffd3a37a020b8c21955);
    }
    if ((x & 0x8) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0xfffffffffffffffa746f4041718432b1);
    }
    if ((x & 0x10) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0xfffffffffffffff4e8de8082e3086581);
    }
    if ((x & 0x20) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0xffffffffffffffe9d1bd0105c610cb7d);
    }
    if ((x & 0x40) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0xffffffffffffffd3a37a020b8c2198e5);
    }
    if ((x & 0x80) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0xffffffffffffffa746f404171843397b);
    }
    if ((x & 0x100) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0xffffffffffffff4e8de8082e308691b6);
    }
    if ((x & 0x200) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0xfffffffffffffe9d1bd0105c610d9e6a);
    }
    if ((x & 0x400) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0xfffffffffffffd3a37a020b8c21d28d0);
    }
    if ((x & 0x800) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0xfffffffffffffa746f40417184420190);
    }
    if ((x & 0x1000) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0xfffffffffffff4e8de8082e308a2c2de);
    }
    if ((x & 0x2000) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0xffffffffffffe9d1bd0105c611c084b4);
    }
    if ((x & 0x4000) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0xffffffffffffd3a37a020b8c256d0547);
    }
    if ((x & 0x8000) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0xffffffffffffa746f40417185289fa0e);
    }
    if ((x & 0x10000) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0xffffffffffff4e8de8082e30c3d3b21b);
    }
    if ((x & 0x20000) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0xfffffffffffe9d1bd0105c6202a65c35);
    }
    if ((x & 0x40000) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0xfffffffffffd3a37a020b8c5f1489862);
    }
    if ((x & 0x80000) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0xfffffffffffa746f404171939280b0a4);
    }
    if ((x & 0x100000) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0xfffffffffff4e8de8082e345e4bf60ca);
    }
    if ((x & 0x200000) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0xffffffffffe9d1bd0105c706c876bfa0);
    }
    if ((x & 0x400000) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0xffffffffffd3a37a020b8ff98ccd776c);
    }
    if ((x & 0x800000) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0xffffffffffa746f4041727a3091acf87);
    }
    if ((x & 0x1000000) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0xffffffffff4e8de8082e6e05d03521c9);
    }
    if ((x & 0x2000000) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0xfffffffffe9d1bd0105d570a98684e54);
    }
    if ((x & 0x4000000) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0xfffffffffd3a37a020bc9a1110c8c656);
    }
    if ((x & 0x8000000) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0xfffffffffa746f404180e411a17228c0);
    }
    if ((x & 0x10000000) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0xfffffffff4e8de80832087e142666c8c);
    }
    if ((x & 0x20000000) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0xffffffffe9d1bd0106bc0eba82d29b40);
    }
    if ((x & 0x40000000) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0xffffffffd3a37a020f641954fda6eedd);
    }
    if ((x & 0x80000000) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0xffffffffa746f40426782229daaa3cfb);
    }
    if ((x & 0x100000000) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0xffffffff4e8de8086bb002532d71e54d);
    }
    if ((x & 0x200000000) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0xfffffffe9d1bd011525efca410b8eab8);
    }
    if ((x & 0x400000000) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0xfffffffd3a37a02490b9d93da3c1ebd0);
    }
    if ((x & 0x800000000) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0xfffffffa746f4050d1633246a8a0e09a);
    }
    if ((x & 0x1000000000) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0xfffffff4e8de80c062846365949b61af);
    }
    if ((x & 0x2000000000) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0xffffffe9d1bd01fbc400bf822dc936b5);
    }
    if ((x & 0x4000000000) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0xffffffd3a37a05e383e14c90273c94f6);
    }
    if ((x & 0x8000000000) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0xffffffa746f41376f74124cd483186d4);
    }
    if ((x & 0x10000000000) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0xffffff4e8de845adac77243cd0914b37);
    }
    if ((x & 0x20000000000) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0xfffffe9d1bd1065a50971275792f1c84);
    }
    if ((x & 0x40000000000) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0xfffffd3a37a3f8b07e7c4871dc00d76f);
    }
    if ((x & 0x80000000000) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0xfffffa746f4fa1506788fbc89750bf71);
    }
    if ((x & 0x100000000000) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0xfffff4e8debe025e24128a3d460731f2);
    }
    if ((x & 0x200000000000) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0xffffe9d1bdf703aef21ea4dcfb0682d8);
    }
    if ((x & 0x400000000000) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0xffffd3a37dda03133bde87a8379c8933);
    }
    if ((x & 0x800000000000) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0xffffa7470363f4515426d76c762b6b62);
    }
    if ((x & 0x1000000000000) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0xffff4e8e25879bfa09ea263360240c1a);
    }
    if ((x & 0x2000000000000) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0xfffe9d1cc60ddab126de1aec4a87e7b9);
    }
    if ((x & 0x4000000000000) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0xfffd3a3b7814eb53cd7629d70fea116a);
    }
    if ((x & 0x8000000000000) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0xfffa747ea0040664238f92f792405806);
    }
    if ((x & 0x10000000000000) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0xfff4e91bff1b8c3d88338e0ebf284a4e);
    }
    if ((x & 0x20000000000000) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0xffe9d2b2f7db2755ddf1d28a378a438c);
    }
    if ((x & 0x40000000000000) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0xffd3a751c0f7e10bd3b9f8ae012fbe07);
    }
    if ((x & 0x80000000000000) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0xffa756521c8daed19f3a1b48fb94c589);
    }
    if ((x & 0x100000000000000) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0xff4ecb59511ec8a5301ba217ef18dd7c);
    }
    if ((x & 0x200000000000000) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0xfe9e115c7b8f884badd25995e79d2f09);
    }
    if ((x & 0x400000000000000) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0xfd3e0c0cf486c174853f3a5931e0ee03);
    }
    if ((x & 0x800000000000000) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0xfa83b2db722a033a7c25bb14315d7fcd);
    }
    if ((x & 0x1000000000000000) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0xf5257d152486cc2c7b9d0c7aed980fc3);
    }
    if ((x & 0x2000000000000000) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0xeac0c6e7dd24392ed02d75b3706e54fb);
    }
    if ((x & 0x4000000000000000) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0xd744fccad69d6af439a68bb9902d3fde);
    }
    if ((x & 0x8000000000000000) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0xb504f333f9de6484597d89b3754abe9f);
    }
    if ((x & 0x10000000000000000) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0x80000000000000000000000000000000);
    }
    if ((x & 0x20000000000000000) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0x40000000000000000000000000000000);
    }
    if ((x & 0x40000000000000000) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0x10000000000000000000000000000000);
    }
    if ((x & 0x80000000000000000) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0x1000000000000000000000000000000);
    }
    if ((x & 0x100000000000000000) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0x10000000000000000000000000000);
    }
    if ((x & 0x200000000000000000) != 0) {
        ratio = internal::unsafe_mul_shift(ratio, 0x1000000000000000000000000);
    }

    if (x != 0) {
        ratio =
            u256 {
                high: 0xffffffffffffffffffffffffffffffff, low: 0xffffffffffffffffffffffffffffffff
            }
            / ratio;
    }

    ratio
}

// Computes the tick corresponding to the price, i.e. log base sqrt(1.000001) of the ratio aligned with the above function s.t. sqrt_ratio_to_tick(tick_to_sqrt_ratio(tick)) == tick
fn sqrt_ratio_to_tick(sqrt_ratio: u256) -> i129 {
    // max price from max tick, exclusive check because this function should never be called on a price equal to max price
    assert(sqrt_ratio < max_sqrt_ratio(), 'SQRT_RATIO_TOO_HIGH');
    // min price from min tick
    assert(sqrt_ratio >= min_sqrt_ratio(), 'SQRT_RATIO_TOO_LOW');

    let (log2_sqrt_ratio, sign) = internal::log2(sqrt_ratio);

    // == 2**64/(log base 2 of tick size)
    // https://www.wolframalpha.com/input?i=floor%28%281%2F+log+base+2+of+%28sqrt%281.000001%29%29%29*2**64%29
    let (high, low) = u128_wide_mul(25572630076711825471857579, log2_sqrt_ratio);

    let tick_mag_x128 = u256 { high, low };

    let error = u256 { low: internal::MAX_ERROR_MAGNITUDE, high: 0 };

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
