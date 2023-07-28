use option::{Option, OptionTrait};
use zeroable::Zeroable;
use integer::{
    u512, u256_wide_mul, u512_safe_div_rem_by_u256, u256_as_non_zero, u256_overflowing_add,
    u256_safe_divmod
};

// Compute floor(x/z) OR ceil(x/z) depending on round_up
fn div(x: u256, z: u256, round_up: bool) -> u256 {
    let (quotient, remainder, _) = u256_safe_divmod(x, u256_as_non_zero(z));
    return if (!round_up | remainder.is_zero()) {
        quotient
    } else {
        quotient + 1_u256
    };
}

// Compute floor(x * y / z) OR ceil(x * y / z) without overflowing if the result fits within 256 bits
fn muldiv(x: u256, y: u256, z: u256, round_up: bool) -> (u256, bool) {
    let numerator = u256_wide_mul(x, y);

    if ((numerator.limb3 == 0) & (numerator.limb2 == 0)) {
        return (div(u256 { low: numerator.limb0, high: numerator.limb1 }, z, round_up), false);
    }

    let (quotient, remainder) = u512_safe_div_rem_by_u256(numerator, u256_as_non_zero(z));

    let overflows = (z <= u256 { low: numerator.limb2, high: numerator.limb3 });

    return if (!round_up | (remainder.is_zero())) {
        (u256 { low: quotient.limb0, high: quotient.limb1 }, overflows)
    } else {
        let (sum, sum_overflows) = u256_overflowing_add(
            u256 { low: quotient.limb0, high: quotient.limb1 }, u256 { low: 1, high: 0 }
        );
        (sum, sum_overflows | overflows)
    };
}
