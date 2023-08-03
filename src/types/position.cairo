use ekubo::types::fees_per_liquidity::{FeesPerLiquidity};
use zeroable::{Zeroable};
use ekubo::math::muldiv::{muldiv};
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
    use super::{Into};

    // we only use the lower 128 bits from this calculation, and if accumulated fees overflow a u128 they are simply discarded
    // we discard the fees instead of asserting because we do not want to fail a withdrawal due to too many fees being accumulated
    // this is an optimized wide multiplication that only cares about limb1
    fn fees_from_fpl_difference(difference: felt252, liquidity: u128) -> u128 {
        let a: u256 = difference.into();

        let (limb1, limb0) = u128_wide_mul(a.low, liquidity);
        let (_, limb1_part) = u128_wide_mul(a.high, liquidity);
        let (limb1, _) = u128_add_with_carry(limb1, limb1_part);
        limb1
    }
}


#[generate_trait]
impl PositionTraitImpl of PositionTrait {
    fn fees(self: Position, fees_per_liquidity_inside_current: FeesPerLiquidity) -> (u128, u128) {
        let diff = fees_per_liquidity_inside_current - self.fees_per_liquidity_inside_last;

        (
            internal::fees_from_fpl_difference(diff.fees_per_liquidity_token0, self.liquidity),
            internal::fees_from_fpl_difference(diff.fees_per_liquidity_token1, self.liquidity)
        )
    }
}
