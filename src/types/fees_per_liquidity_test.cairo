use ekubo::types::i129::{i129};
use ekubo::types::fees_per_liquidity::{FeesPerLiquidity, fees_per_liquidity_new};
use zeroable::Zeroable;
use debug::PrintTrait;

const FELT252_MAX: felt252 =
    3618502788666131213697322783095070105623107215331596699973092056135872020480;

#[test]
fn test_fpl_zeroable() {
    let fpl: FeesPerLiquidity = Zeroable::zero();
    assert(fpl.fees_per_liquidity_token0 == Zeroable::zero(), 'fpl0');
    assert(fpl.fees_per_liquidity_token1 == Zeroable::zero(), 'fpl1');
    assert(!fpl.is_non_zero(), 'nonzero');
    assert(fpl.is_zero(), 'zero');
}

#[test]
fn test_fpl_add_sub_zeroable() {
    let fpl: FeesPerLiquidity = Zeroable::zero();
    assert(!(fpl + fpl).is_non_zero(), 'nonzero');
    assert(!(fpl - fpl).is_non_zero(), 'nonzero');
    assert((fpl + fpl).is_zero(), 'zero');
    assert((fpl - fpl).is_zero(), 'zero');
}

#[test]
fn test_fpl_underflow_sub() {
    let fpl_zero: FeesPerLiquidity = Zeroable::zero();
    let fpl_one = FeesPerLiquidity { fees_per_liquidity_token0: 1, fees_per_liquidity_token1: 1 };

    let difference = fpl_zero - fpl_one;

    assert(
        difference == FeesPerLiquidity {
            fees_per_liquidity_token0: FELT252_MAX, fees_per_liquidity_token1: FELT252_MAX, 
        },
        'overflow'
    );
}

#[test]
fn test_fpl_overflow_add() {
    let fpl_one = FeesPerLiquidity { fees_per_liquidity_token0: 1, fees_per_liquidity_token1: 1 };

    let fpl_max = FeesPerLiquidity {
        fees_per_liquidity_token0: FELT252_MAX, fees_per_liquidity_token1: FELT252_MAX
    };

    let sum = fpl_max + fpl_one;

    assert(
        sum == FeesPerLiquidity { fees_per_liquidity_token0: 0, fees_per_liquidity_token1: 0,  },
        'sum'
    );
}

#[test]
fn test_to_fees_per_liquidity() {
    assert(
        fees_per_liquidity_new(100, 250, 10000) == FeesPerLiquidity {
            fees_per_liquidity_token0: 3402823669209384634633746074317682114,
            fees_per_liquidity_token1: 8507059173023461586584365185794205286
        },
        'example'
    );
}

#[test]
fn test_storage_size() {
    assert(starknet::Store::<FeesPerLiquidity>::size() == 2, 'size');
}
