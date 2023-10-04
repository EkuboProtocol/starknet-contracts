use array::{Array, ArrayTrait};
use ekubo::math::bits::{msb};
use ekubo::math::exp2::{exp2};
use integer::{u128_safe_divmod, u128_as_non_zero, u256_overflow_mul, u256_overflowing_add};
use option::{OptionTrait, Option};
use traits::{TryInto, Into};

// Convert a u128 number to a decimal string in a felt252
fn to_decimal(mut x: u128) -> Option<felt252> {
    // a number greater than this to decimal is going to exceed 31 digits
    if (x > 9999999999999999999999999999999) {
        return Option::None(());
    }

    // special case is that 0 is still printed
    if (x == 0) {
        return Option::Some('0');
    }

    let mut code_points: Array<u8> = Default::default();

    let ten = u128_as_non_zero(10);

    loop {
        if (x == 0) {
            break ();
        }

        let (quotient, remainder) = u128_safe_divmod(x, ten);
        code_points.append(0x30_u8 + remainder.try_into().expect('DIGIT'));
        x = quotient;
    };

    let mut ix: u8 = 0_u8;
    let mut result: u256 = 0;
    let num_digits = code_points.len();
    loop {
        match code_points.pop_front() {
            Option::Some(code_point) => {
                let digit = Into::<u8, u256>::into(code_point)
                    * if (ix < 16) {
                        u256 { low: exp2(ix * 8), high: 0 }
                    } else {
                        u256 { low: 0, high: exp2((ix - 16) * 8) }
                    };

                // shift left the code point by i. since array is least to most significant, this should be correct
                result += digit;

                ix += 1_u8;
            },
            Option::None => { break (); }
        };
    };

    result.try_into()
}

fn append(x: felt252, y: felt252) -> Option<felt252> {
    if (x == 0) {
        Option::Some(y)
    } else if (y == 0) {
        Option::Some(x)
    } else {
        let x_int: u256 = x.into();
        let y_int: u256 = y.into();

        let bit_length_y: u8 = if (y_int.high == 0) {
            ((msb(y_int.low) + 7_u8) / 8_u8) * 8_u8
        } else {
            128 + (((msb(y_int.high) + 7_u8) / 8_u8) * 8_u8)
        };

        let shift_left_factor = if (bit_length_y > 127) {
            u256 { low: 0, high: exp2(bit_length_y - 128) }
        } else {
            u256 { low: exp2(bit_length_y), high: 0 }
        };

        let (shifted, overflow) = u256_overflow_mul(x_int, shift_left_factor);
        if (overflow) {
            Option::None(())
        } else {
            let (combined, overflow) = u256_overflowing_add(shifted, y_int);
            if (overflow) {
                Option::None(())
            } else {
                combined.try_into()
            }
        }
    }
}
