use core::num::traits::Zero;
use starknet::storage_access::StorePacking;
use crate::math::ticks::{max_sqrt_ratio, max_tick, min_sqrt_ratio, min_tick};
use crate::tests::store_packing_test::assert_round_trip;
use crate::types::i129::i129;
use crate::types::pool_price::PoolPrice;

#[test]
fn test_packing_round_trip_many_values() {
    assert_round_trip(
        PoolPrice { sqrt_ratio: 0x100000000000000000000000000000000_u256, tick: Zero::zero() },
    );
    assert_round_trip(PoolPrice { sqrt_ratio: min_sqrt_ratio(), tick: min_tick() });
    assert_round_trip(PoolPrice { sqrt_ratio: max_sqrt_ratio(), tick: max_tick() });
    assert_round_trip(
        PoolPrice { sqrt_ratio: min_sqrt_ratio(), tick: min_tick() - i129 { mag: 1, sign: false } },
    );
    assert_round_trip(
        PoolPrice { sqrt_ratio: u256 { low: 0, high: 123456 }, tick: i129 { mag: 0, sign: false } },
    );
    assert_round_trip(
        PoolPrice { sqrt_ratio: u256 { low: 0, high: 123456 }, tick: i129 { mag: 0, sign: false } },
    );
    assert_round_trip(
        PoolPrice { sqrt_ratio: u256 { low: 0, high: 123456 }, tick: i129 { mag: 0, sign: false } },
    );
}

#[test]
#[should_panic(expected: ('SQRT_RATIO',))]
fn test_fails_if_sqrt_ratio_out_of_range_max() {
    StorePacking::<
        PoolPrice, felt252,
    >::pack(PoolPrice { sqrt_ratio: max_sqrt_ratio() + 1, tick: Zero::zero() });
}

#[test]
#[should_panic(expected: ('SQRT_RATIO',))]
fn test_fails_if_sqrt_ratio_zero() {
    StorePacking::<
        PoolPrice, felt252,
    >::pack(PoolPrice { sqrt_ratio: Zero::zero(), tick: Zero::zero() });
}

#[test]
#[should_panic(expected: ('SQRT_RATIO',))]
fn test_fails_if_sqrt_ratio_one() {
    StorePacking::<PoolPrice, felt252>::pack(PoolPrice { sqrt_ratio: 1, tick: Zero::zero() });
}

#[test]
#[should_panic(expected: ('SQRT_RATIO',))]
fn test_fails_if_sqrt_ratio_out_of_range_min() {
    StorePacking::<
        PoolPrice, felt252,
    >::pack(PoolPrice { sqrt_ratio: min_sqrt_ratio() - 1, tick: Zero::zero() });
}

#[test]
#[should_panic(expected: ('TICK_MAGNITUDE',))]
fn test_fails_if_tick_out_of_range_max() {
    StorePacking::<
        PoolPrice, felt252,
    >::pack(
        PoolPrice {
            sqrt_ratio: 0x100000000000000000000000000000000_u256,
            tick: max_tick() + i129 { mag: 1, sign: false },
        },
    );
}

#[test]
#[should_panic(expected: ('TICK_MAGNITUDE',))]
fn test_fails_if_tick_out_of_range_min() {
    StorePacking::<
        PoolPrice, felt252,
    >::pack(
        PoolPrice {
            sqrt_ratio: 0x100000000000000000000000000000000_u256,
            tick: min_tick() - i129 { mag: 2, sign: false },
        },
    );
}

#[test]
fn test_store_packing_pool_price() {
    let price = StorePacking::<
        PoolPrice, felt252,
    >::unpack(
        StorePacking::<
            PoolPrice, felt252,
        >::pack(
            PoolPrice {
                sqrt_ratio: u256 { low: 0, high: 123456 }, tick: i129 { mag: 100, sign: false },
            },
        ),
    );
    assert(price.sqrt_ratio == u256 { low: 0, high: 123456 }, 'sqrt_ratio');
    assert(price.tick == i129 { mag: 100, sign: false }, 'tick');
}
