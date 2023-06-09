use ekubo::math::exp2::{exp2, exp2_big};

// Computes and returns the index of the most significant bit in the given ratio, s.t. ratio >= 2**msb(ratio)
fn msb(x: u256) -> u8 {
    assert(x != u256 { high: 0, low: 0 }, 'MSB_NONZERO');

    let (mut res, mut rem) = if x.high == 0 {
        (0, x.low)
    } else {
        (128, x.high)
    };

    if (rem >= 0x10000000000000000) {
        rem /= 0x10000000000000000;
        res += 64;
    }
    if (rem >= 0x100000000) {
        rem /= 0x100000000;
        res += 32;
    }
    if (rem >= 0x10000) {
        rem /= 0x10000;
        res += 16;
    }
    if (rem >= 0x100) {
        rem /= 0x100;
        res += 8;
    }
    if (rem >= 0x10) {
        rem /= 0x10;
        res += 4;
    }
    if (rem >= 0x04) {
        rem /= 4;
        res += 2;
    }
    if (rem >= 0x02) {
        rem /= 2;
        res += 1;
    }
    return res;
}

// Computes x>>n
#[inline(always)]
fn shr(n: u8, x: u128) -> u128 {
    x / exp2(n)
}

// Computes x>>n
#[inline(always)]
fn shr_big(n: u8, x: u256) -> u256 {
    x / exp2_big(n)
}
