use core::integer::u512_safe_div_rem_by_u256;
use core::num::traits::{OverflowingAdd, WideMul, Zero};
use core::option::{Option, OptionTrait};

// Compute floor(x/z) OR ceil(x/z) depending on round_up
pub fn div(x: u256, z: NonZero<u256>, round_up: bool) -> u256 {
    let (quotient, remainder) = DivRem::div_rem(x, z);
    return if (!round_up | remainder.is_zero()) {
        quotient
    } else {
        // we know this cannot overflow because max real result of x/z where x and z are both u256
        // is [0, 2**256-1]
        let (result, _) = OverflowingAdd::overflowing_add(quotient, 1_u256);
        result
    };
}

// Compute floor(x * y / z) OR ceil(x * y / z) without overflowing if the result fits within 256
// bits
pub fn muldiv(x: u256, y: u256, z: u256, round_up: bool) -> Option<u256> {
    if (z.is_zero()) {
        return Option::None(());
    }

    let numerator = WideMul::<u256, u256>::wide_mul(x, y);

    // we didn't overflow the 256 bit container, so just div
    if ((numerator.limb3 == 0) & (numerator.limb2 == 0)) {
        return Option::Some(
            div(
                u256 { low: numerator.limb0, high: numerator.limb1 },
                z.try_into().unwrap(),
                round_up,
            ),
        );
    }

    let (quotient, remainder) = u512_safe_div_rem_by_u256(numerator, z.try_into().unwrap());

    if (quotient.limb3.is_non_zero() | quotient.limb2.is_non_zero()) {
        Option::None(())
    } else if (!round_up | (remainder.is_zero())) {
        Option::Some(u256 { low: quotient.limb0, high: quotient.limb1 })
    } else {
        let (sum, sum_overflows) = OverflowingAdd::overflowing_add(
            u256 { low: quotient.limb0, high: quotient.limb1 }, 1_u256,
        );
        if (sum_overflows) {
            Option::None(())
        } else {
            Option::Some(sum)
        }
    }
}
