use ekubo::types::position::{Position, PositionTrait};
use ekubo::types::fees_per_liquidity::{FeesPerLiquidity};
use zeroable::{Zeroable};
use debug::PrintTrait;

impl PrintFees of PrintTrait<(u128, u128)> {
    fn print(self: (u128, u128)) {
        let (x, y) = self;
        x.print();
        y.print();
    }
}

#[test]
fn test_positions_zeroable() {
    let p: Position = Zeroable::zero();
    assert(p.is_zero(), 'is_zero');
    assert(!p.is_non_zero(), 'is_non_zero');
}

#[test]
fn test_is_zero_for_nonzero_fees() {
    let p = Position {
        liquidity: Zeroable::zero(), fees_per_liquidity_inside_last: FeesPerLiquidity {
            fees_per_liquidity_token0: 1, fees_per_liquidity_token1: 1, 
        },
    };
    assert(p.is_zero(), 'is_zero');
    assert(!p.is_non_zero(), 'is_non_zero');
}

#[test]
fn test_is_zero_for_nonzero_liquidity() {
    let p = Position { liquidity: 1, fees_per_liquidity_inside_last: Zeroable::zero() };
    assert(!p.is_zero(), 'is_zero');
    assert(p.is_non_zero(), 'is_non_zero');
}

#[test]
fn test_fees_calculation_zero_liquidity() {
    let p = Position {
        liquidity: Zeroable::zero(), fees_per_liquidity_inside_last: FeesPerLiquidity {
            fees_per_liquidity_token0: 0, fees_per_liquidity_token1: 0, 
        },
    };

    assert(
        p
            .fees(
                FeesPerLiquidity {
                    fees_per_liquidity_token0: 3618502788666131213697322783095070105623107215331596699973092056135872020480,
                    fees_per_liquidity_token1: 3618502788666131213697322783095070105623107215331596699973092056135872020480,
                }
            ) == (0, 0),
        'fees'
    );
}

#[test]
fn test_fees_calculation_one_liquidity_max_difference() {
    assert(
        Position {
            liquidity: 1, fees_per_liquidity_inside_last: FeesPerLiquidity {
                fees_per_liquidity_token0: 1, fees_per_liquidity_token1: 1
            },
        }
            .fees(
                Zeroable::zero()
            ) == (0x8000000000000110000000000000000, 0x8000000000000110000000000000000),
        'fees'
    );
}

#[test]
fn test_fees_calculation_one_liquidity_max_difference_token0_only() {
    assert(
        Position {
            liquidity: 1, fees_per_liquidity_inside_last: FeesPerLiquidity {
                fees_per_liquidity_token0: 1, fees_per_liquidity_token1: 0
            },
        }.fees(Zeroable::zero()) == (0x8000000000000110000000000000000, 0),
        'fees'
    );
}

#[test]
fn test_fees_calculation_one_liquidity_max_difference_token1_only() {
    assert(
        Position {
            liquidity: 1, fees_per_liquidity_inside_last: FeesPerLiquidity {
                fees_per_liquidity_token0: 0, fees_per_liquidity_token1: 1
            },
        }.fees(Zeroable::zero()) == (0, 0x8000000000000110000000000000000),
        'fees'
    );
}


#[test]
fn test_fees_calculation_fees_pre_overflow() {
    assert(
        Position {
            liquidity: 31, fees_per_liquidity_inside_last: FeesPerLiquidity {
                fees_per_liquidity_token0: 1, fees_per_liquidity_token1: 1
            },
        }
            .fees(
                Zeroable::zero()
            ) == (0xf80000000000020f0000000000000000, 0xf80000000000020f0000000000000000),
        'fees'
    );
}

#[test]
fn test_fees_calculation_fees_overflow() {
    assert(
        Position {
            liquidity: 32, fees_per_liquidity_inside_last: FeesPerLiquidity {
                fees_per_liquidity_token0: 1, fees_per_liquidity_token1: 1
            },
        }.fees(Zeroable::zero()) == (0x2200000000000000000, 0x2200000000000000000),
        'fees'
    );
}

#[test]
fn test_fees_calculation_fees_example_value() {
    // just some random values (ideally would be fuzzed)
    let fees_base = FeesPerLiquidity {
        fees_per_liquidity_token0: 234812903512510, fees_per_liquidity_token1: 34901248108108888
    };

    assert(
        Position {
            liquidity: 1333, fees_per_liquidity_inside_last: fees_base, 
        }
            .fees(
                fees_base + FeesPerLiquidity {
                    fees_per_liquidity_token0: 4253529586511730793292182592897102643200, // 25n * 2n**128n / 2n == 12.5 fees per liq
                    fees_per_liquidity_token1: 8507059173023461586584365185794205286 // 2n**128n / 40n == 1 fee per 40 liquidity
                }
            ) == (16662, 33),
        'fees'
    );
}
