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

fn bounded_tick_to_u128(x: i129) -> u128 {
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

// Converts the bounds into a felt for hashing
impl BoundsIntoFelt252 of Into<Bounds, felt252> {
    fn into(self: Bounds) -> felt252 {
        ((bounded_tick_to_u128(self.tick_lower) * 0x100000000)
            + bounded_tick_to_u128(self.tick_upper))
            .into()
    }
}

// Returns the max usable bounds given the tick spacing
fn max_bounds(tick_spacing: u128) -> Bounds {
    assert(tick_spacing != 0, 'TICK_SPACING_MAX_BOUNDS');
    let mag = (tick_constants::MAX_TICK_MAGNITUDE / tick_spacing) * tick_spacing;
    Bounds { tick_lower: i129 { mag, sign: true }, tick_upper: i129 { mag, sign: false } }
}

impl DefaultBounds of Default<Bounds> {
    fn default() -> Bounds {
        Bounds { tick_lower: min_tick(), tick_upper: max_tick() }
    }
}

// Checks that the bounds are valid for the given tick spacing
fn check_bounds_valid(bounds: Bounds, tick_spacing: u128) {
    assert(bounds.tick_lower < bounds.tick_upper, 'BOUNDS_ORDER');
    assert(bounds.tick_lower >= min_tick(), 'BOUNDS_MIN');
    assert(bounds.tick_upper <= max_tick(), 'BOUNDS_MAX');
    assert(
        ((bounds.tick_lower.mag % tick_spacing) == 0)
            & ((bounds.tick_upper.mag % tick_spacing) == 0),
        'BOUNDS_TICK_SPACING'
    );
}
