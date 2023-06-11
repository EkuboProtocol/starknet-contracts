use ekubo::math::mask::{mask_big, mask};

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


#[test]
fn test_mask_big_128() {
    assert(mask_big(128) == u256 { high: 1, low: 0xffffffffffffffffffffffffffffffff }, 'mask');
}

#[test]
fn test_mask_big_255() {
    assert(
        mask_big(255) == u256 {
            high: 0xffffffffffffffffffffffffffffffff, low: 0xffffffffffffffffffffffffffffffff
        },
        'mask'
    );
}
