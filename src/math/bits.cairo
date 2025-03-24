use core::num::traits::Zero;

// Computes and returns the index of the most significant bit in the given ratio, s.t. ratio >=
// 2**mb(integer)
pub fn msb(mut x: u128) -> u8 {
    assert(x.is_non_zero(), 'MSB_NONZERO');

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
        res += 1;
    }

    res
}

// Return the index of the least set bit
pub fn lsb(x: u128) -> u8 {
    assert(x.is_non_zero(), 'LSB_NONZERO');

    msb((~x + 1) & x)
}
