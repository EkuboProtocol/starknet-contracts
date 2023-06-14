use ekubo::types::bounds::{CheckBoundsValidTrait, Bounds};
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
    Bounds { tick_lower: Default::default(), tick_upper: Default::default() }.check_valid(123);
}

#[test]
#[should_panic(expected: ('BOUNDS_MAX', ))]
fn test_check_valid_fails_exceed_max_tick() {
    Bounds {
        tick_lower: Default::default(), tick_upper: max_tick() + i129 { mag: 1, sign: false }
    }.check_valid(1);
}


#[test]
#[should_panic(expected: ('BOUNDS_MIN', ))]
fn test_check_valid_fails_below_min_tick() {
    Bounds {
        tick_lower: min_tick() - i129 { mag: 1, sign: false }, tick_upper: Default::default()
    }.check_valid(1);
}

#[test]
#[should_panic(expected: ('BOUNDS_TICK_SPACING', ))]
fn test_check_valid_fails_tick_spacing_both() {
    Bounds {
        tick_lower: i129 { mag: 1, sign: true }, tick_upper: i129 { mag: 1, sign: false }
    }.check_valid(2);
}

#[test]
#[should_panic(expected: ('BOUNDS_TICK_SPACING', ))]
fn test_check_valid_fails_tick_spacing_lower() {
    Bounds {
        tick_lower: i129 { mag: 1, sign: true }, tick_upper: i129 { mag: 2, sign: false }
    }.check_valid(2);
}

#[test]
#[should_panic(expected: ('BOUNDS_TICK_SPACING', ))]
fn test_check_valid_fails_tick_spacing_upper() {
    Bounds {
        tick_lower: i129 { mag: 2, sign: true }, tick_upper: i129 { mag: 1, sign: false }
    }.check_valid(2);
}

#[test]
fn test_check_valid_tick_spacing_matches() {
    Bounds {
        tick_lower: i129 { mag: 2, sign: true }, tick_upper: i129 { mag: 2, sign: false }
    }.check_valid(2);
}
