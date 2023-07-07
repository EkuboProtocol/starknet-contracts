use array::ArrayTrait;
use debug::PrintTrait;
use option::{Option, OptionTrait};
use traits::{Into, TryInto};
use starknet::storage_access::{
    StorageAccess, SyscallResult, StorageBaseAddress, storage_address_from_base_and_offset
};
use hash::LegacyHash;
use integer::{u128_safe_divmod, u128_as_non_zero};
use zeroable::Zeroable;

// Represents a signed integer in a 129 bit container, where the sign is 1 bit and the other 128 bits are magnitude
// Note the sign can be true while mag is 0, meaning 1 value is wasted 
// (i.e. sign == true && mag == 0 is redundant with sign == false && mag == 0)
#[derive(Copy, Drop, Serde)]
struct i129 {
    mag: u128,
    sign: bool,
}


#[inline(always)]
fn i129_new(mag: u128, sign: bool) -> i129 {
    i129 { mag, sign: sign & (mag != 0) }
}

impl i129Zeroable of Zeroable<i129> {
    fn zero() -> i129 {
        i129_new(0, false)
    }

    fn is_zero(self: i129) -> bool {
        self.mag == 0
    }

    fn is_non_zero(self: i129) -> bool {
        self.mag != 0
    }
}

impl i129PrintTrait of PrintTrait<i129> {
    fn print(self: i129) {
        self.sign.print();
        self.mag.print();
    }
}

impl i129LegacyHash of LegacyHash<i129> {
    fn hash(state: felt252, value: i129) -> felt252 {
        let mut hashable: felt252 = value.mag.into();
        if ((value.mag != 0) & value.sign) {
            hashable += 0x100000000000000000000000000000000; // 2**128
        }

        pedersen(state, hashable)
    }
}

impl i129StorageAccess of StorageAccess<i129> {
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<i129> {
        StorageAccess::<i129>::read_at_offset_internal(address_domain, base, 0_u8)
    }
    fn write(address_domain: u32, base: StorageBaseAddress, value: i129) -> SyscallResult<()> {
        StorageAccess::<i129>::write_at_offset_internal(address_domain, base, 0_u8, value.into())
    }
    fn read_at_offset_internal(
        address_domain: u32, base: StorageBaseAddress, offset: u8
    ) -> SyscallResult<i129> {
        let x: u128 = StorageAccess::<u128>::read_at_offset_internal(address_domain, base, offset)?;

        Result::Ok(
            if x >= 0x80000000000000000000000000000000 {
                i129_new(x - 0x80000000000000000000000000000000, true)
            } else {
                i129_new(x, false)
            }
        )
    }
    fn write_at_offset_internal(
        address_domain: u32, base: StorageBaseAddress, offset: u8, value: i129
    ) -> SyscallResult<()> {
        // i129 is limited to 127 bits and we use the most significant bit to store the sign in storage
        assert(value.mag < 0x80000000000000000000000000000000, 'i129_storage_overflow');

        StorageAccess::<u128>::write_at_offset_internal(
            address_domain,
            base,
            offset,
            if (value.sign & (value.mag != 0)) {
                0x80000000000000000000000000000000 + value.mag
            } else {
                value.mag
            }
        )
    }
    fn size_internal(value: i129) -> u8 {
        StorageAccess::<u128>::size_internal(0xffffffffffffffffffffffffffffffff)
    }
}

impl i129Add of Add<i129> {
    fn add(lhs: i129, rhs: i129) -> i129 {
        i129_add(lhs, rhs)
    }
}

impl i129AddEq of AddEq<i129> {
    #[inline(always)]
    fn add_eq(ref self: i129, other: i129) {
        self = Add::add(self, other);
    }
}

impl i129Sub of Sub<i129> {
    fn sub(lhs: i129, rhs: i129) -> i129 {
        i129_sub(lhs, rhs)
    }
}

impl i129SubEq of SubEq<i129> {
    #[inline(always)]
    fn sub_eq(ref self: i129, other: i129) {
        self = Sub::sub(self, other);
    }
}

impl i129Mul of Mul<i129> {
    fn mul(lhs: i129, rhs: i129) -> i129 {
        i129_mul(lhs, rhs)
    }
}

impl i129MulEq of MulEq<i129> {
    #[inline(always)]
    fn mul_eq(ref self: i129, other: i129) {
        self = Mul::mul(self, other);
    }
}

impl i129Div of Div<i129> {
    fn div(lhs: i129, rhs: i129) -> i129 {
        i129_div(lhs, rhs)
    }
}

impl i129DivEq of DivEq<i129> {
    #[inline(always)]
    fn div_eq(ref self: i129, other: i129) {
        self = Div::div(self, other);
    }
}

impl i129PartialEq of PartialEq<i129> {
    fn eq(lhs: @i129, rhs: @i129) -> bool {
        i129_eq(lhs, rhs)
    }

    fn ne(lhs: @i129, rhs: @i129) -> bool {
        !i129_eq(lhs, rhs)
    }
}

fn i129_option_eq(lhs: @Option<i129>, rhs: @Option<i129>) -> bool {
    match lhs {
        Option::Some(lhs_value) => {
            match rhs {
                Option::Some(rhs_value) => {
                    lhs_value == rhs_value
                },
                Option::None(_) => false
            }
        },
        Option::None(_) => {
            match rhs {
                Option::Some(_) => false,
                Option::None(_) => true
            }
        }
    }
}

impl i129OptionPartialEq of PartialEq<Option<i129>> {
    fn eq(lhs: @Option<i129>, rhs: @Option<i129>) -> bool {
        i129_option_eq(lhs, rhs)
    }

    fn ne(lhs: @Option<i129>, rhs: @Option<i129>) -> bool {
        !i129_option_eq(lhs, rhs)
    }
}

impl i129PartialOrd of PartialOrd<i129> {
    fn le(lhs: i129, rhs: i129) -> bool {
        i129_le(lhs, rhs)
    }
    fn ge(lhs: i129, rhs: i129) -> bool {
        i129_ge(lhs, rhs)
    }

    fn lt(lhs: i129, rhs: i129) -> bool {
        i129_lt(lhs, rhs)
    }
    fn gt(lhs: i129, rhs: i129) -> bool {
        i129_gt(lhs, rhs)
    }
}

impl i129Neg of Neg<i129> {
    fn neg(a: i129) -> i129 {
        i129_neg(a)
    }
}

fn i129_add(a: i129, b: i129) -> i129 {
    if a.sign == b.sign {
        i129_new(a.mag + b.mag, a.sign)
    } else {
        let (larger, smaller) = if a.mag >= b.mag {
            (a, b)
        } else {
            (b, a)
        };
        let difference = larger.mag - smaller.mag;

        i129_new(difference, larger.sign)
    }
}

#[inline(always)]
fn i129_sub(a: i129, b: i129) -> i129 {
    a + i129_new(b.mag, !b.sign)
}

#[inline(always)]
fn i129_mul(a: i129, b: i129) -> i129 {
    i129_new(a.mag * b.mag, a.sign ^ b.sign)
}

#[inline(always)]
fn i129_div(a: i129, b: i129) -> i129 {
    i129_new(a.mag / b.mag, a.sign ^ b.sign)
}

#[inline(always)]
fn i129_eq(a: @i129, b: @i129) -> bool {
    (a.mag == b.mag) & ((a.sign == b.sign) | (*a.mag == 0))
}

fn i129_gt(a: i129, b: i129) -> bool {
    if (a.sign & !b.sign) {
        return false;
    }
    if (!a.sign & b.sign) {
        // if both are zero, return false
        return (a.mag != 0) | (b.mag != 0);
    }
    if (a.sign & b.sign) {
        return a.mag < b.mag;
    } else {
        return a.mag > b.mag;
    }
}

#[inline(always)]
fn i129_ge(a: i129, b: i129) -> bool {
    (i129_eq(@a, @b) | i129_gt(a, b))
}

#[inline(always)]
fn i129_lt(a: i129, b: i129) -> bool {
    return !i129_ge(a, b);
}

#[inline(always)]
fn i129_le(a: i129, b: i129) -> bool {
    !i129_gt(a, b)
}

#[inline(always)]
fn i129_neg(x: i129) -> i129 {
    i129_new(x.mag, !x.sign)
}
