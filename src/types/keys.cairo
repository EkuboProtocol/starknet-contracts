use hash::pedersen;
use starknet::{contract_address_const, ContractAddress};
use option::{Option, OptionTrait};
use traits::{Into, TryInto};
use hash::LegacyHash;
use zeroable::Zeroable;
use ekubo::types::i129::i129;
use ekubo::types::bounds::Bounds;

// Uniquely identifies a pool
// token0 is the token with the smaller address (sorted by integer value)
// token1 is the token with the larger address (sorted by integer value)
// fee is specified as a 0.128 number, so 1% == 2**128 / 100
// tick_spacing is the minimum spacing between initialized ticks, i.e. ticks that positions may use
#[derive(Copy, Drop, Serde)]
struct PoolKey {
    token0: ContractAddress,
    token1: ContractAddress,
    fee: u128,
    tick_spacing: u128,
    extension: ContractAddress,
}

impl PoolKeyHash of LegacyHash<PoolKey> {
    fn hash(state: felt252, value: PoolKey) -> felt252 {
        pedersen(
            state,
            pedersen(
                pedersen(
                    pedersen(value.token0.into(), value.token1.into()),
                    pedersen(value.fee.into(), value.tick_spacing.into())
                ),
                value.extension.into()
            )
        )
    }
}

#[derive(Copy, Drop, Serde)]
struct PositionKey {
    salt: u64,
    owner: ContractAddress,
    bounds: Bounds,
}

impl PositionKeyHash of LegacyHash<PositionKey> {
    fn hash(state: felt252, value: PositionKey) -> felt252 {
        pedersen(
            state, pedersen(value.salt.into(), pedersen(value.owner.into(), value.bounds.into()))
        )
    }
}
