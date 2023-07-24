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
    let hash_with_different_extension = LegacyHash::<PoolKey>::hash(
        0,
        PoolKey {
            token0: contract_address_const::<1>(),
            token1: contract_address_const::<2>(),
            fee: 0,
            tick_spacing: 1,
            extension: contract_address_const::<3>(),
        }
    );
    let hash_with_different_fee = LegacyHash::<PoolKey>::hash(
        0,
        PoolKey {
            token0: contract_address_const::<1>(),
            token1: contract_address_const::<2>(),
            fee: 1,
            tick_spacing: 1,
            extension: Zeroable::zero(),
        }
    );
    let hash_with_different_tick_spacing = LegacyHash::<PoolKey>::hash(
        0,
        PoolKey {
            token0: contract_address_const::<1>(),
            token1: contract_address_const::<2>(),
            fee: 0,
            tick_spacing: 2,
            extension: Zeroable::zero(),
        }
    );
    assert(
        hash == 816564634321650757221487563680589244607980786618433000970843109861186355085, 'id'
    );
    assert(hash != hash_with_different_extension, 'not equal');
    assert(hash != hash_with_different_fee, 'not equal');
    assert(hash != hash_with_different_tick_spacing, 'not equal');
}

#[test]
fn test_position_key_hash() {
    let hash = LegacyHash::<PositionKey>::hash(
        0,
        PositionKey {
            salt: 0, owner: contract_address_const::<1>(), bounds: Bounds {
                lower: Zeroable::zero(), upper: Zeroable::zero()
            },
        }
    );

    let hash_with_diff_salt = LegacyHash::<PositionKey>::hash(
        0,
        PositionKey {
            salt: 1, owner: contract_address_const::<1>(), bounds: Bounds {
                lower: Zeroable::zero(), upper: Zeroable::zero()
            },
        }
    );

    let hash_with_diff_state = LegacyHash::<PositionKey>::hash(
        1,
        PositionKey {
            salt: 1, owner: contract_address_const::<1>(), bounds: Bounds {
                lower: Zeroable::zero(), upper: Zeroable::zero()
            },
        }
    );

    assert(
        hash == 2002598252687967151219363562011409882048622533754935628534834756348593060442, 'id'
    );
    assert(hash != hash_with_diff_salt, 'not equal');
    assert(hash != hash_with_diff_state, 'not equal');
}
