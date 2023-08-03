use traits::{TryInto, Into};
use option::{OptionTrait};
use ekubo::math::muldiv::{div};
use zeroable::{Zeroable};

#[derive(Copy, Drop, Serde, starknet::Store)]
struct FeesPerLiquidity {
    fees_per_liquidity_token0: felt252,
    fees_per_liquidity_token1: felt252,
}

impl AddFeesPerLiquidity of Add<FeesPerLiquidity> {
    fn add(lhs: FeesPerLiquidity, rhs: FeesPerLiquidity) -> FeesPerLiquidity {
        FeesPerLiquidity {
            fees_per_liquidity_token0: lhs.fees_per_liquidity_token0
                + rhs.fees_per_liquidity_token0,
            fees_per_liquidity_token1: lhs.fees_per_liquidity_token1
                + rhs.fees_per_liquidity_token1,
        }
    }
}

impl SubFeesPerLiquidity of Sub<FeesPerLiquidity> {
    fn sub(lhs: FeesPerLiquidity, rhs: FeesPerLiquidity) -> FeesPerLiquidity {
        FeesPerLiquidity {
            fees_per_liquidity_token0: lhs.fees_per_liquidity_token0
                - rhs.fees_per_liquidity_token0,
            fees_per_liquidity_token1: lhs.fees_per_liquidity_token1
                - rhs.fees_per_liquidity_token1,
        }
    }
}

impl FeesPerLiquidityPartialEq of PartialEq<FeesPerLiquidity> {
    fn eq(lhs: @FeesPerLiquidity, rhs: @FeesPerLiquidity) -> bool {
        (lhs.fees_per_liquidity_token0 == rhs.fees_per_liquidity_token0)
            & (lhs.fees_per_liquidity_token1 == rhs.fees_per_liquidity_token1)
    }
    fn ne(lhs: @FeesPerLiquidity, rhs: @FeesPerLiquidity) -> bool {
        !PartialEq::eq(lhs, rhs)
    }
}

impl FeesPerLiquidityZeroable of Zeroable<FeesPerLiquidity> {
    fn zero() -> FeesPerLiquidity {
        FeesPerLiquidity {
            fees_per_liquidity_token0: Zeroable::zero(), fees_per_liquidity_token1: Zeroable::zero()
        }
    }
    fn is_zero(self: FeesPerLiquidity) -> bool {
        (self.fees_per_liquidity_token0.is_zero()) & (self.fees_per_liquidity_token1.is_zero())
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
        fees_per_liquidity_token0: to_fees_per_liquidity(amount0, liquidity),
        fees_per_liquidity_token1: to_fees_per_liquidity(amount1, liquidity),
    }
}

fn fees_per_liquidity_from_amount0(amount0: u128, liquidity: u128) -> FeesPerLiquidity {
    FeesPerLiquidity {
        fees_per_liquidity_token0: to_fees_per_liquidity(amount0, liquidity),
        fees_per_liquidity_token1: Zeroable::zero(),
    }
}

fn fees_per_liquidity_from_amount1(amount1: u128, liquidity: u128) -> FeesPerLiquidity {
    FeesPerLiquidity {
        fees_per_liquidity_token0: Zeroable::zero(),
        fees_per_liquidity_token1: to_fees_per_liquidity(amount1, liquidity),
    }
}
