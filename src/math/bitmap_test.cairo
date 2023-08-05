use ekubo::math::bitmap::{
    Bitmap, BitmapTrait, tick_to_word_and_bit_index, word_and_bit_index_to_tick
};
use ekubo::types::i129::{i129};
use zeroable::{Zeroable};
use option::{OptionTrait};
use ekubo::math::string::{append, to_decimal};
use traits::{Into};

impl PartialEqBitmap of PartialEq<Bitmap> {
    fn eq(lhs: @Bitmap, rhs: @Bitmap) -> bool {
        lhs.value == rhs.value
    }
    fn ne(lhs: @Bitmap, rhs: @Bitmap) -> bool {
        !PartialEq::eq(lhs, rhs)
    }
}

#[test]
fn test_zeroable() {
    let b: Bitmap = Zeroable::zero();
    assert(b.is_zero(), 'is_zero');
    assert(!b.is_non_zero(), 'is_non_ero');
    assert(b.value.is_zero(), 'value.is_zero');
    assert(!Bitmap { value: 1 }.is_zero(), 'one is nonzero');
    assert(Bitmap { value: 1 }.is_non_zero(), 'one is nonzero');
}

#[test]
#[available_gas(3000000000)]
fn test_set_all_bits() {
    let mut b: Bitmap = Zeroable::zero();
    let mut i: u8 = 0;
    loop {
        if (i == 251) {
            break ();
        }

        b = b.set_bit(i);

        i += 1;
    };

    i = 0;
    loop {
        if (i == 251) {
            break ();
        }

        b = b.unset_bit(i);

        i += 1;
    };

    assert(b.is_zero(), 'b.is_zero')
}

#[test]
fn test_set_bit() {
    assert(Bitmap { value: 0 }.set_bit(0) == Bitmap { value: 1 }, 'set 0');
    assert(Bitmap { value: 0 }.set_bit(1) == Bitmap { value: 2 }, 'set 1');
    assert(
        Bitmap { value: 0 }.set_bit(128) == Bitmap { value: 0x100000000000000000000000000000000 },
        'set 128'
    );
    assert(
        Bitmap {
            value: 0
            }.set_bit(128).set_bit(129) == Bitmap {
            value: 0x300000000000000000000000000000000
        },
        'set 128/129'
    );
    assert(
        Bitmap {
            value: 0
            }.set_bit(128).set_bit(129).unset_bit(128) == Bitmap {
            value: 0x200000000000000000000000000000000
        },
        'set 128/129 - unset 128'
    );
    assert(
        Bitmap {
            value: 0
            }.set_bit(250) == Bitmap {
            value: 0x400000000000000000000000000000000000000000000000000000000000000
        },
        'set 251'
    );

    assert(Bitmap { value: 0 }.set_bit(250).unset_bit(250) == Bitmap { value: 0 }, 'set/unset 251');
    assert(
        Bitmap { value: 0 }.set_bit(0).set_bit(0) == Bitmap { value: 2 }, 'set 0 twice sets next'
    );
    assert(Bitmap { value: 0 }.set_bit(0).unset_bit(0) == Bitmap { value: 0 }, 'set/unset 0');
    assert(Bitmap { value: 5 }.set_bit(0).unset_bit(0) == Bitmap { value: 5 }, 'set/unset 0');
}

#[test]
#[should_panic(expected: ('MAX_INDEX', ))]
fn test_set_bit_fails_max() {
    Bitmap { value: 0 }.set_bit(251);
}

#[test]
#[should_panic(expected: ('MAX_INDEX', ))]
fn test_unset_bit_fails_max() {
    Bitmap { value: 0 }.unset_bit(251);
}

// these errors are bad because we should never encounter these in production
#[test]
#[should_panic(expected: ('MAX_INDEX', ))]
fn test_double_set_reverts() {
    Bitmap { value: 0 }.set_bit(251).set_bit(251);
}
#[test]
#[should_panic(expected: ('u128_sub Overflow', ))]
fn test_unset_not_set() {
    Bitmap { value: 0 }.unset_bit(0);
}

#[test]
fn test_next_set_bit_zero() {
    let b: Bitmap = Zeroable::zero();
    assert(b.next_set_bit(0).is_none(), '0');
    assert(b.next_set_bit(250).is_none(), '250');
    assert(b.next_set_bit(251).is_none(), '251');
    assert(b.next_set_bit(255).is_none(), '255');
}

#[test]
fn test_prev_set_bit_zero() {
    let b: Bitmap = Zeroable::zero();
    assert(b.prev_set_bit(0).is_none(), '0');
    assert(b.prev_set_bit(250).is_none(), '250');
    assert(b.prev_set_bit(251).is_none(), '251');
    assert(b.prev_set_bit(255).is_none(), '255');
}

#[test]
fn test_next_set_bit_only_max_bit_set() {
    let b: Bitmap = Zeroable::zero().set_bit(250);
    assert(b.next_set_bit(0).is_none(), '0');
    assert(b.next_set_bit(250).unwrap() == 250, '251');
}

#[test]
fn test_prev_set_bit_only_smallest_bit_set() {
    let b: Bitmap = Zeroable::zero().set_bit(0);
    assert(b.prev_set_bit(0).unwrap() == 0, '0');
    assert(b.prev_set_bit(250).is_none(), '251');
}

fn assert_case_ticks(tick: i129, location: (u128, u8), tick_spacing: u128) {
    let (word, bit) = tick_to_word_and_bit_index(tick: tick, tick_spacing: tick_spacing);
    assert(
        (word, bit) == location,
        append(
            append(append('w.', to_decimal(word).unwrap()).unwrap(), '.b.').unwrap(),
            to_decimal(bit.into()).unwrap()
        )
            .unwrap()
    );
    let prev = word_and_bit_index_to_tick(location, tick_spacing: tick_spacing);
    assert((tick - prev) < i129 { mag: tick_spacing, sign: false }, 'reverse');
}

#[test]
#[available_gas(3000000000)]
fn test_positive_cases_tick_spacing_one() {
    assert_case_ticks(tick: Zeroable::zero(), location: (0, 250), tick_spacing: 1);
    assert_case_ticks(tick: i129 { mag: 0, sign: true }, location: (0, 250), tick_spacing: 1);
    assert_case_ticks(tick: i129 { mag: 249, sign: false }, location: (0, 1), tick_spacing: 1);
    assert_case_ticks(tick: i129 { mag: 250, sign: false }, location: (0, 0), tick_spacing: 1);
    assert_case_ticks(tick: i129 { mag: 251, sign: false }, location: (1, 250), tick_spacing: 1);
    assert_case_ticks(tick: i129 { mag: 252, sign: false }, location: (1, 249), tick_spacing: 1);
}

#[test]
#[available_gas(3000000000)]
fn test_positive_cases_tick_spacing_ten() {
    assert_case_ticks(tick: Zeroable::zero(), location: (0, 250), tick_spacing: 10);
    assert_case_ticks(tick: i129 { mag: 0, sign: true }, location: (0, 250), tick_spacing: 10);
    assert_case_ticks(tick: i129 { mag: 2493, sign: false }, location: (0, 1), tick_spacing: 10);
    assert_case_ticks(tick: i129 { mag: 2506, sign: false }, location: (0, 0), tick_spacing: 10);
    assert_case_ticks(tick: i129 { mag: 2512, sign: false }, location: (1, 250), tick_spacing: 10);
    assert_case_ticks(tick: i129 { mag: 2525, sign: false }, location: (1, 249), tick_spacing: 10);
}

#[test]
#[available_gas(3000000000)]
fn test_positive_cases_non_one_tick_spacing() {
    assert_case_ticks(tick: Zeroable::zero(), location: (0, 250), tick_spacing: 100);
    assert_case_ticks(tick: i129 { mag: 0, sign: true }, location: (0, 250), tick_spacing: 100);
    assert_case_ticks(tick: i129 { mag: 50, sign: false }, location: (0, 250), tick_spacing: 100);
    assert_case_ticks(tick: i129 { mag: 99, sign: false }, location: (0, 250), tick_spacing: 100);
    assert_case_ticks(tick: i129 { mag: 100, sign: false }, location: (0, 249), tick_spacing: 100);
    assert_case_ticks(tick: i129 { mag: 100, sign: false }, location: (0, 200), tick_spacing: 2);
}


#[test]
#[available_gas(3000000000)]
fn test_negative_cases_tick_spacing_one() {
    assert_case_ticks(
        tick: i129 { mag: 253, sign: true }, location: (0x100000001, 1), tick_spacing: 1
    );
    assert_case_ticks(
        tick: i129 { mag: 252, sign: true }, location: (0x100000001, 0), tick_spacing: 1
    );
    assert_case_ticks(
        tick: i129 { mag: 251, sign: true }, location: (0x100000000, 250), tick_spacing: 1
    );
    assert_case_ticks(
        tick: i129 { mag: 250, sign: true }, location: (0x100000000, 249), tick_spacing: 1
    );
    assert_case_ticks(
        tick: i129 { mag: 3, sign: true }, location: (0x100000000, 2), tick_spacing: 1
    );
    assert_case_ticks(
        tick: i129 { mag: 1, sign: true }, location: (0x100000000, 0), tick_spacing: 1
    );
}


#[test]
#[available_gas(3000000000)]
fn test_negative_cases_tick_spacing_ten() {
    assert_case_ticks(
        tick: i129 { mag: 2525, sign: true }, location: (0x100000001, 1), tick_spacing: 10
    );
    assert_case_ticks(
        tick: i129 { mag: 2519, sign: true }, location: (0x100000001, 0), tick_spacing: 10
    );
    assert_case_ticks(
        tick: i129 { mag: 2503, sign: true }, location: (0x100000000, 250), tick_spacing: 10
    );
    assert_case_ticks(
        tick: i129 { mag: 2500, sign: true }, location: (0x100000000, 249), tick_spacing: 10
    );
    assert_case_ticks(
        tick: i129 { mag: 25, sign: true }, location: (0x100000000, 2), tick_spacing: 10
    );
    assert_case_ticks(
        tick: i129 { mag: 5, sign: true }, location: (0x100000000, 0), tick_spacing: 10
    );
}

