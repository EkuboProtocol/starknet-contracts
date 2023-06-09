use ekubo::types::i129::i129;
use integer::{downcast, upcast};
use option::{OptionTrait};

mod internal {
    const NEGATIVE_OFFSET: u128 = 0x100000000;
}

// Returns the word and bit index of the closest tick that is possibly initialized and <= tick
// The word and bit index are where in the bitmap the initialized state is stored for that nearest tick
#[internal]
fn tick_to_word_and_bit_index(tick: i129, tick_spacing: u128) -> (u128, u8) {
    // we don't care about the relative placement of words, only the placement of bits within a word
    if (tick.sign & (tick.mag != 0)) {
        // we want the word to have bits from smallest tick to largest tick, and larger mag here means smaller tick
        // also, the word must 
        (
            ((tick.mag - 1) / (tick_spacing * 128)) + internal::NEGATIVE_OFFSET,
            downcast(((tick.mag - 1) / tick_spacing) % 128).unwrap()
        )
    } else {
        // we want the word to have bits from smallest tick to largest tick, and larger mag here means larger tick
        (
            tick.mag / (tick_spacing * 128),
            127_u8 - downcast((tick.mag / tick_spacing) % 128).unwrap()
        )
    }
}

// Compute the tick corresponding to the word and bit index
#[internal]
fn word_and_bit_index_to_tick(word_and_bit_index: (u128, u8), tick_spacing: u128) -> i129 {
    let (word, bit) = word_and_bit_index;
    if (word >= internal::NEGATIVE_OFFSET) {
        i129 {
            mag: ((word - internal::NEGATIVE_OFFSET) * 128 * tick_spacing)
                + ((upcast(bit) + 1) * tick_spacing),
            sign: true
        }
    } else {
        i129 { mag: (word * 128 * tick_spacing) + (upcast(127 - bit) * tick_spacing), sign: false }
    }
}
