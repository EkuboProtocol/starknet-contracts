use ekubo::types::i129::{i129};
use ekubo::types::fees_per_liquidity::{
    FeesPerLiquidity, to_fees_per_liquidity, fees_per_liquidity_new
};
use zeroable::{Zeroable};

const FELT252_MAX: felt252 =
    3618502788666131213697322783095070105623107215331596699973092056135872020480;

#[test]
fn test_felt252_max_plus_one_is_zero() {
    assert((FELT252_MAX + 1) == 0, 'max+1');
    assert((0_felt252 - 1) == FELT252_MAX, '0-1');
}

#[test]
fn test_fpl_zeroable() {
    let fpl: FeesPerLiquidity = Zeroable::zero();
    assert(fpl.value0 == Zeroable::zero(), 'fpl0');
    assert(fpl.value1 == Zeroable::zero(), 'fpl1');
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
    let fpl_one = FeesPerLiquidity { value0: 1, value1: 1 };

    let difference = fpl_zero - fpl_one;

    assert(difference == FeesPerLiquidity { value0: FELT252_MAX, value1: FELT252_MAX }, 'overflow');
}

#[test]
fn test_fpl_overflow_add() {
    let fpl_one = FeesPerLiquidity { value0: 1, value1: 1 };

    let fpl_max = FeesPerLiquidity { value0: FELT252_MAX, value1: FELT252_MAX };

    let sum = fpl_max + fpl_one;

    assert(sum == FeesPerLiquidity { value0: 0, value1: 0,  }, 'sum');
}

#[test]
fn test_fees_per_liquidity_new() {
    assert(
        fees_per_liquidity_new(100, 250, 10000) == FeesPerLiquidity {
            value0: 3402823669209384634633746074317682114,
            value1: 8507059173023461586584365185794205286
        },
        'example'
    );
}

#[test]
fn test_to_fees_per_liquidity_max_fees() {
    to_fees_per_liquidity(10633823966279327296825105735305134080, 1);
}

#[test]
#[should_panic(expected: ('FEES_OVERFLOW', ))]
fn test_to_fees_per_liquidity_overflows() {
    to_fees_per_liquidity(10633823966279327296825105735305134081, 1);
}

#[test]
#[should_panic(expected: ('ZERO_LIQUIDITY_FEES', ))]
fn test_to_fees_per_liquidity_div_by_zero() {
    to_fees_per_liquidity(1, 0);
}

#[test]
fn test_storage_size() {
    assert(starknet::Store::<FeesPerLiquidity>::size() == 2, 'size');
}
