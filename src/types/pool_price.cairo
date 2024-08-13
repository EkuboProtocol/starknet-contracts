use core::num::traits::{Zero};
use core::option::{OptionTrait, Option};
use core::traits::{Into, TryInto};
use ekubo::math::ticks::{min_sqrt_ratio, max_sqrt_ratio, constants as tick_constants};
use ekubo::types::call_points::{CallPoints};
use ekubo::types::i129::{i129, i129Trait};
use starknet::storage_access::{StorageBaseAddress, StorePacking};

#[derive(Copy, Drop, Serde, PartialEq)]
pub struct PoolPrice {
    // the current ratio, up to 192 bits
    pub sqrt_ratio: u256,
    // the current tick, up to 32 bits
    pub tick: i129,
}

impl PoolPriceStorePacking of StorePacking<PoolPrice, felt252> {
    fn pack(value: PoolPrice) -> felt252 {
        assert(
            (value.sqrt_ratio >= min_sqrt_ratio()) & (value.sqrt_ratio <= max_sqrt_ratio()),
            'SQRT_RATIO'
        );

        // todo: when trading to the minimum tick, the tick is crossed and the pool tick is set to
        // the minimum tick minus one thus the value stored in pool.tick is between min_tick() - 1
        // and max_tick()
        assert(
            if (value.tick.sign) {
                value.tick.mag <= (tick_constants::MAX_TICK_MAGNITUDE + 1)
            } else {
                value.tick.mag <= tick_constants::MAX_TICK_MAGNITUDE
            },
            'TICK_MAGNITUDE'
        );

        let tick_raw_shifted: u128 = if (value.tick.is_negative()) {
            (value.tick.mag + 0x100000000) * 0x100
        } else {
            value.tick.mag * 0x100
        };

        let packed = value.sqrt_ratio
            + ((u256 { low: tick_raw_shifted, high: 0 })
                * 0x1000000000000000000000000000000000000000000000000);

        packed.try_into().unwrap()
    }
    fn unpack(value: felt252) -> PoolPrice {
        let packed_first_slot_u256: u256 = value.into();

        // quotient, remainder
        let (tick_call_points, sqrt_ratio) = DivRem::div_rem(
            packed_first_slot_u256,
            // 2n ** 192n
            0x1000000000000000000000000000000000000000000000000_u256.try_into().unwrap()
        );

        let (tick_raw, _call_points_legacy) = DivRem::div_rem(
            tick_call_points.low, 0x100_u128.try_into().unwrap()
        );

        let tick = if (tick_raw >= 0x100000000) {
            i129 { mag: tick_raw - 0x100000000, sign: (tick_raw != 0x100000000) }
        } else {
            i129 { mag: tick_raw, sign: false }
        };

        PoolPrice { sqrt_ratio, tick }
    }
}

