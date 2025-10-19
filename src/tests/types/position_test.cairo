use core::num::traits::{WideMul, Zero};
use core::traits::Into;
use crate::types::fees_per_liquidity::FeesPerLiquidity;
use crate::types::position::{Position, PositionTrait, multiply_and_get_limb1};

// todo: fuzz with this
fn check_mul(a: u256, b: u128) {
    assert(
        WideMul::<u256, u256>::wide_mul(a, b.into()).limb1 == multiply_and_get_limb1(a, b), 'check',
    );
}

#[test]
fn test_multiply_and_get_limb1() {
    assert(multiply_and_get_limb1(0, 0) == 0, '0*0');
    assert(multiply_and_get_limb1(0x100000000000000000000000000000000_u256, 1) == 1, '1<<128 * 1');
    assert(multiply_and_get_limb1(u256 { high: 5, low: 0 }, 2) == 10, '5<<128 * 2');
    assert(multiply_and_get_limb1(u256 { high: 16, low: 0 } / 3, 2) == 10, '16<<128 / 3 * 2');

    assert(
        multiply_and_get_limb1(
            u256 { high: 0x10000000000000000, low: 0 }, 0x10000000000000000,
        ) == 0,
        '2**192 * 2**64',
    );

    assert(
        multiply_and_get_limb1(
            u256 { high: 0x10000000000000000, low: 0x10000000000000000 }, 0x10000000000000000,
        ) == 1,
        '(2**192 + 2**64) * 2**64',
    );

    assert(
        multiply_and_get_limb1(
            u256 { high: 0x10000000000000000, low: 0x30000000000000000 }, 0x30000000000000000,
        ) == 9,
        '(2**192 + 3*2**64) * 3*2**64',
    );
}

#[test]
fn test_positions_zeroable() {
    let p: Position = Zero::zero();
    assert(p.is_zero(), 'is_zero');
    assert(!p.is_non_zero(), 'is_non_zero');
}

#[test]
fn test_is_zero_for_nonzero_fees() {
    let p = Position {
        liquidity: Zero::zero(),
        fees_per_liquidity_inside_last: FeesPerLiquidity { value0: 1, value1: 1 },
    };
    assert(p.is_zero(), 'is_zero');
    assert(!p.is_non_zero(), 'is_non_zero');
}

#[test]
fn test_is_zero_for_nonzero_liquidity() {
    let p = Position { liquidity: 1, fees_per_liquidity_inside_last: Zero::zero() };
    assert(!p.is_zero(), 'is_zero');
    assert(p.is_non_zero(), 'is_non_zero');
}

#[test]
fn test_fees_calculation_zero_liquidity() {
    let p = Position {
        liquidity: Zero::zero(),
        fees_per_liquidity_inside_last: FeesPerLiquidity { value0: 0, value1: 0 },
    };

    assert(
        p
            .fees(
                FeesPerLiquidity {
                    value0: 3618502788666131213697322783095070105623107215331596699973092056135872020480,
                    value1: 3618502788666131213697322783095070105623107215331596699973092056135872020480,
                },
            ) == (0, 0),
        'fees',
    );
}

#[test]
fn test_fees_calculation_one_liquidity_max_difference() {
    assert(
        Position {
            liquidity: 1, fees_per_liquidity_inside_last: FeesPerLiquidity { value0: 1, value1: 1 },
        }
            .fees(
                Zero::zero(),
            ) == (0x8000000000000110000000000000000, 0x8000000000000110000000000000000),
        'fees',
    );
}

#[test]
fn test_fees_calculation_one_liquidity_max_difference_token0_only() {
    assert(
        Position {
            liquidity: 1, fees_per_liquidity_inside_last: FeesPerLiquidity { value0: 1, value1: 0 },
        }
            .fees(Zero::zero()) == (0x8000000000000110000000000000000, 0),
        'fees',
    );
}

#[test]
fn test_fees_calculation_one_liquidity_max_difference_token1_only() {
    assert(
        Position {
            liquidity: 1, fees_per_liquidity_inside_last: FeesPerLiquidity { value0: 0, value1: 1 },
        }
            .fees(Zero::zero()) == (0, 0x8000000000000110000000000000000),
        'fees',
    );
}


#[test]
fn test_fees_calculation_fees_pre_overflow() {
    assert(
        Position {
            liquidity: 31,
            fees_per_liquidity_inside_last: FeesPerLiquidity { value0: 1, value1: 1 },
        }
            .fees(
                Zero::zero(),
            ) == (0xf80000000000020f0000000000000000, 0xf80000000000020f0000000000000000),
        'fees',
    );
}

#[test]
fn test_fees_calculation_fees_overflow() {
    assert(
        Position {
            liquidity: 32,
            fees_per_liquidity_inside_last: FeesPerLiquidity { value0: 1, value1: 1 },
        }
            .fees(Zero::zero()) == (0x2200000000000000000, 0x2200000000000000000),
        'fees',
    );
}

#[test]
fn test_fees_calculation_fees_example_value() {
    // just some random values (ideally would be fuzzed)
    let fees_base = FeesPerLiquidity { value0: 234812903512510, value1: 34901248108108888 };

    assert(
        Position { liquidity: 1333, fees_per_liquidity_inside_last: fees_base }
            .fees(
                fees_base
                    + FeesPerLiquidity {
                        value0: 4253529586511730793292182592897102643200, // 25n * 2n**128n / 2n == 12.5 fees per liq
                        value1: 8507059173023461586584365185794205286 // 2n**128n / 40n == 1 fee per 40 liquidity
                    },
            ) == (16662, 33),
        'fees',
    );
}
