use ekubo::types::i129::{i129, i129Trait};
use ekubo::types::call_points::{CallPoints};
use starknet::{StorageBaseAddress, StorePacking};
use zeroable::Zeroable;
use traits::{Into, TryInto};
use option::{OptionTrait, Option};
use integer::{u256_as_non_zero, u128_safe_divmod, u128_as_non_zero, u256_safe_divmod};
use ekubo::math::ticks::{min_sqrt_ratio, max_sqrt_ratio, constants as tick_constants};

#[derive(Copy, Drop, Serde, PartialEq)]
struct PoolPrice {
    // the current ratio, up to 192 bits
    sqrt_ratio: u256,
    // the current tick, up to 32 bits
    tick: i129,
    // the places where specified extension should be called, 5 bits
    call_points: CallPoints,
}

impl PoolPriceStorePacking of StorePacking<PoolPrice, felt252> {
    fn pack(value: PoolPrice) -> felt252 {
        assert(
            (value.sqrt_ratio >= min_sqrt_ratio()) & (value.sqrt_ratio <= max_sqrt_ratio()),
            'SQRT_RATIO'
        );

        // todo: when trading to the minimum tick, the tick is crossed and the pool tick is set to the minimum tick minus one
        // thus the value stored in pool.tick is between min_tick() - 1 and max_tick()
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
            + ((u256 { low: tick_raw_shifted, high: 0 }
                + Into::<u8, u256>::into(value.call_points.into()))
                * 0x1000000000000000000000000000000000000000000000000);

        packed.try_into().unwrap()
    }
    fn unpack(value: felt252) -> PoolPrice {
        let packed_first_slot_u256: u256 = value.into();

        // quotient, remainder
        let (tick_call_points, sqrt_ratio, _) = u256_safe_divmod(
            packed_first_slot_u256,
            u256_as_non_zero(0x1000000000000000000000000000000000000000000000000) // 2n ** 192n
        );

        let (tick_raw, call_points_raw) = u128_safe_divmod(
            tick_call_points.low, u128_as_non_zero(0x100)
        );

        let tick = if (tick_raw >= 0x100000000) {
            i129 { mag: tick_raw - 0x100000000, sign: (tick_raw != 0x100000000) }
        } else {
            i129 { mag: tick_raw, sign: false }
        };

        let call_points: CallPoints = TryInto::<u8,
        CallPoints>::try_into(TryInto::<u128, u8>::try_into(call_points_raw).unwrap())
            .unwrap();

        PoolPrice { sqrt_ratio, tick, call_points }
    }
}

