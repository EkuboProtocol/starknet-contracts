use core::hash::LegacyHash;
use core::num::traits::Zero;
use crate::math::ticks::constants as tick_constants;
use crate::types::bounds::Bounds;
use crate::types::i129::i129;
use crate::types::keys::{PoolKey, PoolKeyTrait, PositionKey, SavedBalanceKey};

pub fn check_hashes_differ<T, +LegacyHash<T>, +Copy<T>, +Drop<T>>(x: T, y: T) {
    let a = LegacyHash::hash(0, x);
    let b = LegacyHash::hash(0, y);
    let c = LegacyHash::hash(1, x);
    let d = LegacyHash::hash(1, y);
    assert((a != b) & (a != c) & (a != d) & (b != c) & (b != d) & (c != d), 'hashes differ');
}

#[test]
fn test_pool_key_hash_differs_for_any_field_or_state_change() {
    let base = PoolKey {
        token0: Zero::zero(),
        token1: Zero::zero(),
        fee: Zero::zero(),
        tick_spacing: Zero::zero(),
        extension: Zero::zero(),
    };

    let mut other_token0 = base;
    other_token0.token0 = 1.try_into().unwrap();
    check_hashes_differ(base, other_token0);

    let mut other_token1 = base;
    other_token1.token1 = 1.try_into().unwrap();
    check_hashes_differ(base, other_token1);

    let mut other_fee = base;
    other_fee.fee = 1;
    check_hashes_differ(base, other_fee);

    let mut other_tick_spacing = base;
    other_tick_spacing.tick_spacing = 1;
    check_hashes_differ(base, other_tick_spacing);

    let mut other_extension = base;
    other_extension.extension = 1.try_into().unwrap();
    check_hashes_differ(base, other_extension);

    check_hashes_differ(other_token0, other_token1);
    check_hashes_differ(other_token0, other_fee);
    check_hashes_differ(other_token0, other_tick_spacing);
    check_hashes_differ(other_token0, other_extension);

    check_hashes_differ(other_token1, other_fee);
    check_hashes_differ(other_token1, other_tick_spacing);
    check_hashes_differ(other_token1, other_extension);

    check_hashes_differ(other_fee, other_tick_spacing);
    check_hashes_differ(other_fee, other_extension);

    check_hashes_differ(other_tick_spacing, other_extension);
}

#[test]
#[should_panic(expected: ('TOKEN_ORDER',))]
fn test_pool_key_check_valid_order_wrong_order() {
    PoolKey {
        token0: 2.try_into().unwrap(),
        token1: 0.try_into().unwrap(),
        fee: Zero::zero(),
        tick_spacing: 1,
        extension: Zero::zero(),
    }
        .check_valid();
}

#[test]
#[should_panic(expected: ('TOKEN_ORDER',))]
fn test_pool_key_check_valid_order_same_token() {
    PoolKey {
        token0: 1.try_into().unwrap(),
        token1: 1.try_into().unwrap(),
        fee: Zero::zero(),
        tick_spacing: 1,
        extension: Zero::zero(),
    }
        .check_valid();
}

#[test]
#[should_panic(expected: ('TOKEN_NON_ZERO',))]
fn test_pool_key_check_non_zero() {
    PoolKey {
        token0: 0.try_into().unwrap(),
        token1: 2.try_into().unwrap(),
        fee: Zero::zero(),
        tick_spacing: 1,
        extension: Zero::zero(),
    }
        .check_valid();
}

#[test]
#[should_panic(expected: ('TICK_SPACING',))]
fn test_pool_key_check_tick_spacing_non_zero() {
    PoolKey {
        token0: 1.try_into().unwrap(),
        token1: 2.try_into().unwrap(),
        fee: Zero::zero(),
        tick_spacing: Zero::zero(),
        extension: Zero::zero(),
    }
        .check_valid();
}

#[test]
#[should_panic(expected: ('TICK_SPACING',))]
fn test_pool_key_check_tick_spacing_max() {
    PoolKey {
        token0: 1.try_into().unwrap(),
        token1: 2.try_into().unwrap(),
        fee: Zero::zero(),
        tick_spacing: tick_constants::MAX_TICK_SPACING + 1,
        extension: Zero::zero(),
    }
        .check_valid();
}

#[test]
fn test_pool_key_check_valid_is_valid() {
    PoolKey {
        token0: 1.try_into().unwrap(),
        token1: 2.try_into().unwrap(),
        fee: Zero::zero(),
        tick_spacing: 1,
        extension: Zero::zero(),
    }
        .check_valid();

    PoolKey {
        token0: 1.try_into().unwrap(),
        token1: 2.try_into().unwrap(),
        fee: Zero::zero(),
        tick_spacing: tick_constants::MAX_TICK_SPACING,
        extension: Zero::zero(),
    }
        .check_valid();

    PoolKey {
        token0: 1.try_into().unwrap(),
        token1: 2.try_into().unwrap(),
        fee: 0xffffffffffffffffffffffffffffffff,
        tick_spacing: tick_constants::MAX_TICK_SPACING,
        extension: Zero::zero(),
    }
        .check_valid();

    PoolKey {
        token0: 1.try_into().unwrap(),
        token1: 2.try_into().unwrap(),
        fee: 0xffffffffffffffffffffffffffffffff,
        tick_spacing: tick_constants::MAX_TICK_SPACING,
        extension: 2.try_into().unwrap(),
    }
        .check_valid();
}

#[test]
fn test_pool_key_hash() {
    let hash = LegacyHash::<
        PoolKey,
    >::hash(
        0,
        PoolKey {
            token0: 1.try_into().unwrap(),
            token1: 2.try_into().unwrap(),
            fee: 0,
            tick_spacing: 1,
            extension: Zero::zero(),
        },
    );
    let hash_with_different_extension = LegacyHash::<
        PoolKey,
    >::hash(
        0,
        PoolKey {
            token0: 1.try_into().unwrap(),
            token1: 2.try_into().unwrap(),
            fee: 0,
            tick_spacing: 1,
            extension: 3.try_into().unwrap(),
        },
    );
    let hash_with_different_fee = LegacyHash::<
        PoolKey,
    >::hash(
        0,
        PoolKey {
            token0: 1.try_into().unwrap(),
            token1: 2.try_into().unwrap(),
            fee: 1,
            tick_spacing: 1,
            extension: Zero::zero(),
        },
    );
    let hash_with_different_tick_spacing = LegacyHash::<
        PoolKey,
    >::hash(
        0,
        PoolKey {
            token0: 1.try_into().unwrap(),
            token1: 2.try_into().unwrap(),
            fee: 0,
            tick_spacing: 2,
            extension: Zero::zero(),
        },
    );
    assert(hash != hash_with_different_extension, 'not equal');
    assert(hash != hash_with_different_fee, 'not equal');
    assert(hash != hash_with_different_tick_spacing, 'not equal');
}


#[test]
fn test_pool_key_hash_result() {
    assert(
        LegacyHash::<
            PoolKey,
        >::hash(
            1234,
            PoolKey {
                token0: 1.try_into().unwrap(),
                token1: 2.try_into().unwrap(),
                fee: 3,
                tick_spacing: 4,
                extension: 5.try_into().unwrap(),
            },
        ) == 0x2cfe2f704e1821da98a42a506dbd7fa4f356af4a491d2bd0901beedd4027db6,
        'hash',
    );
}

#[test]
fn test_pool_key_hash_result_reverse() {
    assert(
        LegacyHash::<
            PoolKey,
        >::hash(
            4321,
            PoolKey {
                token0: 5.try_into().unwrap(),
                token1: 4.try_into().unwrap(),
                fee: 32,
                tick_spacing: 2,
                extension: 1.try_into().unwrap(),
            },
        ) == 0x48442dcb25c83d8e9eab16c4d669e79407743073e9b76798ec54d528dd35aa2,
        'hash',
    );
}


#[test]
fn test_position_key_hash_differs_for_any_field_or_state_change() {
    let base = PositionKey {
        salt: Zero::zero(),
        owner: Zero::zero(),
        bounds: Bounds { lower: Zero::zero(), upper: Zero::zero() },
    };

    let mut other_salt = base;
    other_salt.salt = 1;

    let mut other_owner = base;
    other_owner.owner = 1.try_into().unwrap();

    let mut other_lower = base;
    other_lower.bounds.lower = i129 { mag: 1, sign: true };

    let mut other_upper = base;
    other_upper.bounds.upper = i129 { mag: 1, sign: false };

    check_hashes_differ(base, other_salt);
    check_hashes_differ(base, other_owner);
    check_hashes_differ(base, other_lower);
    check_hashes_differ(base, other_upper);

    check_hashes_differ(other_salt, other_owner);
    check_hashes_differ(other_salt, other_lower);
    check_hashes_differ(other_salt, other_upper);

    check_hashes_differ(other_owner, other_lower);
    check_hashes_differ(other_owner, other_upper);

    check_hashes_differ(other_lower, other_upper);
}

#[test]
fn test_position_key_hash() {
    let hash = LegacyHash::<
        PositionKey,
    >::hash(
        0,
        PositionKey {
            salt: 0,
            owner: 1.try_into().unwrap(),
            bounds: Bounds { lower: Zero::zero(), upper: Zero::zero() },
        },
    );

    let hash_with_diff_salt = LegacyHash::<
        PositionKey,
    >::hash(
        0,
        PositionKey {
            salt: 1,
            owner: 1.try_into().unwrap(),
            bounds: Bounds { lower: Zero::zero(), upper: Zero::zero() },
        },
    );

    let hash_with_diff_state = LegacyHash::<
        PositionKey,
    >::hash(
        1,
        PositionKey {
            salt: 1,
            owner: 1.try_into().unwrap(),
            bounds: Bounds { lower: Zero::zero(), upper: Zero::zero() },
        },
    );
    assert(hash != hash_with_diff_salt, 'not equal');
    assert(hash != hash_with_diff_state, 'not equal');
}

#[test]
fn test_position_key_hash_result() {
    assert(
        LegacyHash::hash(
            1234,
            PositionKey {
                salt: 1,
                owner: 2.try_into().unwrap(),
                bounds: Bounds {
                    lower: i129 { mag: 3, sign: false }, upper: i129 { mag: 4, sign: false },
                },
            },
        ) == 0x103df9e683d9ca32325eb076200ba9e872904b133018ce0d3943756fcb2d01e,
        'hash',
    );
}

#[test]
fn test_position_key_hash_result_reverse() {
    assert(
        LegacyHash::hash(
            4321,
            PositionKey {
                salt: 5,
                owner: 4.try_into().unwrap(),
                bounds: Bounds {
                    lower: i129 { mag: 2, sign: true }, upper: i129 { mag: 1, sign: true },
                },
            },
        ) == 0x559ca4d70a491d29c8d29d8513a71c3ae28b410766cea8c55859c9097071603,
        'hash',
    );
}

#[test]
fn test_saved_balance_key_hash_differs() {
    let base = SavedBalanceKey {
        owner: 1.try_into().unwrap(), token: 2.try_into().unwrap(), salt: 3,
    };

    let mut other_owner = base;
    other_owner.owner = 2.try_into().unwrap();
    check_hashes_differ(base, other_owner);

    let mut other_token = base;
    other_token.token = 3.try_into().unwrap();
    check_hashes_differ(base, other_token);
    check_hashes_differ(other_owner, other_token);

    let mut other_salt = base;
    other_salt.salt = 4;
    check_hashes_differ(base, other_salt);
    check_hashes_differ(other_owner, other_salt);
    check_hashes_differ(other_token, other_salt);
}

#[test]
fn test_saved_balance_key_hash() {
    assert(
        LegacyHash::hash(
            1,
            SavedBalanceKey { owner: 2.try_into().unwrap(), token: 3.try_into().unwrap(), salt: 4 },
        ) == 0x4c1cec8ca0d266e102559432703b9807b75dae05048908f6dedcb29f125e2da,
        'hash',
    );
}

#[test]
fn test_saved_balance_key_hash_reverse() {
    assert(
        LegacyHash::hash(
            4,
            SavedBalanceKey { owner: 3.try_into().unwrap(), token: 2.try_into().unwrap(), salt: 1 },
        ) == 0x1439c58e1c389a2ac51f8462ecc0a4ec7f812be1c04e3b82ce2af1c2cf959ef,
        'hash',
    );
}
