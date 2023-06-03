use ekubo::math::exp2::exp2;

#[test]
fn test_exp2_0() {
    assert(exp2(0) == u256 { high: 0, low: 1 }, '2**0 == 1');
}

#[test]
fn test_exp2_1() {
    assert(exp2(1) == u256 { high: 0, low: 2 }, '2**1 == 2');
}

#[test]
fn test_exp2_2() {
    assert(exp2(2) == u256 { high: 0, low: 4 }, '2**2 == 4');
}

#[test]
fn test_exp2_3() {
    assert(exp2(3) == u256 { high: 0, low: 8 }, '2**3 == 8');
}

#[test]
fn test_exp2_64() {
    assert(exp2(64) == u256 { high: 0, low: 18446744073709551616 }, '2**64');
}

#[test]
fn test_exp2_127() {
    assert(exp2(127) == u256 { high: 0, low: 170141183460469231731687303715884105728 }, '2**127');
}

#[test]
fn test_exp2_128() {
    assert(exp2(128) == u256 { high: 1, low: 0 }, '2**128');
}

#[test]
fn test_exp2_255() {
    assert(exp2(255) == u256 { high: 0x80000000000000000000000000000000, low: 0 }, '2**128');
}
