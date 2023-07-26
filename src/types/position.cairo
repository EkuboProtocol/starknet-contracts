// Represents a liquidity position
#[derive(Copy, Drop, Serde, storage_access::StorageAccess)]
struct Position {
    // the amount of liquidity owned by the position
    liquidity: u128,
    // the fee growth inside the tick range of the position, the last time it was computed
    fee_growth_inside_last_token0: u256,
    fee_growth_inside_last_token1: u256,
}

impl PositionDefault of Default<Position> {
    fn default() -> Position {
        Position {
            liquidity: Zeroable::zero(),
            fee_growth_inside_last_token0: Zeroable::zero(),
            fee_growth_inside_last_token1: Zeroable::zero(),
        }
    }
}
