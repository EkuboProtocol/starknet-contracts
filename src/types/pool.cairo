use ekubo::types::i129::{i129};
use ekubo::types::call_points::{CallPoints};

#[derive(Copy, Drop, Serde, storage_access::StorageAccess)]
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
