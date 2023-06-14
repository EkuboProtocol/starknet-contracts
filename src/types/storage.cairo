use ekubo::types::i129::{i129, Felt252IntoI129, i129OptionPartialEq};
use starknet::ContractAddress;
use starknet::storage_access::{
    StorageAccess, SyscallResult, storage_address_from_base_and_offset, StorageBaseAddress,
    storage_read_syscall, storage_write_syscall
};
use traits::{TryInto, Into};
use option::{Option, OptionTrait};
use integer::{u128_as_non_zero, u128_safe_divmod};

#[derive(Copy, Drop, Serde, storage_access::StorageAccess)]
struct Pool {
    // the current ratio, up to 192 bits
    sqrt_ratio: u256,
    // the current tick, up to 32 bits
    tick: i129,
    // the current liquidity, i.e. between tick_prev and tick_next
    liquidity: u128,
    /// the fee growth, all time fees collected per liquidity, full 128x128
    fee_growth_global_token0: u256,
    fee_growth_global_token1: u256,
}

// Represents a liquidity position
#[derive(Copy, Drop, Serde, storage_access::StorageAccess)]
struct Position {
    // the amount of liquidity owned by the position
    liquidity: u128,
    // the fee growth inside the tick range of the position, the last time it was computed
    fee_growth_inside_last_token0: u256,
    fee_growth_inside_last_token1: u256,
}

// The state that is stored for each active tick
#[derive(Copy, Drop, Serde, storage_access::StorageAccess)]
struct Tick {
    // how liquidity changes when this tick is crossed
    liquidity_delta: i129,
    // the total amount of liquidity associated with the tick, necessary to know whether we should remove it from the linked list
    liquidity_net: u128,
    // the fee growth that is on the other side of the tick, from the current tick
    fee_growth_outside_token0: u256,
    fee_growth_outside_token1: u256,
}
