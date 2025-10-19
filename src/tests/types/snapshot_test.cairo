use core::num::traits::Zero;
use starknet::storage_access::StorePacking;
use crate::types::i129::i129;
use crate::types::snapshot::Snapshot;

fn assert_round_trip<T, U, +StorePacking<T, U>, +PartialEq<T>, +Drop<T>, +Copy<T>>(value: T) {
    assert(StorePacking::<T, U>::unpack(StorePacking::<T, U>::pack(value)) == value, 'roundtrip');
}

#[test]
fn test_pool_state_packing_round_trip_many_values() {
    assert_round_trip(Snapshot { block_timestamp: Zero::zero(), tick_cumulative: Zero::zero() });
    assert_round_trip(
        Snapshot { block_timestamp: 1, tick_cumulative: i129 { mag: 2, sign: false } },
    );
    assert_round_trip(
        Snapshot { block_timestamp: 1, tick_cumulative: i129 { mag: 2, sign: true } },
    );
    assert_round_trip(
        Snapshot {
            block_timestamp: 0xffffffffffffffff,
            tick_cumulative: i129 { mag: 0x7fffffffffffffffffffffff, sign: false },
        },
    );
    assert_round_trip(
        Snapshot {
            block_timestamp: 0xffffffffffffffff,
            tick_cumulative: i129 { mag: 0x7fffffffffffffffffffffff, sign: true },
        },
    );
    assert_round_trip(
        Snapshot {
            block_timestamp: 0,
            tick_cumulative: i129 { mag: 0xffffffffffffffffffffffffffffffff, sign: false },
        },
    );
    assert_round_trip(
        Snapshot {
            block_timestamp: 0xffffffffffffffff, tick_cumulative: i129 { mag: 0, sign: false },
        },
    );
    assert_round_trip(
        Snapshot {
            block_timestamp: 0xffffffffffffffff,
            tick_cumulative: i129 { mag: 0xffffffffffffffffffffffffffffffff, sign: false },
        },
    );
    assert_round_trip(
        Snapshot {
            block_timestamp: 0,
            tick_cumulative: i129 { mag: 0xffffffffffffffffffffffffffffffff, sign: true },
        },
    );
    assert_round_trip(
        Snapshot {
            block_timestamp: 0xffffffffffffffff,
            tick_cumulative: i129 { mag: 0xffffffffffffffffffffffffffffffff, sign: true },
        },
    );
}
