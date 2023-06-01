use option::Option;
use option::OptionTrait;
use integer::{u256_wide_mul, u512_safe_div_rem_by_u256, u256_as_non_zero, u256_safe_divmod};

// Compute floor(x * y / z) OR ceil(x * y / z) without overflowing if the result fits within 256 bits
fn muldiv(x: u256, y: u256, z: u256, round_up: bool) -> u256 {
    let numerator = u256_wide_mul(x, y);

    if ((numerator.limb3 == 0) & (numerator.limb2 == 0)) {
        let (quotient, remainder) = u256_safe_divmod(
            u256 { low: numerator.limb0, high: numerator.limb1 }, u256_as_non_zero(z)
        );
        return if (!round_up | remainder == u256 { low: 0, high: 0 }) {
            quotient
        } else {
            quotient + u256 { low: 1, high: 0 }
        };
    }

    assert(z > u256 { low: numerator.limb2, high: numerator.limb3 }, 'MULDIV_OVERFLOW_OR_DBZ');

    let (quotient, remainder) = u512_safe_div_rem_by_u256(numerator, u256_as_non_zero(z));
    return if (!round_up | remainder == u256 { low: 0, high: 0 }) {
        u256 { low: quotient.limb0, high: quotient.limb1 }
    } else {
        u256 { low: quotient.limb0, high: quotient.limb1 } + u256 { low: 1, high: 0 }
    };
}
