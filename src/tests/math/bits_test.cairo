use crate::math::bits::{lsb, msb};

#[test]
#[should_panic(expected: ('MSB_NONZERO',))]
fn msb_0_panics() {
    msb(0);
}

#[test]
#[should_panic(expected: ('LSB_NONZERO',))]
fn lsb_0_panics() {
    lsb(0);
}


#[test]
fn msb_1() {
    let res = msb(1);
    assert(res == 0_u8, 'msb of one is zero');
}

#[test]
fn lsb_1() {
    let res = lsb(1);
    assert(res == 0_u8, 'lsb');
}

#[test]
fn lsb_2() {
    let res = lsb(2);
    assert(res == 1_u8, 'lsb');
}

#[test]
fn lsb_3() {
    let res = lsb(3);
    assert(res == 0_u8, 'lsb');
}

#[test]
fn lsb_2_127_plus_one() {
    let res = lsb(0x80000000000000000000000000000001);
    assert(res == 0_u8, 'lsb');
}

#[test]
fn lsb_2_127_plus_two() {
    let res = lsb(0x80000000000000000000000000000002);
    assert(res == 1_u8, 'lsb');
}

#[test]
fn msb_2() {
    let res = msb(2);
    assert(res == 1_u8, 'msb of two is one');
}

#[test]
fn msb_3() {
    let res = msb(3);
    assert(res == 1_u8, 'msb of three is one');
}

#[test]
fn msb_4() {
    let res = msb(4);
    assert(res == 2_u8, 'msb of four is two');
}


#[test]
fn msb_high_plus_four() {
    let res = msb(0x80000000000000000000000000000004);
    assert(res == 127, 'msb of 2**127 + 4 is 127');
}

#[test]
fn msb_2_96_less_one() {
    let res = msb(0xffffffffffffffffffffffff);
    assert(res == 95, 'msb of 2**96 - 1 == 95');
}

#[test]
fn msb_many_iterations_min_gas() {
    let mut i: u128 = 0;
    while (i != 1024) {
        msb(i + 1);

        i += 1;
    };
}


#[test]
fn msb_max() {
    let res = msb(0xffffffffffffffffffffffffffffffff);
    assert(res == 127, 'msb of max u128');
}

#[test]
fn lsb_max() {
    let res = lsb(0xffffffffffffffffffffffffffffffff);
    assert(res == 0, 'lsb of max u128');
}

