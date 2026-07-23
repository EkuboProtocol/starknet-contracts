use core::num::traits::Zero;
use core::option::OptionTrait;
use crate::math::bitmap::{
    Bitmap, BitmapTrait, tick_to_word_and_bit_index, word_and_bit_index_to_tick,
};
use crate::types::i129::i129;

fn bit_is_set(value: u256, index: u8) -> bool {
    if index < 128 {
        (value.low & crate::math::exp2::exp2(index)).is_non_zero()
    } else {
        (value.high & crate::math::exp2::exp2(index - 128)).is_non_zero()
    }
}

#[test]
#[fuzzer]
fn fuzz_bitmap_search_matches_linear_reference(value: felt252, index_seed: u8) {
    let bitmap = Bitmap { value };
    let value_u256: u256 = value.into();
    let index = index_seed % 251;

    let mut expected_next = Option::None(());
    let mut i = 0;
    while i <= index {
        if bit_is_set(value_u256, i) {
            expected_next = Option::Some(i);
        }
        i += 1;
    }

    let mut expected_prev = Option::None(());
    i = index;
    while i < 251 {
        if bit_is_set(value_u256, i) {
            expected_prev = Option::Some(i);
            break;
        }
        i += 1;
    }

    assert_eq!(bitmap.next_set_bit(index), expected_next);
    assert_eq!(bitmap.prev_set_bit(index), expected_prev);
}

#[test]
#[fuzzer]
fn fuzz_set_unset_bit_round_trip(index_seed: u8) {
    let index = index_seed % 251;
    let empty: Bitmap = Zero::zero();
    let set = empty.set_bit(index);

    assert(set.is_non_zero(), 'bit set');
    assert_eq!(set.next_set_bit(index), Option::Some(index));
    assert_eq!(set.prev_set_bit(index), Option::Some(index));
    assert(set.unset_bit(index) == empty, 'round trip');
}

#[test]
#[fuzzer]
fn fuzz_tick_word_and_bit_round_trip(
    tick_magnitude_seed: u128, sign: bool, tick_spacing_seed: u32,
) {
    let tick_spacing: u128 = (tick_spacing_seed % 354892).into() + 1;
    let tick = i129 { mag: tick_magnitude_seed % 88722884, sign };
    let (word, bit) = tick_to_word_and_bit_index(tick, tick_spacing);
    let mapped_tick = word_and_bit_index_to_tick((word, bit), tick_spacing);

    assert(mapped_tick <= tick, 'mapped tick <= input');
    assert(tick - mapped_tick < i129 { mag: tick_spacing, sign: false }, 'within spacing');
    assert_eq!(tick_to_word_and_bit_index(mapped_tick, tick_spacing), (word, bit));
}

#[test]
fn test_zeroable() {
    let b: Bitmap = Zero::zero();
    assert(b.is_zero(), 'is_zero');
    assert(!b.is_non_zero(), 'is_non_ero');
    assert(b.value.is_zero(), 'value.is_zero');
    assert(!Bitmap { value: 1 }.is_zero(), 'one is nonzero');
    assert(Bitmap { value: 1 }.is_non_zero(), 'one is nonzero');
}

#[test]
fn test_set_all_bits() {
    let mut b: Bitmap = Zero::zero();
    let mut i: u8 = 0;
    while (i != 251) {
        b = b.set_bit(i);

        i += 1;
    }

    i = 0;
    while i != 251 {
        b = b.unset_bit(i);

        i += 1;
    }

    assert(b.is_zero(), 'b.is_zero')
}

#[test]
fn test_set_bit() {
    assert(Bitmap { value: 0 }.set_bit(0) == Bitmap { value: 1 }, 'set 0');
    assert(Bitmap { value: 0 }.set_bit(1) == Bitmap { value: 2 }, 'set 1');
    assert(
        Bitmap { value: 0 }.set_bit(128) == Bitmap { value: 0x100000000000000000000000000000000 },
        'set 128',
    );
    assert(
        Bitmap { value: 0 }
            .set_bit(128)
            .set_bit(129) == Bitmap { value: 0x300000000000000000000000000000000 },
        'set 128/129',
    );
    assert(
        Bitmap { value: 0 }
            .set_bit(128)
            .set_bit(129)
            .unset_bit(128) == Bitmap { value: 0x200000000000000000000000000000000 },
        'set 128/129 - unset 128',
    );
    assert(
        Bitmap { value: 0 }
            .set_bit(
                250,
            ) == Bitmap {
                value: 0x400000000000000000000000000000000000000000000000000000000000000,
            },
        'set 250',
    );

    assert(Bitmap { value: 0 }.set_bit(250).unset_bit(250) == Bitmap { value: 0 }, 'set/unset 251');
    assert(
        Bitmap { value: 0 }.set_bit(0).set_bit(0) == Bitmap { value: 2 }, 'set 0 twice sets next',
    );
    assert(Bitmap { value: 0 }.set_bit(0).unset_bit(0) == Bitmap { value: 0 }, 'set/unset 0');
    assert(Bitmap { value: 5 }.set_bit(0).unset_bit(0) == Bitmap { value: 5 }, 'set/unset 0');
}

#[test]
#[should_panic(expected: ('MAX_INDEX',))]
fn test_set_bit_fails_max() {
    Bitmap { value: 0 }.set_bit(251);
}
#[test]
#[should_panic(expected: ('MAX_INDEX',))]
fn test_unset_bit_fails_max() {
    Bitmap { value: 0 }.unset_bit(251);
}
#[test]
#[should_panic(expected: ('Option::unwrap failed.',))]
fn test_double_set_reverts() {
    Bitmap { value: 0 }.set_bit(250).set_bit(250).set_bit(250);
}
#[test]
#[should_panic(expected: ('u128_sub Overflow',))]
fn test_unset_not_set() {
    Bitmap { value: 0 }.unset_bit(0);
}

#[test]
fn test_next_set_bit_zero() {
    let b: Bitmap = Zero::zero();
    assert(b.next_set_bit(0).is_none(), '0');
    assert(b.next_set_bit(1).is_none(), '1');
    assert(b.next_set_bit(128).is_none(), '128');
    assert(b.next_set_bit(250).is_none(), '250');
    assert(b.next_set_bit(251).is_none(), '251');
    assert(b.next_set_bit(255).is_none(), '255');
}

#[test]
fn test_prev_set_bit_zero() {
    let b: Bitmap = Zero::zero();
    assert(b.prev_set_bit(0).is_none(), '0');
    assert(b.prev_set_bit(1).is_none(), '1');
    assert(b.prev_set_bit(128).is_none(), '128');
    assert(b.prev_set_bit(250).is_none(), '250');
    assert(b.prev_set_bit(251).is_none(), '251');
    assert(b.prev_set_bit(255).is_none(), '255');
}

#[test]
fn test_next_set_bit_only_max_bit_set() {
    let b: Bitmap = Zero::zero().set_bit(250);
    assert(b.next_set_bit(0).is_none(), '0');
    assert(b.next_set_bit(1).is_none(), '1');
    assert(b.next_set_bit(128).is_none(), '128');
    assert(b.next_set_bit(249).is_none(), '249');
    assert(b.next_set_bit(250).unwrap() == 250, '250');
    assert(b.next_set_bit(251).unwrap() == 250, '251');
    assert(b.next_set_bit(255).unwrap() == 250, '255');
}

#[test]
fn test_next_set_bit_only_min_bit_set() {
    let b: Bitmap = Zero::zero().set_bit(0);
    assert(b.next_set_bit(0).unwrap() == 0, '0');
    assert(b.next_set_bit(1).unwrap() == 0, '1');
    assert(b.next_set_bit(128).unwrap() == 0, '128');
    assert(b.next_set_bit(249).unwrap() == 0, '249');
    assert(b.next_set_bit(250).unwrap() == 0, '250');
    assert(b.next_set_bit(251).unwrap() == 0, '251');
    assert(b.next_set_bit(255).unwrap() == 0, '255');
}

#[test]
fn test_prev_set_bit_only_min_bit_set() {
    let b: Bitmap = Zero::zero().set_bit(0);
    assert(b.prev_set_bit(0).unwrap() == 0, '0');
    assert(b.prev_set_bit(1).is_none(), '1');
    assert(b.prev_set_bit(128).is_none(), '128');
    assert(b.prev_set_bit(249).is_none(), '249');
    assert(b.prev_set_bit(250).is_none(), '250');
    assert(b.prev_set_bit(251).is_none(), '251');
    assert(b.prev_set_bit(255).is_none(), '255');
}

#[test]
fn test_prev_set_bit_only_max_bit_set() {
    let b: Bitmap = Zero::zero().set_bit(250);
    assert(b.prev_set_bit(0).unwrap() == 250, '0');
    assert(b.prev_set_bit(1).unwrap() == 250, '1');
    assert(b.prev_set_bit(128).unwrap() == 250, '128');
    assert(b.prev_set_bit(249).unwrap() == 250, '249');
    assert(b.prev_set_bit(250).unwrap() == 250, '250');
    assert(b.prev_set_bit(251).is_none(), '251');
    assert(b.prev_set_bit(255).is_none(), '255');
}

#[test]
fn test_next_set_bit_complex_scenario() {
    let b: Bitmap = Zero::zero().set_bit(53).set_bit(127).set_bit(128).set_bit(200).set_bit(213);

    assert(b.prev_set_bit(0).unwrap() == 53, '0.prev');
    assert(b.next_set_bit(0).is_none(), '0.next');

    assert(b.prev_set_bit(25).unwrap() == 53, '25.prev');
    assert(b.next_set_bit(25).is_none(), '25.next');

    assert(b.prev_set_bit(52).unwrap() == 53, '52.prev');
    assert(b.next_set_bit(52).is_none(), '52.next');

    assert(b.prev_set_bit(53).unwrap() == 53, '53.prev');
    assert(b.next_set_bit(53).unwrap() == 53, '53.next');

    assert(b.prev_set_bit(54).unwrap() == 127, '54.prev');
    assert(b.next_set_bit(54).unwrap() == 53, '54.next');

    assert(b.prev_set_bit(126).unwrap() == 127, '126.prev');
    assert(b.next_set_bit(126).unwrap() == 53, '126.next');

    assert(b.prev_set_bit(127).unwrap() == 127, '127.prev');
    assert(b.next_set_bit(127).unwrap() == 127, '127.next');

    assert(b.prev_set_bit(128).unwrap() == 128, '128.prev');
    assert(b.next_set_bit(128).unwrap() == 128, '128.next');

    assert(b.prev_set_bit(129).unwrap() == 200, '129.prev');
    assert(b.next_set_bit(129).unwrap() == 128, '129.next');

    assert(b.prev_set_bit(199).unwrap() == 200, '199.prev');
    assert(b.next_set_bit(199).unwrap() == 128, '199.next');

    assert(b.prev_set_bit(200).unwrap() == 200, '200.prev');
    assert(b.next_set_bit(200).unwrap() == 200, '200.next');

    assert(b.prev_set_bit(201).unwrap() == 213, '201.prev');
    assert(b.next_set_bit(201).unwrap() == 200, '201.next');

    assert(b.prev_set_bit(212).unwrap() == 213, '212.prev');
    assert(b.next_set_bit(212).unwrap() == 200, '212.next');

    assert(b.prev_set_bit(213).unwrap() == 213, '213.prev');
    assert(b.next_set_bit(213).unwrap() == 213, '213.next');

    assert(b.prev_set_bit(214).is_none(), '213.prev');
    assert(b.next_set_bit(214).unwrap() == 213, '213.next');

    assert(b.prev_set_bit(250).is_none(), '250.prev');
    assert(b.next_set_bit(250).unwrap() == 213, '250.next');
    assert(b.prev_set_bit(251).is_none(), '251.prev');
    assert(b.next_set_bit(251).unwrap() == 213, '251.next');
    assert(b.prev_set_bit(255).is_none(), '255.prev');
    assert(b.next_set_bit(255).unwrap() == 213, '255.next');
}

fn assert_case_ticks(tick: i129, location: (u128, u8), tick_spacing: u128) {
    let (word, bit) = tick_to_word_and_bit_index(tick: tick, tick_spacing: tick_spacing);
    assert_eq!((word, bit), location);
    let prev = word_and_bit_index_to_tick(location, tick_spacing: tick_spacing);
    assert((tick - prev) < i129 { mag: tick_spacing, sign: false }, 'reverse');
}

#[test]
fn test_positive_cases_tick_spacing_one() {
    assert_case_ticks(tick: Zero::zero(), location: (0, 250), tick_spacing: 1);
    assert_case_ticks(tick: i129 { mag: 0, sign: true }, location: (0, 250), tick_spacing: 1);
    assert_case_ticks(tick: i129 { mag: 249, sign: false }, location: (0, 1), tick_spacing: 1);
    assert_case_ticks(tick: i129 { mag: 250, sign: false }, location: (0, 0), tick_spacing: 1);
    assert_case_ticks(tick: i129 { mag: 251, sign: false }, location: (1, 250), tick_spacing: 1);
    assert_case_ticks(tick: i129 { mag: 252, sign: false }, location: (1, 249), tick_spacing: 1);
}

#[test]
fn test_positive_cases_tick_spacing_ten() {
    assert_case_ticks(tick: Zero::zero(), location: (0, 250), tick_spacing: 10);
    assert_case_ticks(tick: i129 { mag: 0, sign: true }, location: (0, 250), tick_spacing: 10);
    assert_case_ticks(tick: i129 { mag: 2493, sign: false }, location: (0, 1), tick_spacing: 10);
    assert_case_ticks(tick: i129 { mag: 2506, sign: false }, location: (0, 0), tick_spacing: 10);
    assert_case_ticks(tick: i129 { mag: 2512, sign: false }, location: (1, 250), tick_spacing: 10);
    assert_case_ticks(tick: i129 { mag: 2525, sign: false }, location: (1, 249), tick_spacing: 10);
}

#[test]
fn test_positive_cases_non_one_tick_spacing() {
    assert_case_ticks(tick: Zero::zero(), location: (0, 250), tick_spacing: 100);
    assert_case_ticks(tick: i129 { mag: 0, sign: true }, location: (0, 250), tick_spacing: 100);
    assert_case_ticks(tick: i129 { mag: 50, sign: false }, location: (0, 250), tick_spacing: 100);
    assert_case_ticks(tick: i129 { mag: 99, sign: false }, location: (0, 250), tick_spacing: 100);
    assert_case_ticks(tick: i129 { mag: 100, sign: false }, location: (0, 249), tick_spacing: 100);
    assert_case_ticks(tick: i129 { mag: 100, sign: false }, location: (0, 200), tick_spacing: 2);
}


#[test]
fn test_negative_cases_tick_spacing_one() {
    assert_case_ticks(
        tick: i129 { mag: 253, sign: true }, location: (0x100000001, 1), tick_spacing: 1,
    );
    assert_case_ticks(
        tick: i129 { mag: 252, sign: true }, location: (0x100000001, 0), tick_spacing: 1,
    );
    assert_case_ticks(
        tick: i129 { mag: 251, sign: true }, location: (0x100000000, 250), tick_spacing: 1,
    );
    assert_case_ticks(
        tick: i129 { mag: 250, sign: true }, location: (0x100000000, 249), tick_spacing: 1,
    );
    assert_case_ticks(
        tick: i129 { mag: 3, sign: true }, location: (0x100000000, 2), tick_spacing: 1,
    );
    assert_case_ticks(
        tick: i129 { mag: 1, sign: true }, location: (0x100000000, 0), tick_spacing: 1,
    );
}


#[test]
fn test_negative_cases_tick_spacing_ten() {
    assert_case_ticks(
        tick: i129 { mag: 2525, sign: true }, location: (0x100000001, 1), tick_spacing: 10,
    );
    assert_case_ticks(
        tick: i129 { mag: 2519, sign: true }, location: (0x100000001, 0), tick_spacing: 10,
    );
    assert_case_ticks(
        tick: i129 { mag: 2503, sign: true }, location: (0x100000000, 250), tick_spacing: 10,
    );
    assert_case_ticks(
        tick: i129 { mag: 2500, sign: true }, location: (0x100000000, 249), tick_spacing: 10,
    );
    assert_case_ticks(
        tick: i129 { mag: 25, sign: true }, location: (0x100000000, 2), tick_spacing: 10,
    );
    assert_case_ticks(
        tick: i129 { mag: 5, sign: true }, location: (0x100000000, 0), tick_spacing: 10,
    );
}
