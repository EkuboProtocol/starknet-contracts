use ekubo::math::mask::{mask};

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
#[should_panic(expected: ('mask', ))]
fn test_mask_128() {
    mask(128);
}
