use ekubo::math::bits::{msb, shr_big,lsb,lsb_low};

#[test]
#[should_panic(expected: ('MSB_NONZERO', ))]
fn msb_0_panics() {
    msb(u256 { high: 0, low: 0 });
}

#[test]
#[should_panic(expected: ('MSB_NONZERO', ))]
fn lsb_0_panics() {
    lsb(u256 { high: 0, low: 0 });
}


#[test]
fn msb_1() {
    let res = msb(u256 { high: 0, low: 1 });
    assert(res == 0_u8, 'msb of one is zero');
}

#[test]
fn lsb_1() {
    let res = lsb(u256 { high: 0, low: 1 });
    assert(res == 0_u8, 'lsb');
}

#[test]
fn lsb_2() {
    let res = lsb(u256 { high: 0, low: 2 });
    assert(res == 1_u8, 'lsb');
}

#[test]
fn lsb_3() {
    let res = lsb(u256 { high: 0, low: 3 });
    assert(res == 0_u8, 'lsb');
}

#[test]
fn lsb_2_128() {
    let res = lsb(u256 { high: 1, low: 0 });
    assert(res == 128_u8, 'lsb');
}

#[test]
fn lsb_2_128_plus_one() {
    let res = lsb(u256 { high: 1, low: 1 });
    assert(res == 0_u8, 'lsb');
}

#[test]
fn lsb_2_128_plus_two() {
    let res = lsb(u256 { high: 1, low: 2 });
    assert(res == 1_u8, 'lsb');
}

#[test]
fn lsb_2_255() {
    let res = lsb(u256 { high: 0x80000000000000000000000000000000, low: 0 });
    assert(res == 255_u8, 'lsb');
}

#[test]
fn lsb_2_255_plus_one() {
    let res = lsb(u256 { high: 0x80000000000000000000000000000000, low: 1 });
    assert(res == 0_u8, 'lsb');
}

#[test]
fn lsb_2_255_plus_one_high() {
    let res = lsb(u256 { high: 0x80000000000000000000000000000001, low: 0 });
    assert(res == 128_u8, 'lsb');
}

#[test]
fn msb_2() {
    let res = msb(u256 { high: 0, low: 2 });
    assert(res == 1_u8, 'msb of two is one');
}

#[test]
fn msb_3() {
    let res = msb(u256 { high: 0, low: 3 });
    assert(res == 1_u8, 'msb of three is one');
}

#[test]
fn msb_4() {
    let res = msb(u256 { high: 0, low: 4 });
    assert(res == 2_u8, 'msb of four is two');
}

#[test]
fn msb_high() {
    let res = msb(u256 { high: 1, low: 0 });
    assert(res == 128, 'msb of 2**128 is 128');
}

#[test]
fn msb_high_plus_four() {
    let res = msb(u256 { high: 1, low: 4 });
    assert(res == 128, 'msb of 2**128 + 4 is 128');
}

#[test]
fn msb_2_96_less_one() {
    let res = msb(u256 { high: 0, low: 79228162514264337589248983040 });
    assert(res == 95, 'msb of 2**96 - a bit == 95');
}

#[test]
fn msb_2_255() {
    let res = msb(u256 { high: 0x80000000000000000000000000000000, low: 0 });
    assert(res == 255, 'msb of 2**255 is 255');
}

#[test]
fn msb_2_255_plus_one() {
    let res = msb(u256 { high: 0x80000000000000000000000000000000, low: 1 });
    assert(res == 255, 'msb of 2**255 + 1 is 255');
}

#[test]
#[available_gas(78000000)]
fn msb_many_iterations_min_gas() {
    let mut i: u128 = 0;
    loop {
        if (i == 1024) {
            break ();
        }

        if ((i % 2) == 0) {
            msb(u256 { high: i + 1, low: 0 });
        } else {
            msb(u256 { high: 0, low: i + 1 });
        };

        i += 1;
    };
}


#[test]
fn msb_max() {
    let res = msb(
        u256 { high: 0xffffffffffffffffffffffffffffffff, low: 0xffffffffffffffffffffffffffffffff }
    );
    assert(res == 255, 'msb of max uint256');
}

#[test]
fn msb_min_value_max() {
    let res = msb(u256 { high: 0x80000000000000000000000000000000, low: 0 });
    assert(res == 255, 'msb of max');
}


#[test]
fn test_shr_big_0_0() {
    assert(shr_big(0, u256 { high: 0, low: 0 }) == u256 { high: 0, low: 0 }, '0 >> 0 == 0');
}


#[test]
fn test_shr_big_1_0() {
    assert(shr_big(1, u256 { high: 0, low: 0 }) == u256 { high: 0, low: 0 }, '0 >> 1 == 0');
}

#[test]
fn test_shr_big_255_0() {
    assert(shr_big(255, u256 { high: 0, low: 0 }) == u256 { high: 0, low: 0 }, '0 >> 255 == 0');
}

#[test]
fn test_shr_big_255_max() {
    assert(
        shr_big(
            255,
            u256 {
                high: 0xffffffffffffffffffffffffffffffff, low: 0xffffffffffffffffffffffffffffffff
            }
        ) == u256 {
            high: 0, low: 1
        },
        'max >> 255 == 1'
    );
}
