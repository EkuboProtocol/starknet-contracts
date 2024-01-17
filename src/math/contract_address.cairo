use core::integer::{u256_from_felt252, u128_wrapping_sub};
use core::traits::{Into};
use starknet::{ContractAddress, ContractAddressIntoFelt252};

// Allows comparing contract addresses as if they are integers
impl ContractAddressOrder of PartialOrd<ContractAddress> {
    #[inline(always)]
    fn le(lhs: ContractAddress, rhs: ContractAddress) -> bool {
        u256_from_felt252(lhs.into()) <= u256_from_felt252(rhs.into())
    }
    #[inline(always)]
    fn ge(lhs: ContractAddress, rhs: ContractAddress) -> bool {
        u256_from_felt252(lhs.into()) >= u256_from_felt252(rhs.into())
    }

    #[inline(always)]
    fn lt(lhs: ContractAddress, rhs: ContractAddress) -> bool {
        u256_from_felt252(lhs.into()) < u256_from_felt252(rhs.into())
    }
    #[inline(always)]
    fn gt(lhs: ContractAddress, rhs: ContractAddress) -> bool {
        u256_from_felt252(lhs.into()) > u256_from_felt252(rhs.into())
    }
}

