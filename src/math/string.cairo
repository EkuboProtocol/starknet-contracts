use array::{Array, ArrayTrait};
use integer::{u128_safe_divmod, u128_as_non_zero};
use traits::{TryInto, Into};
use option::{OptionTrait};
use ekubo::math::exp2::{exp2};

// Convert a u128 number to a decimal string in a felt252
fn to_decimal(mut x: u128) -> felt252 {
    // a number greater than this to decimal is going to exceed 31 digits
    assert(x < 5070602400912917605986812821504, 'DIGITS');

    // special case is that 0 is still printed
    if (x == 0) {
        return '0';
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
    let mut result: u128 = 0;
    let num_digits = code_points.len();
    loop {
        match code_points.pop_front() {
            Option::Some(code_point) => {
                let digit = Into::<u8, u128>::into(code_point) * exp2(ix * 8);

                // shift left the code point by i. since array is least to most significant, this should be correct
                result += digit;

                ix += 1_u8;
            },
            Option::None(_) => {
                break ();
            }
        };
    };

    result.into()
}
