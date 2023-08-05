use ekubo::math::bitmap::{
    Bitmap, BitmapTrait, tick_to_word_and_bit_index, word_and_bit_index_to_tick
};
use ekubo::types::i129::{i129};
use zeroable::{Zeroable};
use option::{OptionTrait};

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
#[should_panic(expected: ('Option::unwrap failed.', ))]
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


#[test]
fn test_word_and_bit_index_0_tick_spacing_1() {
    let (word, bit) = tick_to_word_and_bit_index(tick: Zeroable::zero(), tick_spacing: 1);
    assert(word == 0, 'word');
    assert(bit == 250, 'bit');

    assert(word_and_bit_index_to_tick((0, 250), tick_spacing: 1).is_zero(), 'reverse');
}

#[test]
fn test_word_and_bit_index_negative_0_tick_spacing_1() {
    let (word, bit) = tick_to_word_and_bit_index(
        tick: i129 { mag: 0, sign: true }, tick_spacing: 1
    );
    assert(word == 0, 'word');
    assert(bit == 250, 'bit');

    assert(word_and_bit_index_to_tick((0, 250), tick_spacing: 1).is_zero(), 'reverse');
}

#[test]
fn test_word_and_bit_index_0_tick_spacing_100() {
    let (word, bit) = tick_to_word_and_bit_index(tick: Zeroable::zero(), tick_spacing: 100);
    assert(word == 0, 'word');
    assert(bit == 250, 'bit');

    assert(word_and_bit_index_to_tick((0, 250), tick_spacing: 100).is_zero(), 'reverse');
}

#[test]
fn test_word_and_bit_index_negative_0_tick_spacing_100() {
    let (word, bit) = tick_to_word_and_bit_index(
        tick: i129 { mag: 0, sign: true }, tick_spacing: 100
    );
    assert(word == 0, 'word');
    assert(bit == 250, 'bit');

    assert(word_and_bit_index_to_tick((0, 250), tick_spacing: 100).is_zero(), 'reverse');
}

#[test]
fn test_word_and_bit_index_50_tick_spacing_100() {
    let (word, bit) = tick_to_word_and_bit_index(
        tick: i129 { mag: 50, sign: false }, tick_spacing: 100
    );
    assert(word == 0, 'word');
    assert(bit == 250, 'bit');

    assert(word_and_bit_index_to_tick((0, 250), tick_spacing: 100).is_zero(), 'reverse');
}

#[test]
fn test_word_and_bit_index_99_tick_spacing_100() {
    let (word, bit) = tick_to_word_and_bit_index(
        tick: i129 { mag: 99, sign: false }, tick_spacing: 100
    );
    assert(word == 0, 'word');
    assert(bit == 250, 'bit');

    assert(word_and_bit_index_to_tick((0, 250), tick_spacing: 100).is_zero(), 'reverse')
}

#[test]
fn test_word_and_bit_index_100_tick_spacing_100() {
    let (word, bit) = tick_to_word_and_bit_index(
        tick: i129 { mag: 100, sign: false }, tick_spacing: 100
    );
    assert(word == 0, 'word');
    assert(bit == 249, 'bit');

    assert(
        word_and_bit_index_to_tick((0, 249), tick_spacing: 100) == i129 { mag: 100, sign: false },
        'reverse'
    )
}

use debug::PrintTrait;
#[test]
fn test_word_and_bit_index_100_tick_spacing_2() {
    let (word, bit) = tick_to_word_and_bit_index(
        tick: i129 { mag: 100, sign: false }, tick_spacing: 2
    );
    assert(word == 0, 'word');
    assert(bit == 201, 'bit');

    assert(
        word_and_bit_index_to_tick((0, 201), tick_spacing: 2) == i129 { mag: 100, sign: false },
        'reverse'
    );
}

#[test]
fn test_word_and_bit_index_end_of_first_positive_word() {
    let (word, bit) = tick_to_word_and_bit_index(
        tick: i129 { mag: 251, sign: false }, tick_spacing: 1
    );
    assert(word == 0, 'word');
    assert(bit == 0, 'bit');

    assert(
        word_and_bit_index_to_tick((0, 0), tick_spacing: 1) == i129 { mag: 251, sign: false },
        'reverse'
    );
}

#[test]
fn test_word_and_bit_index_beginning_of_next_word_tick_spacing_1() {
    let (word, bit) = tick_to_word_and_bit_index(
        tick: i129 { mag: 252, sign: false }, tick_spacing: 1
    );
    assert(word == 1, 'word');
    assert(bit == 251, 'bit');
}

#[test]
fn test_word_and_bit_index_beginning_of_next_word_tick_spacing_3() {
    let (word, bit) = tick_to_word_and_bit_index(
        tick: i129 { mag: 756, sign: false }, tick_spacing: 3
    );
    assert(word == 1, 'word');
    assert(bit == 251, 'bit');

    assert(
        word_and_bit_index_to_tick((1, 251), tick_spacing: 3) == i129 { mag: 756, sign: false },
        'reverse'
    );
}

#[test]
fn test_word_and_bit_index_end_of_word_zero() {
    let (word, bit) = tick_to_word_and_bit_index(
        tick: i129 { mag: 755, sign: false }, tick_spacing: 3
    );
    assert(word == 0, 'word');
    assert(bit == 0, 'bit');

    assert(
        word_and_bit_index_to_tick((0, 0), tick_spacing: 3) == i129 { mag: 753, sign: false },
        'reverse'
    );
}

#[test]
fn test_word_and_bit_index_757_tick_spacing_3() {
    let (word, bit) = tick_to_word_and_bit_index(
        tick: i129 { mag: 757, sign: false }, tick_spacing: 3
    );
    assert(word == 1, 'word');
    assert(bit == 251, 'bit');

    assert(
        word_and_bit_index_to_tick((1, 251), tick_spacing: 3) == i129 { mag: 756, sign: false },
        'reverse'
    );
}

#[test]
fn test_word_and_bit_index_758_tick_spacing_3() {
    let (word, bit) = tick_to_word_and_bit_index(
        tick: i129 { mag: 758, sign: false }, tick_spacing: 3
    );

    assert(word == 1, 'word');
    assert(bit == 251, 'bit');
    assert(
        word_and_bit_index_to_tick((1, 251), tick_spacing: 3) == i129 { mag: 756, sign: false },
        'reverse'
    );
}

#[test]
fn test_word_and_bit_index_negative_1_tick_spacing_3() {
    let (word, bit) = tick_to_word_and_bit_index(
        tick: i129 { mag: 1, sign: true }, tick_spacing: 3
    );
    assert(word == 0x100000000, 'word');
    assert(bit == 0, 'bit');

    assert(
        word_and_bit_index_to_tick((0x100000000, 0), tick_spacing: 3) == i129 {
            mag: 3, sign: true
        },
        'reverse'
    );
}

#[test]
fn test_word_and_bit_index_negative_3_tick_spacing_3() {
    let (word, bit) = tick_to_word_and_bit_index(
        tick: i129 { mag: 3, sign: true }, tick_spacing: 3
    );
    assert(word == 0x100000000, 'word');
    assert(bit == 0, 'bit');

    assert(
        word_and_bit_index_to_tick((0x100000000, 0), tick_spacing: 3) == i129 {
            mag: 3, sign: true
        },
        'reverse'
    );
}

#[test]
fn test_word_and_bit_index_negative_4_tick_spacing_3() {
    let (word, bit) = tick_to_word_and_bit_index(
        tick: i129 { mag: 4, sign: true }, tick_spacing: 3
    );
    assert(word == 0x100000000, 'word');
    assert(bit == 1, 'bit');

    assert(
        word_and_bit_index_to_tick((0x100000000, 1), tick_spacing: 3) == i129 {
            mag: 6, sign: true
        },
        'reverse'
    );
}

#[test]
fn test_word_and_bit_index_negative_2_tick_spacing_3() {
    let (word, bit) = tick_to_word_and_bit_index(
        tick: i129 { mag: 2, sign: true }, tick_spacing: 3
    );
    assert(word == 0x100000000, 'word');
    assert(bit == 0, 'bit');

    assert(
        word_and_bit_index_to_tick((0x100000000, 0), tick_spacing: 3) == i129 {
            mag: 3, sign: true
        },
        'reverse'
    );
}


#[test]
fn test_word_and_bit_index_negative_1_tick_spacing_1() {
    let (word, bit) = tick_to_word_and_bit_index(
        tick: i129 { mag: 1, sign: true }, tick_spacing: 1
    );
    assert(word == 0x100000000, 'word');
    assert(bit == 0, 'bit');

    assert(
        word_and_bit_index_to_tick((0x100000000, 0), tick_spacing: 1) == i129 {
            mag: 1, sign: true
        },
        'reverse'
    );
}

#[test]
fn test_word_and_bit_index_negative_3_tick_spacing_1() {
    let (word, bit) = tick_to_word_and_bit_index(
        tick: i129 { mag: 3, sign: true }, tick_spacing: 1
    );
    assert(word == 0x100000000, 'word');
    assert(bit == 2, 'bit');

    assert(
        word_and_bit_index_to_tick((0x100000000, 2), tick_spacing: 1) == i129 {
            mag: 3, sign: true
        },
        'reverse'
    );
}

#[test]
fn test_word_and_bit_index_negative_128_tick_spacing_1() {
    let (word, bit) = tick_to_word_and_bit_index(
        tick: i129 { mag: 128, sign: true }, tick_spacing: 1
    );
    assert(word == 0x100000000, 'word');
    assert(bit == 127, 'bit');

    assert(
        word_and_bit_index_to_tick((0x100000000, 127), tick_spacing: 1) == i129 {
            mag: 128, sign: true
        },
        'reverse'
    );
}

#[test]
fn test_word_and_bit_index_negative_253_tick_spacing_1() {
    let (word, bit) = tick_to_word_and_bit_index(
        tick: i129 { mag: 253, sign: true }, tick_spacing: 1
    );
    assert(word == 0x100000001, 'word');
    assert(bit == 0, 'bit');

    assert(
        word_and_bit_index_to_tick((0x100000001, 0), tick_spacing: 1) == i129 {
            mag: 253, sign: true
        },
        'reverse'
    );
}

#[test]
fn test_word_and_bit_index_negative_757_tick_spacing_3() {
    let (word, bit) = tick_to_word_and_bit_index(
        tick: i129 { mag: 757, sign: true }, tick_spacing: 3
    );
    assert(word == 0x100000001, 'word');
    assert(bit == 0, 'bit');

    assert(
        word_and_bit_index_to_tick((0x100000001, 0), tick_spacing: 3) == i129 {
            mag: 759, sign: true
        },
        'reverse'
    );
}

#[test]
fn test_word_and_bit_index_negative_756_tick_spacing_3() {
    let (word, bit) = tick_to_word_and_bit_index(
        tick: i129 { mag: 756, sign: true }, tick_spacing: 3
    );
    assert(word == 0x100000000, 'word');
    assert(bit == 251, 'bit');

    assert(
        word_and_bit_index_to_tick((0x100000000, 251), tick_spacing: 3) == i129 {
            mag: 756, sign: true
        },
        'reverse'
    );
}

#[test]
fn test_word_and_bit_index_negative_755_tick_spacing_3() {
    let (word, bit) = tick_to_word_and_bit_index(
        tick: i129 { mag: 755, sign: true }, tick_spacing: 3
    );
    assert(word == 0x100000000, 'word');
    assert(bit == 251, 'bit');

    assert(
        word_and_bit_index_to_tick((0x100000000, 251), tick_spacing: 3) == i129 {
            mag: 756, sign: true
        },
        'reverse'
    );
}

