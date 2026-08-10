use crate::math::delta::{amount0_delta, amount1_delta};
use crate::math::ticks::{max_sqrt_ratio, min_sqrt_ratio};

fn bounded_sqrt_ratio(seed: u256) -> u256 {
    min_sqrt_ratio() + (seed % (max_sqrt_ratio() - min_sqrt_ratio() + 1_u256))
}

#[test]
#[fuzzer]
fn fuzz_amount0_delta_symmetry_and_rounding(
    sqrt_ratio_a_seed: u256, sqrt_ratio_b_seed: u256, liquidity_seed: u64,
) {
    let sqrt_ratio_a = bounded_sqrt_ratio(sqrt_ratio_a_seed);
    let sqrt_ratio_b = bounded_sqrt_ratio(sqrt_ratio_b_seed);
    let liquidity: u128 = liquidity_seed.into();

    let down = amount0_delta(sqrt_ratio_a, sqrt_ratio_b, liquidity, false);
    let up = amount0_delta(sqrt_ratio_a, sqrt_ratio_b, liquidity, true);

    assert_eq!(down, amount0_delta(sqrt_ratio_b, sqrt_ratio_a, liquidity, false));
    assert_eq!(up, amount0_delta(sqrt_ratio_b, sqrt_ratio_a, liquidity, true));
    assert(down <= up, 'rounding order');
    assert(up - down <= 1, 'rounding error');
    if (liquidity == 0) | (sqrt_ratio_a == sqrt_ratio_b) {
        assert_eq!(down, 0);
        assert_eq!(up, 0);
    }
}

#[test]
#[fuzzer]
fn fuzz_amount1_delta_symmetry_and_rounding(
    sqrt_ratio_a_seed: u256, sqrt_ratio_b_seed: u256, liquidity_seed: u64,
) {
    // Restricting liquidity to u64 keeps the full supported price range representable in u128.
    let sqrt_ratio_a = bounded_sqrt_ratio(sqrt_ratio_a_seed);
    let sqrt_ratio_b = bounded_sqrt_ratio(sqrt_ratio_b_seed);
    let liquidity: u128 = liquidity_seed.into();

    let down = amount1_delta(sqrt_ratio_a, sqrt_ratio_b, liquidity, false);
    let up = amount1_delta(sqrt_ratio_a, sqrt_ratio_b, liquidity, true);

    assert_eq!(down, amount1_delta(sqrt_ratio_b, sqrt_ratio_a, liquidity, false));
    assert_eq!(up, amount1_delta(sqrt_ratio_b, sqrt_ratio_a, liquidity, true));
    assert(down <= up, 'rounding order');
    assert(up - down <= 1, 'rounding error');
    if (liquidity == 0) | (sqrt_ratio_a == sqrt_ratio_b) {
        assert_eq!(down, 0);
        assert_eq!(up, 0);
    }
}

#[test]
fn test_amount0_delta_price_down() {
    let delta = amount0_delta(
        u256 { low: 339942424496442021441932674757011200255, high: 0 },
        0x100000000000000000000000000000000_u256,
        1000000,
        false,
    );
    assert(delta == 1000, 'delta');
}


#[test]
fn test_amount0_delta_price_down_reverse() {
    let delta = amount0_delta(
        0x100000000000000000000000000000000_u256,
        u256 { low: 339942424496442021441932674757011200255, high: 0 },
        1000000,
        false,
    );
    assert(delta == 1000, 'delta');
}

#[test]
fn test_amount0_delta_price_example_down() {
    let delta = amount0_delta(
        0x100000000000000000000000000000000_u256,
        u256 { low: 34028236692093846346337460743176821145, high: 1 },
        1000000000000000000,
        false,
    );
    assert(delta == 90909090909090909, 'delta');
}

#[test]
fn test_amount0_delta_price_example_up() {
    let delta = amount0_delta(
        0x100000000000000000000000000000000_u256,
        u256 { low: 34028236692093846346337460743176821145, high: 1 },
        1000000000000000000,
        true,
    );
    assert(delta == 90909090909090910, 'delta');
}


#[test]
fn test_amount0_delta_price_up() {
    let delta = amount0_delta(
        u256 { low: 340622989910849312776150758189957120, high: 1 },
        0x100000000000000000000000000000000_u256,
        1000000,
        false,
    );
    assert(delta == 999, 'delta');
}

#[test]
fn test_amount0_delta_price_down_round_up() {
    let delta = amount0_delta(
        u256 { low: 339942424496442021441932674757011200255, high: 0 },
        0x100000000000000000000000000000000_u256,
        1000000,
        true,
    );
    assert(delta == 1001, 'delta');
}

#[test]
fn test_amount0_delta_price_up_round_up() {
    let delta = amount0_delta(
        u256 { low: 340622989910849312776150758189957120, high: 1 },
        0x100000000000000000000000000000000_u256,
        1000000,
        true,
    );
    assert(delta == 1000, 'delta');
}

#[test]
fn test_amount1_delta_price_down() {
    let delta = amount1_delta(
        u256 { low: 339942424496442021441932674757011200255, high: 0 },
        0x100000000000000000000000000000000_u256,
        1000000,
        false,
    );
    assert(delta == 999, 'delta');
}

#[test]
fn test_amount1_delta_price_down_reverse() {
    let delta = amount1_delta(
        0x100000000000000000000000000000000_u256,
        u256 { low: 339942424496442021441932674757011200255, high: 0 },
        1000000,
        false,
    );
    assert(delta == 999, 'delta');
}

#[test]
fn test_amount1_delta_price_up() {
    let delta = amount1_delta(
        u256 { low: 340622989910849312776150758189957120, high: 1 },
        0x100000000000000000000000000000000_u256,
        1000000,
        false,
    );
    assert(delta == 1001, 'delta');
}


#[test]
fn test_amount1_delta_price_example_down() {
    let delta = amount1_delta(
        0x100000000000000000000000000000000_u256,
        u256 { low: 309347606291762239512158734028880192232, high: 0 },
        1000000000000000000,
        false,
    );
    assert(delta == 90909090909090909, 'delta');
}


#[test]
fn test_amount1_delta_price_example_up() {
    let delta = amount1_delta(
        0x100000000000000000000000000000000_u256,
        u256 { low: 309347606291762239512158734028880192232, high: 0 },
        1000000000000000000,
        true,
    );
    assert(delta == 90909090909090910, 'delta');
}


#[test]
fn test_amount1_delta_price_down_round_up() {
    let delta = amount1_delta(
        u256 { low: 339942424496442021441932674757011200255, high: 0 },
        0x100000000000000000000000000000000_u256,
        1000000,
        true,
    );
    assert(delta == 1000, 'delta');
}

#[test]
fn test_amount1_delta_price_up_round_up() {
    let delta = amount1_delta(
        u256 { low: 340622989910849312776150758189957120, high: 1 },
        0x100000000000000000000000000000000_u256,
        1000000,
        true,
    );
    assert(delta == 1002, 'delta');
}

#[test]
#[should_panic(expected: ('OVERFLOW_AMOUNT1_DELTA',))]
fn test_amount1_delta_overflow_entire_price_range_max_liquidity() {
    amount1_delta(
        sqrt_ratio_a: min_sqrt_ratio(),
        sqrt_ratio_b: max_sqrt_ratio(),
        liquidity: 0xffffffffffffffffffffffffffffffff,
        round_up: false,
    );
}

#[test]
fn test_amount1_delta_no_overflow_half_price_range_half_liquidity() {
    assert(
        amount1_delta(
            sqrt_ratio_a: 0x100000000000000000000000000000000_u256,
            sqrt_ratio_b: max_sqrt_ratio(),
            liquidity: 0xffffffffffffffff,
            round_up: false,
        ) == 0xfffffc080ed7b4536f352cf617ac4df5,
        'delta',
    );
}
