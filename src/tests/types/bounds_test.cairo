use core::hash::LegacyHash;
use core::num::traits::Zero;
use crate::math::ticks::{max_tick, min_tick};
use crate::tests::types::keys_test::check_hashes_differ;
use crate::types::bounds::{Bounds, BoundsTrait, max_bounds};
use crate::types::i129::i129;

#[test]
fn test_legacy_hash_bounds() {
    let base: Bounds = max_bounds(1);

    let mut other_lower = base;
    other_lower.lower = i129 { mag: 1, sign: true };

    let mut other_upper = base;
    other_upper.upper = i129 { mag: 1, sign: false };

    check_hashes_differ(base, other_lower);
    check_hashes_differ(base, other_upper);
    check_hashes_differ(other_lower, other_upper);
}

#[test]
fn test_legacy_hash_bounds_result() {
    let mut base: Bounds = max_bounds(1);

    assert(
        LegacyHash::hash(
            1, base,
        ) == 0x6c42881e4742039126ad0a222a95e45a9839da6ca5a57be07d07ef3c5f32813,
        'hash',
    );

    assert(
        LegacyHash::hash(
            2, base,
        ) == 0x1ba5884f70dc5d63515a033ebf4b813de0620a28c1868cec3fc338db27b8f5c,
        'hash',
    );

    base.lower = i129 { mag: 0, sign: false };
    assert(
        LegacyHash::hash(
            2, base,
        ) == 0x12cec395c34e44f4e611bd1d7a6063fa101cb17f8bc8e81c59a37fca4650cf8,
        'hash',
    );

    base.lower = i129 { mag: 0, sign: true };
    assert(
        LegacyHash::hash(
            2, base,
        ) == 0x12cec395c34e44f4e611bd1d7a6063fa101cb17f8bc8e81c59a37fca4650cf8,
        'hash',
    );

    base.upper = i129 { mag: 1, sign: true };
    assert(
        LegacyHash::hash(
            2, base,
        ) == 0x6a3c9bc74cf8b0759a66e4d6ba6e7ee61509a00539fdcd67b951ae1cdac6a9e,
        'hash',
    );
}


#[test]
fn test_check_valid_succeeds_default_1() {
    max_bounds(1).check_valid(1);
}

#[test]
#[should_panic(expected: ('BOUNDS_TICK_SPACING',))]
fn test_check_valid_fails_default_123() {
    max_bounds(1).check_valid(123);
}

#[test]
#[should_panic(expected: ('BOUNDS_ORDER',))]
fn test_check_valid_fails_zero() {
    Bounds { lower: Zero::zero(), upper: Zero::zero() }.check_valid(123);
}

#[test]
#[should_panic(expected: ('BOUNDS_MAX',))]
fn test_check_valid_fails_exceed_max_tick() {
    Bounds { lower: Zero::zero(), upper: max_tick() + i129 { mag: 1, sign: false } }.check_valid(1);
}


#[test]
#[should_panic(expected: ('BOUNDS_MIN',))]
fn test_check_valid_fails_below_min_tick() {
    Bounds { lower: min_tick() - i129 { mag: 1, sign: false }, upper: Zero::zero() }.check_valid(1);
}

#[test]
#[should_panic(expected: ('BOUNDS_TICK_SPACING',))]
fn test_check_valid_fails_tick_spacing_both() {
    Bounds { lower: i129 { mag: 1, sign: true }, upper: i129 { mag: 1, sign: false } }
        .check_valid(2);
}

#[test]
#[should_panic(expected: ('BOUNDS_TICK_SPACING',))]
fn test_check_valid_fails_tick_spacing_lower() {
    Bounds { lower: i129 { mag: 1, sign: true }, upper: i129 { mag: 2, sign: false } }
        .check_valid(2);
}

#[test]
#[should_panic(expected: ('BOUNDS_TICK_SPACING',))]
fn test_check_valid_fails_tick_spacing_upper() {
    Bounds { lower: i129 { mag: 2, sign: true }, upper: i129 { mag: 1, sign: false } }
        .check_valid(2);
}

#[test]
fn test_check_valid_tick_spacing_matches() {
    Bounds { lower: i129 { mag: 2, sign: true }, upper: i129 { mag: 2, sign: false } }
        .check_valid(2);
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
#[should_panic(expected: ('MAX_BOUNDS_TICK_SPACING_LARGE',))]
fn test_max_bounds_max_plus_one() {
    max_bounds(88722884);
}

#[test]
#[should_panic(expected: ('MAX_BOUNDS_TICK_SPACING_ZERO',))]
fn test_max_bounds_zero() {
    max_bounds(0);
}
