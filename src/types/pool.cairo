use ekubo::types::i129::{i129};
use ekubo::types::call_points::{CallPoints};
use starknet::{StorageBaseAddress, SyscallResult};
use zeroable::Zeroable;
use traits::{Into, TryInto};
use option::{OptionTrait, Option};
use integer::{u256_as_non_zero, u128_safe_divmod};
use ekubo::math::ticks::{min_sqrt_ratio, max_sqrt_ratio, constants as tick_constants};
use ekubo::math::muldiv::{u256_safe_divmod_audited};

#[derive(Copy, Drop, Serde, starknet::Store)]
struct Pool {
    // the current ratio, up to 192 bits
    sqrt_ratio: u256,
    // the current tick, up to 32 bits
    tick: i129,
    // the places where specified extension should be called
    call_points: CallPoints,
    // the current liquidity, i.e. between tick_prev and tick_next
    liquidity: u128,
    /// the fee growth, all time fees collected per liquidity, full 128x128
    fee_growth_global_token0: u256,
    fee_growth_global_token1: u256,
}

