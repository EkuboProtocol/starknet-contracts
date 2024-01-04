// Returns 2^(n+1) - 1
fn mask(n: u8) -> u128 {
    if (n == 0) {
        return 0x1;
    }
    if (n == 1) {
        return 0x3;
    }
    if (n == 2) {
        return 0x7;
    }
    if (n == 3) {
        return 0xf;
    }
    if (n == 4) {
        return 0x1f;
    }
    if (n == 5) {
        return 0x3f;
    }
    if (n == 6) {
        return 0x7f;
    }
    if (n == 7) {
        return 0xff;
    }
    if (n == 8) {
        return 0x1ff;
    }
    if (n == 9) {
        return 0x3ff;
    }
    if (n == 10) {
        return 0x7ff;
    }
    if (n == 11) {
        return 0xfff;
    }
    if (n == 12) {
        return 0x1fff;
    }
    if (n == 13) {
        return 0x3fff;
    }
    if (n == 14) {
        return 0x7fff;
    }
    if (n == 15) {
        return 0xffff;
    }
    if (n == 16) {
        return 0x1ffff;
    }
    if (n == 17) {
        return 0x3ffff;
    }
    if (n == 18) {
        return 0x7ffff;
    }
    if (n == 19) {
        return 0xfffff;
    }
    if (n == 20) {
        return 0x1fffff;
    }
    if (n == 21) {
        return 0x3fffff;
    }
    if (n == 22) {
        return 0x7fffff;
    }
    if (n == 23) {
        return 0xffffff;
    }
    if (n == 24) {
        return 0x1ffffff;
    }
    if (n == 25) {
        return 0x3ffffff;
    }
    if (n == 26) {
        return 0x7ffffff;
    }
    if (n == 27) {
        return 0xfffffff;
    }
    if (n == 28) {
        return 0x1fffffff;
    }
    if (n == 29) {
        return 0x3fffffff;
    }
    if (n == 30) {
        return 0x7fffffff;
    }
    if (n == 31) {
        return 0xffffffff;
    }
    if (n == 32) {
        return 0x1ffffffff;
    }
    if (n == 33) {
        return 0x3ffffffff;
    }
    if (n == 34) {
        return 0x7ffffffff;
    }
    if (n == 35) {
        return 0xfffffffff;
    }
    if (n == 36) {
        return 0x1fffffffff;
    }
    if (n == 37) {
        return 0x3fffffffff;
    }
    if (n == 38) {
        return 0x7fffffffff;
    }
    if (n == 39) {
        return 0xffffffffff;
    }
    if (n == 40) {
        return 0x1ffffffffff;
    }
    if (n == 41) {
        return 0x3ffffffffff;
    }
    if (n == 42) {
        return 0x7ffffffffff;
    }
    if (n == 43) {
        return 0xfffffffffff;
    }
    if (n == 44) {
        return 0x1fffffffffff;
    }
    if (n == 45) {
        return 0x3fffffffffff;
    }
    if (n == 46) {
        return 0x7fffffffffff;
    }
    if (n == 47) {
        return 0xffffffffffff;
    }
    if (n == 48) {
        return 0x1ffffffffffff;
    }
    if (n == 49) {
        return 0x3ffffffffffff;
    }
    if (n == 50) {
        return 0x7ffffffffffff;
    }
    if (n == 51) {
        return 0xfffffffffffff;
    }
    if (n == 52) {
        return 0x1fffffffffffff;
    }
    if (n == 53) {
        return 0x3fffffffffffff;
    }
    if (n == 54) {
        return 0x7fffffffffffff;
    }
    if (n == 55) {
        return 0xffffffffffffff;
    }
    if (n == 56) {
        return 0x1ffffffffffffff;
    }
    if (n == 57) {
        return 0x3ffffffffffffff;
    }
    if (n == 58) {
        return 0x7ffffffffffffff;
    }
    if (n == 59) {
        return 0xfffffffffffffff;
    }
    if (n == 60) {
        return 0x1fffffffffffffff;
    }
    if (n == 61) {
        return 0x3fffffffffffffff;
    }
    if (n == 62) {
        return 0x7fffffffffffffff;
    }
    if (n == 63) {
        return 0xffffffffffffffff;
    }
    if (n == 64) {
        return 0x1ffffffffffffffff;
    }
    if (n == 65) {
        return 0x3ffffffffffffffff;
    }
    if (n == 66) {
        return 0x7ffffffffffffffff;
    }
    if (n == 67) {
        return 0xfffffffffffffffff;
    }
    if (n == 68) {
        return 0x1fffffffffffffffff;
    }
    if (n == 69) {
        return 0x3fffffffffffffffff;
    }
    if (n == 70) {
        return 0x7fffffffffffffffff;
    }
    if (n == 71) {
        return 0xffffffffffffffffff;
    }
    if (n == 72) {
        return 0x1ffffffffffffffffff;
    }
    if (n == 73) {
        return 0x3ffffffffffffffffff;
    }
    if (n == 74) {
        return 0x7ffffffffffffffffff;
    }
    if (n == 75) {
        return 0xfffffffffffffffffff;
    }
    if (n == 76) {
        return 0x1fffffffffffffffffff;
    }
    if (n == 77) {
        return 0x3fffffffffffffffffff;
    }
    if (n == 78) {
        return 0x7fffffffffffffffffff;
    }
    if (n == 79) {
        return 0xffffffffffffffffffff;
    }
    if (n == 80) {
        return 0x1ffffffffffffffffffff;
    }
    if (n == 81) {
        return 0x3ffffffffffffffffffff;
    }
    if (n == 82) {
        return 0x7ffffffffffffffffffff;
    }
    if (n == 83) {
        return 0xfffffffffffffffffffff;
    }
    if (n == 84) {
        return 0x1fffffffffffffffffffff;
    }
    if (n == 85) {
        return 0x3fffffffffffffffffffff;
    }
    if (n == 86) {
        return 0x7fffffffffffffffffffff;
    }
    if (n == 87) {
        return 0xffffffffffffffffffffff;
    }
    if (n == 88) {
        return 0x1ffffffffffffffffffffff;
    }
    if (n == 89) {
        return 0x3ffffffffffffffffffffff;
    }
    if (n == 90) {
        return 0x7ffffffffffffffffffffff;
    }
    if (n == 91) {
        return 0xfffffffffffffffffffffff;
    }
    if (n == 92) {
        return 0x1fffffffffffffffffffffff;
    }
    if (n == 93) {
        return 0x3fffffffffffffffffffffff;
    }
    if (n == 94) {
        return 0x7fffffffffffffffffffffff;
    }
    if (n == 95) {
        return 0xffffffffffffffffffffffff;
    }
    if (n == 96) {
        return 0x1ffffffffffffffffffffffff;
    }
    if (n == 97) {
        return 0x3ffffffffffffffffffffffff;
    }
    if (n == 98) {
        return 0x7ffffffffffffffffffffffff;
    }
    if (n == 99) {
        return 0xfffffffffffffffffffffffff;
    }
    if (n == 100) {
        return 0x1fffffffffffffffffffffffff;
    }
    if (n == 101) {
        return 0x3fffffffffffffffffffffffff;
    }
    if (n == 102) {
        return 0x7fffffffffffffffffffffffff;
    }
    if (n == 103) {
        return 0xffffffffffffffffffffffffff;
    }
    if (n == 104) {
        return 0x1ffffffffffffffffffffffffff;
    }
    if (n == 105) {
        return 0x3ffffffffffffffffffffffffff;
    }
    if (n == 106) {
        return 0x7ffffffffffffffffffffffffff;
    }
    if (n == 107) {
        return 0xfffffffffffffffffffffffffff;
    }
    if (n == 108) {
        return 0x1fffffffffffffffffffffffffff;
    }
    if (n == 109) {
        return 0x3fffffffffffffffffffffffffff;
    }
    if (n == 110) {
        return 0x7fffffffffffffffffffffffffff;
    }
    if (n == 111) {
        return 0xffffffffffffffffffffffffffff;
    }
    if (n == 112) {
        return 0x1ffffffffffffffffffffffffffff;
    }
    if (n == 113) {
        return 0x3ffffffffffffffffffffffffffff;
    }
    if (n == 114) {
        return 0x7ffffffffffffffffffffffffffff;
    }
    if (n == 115) {
        return 0xfffffffffffffffffffffffffffff;
    }
    if (n == 116) {
        return 0x1fffffffffffffffffffffffffffff;
    }
    if (n == 117) {
        return 0x3fffffffffffffffffffffffffffff;
    }
    if (n == 118) {
        return 0x7fffffffffffffffffffffffffffff;
    }
    if (n == 119) {
        return 0xffffffffffffffffffffffffffffff;
    }
    if (n == 120) {
        return 0x1ffffffffffffffffffffffffffffff;
    }
    if (n == 121) {
        return 0x3ffffffffffffffffffffffffffffff;
    }
    if (n == 122) {
        return 0x7ffffffffffffffffffffffffffffff;
    }
    if (n == 123) {
        return 0xfffffffffffffffffffffffffffffff;
    }
    if (n == 124) {
        return 0x1fffffffffffffffffffffffffffffff;
    }
    if (n == 125) {
        return 0x3fffffffffffffffffffffffffffffff;
    }
    if (n == 126) {
        return 0x7fffffffffffffffffffffffffffffff;
    }
    assert(n == 127, 'mask');
    0xffffffffffffffffffffffffffffffff
}
