use traits::{TryInto, Into};
use option::{OptionTrait};
use ekubo::math::muldiv::{div};
use zeroable::{Zeroable};

#[derive(Copy, Drop, Serde, starknet::Store)]
struct FeesPerLiquidity {
    value0: felt252,
    value1: felt252,
}

impl AddFeesPerLiquidity of Add<FeesPerLiquidity> {
    fn add(lhs: FeesPerLiquidity, rhs: FeesPerLiquidity) -> FeesPerLiquidity {
        FeesPerLiquidity { value0: lhs.value0 + rhs.value0, value1: lhs.value1 + rhs.value1,  }
    }
}

impl SubFeesPerLiquidity of Sub<FeesPerLiquidity> {
    fn sub(lhs: FeesPerLiquidity, rhs: FeesPerLiquidity) -> FeesPerLiquidity {
        FeesPerLiquidity { value0: lhs.value0 - rhs.value0, value1: lhs.value1 - rhs.value1,  }
    }
}

impl FeesPerLiquidityPartialEq of PartialEq<FeesPerLiquidity> {
    fn eq(lhs: @FeesPerLiquidity, rhs: @FeesPerLiquidity) -> bool {
        (lhs.value0 == rhs.value0) & (lhs.value1 == rhs.value1)
    }
    fn ne(lhs: @FeesPerLiquidity, rhs: @FeesPerLiquidity) -> bool {
        !PartialEq::eq(lhs, rhs)
    }
}

impl FeesPerLiquidityZeroable of Zeroable<FeesPerLiquidity> {
    fn zero() -> FeesPerLiquidity {
        FeesPerLiquidity { value0: Zeroable::zero(), value1: Zeroable::zero() }
    }
    fn is_zero(self: FeesPerLiquidity) -> bool {
        (self.value0.is_zero()) & (self.value1.is_zero())
    }
    fn is_non_zero(self: FeesPerLiquidity) -> bool {
        !Zeroable::is_zero(self)
    }
}

fn to_fees_per_liquidity(amount: u128, liquidity: u128) -> felt252 {
    assert(liquidity.is_non_zero(), 'ZERO_LIQUIDITY_FEES');
    (u256 { low: 0, high: amount } / liquidity.into()).try_into().expect('FEES_OVERFLOW')
}

fn fees_per_liquidity_new(amount0: u128, amount1: u128, liquidity: u128) -> FeesPerLiquidity {
    FeesPerLiquidity {
        value0: to_fees_per_liquidity(amount0, liquidity),
        value1: to_fees_per_liquidity(amount1, liquidity),
    }
}

fn fees_per_liquidity_from_amount0(amount0: u128, liquidity: u128) -> FeesPerLiquidity {
    FeesPerLiquidity {
        value0: to_fees_per_liquidity(amount0, liquidity), value1: Zeroable::zero(), 
    }
}

fn fees_per_liquidity_from_amount1(amount1: u128, liquidity: u128) -> FeesPerLiquidity {
    FeesPerLiquidity {
        value0: Zeroable::zero(), value1: to_fees_per_liquidity(amount1, liquidity), 
    }
}
