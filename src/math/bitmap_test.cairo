use ekubo::math::bitmap::{tick_to_word_and_bit_index, word_and_bit_index_to_tick};
use ekubo::types::i129::i129;
use zeroable::Zeroable;

#[test]
fn test_word_and_bit_index_0_tick_spacing_1() {
    let (word, bit) = tick_to_word_and_bit_index(tick: Zeroable::zero(), tick_spacing: 1);
    assert(word == 0, 'word');
    assert(bit == 127, 'bit');

    assert(word_and_bit_index_to_tick((0, 127), tick_spacing: 1).is_zero(), 'reverse');
}

#[test]
fn test_word_and_bit_index_negative_0_tick_spacing_1() {
    let (word, bit) = tick_to_word_and_bit_index(
        tick: i129 { mag: 0, sign: true }, tick_spacing: 1
    );
    assert(word == 0, 'word');
    assert(bit == 127, 'bit');

    assert(word_and_bit_index_to_tick((0, 127), tick_spacing: 100).is_zero(), 'reverse');
}

#[test]
fn test_word_and_bit_index_0_tick_spacing_100() {
    let (word, bit) = tick_to_word_and_bit_index(tick: Zeroable::zero(), tick_spacing: 100);
    assert(word == 0, 'word');
    assert(bit == 127, 'bit');

    assert(word_and_bit_index_to_tick((0, 127), tick_spacing: 100).is_zero(), 'reverse');
}

#[test]
fn test_word_and_bit_index_negative_0_tick_spacing_100() {
    let (word, bit) = tick_to_word_and_bit_index(
        tick: i129 { mag: 0, sign: true }, tick_spacing: 100
    );
    assert(word == 0, 'word');
    assert(bit == 127, 'bit');

    assert(word_and_bit_index_to_tick((0, 127), tick_spacing: 100).is_zero(), 'reverse');
}

#[test]
fn test_word_and_bit_index_50_tick_spacing_100() {
    let (word, bit) = tick_to_word_and_bit_index(
        tick: i129 { mag: 50, sign: false }, tick_spacing: 100
    );
    assert(word == 0, 'word');
    assert(bit == 127, 'bit');

    assert(word_and_bit_index_to_tick((0, 127), tick_spacing: 100).is_zero(), 'reverse');
}

#[test]
fn test_word_and_bit_index_99_tick_spacing_100() {
    let (word, bit) = tick_to_word_and_bit_index(
        tick: i129 { mag: 99, sign: false }, tick_spacing: 100
    );
    assert(word == 0, 'word');
    assert(bit == 127, 'bit');

    assert(word_and_bit_index_to_tick((0, 127), 100).is_zero(), 'reverse')
}

#[test]
fn test_word_and_bit_index_100_tick_spacing_100() {
    let (word, bit) = tick_to_word_and_bit_index(
        tick: i129 { mag: 100, sign: false }, tick_spacing: 100
    );
    assert(word == 0, 'word');
    assert(bit == 126, 'bit');

    assert(word_and_bit_index_to_tick((0, 126), 100) == i129 { mag: 100, sign: false }, 'reverse')
}

#[test]
fn test_word_and_bit_index_100_tick_spacing_2() {
    let (word, bit) = tick_to_word_and_bit_index(
        tick: i129 { mag: 100, sign: false }, tick_spacing: 2
    );
    assert(word == 0, 'word');
    assert(bit == 77, 'bit');

    assert(
        word_and_bit_index_to_tick((0, 77), tick_spacing: 2) == i129 { mag: 100, sign: false },
        'reverse'
    );
}

#[test]
fn test_word_and_bit_index_127_tick_spacing_1() {
    let (word, bit) = tick_to_word_and_bit_index(
        tick: i129 { mag: 127, sign: false }, tick_spacing: 1
    );
    assert(word == 0, 'word');
    assert(bit == 0, 'bit');

    assert(
        word_and_bit_index_to_tick((0, 0), tick_spacing: 1) == i129 { mag: 127, sign: false },
        'reverse'
    );
}

#[test]
fn test_word_and_bit_index_128_tick_spacing_1() {
    let (word, bit) = tick_to_word_and_bit_index(
        tick: i129 { mag: 128, sign: false }, tick_spacing: 1
    );
    assert(word == 1, 'word');
    assert(bit == 127, 'bit')
}

#[test]
fn test_word_and_bit_index_384_tick_spacing_3() {
    let (word, bit) = tick_to_word_and_bit_index(
        tick: i129 { mag: 384, sign: false }, tick_spacing: 3
    );
    assert(word == 1, 'word');
    assert(bit == 127, 'bit');

    assert(
        word_and_bit_index_to_tick((1, 127), tick_spacing: 3) == i129 { mag: 384, sign: false },
        'reverse'
    );
}

#[test]
fn test_word_and_bit_index_383_tick_spacing_3() {
    let (word, bit) = tick_to_word_and_bit_index(
        tick: i129 { mag: 383, sign: false }, tick_spacing: 3
    );
    assert(word == 0, 'word');
    assert(bit == 0, 'bit');

    assert(
        word_and_bit_index_to_tick((0, 0), tick_spacing: 3) == i129 { mag: 381, sign: false },
        'reverse'
    );
}

#[test]
fn test_word_and_bit_index_385_tick_spacing_3() {
    let (word, bit) = tick_to_word_and_bit_index(
        tick: i129 { mag: 385, sign: false }, tick_spacing: 3
    );
    assert(word == 1, 'word');
    assert(bit == 127, 'bit');

    assert(
        word_and_bit_index_to_tick((1, 127), tick_spacing: 3) == i129 { mag: 384, sign: false },
        'reverse'
    );
}

#[test]
fn test_word_and_bit_index_388_tick_spacing_3() {
    let (word, bit) = tick_to_word_and_bit_index(
        tick: i129 { mag: 388, sign: false }, tick_spacing: 3
    );
    assert(word == 1, 'word');
    assert(bit == 126, 'bit');

    assert(
        word_and_bit_index_to_tick((1, 126), tick_spacing: 3) == i129 { mag: 387, sign: false },
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
fn test_word_and_bit_index_negative_129_tick_spacing_1() {
    let (word, bit) = tick_to_word_and_bit_index(
        tick: i129 { mag: 129, sign: true }, tick_spacing: 1
    );
    assert(word == 0x100000001, 'word');
    assert(bit == 0, 'bit');

    assert(
        word_and_bit_index_to_tick((0x100000001, 0), tick_spacing: 1) == i129 {
            mag: 129, sign: true
        },
        'reverse'
    );
}

#[test]
fn test_word_and_bit_index_negative_386_tick_spacing_3() {
    let (word, bit) = tick_to_word_and_bit_index(
        tick: i129 { mag: 386, sign: true }, tick_spacing: 3
    );
    assert(word == 0x100000001, 'word');
    assert(bit == 0, 'bit');

    assert(
        word_and_bit_index_to_tick((0x100000001, 0), tick_spacing: 3) == i129 {
            mag: 387, sign: true
        },
        'reverse'
    );
}

#[test]
fn test_word_and_bit_index_negative_385_tick_spacing_3() {
    let (word, bit) = tick_to_word_and_bit_index(
        tick: i129 { mag: 384, sign: true }, tick_spacing: 3
    );
    assert(word == 0x100000000, 'word');
    assert(bit == 127, 'bit');

    assert(
        word_and_bit_index_to_tick((0x100000000, 127), tick_spacing: 3) == i129 {
            mag: 384, sign: true
        },
        'reverse'
    );
}

#[test]
fn test_word_and_bit_index_negative_384_tick_spacing_3() {
    let (word, bit) = tick_to_word_and_bit_index(
        tick: i129 { mag: 384, sign: true }, tick_spacing: 3
    );
    assert(word == 0x100000000, 'word');
    assert(bit == 127, 'bit');

    assert(
        word_and_bit_index_to_tick((0x100000000, 127), tick_spacing: 3) == i129 {
            mag: 384, sign: true
        },
        'reverse'
    );
}

