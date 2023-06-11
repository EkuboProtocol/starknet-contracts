use ekubo::types::keys::{PoolKey, PositionKey};
use ekubo::types::i129::i129;
use starknet::contract_address_const;
use hash::LegacyHash;

#[test]
fn test_pool_key_hash() {
    let hash = LegacyHash::<PoolKey>::hash(
        0,
        PoolKey {
            token0: contract_address_const::<1>(),
            token1: contract_address_const::<2>(),
            fee: 0,
            tick_spacing: 1
        }
    );
    assert(
        hash == 481493888082425488287062412298769332468812900917176967306025147877406114702, 'id'
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
