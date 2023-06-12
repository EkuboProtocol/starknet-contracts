use ekubo::types::i129::{i129};
use debug::PrintTrait;

impl DeltaPrint of PrintTrait<Delta> {
    fn print(self: Delta) {
        self.amount0.print();
        self.amount1.print();
    }
}

// From the perspective of the core contract, this represents the change in balances.
// For example, swapping 100 token0 for 150 token1 would result in a Delta of { amount0: 100, amount1: -150 }
// Note in case the price limit is reached, the amount0 or amount1_delta may be less than the amount specified in the swap parameters.
#[derive(Copy, Drop, Serde)]
struct Delta {
    amount0: i129,
    amount1: i129,
}

impl DefaultDelta of Default<Delta> {
    fn default() -> Delta {
        Delta { amount0: Default::default(), amount1: Default::default(),  }
    }
}

impl AddDelta of Add<Delta> {
    fn add(lhs: Delta, rhs: Delta) -> Delta {
        Delta { amount0: lhs.amount0 + rhs.amount0, amount1: lhs.amount1 + rhs.amount1,  }
    }
}

impl DeltaAddEq of AddEq<Delta> {
    #[inline(always)]
    fn add_eq(ref self: Delta, other: Delta) {
        self = Add::add(self, other);
    }
}
