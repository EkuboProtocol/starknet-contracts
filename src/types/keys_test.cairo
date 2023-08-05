use ekubo::types::keys::{PoolKey, PoolKeyTrait, PositionKey};
use ekubo::types::i129::{i129};
use ekubo::types::bounds::{Bounds};
use starknet::{contract_address_const};
use hash::{LegacyHash};
use ekubo::math::ticks::{constants as tick_constants};
use debug::PrintTrait;

fn check_hashes_differ<
    T, impl TLegacyHash: LegacyHash<T>, impl TCopy: Copy<T>, impl TDrop: Drop<T>
>(
    x: T, y: T
) {
    let a = LegacyHash::<T>::hash(0, x);
    let b = LegacyHash::<T>::hash(0, y);
    let c = LegacyHash::<T>::hash(1, x);
    let d = LegacyHash::<T>::hash(1, y);
    assert((a != b) & (a != c) & (a != d) & (b != c) & (b != d) & (c != d), 'hashes differ');
}

#[test]
fn test_pool_key_hash_differs_for_any_field_or_state_change() {
    let base = PoolKey {
        token0: Zeroable::zero(),
        token1: Zeroable::zero(),
        fee: Zeroable::zero(),
        tick_spacing: Zeroable::zero(),
        extension: Zeroable::zero(),
    };

    let mut other_token0 = base;
    other_token0.token0 = contract_address_const::<1>();
    check_hashes_differ(base, other_token0);

    let mut other_token1 = base;
    other_token1.token1 = contract_address_const::<1>();
    check_hashes_differ(base, other_token1);

    let mut other_fee = base;
    other_fee.fee = 1;
    check_hashes_differ(base, other_fee);

    let mut other_tick_spacing = base;
    other_tick_spacing.tick_spacing = 1;
    check_hashes_differ(base, other_tick_spacing);

    let mut other_extension = base;
    other_extension.extension = contract_address_const::<1>();
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
#[should_panic(expected: ('TOKEN_ORDER', ))]
fn test_pool_key_check_valid_order_wrong_order() {
    PoolKey {
        token0: contract_address_const::<2>(),
        token1: contract_address_const::<0>(),
        fee: Zeroable::zero(),
        tick_spacing: 1,
        extension: Zeroable::zero(),
    }.check_valid();
}

#[test]
#[should_panic(expected: ('TOKEN_ORDER', ))]
fn test_pool_key_check_valid_order_same_token() {
    PoolKey {
        token0: contract_address_const::<1>(),
        token1: contract_address_const::<1>(),
        fee: Zeroable::zero(),
        tick_spacing: 1,
        extension: Zeroable::zero(),
    }.check_valid();
}

#[test]
#[should_panic(expected: ('TOKEN_NON_ZERO', ))]
fn test_pool_key_check_non_zero() {
    PoolKey {
        token0: contract_address_const::<0>(),
        token1: contract_address_const::<2>(),
        fee: Zeroable::zero(),
        tick_spacing: 1,
        extension: Zeroable::zero(),
    }.check_valid();
}

#[test]
#[should_panic(expected: ('TICK_SPACING', ))]
fn test_pool_key_check_tick_spacing_non_zero() {
    PoolKey {
        token0: contract_address_const::<1>(),
        token1: contract_address_const::<2>(),
        fee: Zeroable::zero(),
        tick_spacing: Zeroable::zero(),
        extension: Zeroable::zero(),
    }.check_valid();
}

#[test]
#[should_panic(expected: ('TICK_SPACING', ))]
fn test_pool_key_check_tick_spacing_max() {
    PoolKey {
        token0: contract_address_const::<1>(),
        token1: contract_address_const::<2>(),
        fee: Zeroable::zero(),
        tick_spacing: tick_constants::MAX_TICK_SPACING + 1,
        extension: Zeroable::zero(),
    }.check_valid();
}

#[test]
fn test_pool_key_check_valid_is_valid() {
    PoolKey {
        token0: contract_address_const::<1>(),
        token1: contract_address_const::<2>(),
        fee: Zeroable::zero(),
        tick_spacing: 1,
        extension: Zeroable::zero(),
    }.check_valid();

    PoolKey {
        token0: contract_address_const::<1>(),
        token1: contract_address_const::<2>(),
        fee: Zeroable::zero(),
        tick_spacing: tick_constants::MAX_TICK_SPACING,
        extension: Zeroable::zero(),
    }.check_valid();

    PoolKey {
        token0: contract_address_const::<1>(),
        token1: contract_address_const::<2>(),
        fee: 0xffffffffffffffffffffffffffffffff,
        tick_spacing: tick_constants::MAX_TICK_SPACING,
        extension: Zeroable::zero(),
    }.check_valid();

    PoolKey {
        token0: contract_address_const::<1>(),
        token1: contract_address_const::<2>(),
        fee: 0xffffffffffffffffffffffffffffffff,
        tick_spacing: tick_constants::MAX_TICK_SPACING,
        extension: contract_address_const::<2>(),
    }.check_valid();
}

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
fn test_position_key_hash_differs_for_any_field_or_state_change() {
    let base = PositionKey {
        salt: Zeroable::zero(), owner: Zeroable::zero(), bounds: Bounds {
            lower: Zeroable::zero(), upper: Zeroable::zero()
        }
    };

    let mut other_salt = base;
    other_salt.salt = 1;

    let mut other_owner = base;
    other_owner.owner = contract_address_const::<1>();

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

    assert(hash == 0xae1cb865e2141d5a02075e11fdafd23e0459cf254cfc7511d346c1fcee1123, 'id');
    assert(hash != hash_with_diff_salt, 'not equal');
    assert(hash != hash_with_diff_state, 'not equal');
}
