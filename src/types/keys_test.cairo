use ekubo::types::keys::{PoolKey, PositionKey};
use ekubo::types::i129::i129;
use ekubo::types::bounds::Bounds;
use starknet::contract_address_const;
use hash::LegacyHash;
use debug::PrintTrait;

#[test]
fn test_pool_key_hash() {
    let hash = LegacyHash::<PoolKey>::hash(
        0,
        PoolKey {
            token0: contract_address_const::<1>(),
            token1: contract_address_const::<2>(),
            fee: 0,
            tick_spacing: 1,
            extension: Zeroable::zero(),
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
            owner: contract_address_const::<1>(), bounds: Bounds {
                tick_lower: i129 { mag: 0, sign: false }, tick_upper: i129 { mag: 0, sign: false }
            },
        }
    );
    assert(
        hash == 1411812989538278467630150792407132233026760638173269385928914869656690555734, 'id'
    );
}
