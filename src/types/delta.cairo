use ekubo::types::i129::{i129};
use debug::PrintTrait;

impl DeltaPrint of PrintTrait<Delta> {
    fn print(self: Delta) {
        self.amount0_delta.print();
        self.amount1_delta.print();
    }
}

// From the perspective of the core contract, this represents the change in balances.
// For example, swapping 100 token0 for 150 token1 would result in a Delta of { amount0_delta: 100, amount1_delta: -150 }
// Note in case the price limit is reached, the amount0_delta or amount1_delta may be less than the amount specified in the swap parameters.
#[derive(Copy, Drop, Serde)]
struct Delta {
    amount0_delta: i129,
    amount1_delta: i129,
}

impl DefaultDelta of Default<Delta> {
    fn default() -> Delta {
        Delta { amount0_delta: Default::default(), amount1_delta: Default::default(),  }
    }
}
