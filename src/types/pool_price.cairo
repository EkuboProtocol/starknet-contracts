use core::option::OptionTrait;
use core::traits::{Into, TryInto};
use starknet::storage_access::StorePacking;
use crate::math::ticks::{constants as tick_constants, max_sqrt_ratio, min_sqrt_ratio};
use crate::types::i129::{i129, i129Trait};

#[derive(Copy, Drop, Serde, PartialEq)]
pub struct PoolPrice {
    // the current ratio, up to 192 bits
    pub sqrt_ratio: u256,
    // the current tick, up to 32 bits
    pub tick: i129,
}

const X192: u256 = 0x1000000000000000000000000000000000000000000000000;
const DENOMINATOR_X192: NonZero<u256> = 0x1000000000000000000000000000000000000000000000000;
const X8: u128 = 0x100;
const DENOMINATOR_X8: NonZero<u128> = 0x100;
const SIGN_MODIFIER: u128 = 0x100000000;

impl PoolPriceStorePacking of StorePacking<PoolPrice, felt252> {
    fn pack(value: PoolPrice) -> felt252 {
        assert(
            (value.sqrt_ratio >= min_sqrt_ratio()) & (value.sqrt_ratio <= max_sqrt_ratio()),
            'SQRT_RATIO',
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
            'TICK_MAGNITUDE',
        );

        let tick_raw_shifted: u128 = if (value.tick.is_negative()) {
            (value.tick.mag + SIGN_MODIFIER) * X8
        } else {
            value.tick.mag * X8
        };

        let packed = value.sqrt_ratio + ((u256 { low: tick_raw_shifted, high: 0 }) * X192);

        packed.try_into().unwrap()
    }
    fn unpack(value: felt252) -> PoolPrice {
        let packed_first_slot_u256: u256 = value.into();

        // quotient, remainder
        let (tick_call_points, sqrt_ratio) = DivRem::div_rem(
            packed_first_slot_u256, DENOMINATOR_X192,
        );

        let (tick_raw, _call_points_legacy) = DivRem::div_rem(tick_call_points.low, DENOMINATOR_X8);

        let tick = if (tick_raw >= SIGN_MODIFIER) {
            i129 { mag: tick_raw - SIGN_MODIFIER, sign: (tick_raw != SIGN_MODIFIER) }
        } else {
            i129 { mag: tick_raw, sign: false }
        };

        PoolPrice { sqrt_ratio, tick }
    }
}

