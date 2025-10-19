use crate::math::mask::mask;

#[test]
fn test_mask_0() {
    assert(mask(0) == 1, 'mask');
}

#[test]
fn test_mask_1() {
    assert(mask(1) == 3, 'mask');
}

#[test]
fn test_mask_2() {
    assert(mask(2) == 7, 'mask');
}

#[test]
fn test_mask_3() {
    assert(mask(3) == 15, 'mask');
}

#[test]
fn test_mask_4() {
    assert(mask(4) == 31, 'mask');
}

#[test]
fn test_mask_126() {
    assert(mask(126) == 0x7fffffffffffffffffffffffffffffff, 'mask');
}

#[test]
fn test_mask_127() {
    assert(mask(127) == 0xffffffffffffffffffffffffffffffff, 'mask');
}

#[test]
#[should_panic(expected: ('mask',))]
fn test_mask_128() {
    mask(128);
}

#[test]
#[should_panic(expected: ('mask',))]
fn test_mask_129() {
    mask(129);
}

#[test]
#[should_panic(expected: ('mask',))]
fn test_mask_255() {
    mask(255);
}
