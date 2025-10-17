use crate::math::exp2::exp2;

#[test]
fn test_exp2_0() {
    assert(exp2(0) == 0x1, '2**0');
}

#[test]
fn test_exp2_1() {
    assert(exp2(1) == 0x2, '2**1');
}

#[test]
fn test_exp2_2() {
    assert(exp2(2) == 0x4, '2**2');
}

#[test]
fn test_exp2_3() {
    assert(exp2(3) == 0x8, '2**3');
}

#[test]
fn test_exp2_4() {
    assert(exp2(4) == 0x10, '2**4');
}

#[test]
fn test_exp2_64() {
    assert(exp2(64) == 0x10000000000000000, '2**64');
}

#[test]
fn test_exp2_126() {
    assert(exp2(126) == 0x40000000000000000000000000000000, '2**126');
}

#[test]
fn test_exp2_127() {
    assert(exp2(127) == 0x80000000000000000000000000000000, '2**127');
}

#[test]
#[should_panic(expected: ('exp2',))]
fn test_exp2_128() {
    exp2(128);
}

#[test]
#[should_panic(expected: ('exp2',))]
fn test_exp2_129() {
    exp2(129);
}

#[test]
#[should_panic(expected: ('exp2',))]
fn test_exp2_255() {
    exp2(255);
}

