use parlay::types::keys::{PoolKey, PositionKey};
use parlay::types::i129::i129;
use starknet::contract_address_const;
use debug::PrintTrait;
use core::hash::LegacyHash;


#[test]
fn test_pool_key_hash() {
    let hash = LegacyHash::<PoolKey>::hash(
        0,
        PoolKey {
            token0: contract_address_const::<1>(), token1: contract_address_const::<2>(), fee: 0
        }
    );
    assert(
        hash == 2757657549542566174702412856786580735427995385478903620917979722923085594620, 'id'
    );
}

#[test]
fn test_position_key_hash() {
    let hash = LegacyHash::<PositionKey>::hash(
        0,
        PositionKey {
            owner: contract_address_const::<1>(), tick_lower: i129 {
                mag: 0, sign: false
                }, tick_upper: i129 {
                mag: 0, sign: false
            },
        }
    );
    assert(
        hash == 498631414849929381120934161501384849129150136695721711031999307687030251904, 'id'
    );
}
