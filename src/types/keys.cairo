use parlay::types::i129::i129;
use starknet::ContractAddress;
use hash::pedersen;
use option::{Option, OptionTrait};
use traits::{Into, TryInto};
use core::hash::LegacyHash;

#[derive(Copy, Drop, Serde)]
struct PoolKey {
    token0: ContractAddress,
    token1: ContractAddress,
    fee: u128,
}

impl PoolKeyHash of LegacyHash<PoolKey> {
    fn hash(state: felt252, value: PoolKey) -> felt252 {
        pedersen(
            state, pedersen(pedersen(value.token0.into(), value.token1.into()), value.fee.into())
        )
    }
}

#[derive(Copy, Drop, Serde)]
struct PositionKey {
    owner: ContractAddress,
    tick_lower: i129,
    tick_upper: i129
}

impl PositionKeyHash of LegacyHash<PositionKey> {
    fn hash(state: felt252, value: PositionKey) -> felt252 {
        pedersen(
            state,
            pedersen(value.owner.into(), pedersen(value.tick_lower.into(), value.tick_upper.into()))
        )
    }
}
