use core::option::{OptionTrait};
use core::traits::{TryInto, Into};
use ekubo::types::i129::{i129};
use starknet::storage_access::{StorePacking};

#[derive(Copy, Drop, PartialEq, Serde)]
pub struct Snapshot {
    // The timestamp of the block when the snapshot was taken
    pub block_timestamp: u64,
    // The cumulative value of tick * seconds passed since the pool was initialized to the time this
    // snapshot was taken
    pub tick_cumulative: i129,
}

impl SnapshotPacking of StorePacking<Snapshot, felt252> {
    fn pack(value: Snapshot) -> felt252 {
        let total = u256 {
            high: if value.tick_cumulative.sign {
                value.block_timestamp.into() + 0x10000000000000000_u128
            } else {
                value.block_timestamp.into()
            },
            low: value.tick_cumulative.mag
        };
        total.try_into().unwrap()
    }

    fn unpack(value: felt252) -> Snapshot {
        let split: u256 = value.into();

        let (block_timestamp, sign) = if split.high >= 0x10000000000000000_u128 {
            (split.high - 0x10000000000000000_u128, true)
        } else {
            (split.high, false)
        };

        Snapshot {
            block_timestamp: block_timestamp.try_into().unwrap(),
            tick_cumulative: i129 { mag: split.low, sign }
        }
    }
}
