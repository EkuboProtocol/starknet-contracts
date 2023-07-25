use ekubo::types::i129::{i129};

// The state that is stored for each active tick
#[derive(Copy, Drop, Serde, starknet::Store)]
struct Tick {
    // how liquidity changes when this tick is crossed
    liquidity_delta: i129,
    // the total amount of liquidity associated with the tick, necessary to know whether we should remove it from the linked list
    liquidity_net: u128,
    // the fee growth that is on the other side of the tick, from the current tick
    fee_growth_outside_token0: u256,
    fee_growth_outside_token1: u256,
}
