use ekubo::math::ticks::{min_tick, max_tick, constants as tick_constants};
use starknet::ContractAddress;
use ekubo::types::keys::{PositionKey, PoolKey};
use ekubo::types::i129::{i129, i129Trait};
use traits::{Into};

// Tick bounds for a position
#[derive(Copy, Drop, Serde, PartialEq, Hash)]
struct Bounds {
    lower: i129,
    upper: i129
}

// Returns the max usable bounds given the tick spacing
fn max_bounds(tick_spacing: u128) -> Bounds {
    assert(tick_spacing != 0, 'MAX_BOUNDS_TICK_SPACING_ZERO');
    assert(tick_spacing <= tick_constants::MAX_TICK_MAGNITUDE, 'MAX_BOUNDS_TICK_SPACING_LARGE');
    let mag = (tick_constants::MAX_TICK_MAGNITUDE / tick_spacing) * tick_spacing;
    Bounds { lower: i129 { mag, sign: true }, upper: i129 { mag, sign: false } }
}

#[generate_trait]
impl BoudnsTraitImpl of BoundsTrait {
    fn check_valid(self: Bounds, tick_spacing: u128) {
        assert(self.lower < self.upper, 'BOUNDS_ORDER');
        assert(self.lower >= min_tick(), 'BOUNDS_MIN');
        assert(self.upper <= max_tick(), 'BOUNDS_MAX');
        assert(
            ((self.lower.mag % tick_spacing) == 0) & ((self.upper.mag % tick_spacing) == 0),
            'BOUNDS_TICK_SPACING'
        );
    }
}
