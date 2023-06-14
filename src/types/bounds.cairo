use ekubo::math::ticks::{min_tick, max_tick, constants as tick_constants};
use starknet::ContractAddress;
use ekubo::types::keys::{PositionKey, PoolKey};
use ekubo::types::i129::{i129};
use traits::Into;

// Bounds for a position
#[derive(Copy, Drop, Serde)]
struct Bounds {
    tick_lower: i129,
    tick_upper: i129
}

mod internal {
    use super::i129;

    fn bounded_tick_to_u128(x: i129) -> u128 {
        assert(x.mag < 0x80000000, 'BOUNDS_MAG');
        if (x.mag == 0) {
            0
        } else {
            (x.mag + if x.sign {
                0x80000000
            } else {
                0
            })
        }
    }
}

// Converts the bounds into a felt for hashing
impl BoundsIntoFelt252 of Into<Bounds, felt252> {
    fn into(self: Bounds) -> felt252 {
        ((internal::bounded_tick_to_u128(self.tick_lower) * 0x100000000)
            + internal::bounded_tick_to_u128(self.tick_upper))
            .into()
    }
}

// Returns the max usable bounds given the tick spacing
fn max_bounds(tick_spacing: u128) -> Bounds {
    assert(tick_spacing != 0, 'MAX_BOUNDS_TICK_SPACING_ZERO');
    assert(tick_spacing <= tick_constants::MAX_TICK_MAGNITUDE, 'MAX_BOUNDS_TICK_SPACING_LARGE');
    let mag = (tick_constants::MAX_TICK_MAGNITUDE / tick_spacing) * tick_spacing;
    Bounds { tick_lower: i129 { mag, sign: true }, tick_upper: i129 { mag, sign: false } }
}

impl DefaultBounds of Default<Bounds> {
    fn default() -> Bounds {
        Bounds { tick_lower: min_tick(), tick_upper: max_tick() }
    }
}

#[generate_trait]
impl CheckBoundsValidImpl of CheckBoundsValidTrait {
    fn check_valid(self: Bounds, tick_spacing: u128) {
        assert(self.tick_lower < self.tick_upper, 'BOUNDS_ORDER');
        assert(self.tick_lower >= min_tick(), 'BOUNDS_MIN');
        assert(self.tick_upper <= max_tick(), 'BOUNDS_MAX');
        assert(
            ((self.tick_lower.mag % tick_spacing) == 0)
                & ((self.tick_upper.mag % tick_spacing) == 0),
            'BOUNDS_TICK_SPACING'
        );
    }
}
