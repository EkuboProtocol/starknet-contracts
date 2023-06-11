use ekubo::math::exp2::{exp2, exp2_big};

// Computes and returns the index of the most significant bit in the given ratio, s.t. ratio >= 2**mb(integer)
fn msb_low(mut x: u128) -> u8 {
    assert(x != 0, 'MSB_NONZERO');

    let mut res: u8 = 0;
    if (x >= 0x10000000000000000) {
        x /= 0x10000000000000000;
        res += 64;
    }
    if (x >= 0x100000000) {
        x /= 0x100000000;
        res += 32;
    }
    if (x >= 0x10000) {
        x /= 0x10000;
        res += 16;
    }
    if (x >= 0x100) {
        x /= 0x100;
        res += 8;
    }
    if (x >= 0x10) {
        x /= 0x10;
        res += 4;
    }
    if (x >= 0x04) {
        x /= 4;
        res += 2;
    }
    if (x >= 0x02) {
        x /= 2;
        res += 1;
    }

    res
}

// Computes and returns the index of the most significant bit in the given integer, s.t. ratio >= 2**msb(integer)
fn msb(x: u256) -> u8 {
    if x.high == 0 {
        msb_low(x.low)
    } else {
        128_u8 + msb_low(x.high)
    }
}


impl NegU128 of Neg<u128> {
    #[inline]
    fn neg(a: u128) -> u128 {
        if (a == 0) {
            0
        } else {
            (0xffffffffffffffffffffffffffffffff - a) + 1
        }
    }
}

// Return the index of the least set bit
fn lsb_low(x: u128) -> u8 {
    // errors if x == 0
    msb_low((-x) & x)
}

// Return the index of the least set bit
fn lsb(x: u256) -> u8 {
    if (x.low == 0) {
        // if high is 0, this will revert
        128 + lsb_low(x.high)
    } else {
        lsb_low(x.low)
    }
}
