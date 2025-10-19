use core::array::{Array, ArrayTrait};
use core::num::traits::Zero;
use core::option::OptionTrait;
use core::traits::{Into, TryInto};
use crate::math::exp2::exp2;

// Convert a u64 number to a decimal string in a felt252
pub fn to_decimal(mut x: u64) -> felt252 {
    // special case is that 0 is still printed
    if (x.is_zero()) {
        return '0';
    }

    let mut code_points: Array<u8> = Default::default();

    let TEN: NonZero<u64> = 10_u64.try_into().unwrap();

    while x.is_non_zero() {
        let (quotient, remainder) = DivRem::div_rem(x, TEN);
        code_points.append(0x30_u8 + remainder.try_into().expect('DIGIT'));
        x = quotient;
    }

    let mut ix: u8 = 0_u8;
    let mut result: u256 = 0;
    while let Option::Some(code_point) = code_points.pop_front() {
        let digit = Into::<u8, u256>::into(code_point)
            * if (ix < 16) {
                u256 { low: exp2(ix * 8), high: 0 }
            } else {
                u256 { low: 0, high: exp2((ix - 16) * 8) }
            };

        // shift left the code point by i. since array is least to most significant, this should be
        // correct
        result += digit;

        ix += 1_u8;
    }

    result.try_into().unwrap()
}
