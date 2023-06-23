use ekubo::types::bounds::{CheckBoundsValidTrait, Bounds, max_bounds};
use ekubo::types::i129::i129;
use ekubo::math::ticks::{max_tick, min_tick};

#[test]
fn test_check_valid_succeeds_default_1() {
    Default::<Bounds>::default().check_valid(1);
}

#[test]
#[should_panic(expected: ('BOUNDS_TICK_SPACING', ))]
fn test_check_valid_fails_default_123() {
    Default::<Bounds>::default().check_valid(123);
}

#[test]
#[should_panic(expected: ('BOUNDS_ORDER', ))]
fn test_check_valid_fails_zero() {
    Bounds { lower: Zeroable::zero(), upper: Zeroable::zero() }.check_valid(123);
}

#[test]
#[should_panic(expected: ('BOUNDS_MAX', ))]
fn test_check_valid_fails_exceed_max_tick() {
    Bounds {
        lower: Zeroable::zero(), upper: max_tick() + i129 { mag: 1, sign: false }
    }.check_valid(1);
}


#[test]
#[should_panic(expected: ('BOUNDS_MIN', ))]
fn test_check_valid_fails_below_min_tick() {
    Bounds {
        lower: min_tick() - i129 { mag: 1, sign: false }, upper: Zeroable::zero()
    }.check_valid(1);
}

#[test]
#[should_panic(expected: ('BOUNDS_TICK_SPACING', ))]
fn test_check_valid_fails_tick_spacing_both() {
    Bounds {
        lower: i129 { mag: 1, sign: true }, upper: i129 { mag: 1, sign: false }
    }.check_valid(2);
}

#[test]
#[should_panic(expected: ('BOUNDS_TICK_SPACING', ))]
fn test_check_valid_fails_tick_spacing_lower() {
    Bounds {
        lower: i129 { mag: 1, sign: true }, upper: i129 { mag: 2, sign: false }
    }.check_valid(2);
}

#[test]
#[should_panic(expected: ('BOUNDS_TICK_SPACING', ))]
fn test_check_valid_fails_tick_spacing_upper() {
    Bounds {
        lower: i129 { mag: 2, sign: true }, upper: i129 { mag: 1, sign: false }
    }.check_valid(2);
}

#[test]
fn test_check_valid_tick_spacing_matches() {
    Bounds {
        lower: i129 { mag: 2, sign: true }, upper: i129 { mag: 2, sign: false }
    }.check_valid(2);
}

#[test]
fn test_default_bounds() {
    let bounds: Bounds = Default::default();
    assert(bounds.lower == min_tick(), 'min');
    assert(bounds.upper == max_tick(), 'max');
}

#[test]
fn test_max_bounds_1_spacing() {
    let bounds = max_bounds(1);
    assert(bounds.lower == min_tick(), 'min');
    assert(bounds.upper == max_tick(), 'max');
}

#[test]
fn test_max_bounds_2_spacing() {
    let bounds = max_bounds(2);
    assert(bounds.lower == i129 { mag: 88722882, sign: true }, 'min');
    assert(bounds.upper == i129 { mag: 88722882, sign: false }, 'max');
}

#[test]
fn test_max_bounds_max_spacing() {
    let bounds = max_bounds(88722883);
    assert(bounds.lower == i129 { mag: 88722883, sign: true }, 'min');
    assert(bounds.upper == i129 { mag: 88722883, sign: false }, 'max');
}

#[test]
fn test_max_bounds_max_minus_one_spacing() {
    let bounds = max_bounds(88722882);
    assert(bounds.lower == i129 { mag: 88722882, sign: true }, 'min');
    assert(bounds.upper == i129 { mag: 88722882, sign: false }, 'max');
}

#[test]
#[should_panic(expected: ('MAX_BOUNDS_TICK_SPACING_LARGE', ))]
fn test_max_bounds_max_plus_one() {
    max_bounds(88722884);
}

#[test]
#[should_panic(expected: ('MAX_BOUNDS_TICK_SPACING_ZERO', ))]
fn test_max_bounds_zero() {
    max_bounds(0);
}
