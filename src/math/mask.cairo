// Returns 2**n
fn mask(n: u8) -> u128 {
    assert(n < 128, 'mask');
    if (n == 0) {
        0x1
    } else if (n == 1) {
        0x3
    } else if (n == 2) {
        0x7
    } else if (n == 3) {
        0xf
    } else if (n == 4) {
        0x1f
    } else if (n == 5) {
        0x3f
    } else if (n == 6) {
        0x7f
    } else if (n == 7) {
        0xff
    } else if (n == 8) {
        0x1ff
    } else if (n == 9) {
        0x3ff
    } else if (n == 10) {
        0x7ff
    } else if (n == 11) {
        0xfff
    } else if (n == 12) {
        0x1fff
    } else if (n == 13) {
        0x3fff
    } else if (n == 14) {
        0x7fff
    } else if (n == 15) {
        0xffff
    } else if (n == 16) {
        0x1ffff
    } else if (n == 17) {
        0x3ffff
    } else if (n == 18) {
        0x7ffff
    } else if (n == 19) {
        0xfffff
    } else if (n == 20) {
        0x1fffff
    } else if (n == 21) {
        0x3fffff
    } else if (n == 22) {
        0x7fffff
    } else if (n == 23) {
        0xffffff
    } else if (n == 24) {
        0x1ffffff
    } else if (n == 25) {
        0x3ffffff
    } else if (n == 26) {
        0x7ffffff
    } else if (n == 27) {
        0xfffffff
    } else if (n == 28) {
        0x1fffffff
    } else if (n == 29) {
        0x3fffffff
    } else if (n == 30) {
        0x7fffffff
    } else if (n == 31) {
        0xffffffff
    } else if (n == 32) {
        0x1ffffffff
    } else if (n == 33) {
        0x3ffffffff
    } else if (n == 34) {
        0x7ffffffff
    } else if (n == 35) {
        0xfffffffff
    } else if (n == 36) {
        0x1fffffffff
    } else if (n == 37) {
        0x3fffffffff
    } else if (n == 38) {
        0x7fffffffff
    } else if (n == 39) {
        0xffffffffff
    } else if (n == 40) {
        0x1ffffffffff
    } else if (n == 41) {
        0x3ffffffffff
    } else if (n == 42) {
        0x7ffffffffff
    } else if (n == 43) {
        0xfffffffffff
    } else if (n == 44) {
        0x1fffffffffff
    } else if (n == 45) {
        0x3fffffffffff
    } else if (n == 46) {
        0x7fffffffffff
    } else if (n == 47) {
        0xffffffffffff
    } else if (n == 48) {
        0x1ffffffffffff
    } else if (n == 49) {
        0x3ffffffffffff
    } else if (n == 50) {
        0x7ffffffffffff
    } else if (n == 51) {
        0xfffffffffffff
    } else if (n == 52) {
        0x1fffffffffffff
    } else if (n == 53) {
        0x3fffffffffffff
    } else if (n == 54) {
        0x7fffffffffffff
    } else if (n == 55) {
        0xffffffffffffff
    } else if (n == 56) {
        0x1ffffffffffffff
    } else if (n == 57) {
        0x3ffffffffffffff
    } else if (n == 58) {
        0x7ffffffffffffff
    } else if (n == 59) {
        0xfffffffffffffff
    } else if (n == 60) {
        0x1fffffffffffffff
    } else if (n == 61) {
        0x3fffffffffffffff
    } else if (n == 62) {
        0x7fffffffffffffff
    } else if (n == 63) {
        0xffffffffffffffff
    } else if (n == 64) {
        0x1ffffffffffffffff
    } else if (n == 65) {
        0x3ffffffffffffffff
    } else if (n == 66) {
        0x7ffffffffffffffff
    } else if (n == 67) {
        0xfffffffffffffffff
    } else if (n == 68) {
        0x1fffffffffffffffff
    } else if (n == 69) {
        0x3fffffffffffffffff
    } else if (n == 70) {
        0x7fffffffffffffffff
    } else if (n == 71) {
        0xffffffffffffffffff
    } else if (n == 72) {
        0x1ffffffffffffffffff
    } else if (n == 73) {
        0x3ffffffffffffffffff
    } else if (n == 74) {
        0x7ffffffffffffffffff
    } else if (n == 75) {
        0xfffffffffffffffffff
    } else if (n == 76) {
        0x1fffffffffffffffffff
    } else if (n == 77) {
        0x3fffffffffffffffffff
    } else if (n == 78) {
        0x7fffffffffffffffffff
    } else if (n == 79) {
        0xffffffffffffffffffff
    } else if (n == 80) {
        0x1ffffffffffffffffffff
    } else if (n == 81) {
        0x3ffffffffffffffffffff
    } else if (n == 82) {
        0x7ffffffffffffffffffff
    } else if (n == 83) {
        0xfffffffffffffffffffff
    } else if (n == 84) {
        0x1fffffffffffffffffffff
    } else if (n == 85) {
        0x3fffffffffffffffffffff
    } else if (n == 86) {
        0x7fffffffffffffffffffff
    } else if (n == 87) {
        0xffffffffffffffffffffff
    } else if (n == 88) {
        0x1ffffffffffffffffffffff
    } else if (n == 89) {
        0x3ffffffffffffffffffffff
    } else if (n == 90) {
        0x7ffffffffffffffffffffff
    } else if (n == 91) {
        0xfffffffffffffffffffffff
    } else if (n == 92) {
        0x1fffffffffffffffffffffff
    } else if (n == 93) {
        0x3fffffffffffffffffffffff
    } else if (n == 94) {
        0x7fffffffffffffffffffffff
    } else if (n == 95) {
        0xffffffffffffffffffffffff
    } else if (n == 96) {
        0x1ffffffffffffffffffffffff
    } else if (n == 97) {
        0x3ffffffffffffffffffffffff
    } else if (n == 98) {
        0x7ffffffffffffffffffffffff
    } else if (n == 99) {
        0xfffffffffffffffffffffffff
    } else if (n == 100) {
        0x1fffffffffffffffffffffffff
    } else if (n == 101) {
        0x3fffffffffffffffffffffffff
    } else if (n == 102) {
        0x7fffffffffffffffffffffffff
    } else if (n == 103) {
        0xffffffffffffffffffffffffff
    } else if (n == 104) {
        0x1ffffffffffffffffffffffffff
    } else if (n == 105) {
        0x3ffffffffffffffffffffffffff
    } else if (n == 106) {
        0x7ffffffffffffffffffffffffff
    } else if (n == 107) {
        0xfffffffffffffffffffffffffff
    } else if (n == 108) {
        0x1fffffffffffffffffffffffffff
    } else if (n == 109) {
        0x3fffffffffffffffffffffffffff
    } else if (n == 110) {
        0x7fffffffffffffffffffffffffff
    } else if (n == 111) {
        0xffffffffffffffffffffffffffff
    } else if (n == 112) {
        0x1ffffffffffffffffffffffffffff
    } else if (n == 113) {
        0x3ffffffffffffffffffffffffffff
    } else if (n == 114) {
        0x7ffffffffffffffffffffffffffff
    } else if (n == 115) {
        0xfffffffffffffffffffffffffffff
    } else if (n == 116) {
        0x1fffffffffffffffffffffffffffff
    } else if (n == 117) {
        0x3fffffffffffffffffffffffffffff
    } else if (n == 118) {
        0x7fffffffffffffffffffffffffffff
    } else if (n == 119) {
        0xffffffffffffffffffffffffffffff
    } else if (n == 120) {
        0x1ffffffffffffffffffffffffffffff
    } else if (n == 121) {
        0x3ffffffffffffffffffffffffffffff
    } else if (n == 122) {
        0x7ffffffffffffffffffffffffffffff
    } else if (n == 123) {
        0xfffffffffffffffffffffffffffffff
    } else if (n == 124) {
        0x1fffffffffffffffffffffffffffffff
    } else if (n == 125) {
        0x3fffffffffffffffffffffffffffffff
    } else if (n == 126) {
        0x7fffffffffffffffffffffffffffffff
    } else {
        0xffffffffffffffffffffffffffffffff
    }
}

