use core::num::traits::{Zero};
use core::traits::{Into};
use ekubo::math::muldiv::{muldiv};
use ekubo::types::fees_per_liquidity::{FeesPerLiquidity};

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
impl PositionZero of Zero<Position> {
    #[inline(always)]
    fn zero() -> Position {
        Position { liquidity: Zero::zero(), fees_per_liquidity_inside_last: Zero::zero() }
    }

    #[inline(always)]
    fn is_zero(self: @Position) -> bool {
        self.liquidity.is_zero()
    }

    #[inline(always)]
    fn is_non_zero(self: @Position) -> bool {
        !self.liquidity.is_zero()
    }
}

pub(crate) fn multiply_and_get_limb1(a: u256, b: u128) -> u128 {
    muldiv(a, b.into(), 0x100000000000000000000000000000000, false).unwrap().low
}

#[generate_trait]
impl PositionTraitImpl of PositionTrait {
    fn fees(self: Position, fees_per_liquidity_inside_current: FeesPerLiquidity) -> (u128, u128) {
        let diff = fees_per_liquidity_inside_current - self.fees_per_liquidity_inside_last;

        // we only use the lower 128 bits from this calculation, and if accumulated fees overflow a u128 they are simply discarded
        // we discard the fees instead of asserting because we do not want to fail a withdrawal due to too many fees being accumulated
        // this is an optimized wide multiplication that only cares about limb1
        (
            multiply_and_get_limb1(diff.value0.into(), self.liquidity),
            multiply_and_get_limb1(diff.value1.into(), self.liquidity)
        )
    }
}
