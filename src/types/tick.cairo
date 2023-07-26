use ekubo::types::i129::{i129};
use ekubo::types::fees_per_liquidity::{FeesPerLiquidity};

// The state that is stored for each active tick
#[derive(Copy, Drop, Serde, starknet::Store)]
struct Tick {
    // how liquidity changes when this tick is crossed
    liquidity_delta: i129,
    // the total amount of liquidity associated with the tick, necessary to know whether we should remove it from the linked list
    liquidity_net: u128,
    // the fees per liquidity on the other side of this tick
    fees_outside: FeesPerLiquidity,
}
