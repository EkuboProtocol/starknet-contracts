use ekubo::types::fees_per_liquidity::{FeesPerLiquidity};
use zeroable::{Zeroable};
use traits::{Into};

// Represents a liquidity position
// Packed together in a single struct because whenever liquidity changes we typically change fees per liquidity as well
#[derive(Copy, Drop, Serde, starknet::Store)]
struct Position {
    // the amount of liquidity owned by the position
    liquidity: u128,
    // the fee per liquidity inside the tick range of the position, the last time it was computed
    fees_per_liquidity_inside_last: FeesPerLiquidity,
}

// we only check liquidity is non-zero because fees per liquidity inside is irrelevant if liquidity is 0
impl PositionZeroable of Zeroable<Position> {
    fn zero() -> Position {
        Position { liquidity: Zeroable::zero(), fees_per_liquidity_inside_last: Zeroable::zero() }
    }

    fn is_zero(self: Position) -> bool {
        self.liquidity.is_zero()
    }

    fn is_non_zero(self: Position) -> bool {
        !self.liquidity.is_zero()
    }
}

mod internal {
    use integer::{u128_wide_mul, u128_add_with_carry};

    fn multiply_and_get_limb1(a: u256, b: u128) -> u128 {
        let (limb1_p0, _) = u128_wide_mul(a.low, b);
        let (_, limb1_p1) = u128_wide_mul(a.high, b);
        let (limb1, _) = u128_add_with_carry(limb1_p0, limb1_p1);
        limb1
    }
}


#[generate_trait]
impl PositionTraitImpl of PositionTrait {
    fn fees(self: Position, fees_per_liquidity_inside_current: FeesPerLiquidity) -> (u128, u128) {
        let diff = fees_per_liquidity_inside_current - self.fees_per_liquidity_inside_last;

        // we only use the lower 128 bits from this calculation, and if accumulated fees overflow a u128 they are simply discarded
        // we discard the fees instead of asserting because we do not want to fail a withdrawal due to too many fees being accumulated
        // this is an optimized wide multiplication that only cares about limb1
        (
            internal::multiply_and_get_limb1(diff.value0.into(), self.liquidity),
            internal::multiply_and_get_limb1(diff.value1.into(), self.liquidity)
        )
    }
}
