use core::num::traits::{Zero};
use core::option::{OptionTrait};
use core::traits::{TryInto, Into};
use ekubo::math::muldiv::{div};

#[derive(Copy, Drop, Serde, PartialEq, starknet::Store, Debug)]
pub struct FeesPerLiquidity {
    pub value0: felt252,
    pub value1: felt252,
}

impl AddFeesPerLiquidity of Add<FeesPerLiquidity> {
    #[inline(always)]
    fn add(lhs: FeesPerLiquidity, rhs: FeesPerLiquidity) -> FeesPerLiquidity {
        FeesPerLiquidity { value0: lhs.value0 + rhs.value0, value1: lhs.value1 + rhs.value1, }
    }
}

impl SubFeesPerLiquidity of Sub<FeesPerLiquidity> {
    #[inline(always)]
    fn sub(lhs: FeesPerLiquidity, rhs: FeesPerLiquidity) -> FeesPerLiquidity {
        FeesPerLiquidity { value0: lhs.value0 - rhs.value0, value1: lhs.value1 - rhs.value1, }
    }
}

impl FeesPerLiquidityZero of Zero<FeesPerLiquidity> {
    #[inline(always)]
    fn zero() -> FeesPerLiquidity {
        FeesPerLiquidity { value0: Zero::zero(), value1: Zero::zero() }
    }
    #[inline(always)]
    fn is_zero(self: @FeesPerLiquidity) -> bool {
        (self.value0.is_zero()) & (self.value1.is_zero())
    }
    #[inline(always)]
    fn is_non_zero(self: @FeesPerLiquidity) -> bool {
        !Zero::is_zero(self)
    }
}

#[inline(always)]
pub fn to_fees_per_liquidity(amount: u128, liquidity: u128) -> felt252 {
    assert(liquidity.is_non_zero(), 'ZERO_LIQUIDITY_FEES');
    (u256 { low: 0, high: amount } / liquidity.into()).try_into().expect('FEES_OVERFLOW')
}

#[inline(always)]
pub fn fees_per_liquidity_new(amount0: u128, amount1: u128, liquidity: u128) -> FeesPerLiquidity {
    FeesPerLiquidity {
        value0: to_fees_per_liquidity(amount0, liquidity),
        value1: to_fees_per_liquidity(amount1, liquidity),
    }
}

#[inline(always)]
pub fn fees_per_liquidity_from_amount0(amount0: u128, liquidity: u128) -> FeesPerLiquidity {
    FeesPerLiquidity { value0: to_fees_per_liquidity(amount0, liquidity), value1: Zero::zero(), }
}

#[inline(always)]
pub fn fees_per_liquidity_from_amount1(amount1: u128, liquidity: u128) -> FeesPerLiquidity {
    FeesPerLiquidity { value0: Zero::zero(), value1: to_fees_per_liquidity(amount1, liquidity), }
}
