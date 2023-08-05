use ekubo::types::i129::{i129, i129Trait};
use integer::{downcast, upcast};
use option::{OptionTrait};
use ekubo::math::bits::{msb, lsb};
use ekubo::math::exp2::{exp2};
use ekubo::math::mask::{mask};
use traits::{Into, TryInto};
use zeroable::{Zeroable};

#[derive(Copy, Drop, starknet::Store)]
struct Bitmap {
    // there are 252 bits in this number
    value: felt252
}

impl BitmapZeroable of Zeroable<Bitmap> {
    fn zero() -> Bitmap {
        Bitmap { value: Zeroable::zero() }
    }
    fn is_zero(self: Bitmap) -> bool {
        self.value.is_zero()
    }
    fn is_non_zero(self: Bitmap) -> bool {
        self.value.is_non_zero()
    }
}

#[generate_trait]
impl BitmapTraitImpl of BitmapTrait {
    fn next_set_bit(self: Bitmap, index: u8) -> Option<u8> {
        if (self.is_zero()) {
            return Option::None(());
        }

        let x: u256 = self.value.into();

        if (index < 128) {
            let masked = x.low & mask(index);
            if (masked.is_zero()) {
                return Option::None(());
            }
            Option::Some(msb(masked))
        } else {
            assert(index < 252, 'MAX_INDEX');
            let masked = x & u256 {
                high: mask(index - 128), low: 0xffffffffffffffffffffffffffffffff
            };

            if (masked.is_zero()) {
                return Option::None(());
            }

            if (masked.high > 0) {
                Option::Some(msb(masked.high) + 128)
            } else {
                Option::Some(msb(masked.low))
            }
        }
    }
    fn prev_set_bit(self: Bitmap, index: u8) -> Option<u8> {
        if (self.is_zero()) {
            return Option::None(());
        }

        let x: u256 = self.value.into();

        let mask: u256 = if index < 128 {
            u256 { low: ~(exp2(index) - 1), high: 0xffffffffffffffffffffffffffffffff }
        } else {
            assert(index < 252, 'MAX_INDEX');
            u256 { low: 0, high: ~(exp2(index - 128) - 1) }
        };

        let masked = x & mask;

        if (masked.is_zero()) {
            Option::None(())
        } else if (masked.low.is_non_zero()) {
            Option::Some(lsb(masked.low))
        } else {
            Option::Some(lsb(masked.high) + 128)
        }
    }
    fn set_bit(self: Bitmap, index: u8) -> Bitmap {
        let mut x: u256 = self.value.into();

        if index < 128 {
            x += exp2(index).into()
        } else {
            assert(index < 252, 'MAX_INDEX');
            x += u256 { high: exp2(index - 128), low: 0 };
        }

        Bitmap { value: x.try_into().unwrap() }
    }
    fn unset_bit(self: Bitmap, index: u8) -> Bitmap {
        let mut x: u256 = self.value.into();

        if index < 128 {
            x -= exp2(index).into()
        } else {
            assert(index < 252, 'MAX_INDEX');
            x -= u256 { high: exp2(index - 128), low: 0 };
        }

        Bitmap { value: x.try_into().unwrap() }
    }
}

mod internal {
    const NEGATIVE_OFFSET: u128 = 0x100000000;
}

// Returns the word and bit index of the closest tick that is possibly initialized and <= tick
// The word and bit index are where in the bitmap the initialized state is stored for that nearest tick
#[internal]
fn tick_to_word_and_bit_index(tick: i129, tick_spacing: u128) -> (u128, u8) {
    // we don't care about the relative placement of words, only the placement of bits within a word
    if (tick.is_negative()) {
        // we want the word to have bits from smallest tick to largest tick, and larger mag here means smaller tick
        (
            ((tick.mag - 1) / (tick_spacing * 252)) + internal::NEGATIVE_OFFSET,
            downcast(((tick.mag - 1) / tick_spacing) % 252).unwrap()
        )
    } else {
        // todo: this can be done more efficiently by using divmod
        // we want the word to have bits from smallest tick to largest tick, and larger mag here means larger tick
        (
            tick.mag / (tick_spacing * 252),
            251_u8 - downcast((tick.mag / tick_spacing) % 252).unwrap()
        )
    }
}

// Compute the tick corresponding to the word and bit index
#[internal]
fn word_and_bit_index_to_tick(word_and_bit_index: (u128, u8), tick_spacing: u128) -> i129 {
    let (word, bit) = word_and_bit_index;
    if (word >= internal::NEGATIVE_OFFSET) {
        i129 {
            mag: ((word - internal::NEGATIVE_OFFSET) * 252 * tick_spacing)
                + ((upcast(bit) + 1) * tick_spacing),
            sign: true
        }
    } else {
        i129 { mag: (word * 252 * tick_spacing) + (upcast(251 - bit) * tick_spacing), sign: false }
    }
}
