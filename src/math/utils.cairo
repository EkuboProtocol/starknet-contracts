use ekubo::types::i129::i129;
use integer::{u256_overflow_sub, u256_from_felt252};
use starknet::{ContractAddress, ContractAddressIntoFelt252};

#[inline(always)]
fn unsafe_sub(x: u256, y: u256) -> u256 {
    let (res, _) = u256_overflow_sub(x, y);
    res
}


#[inline(always)]
fn add_delta(x: u128, y: i129) -> u128 {
    let sum = i129 { mag: x, sign: false } + y;
    assert((sum.mag == 0) | !sum.sign, 'DELTA_UNDERFLOW');
    sum.mag
}

// Allows comparing contract addresses as if they are integers
impl ContractAddressOrder of PartialOrd<ContractAddress> {
    fn le(lhs: ContractAddress, rhs: ContractAddress) -> bool {
        PartialOrd::<u256>::le(
            u256_from_felt252(ContractAddressIntoFelt252::into(lhs)),
            u256_from_felt252(ContractAddressIntoFelt252::into(rhs))
        )
    }
    fn ge(lhs: ContractAddress, rhs: ContractAddress) -> bool {
        PartialOrd::<u256>::ge(
            u256_from_felt252(ContractAddressIntoFelt252::into(lhs)),
            u256_from_felt252(ContractAddressIntoFelt252::into(rhs))
        )
    }

    fn lt(lhs: ContractAddress, rhs: ContractAddress) -> bool {
        PartialOrd::<u256>::lt(
            u256_from_felt252(ContractAddressIntoFelt252::into(lhs)),
            u256_from_felt252(ContractAddressIntoFelt252::into(rhs))
        )
    }
    fn gt(lhs: ContractAddress, rhs: ContractAddress) -> bool {
        PartialOrd::<u256>::gt(
            u256_from_felt252(ContractAddressIntoFelt252::into(lhs)),
            u256_from_felt252(ContractAddressIntoFelt252::into(rhs))
        )
    }
}


#[inline(always)]
fn u128_max(a: u128, b: u128) -> u128 {
    if a > b {
        a
    } else {
        b
    }
}
