use core::num::traits::Zero;
use core::option::OptionTrait;
use core::traits::{Into, TryInto};
use crate::math::bits::{lsb, msb};
use crate::math::exp2::exp2;
use crate::math::mask::mask;
use crate::types::i129::{i129, i129Trait};

#[derive(Copy, Drop, starknet::Store, PartialEq)]
pub struct Bitmap {
    // there are 251 bits that can all be set to 1 without exceeding the max prime of felt252
    pub(crate) value: felt252,
}

impl BitmapZero of Zero<Bitmap> {
    fn zero() -> Bitmap {
        Bitmap { value: Zero::zero() }
    }
    fn is_zero(self: @Bitmap) -> bool {
        self.value.is_zero()
    }
    fn is_non_zero(self: @Bitmap) -> bool {
        self.value.is_non_zero()
    }
}

#[generate_trait]
pub impl BitmapTraitImpl of BitmapTrait {
    // Returns the index of the most significant bit of less or equal significance as the index bit
    fn next_set_bit(self: Bitmap, index: u8) -> Option<u8> {
        if (self.is_zero()) {
            return Option::None(());
        }

        let x: u256 = self.value.into();

        if (index < 128) {
            let masked = x.low & mask(index);
            if (masked.is_zero()) {
                Option::None(())
            } else {
                Option::Some(msb(masked))
            }
        } else {
            let masked_high = x.high & mask(index - 128);
            if (masked_high.is_non_zero()) {
                Option::Some(msb(masked_high) + 128)
            } else {
                if (x.low.is_zero()) {
                    Option::None(())
                } else {
                    Option::Some(msb(x.low))
                }
            }
        }
    }

    // Returns the index of the least significant bit more or equally significant as the bit at
    // index
    fn prev_set_bit(self: Bitmap, index: u8) -> Option<u8> {
        if (self.is_zero()) {
            return Option::None(());
        }

        let x: u256 = self.value.into();

        if (index < 128) {
            let masked_low = x.low & (~(exp2(index) - 1));
            if (masked_low.is_zero()) {
                if x.high.is_non_zero() {
                    Option::Some(lsb(x.high) + 128)
                } else {
                    Option::None(())
                }
            } else {
                Option::Some(lsb(masked_low))
            }
        } else {
            let masked = x.high & (~(exp2(index - 128) - 1));
            if (masked.is_non_zero()) {
                Option::Some(lsb(masked) + 128)
            } else {
                Option::None(())
            }
        }
    }

    // Sets the bit at the given index to and returns the new bitmap.
    // Note this method is not idempotent. You should only call it if you know the bit is not set
    // through some external means.
    fn set_bit(self: Bitmap, index: u8) -> Bitmap {
        let mut x: u256 = self.value.into();

        if index < 128 {
            Bitmap { value: u256 { high: x.high, low: x.low + exp2(index) }.try_into().unwrap() }
        } else {
            assert(index < 251, 'MAX_INDEX');
            Bitmap {
                value: u256 { high: x.high + exp2(index - 128), low: x.low }.try_into().unwrap(),
            }
        }
    }

    // Unsets the 1 bit at the given index and returns the new bitmap.
    // Note this method is not idempotent. You should only call it if you know the bit is set
    // through some external means.
    fn unset_bit(self: Bitmap, index: u8) -> Bitmap {
        let x: u256 = self.value.into();

        if index < 128 {
            Bitmap { value: u256 { high: x.high, low: x.low - exp2(index) }.try_into().unwrap() }
        } else {
            assert(index < 251, 'MAX_INDEX');
            Bitmap {
                value: u256 { high: x.high - exp2(index - 128), low: x.low }.try_into().unwrap(),
            }
        }
    }
}


const NEGATIVE_OFFSET: u128 = 0x100000000;


// Returns the word and bit index of the closest tick that is possibly initialized and <= tick
// The word and bit index are where in the bitmap the initialized state is stored for that nearest
// tick
pub fn tick_to_word_and_bit_index(tick: i129, tick_spacing: u128) -> (u128, u8) {
    // we don't care about the relative placement of words, only the placement of bits within a word
    if (tick.is_negative()) {
        // we want the word to have bits from smallest tick to largest tick, and larger mag here
        // means smaller tick
        (
            ((tick.mag - 1) / (tick_spacing * 251)) + NEGATIVE_OFFSET,
            (((tick.mag - 1) / tick_spacing) % 251).try_into().unwrap(),
        )
    } else {
        // todo: this can be done more efficiently by using divmod
        // we want the word to have bits from smallest tick to largest tick, and larger mag here
        // means larger tick
        (
            tick.mag / (tick_spacing * 251),
            250_u8 - ((tick.mag / tick_spacing) % 251).try_into().unwrap(),
        )
    }
}

// Compute the tick corresponding to the word and bit index
pub fn word_and_bit_index_to_tick(word_and_bit_index: (u128, u8), tick_spacing: u128) -> i129 {
    let (word, bit) = word_and_bit_index;
    if (word >= NEGATIVE_OFFSET) {
        i129 {
            mag: ((word - NEGATIVE_OFFSET) * 251 * tick_spacing)
                + ((bit.into() + 1) * tick_spacing),
            sign: true,
        }
    } else {
        i129 { mag: (word * 251 * tick_spacing) + ((250 - bit).into() * tick_spacing), sign: false }
    }
}
