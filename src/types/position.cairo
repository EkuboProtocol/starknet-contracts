use ekubo::types::fees_per_liquidity::{FeesPerLiquidity};

// Represents a liquidity position
#[derive(Copy, Drop, Serde, starknet::Store)]
struct Position {
    // the amount of liquidity owned by the position
    liquidity: u128,
    // the fee per liquidity inside the tick range of the position, the last time it was computed
    fees_per_liquidity_inside_last: FeesPerLiquidity,
}

impl PositionDefault of Default<Position> {
    fn default() -> Position {
        Position { liquidity: Zeroable::zero(), fees_per_liquidity_inside_last: Zeroable::zero(),  }
    }
}
