use ekubo::types::i129::i129;
use starknet::{contract_address_const, ContractAddress};
use hash::pedersen;
use option::{Option, OptionTrait};
use traits::{Into, TryInto};
use hash::LegacyHash;
use zeroable::Zeroable;

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

impl DefaultPoolKey of Default<PoolKey> {
    fn default() -> PoolKey {
        PoolKey {
            token0: contract_address_const::<0>(),
            token1: contract_address_const::<0>(),
            fee: 0,
            tick_spacing: 0,
            extension: Zeroable::zero()
        }
    }
}

impl PoolKeyHash of LegacyHash<PoolKey> {
    fn hash(state: felt252, value: PoolKey) -> felt252 {
        pedersen(
            state,
            pedersen(
                pedersen(value.token0.into(), value.token1.into()),
                pedersen(value.fee.into(), value.tick_spacing.into())
            ),
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
