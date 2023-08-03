use ekubo::math::delta::{amount0_delta, amount1_delta, ordered_non_zero};
use ekubo::math::ticks::{min_sqrt_ratio, max_sqrt_ratio};

#[test]
fn test_ordered_non_zero() {
    assert(ordered_non_zero(1_u128, 2) == (1, 2), '1,2');
    assert(ordered_non_zero(2_u128, 1) == (1, 2), '2,1');
    assert(ordered_non_zero(2_u128, 2) == (2, 2), '2,1');
    assert(ordered_non_zero(3_u256, 2) == (2, 3), '3,2');
    assert(ordered_non_zero(2_u256, 3) == (2, 3), '2,3');
}

#[test]
#[should_panic(expected: ('NONZERO', ))]
fn test_ordered_non_zero_panics_zero() {
    ordered_non_zero(0_u128, 1);
}
#[test]
#[should_panic(expected: ('NONZERO', ))]
fn test_ordered_non_zero_panics_zero_second() {
    ordered_non_zero(1_u128, 0);
}
#[test]
#[should_panic(expected: ('NONZERO', ))]
fn test_ordered_non_zero_panics_zero_both() {
    ordered_non_zero(0_u128, 0);
}

#[test]
fn test_amount0_delta_price_down() {
    let delta = amount0_delta(
        u256 { low: 339942424496442021441932674757011200255, high: 0 },
        u256 { high: 1, low: 0 },
        1000000,
        false
    );
    assert(delta == 1000, 'delta');
}


#[test]
fn test_amount0_delta_price_down_reverse() {
    let delta = amount0_delta(
        u256 { high: 1, low: 0 },
        u256 { low: 339942424496442021441932674757011200255, high: 0 },
        1000000,
        false
    );
    assert(delta == 1000, 'delta');
}

#[test]
fn test_amount0_delta_price_example_down() {
    let delta = amount0_delta(
        u256 { high: 1, low: 0 },
        u256 { low: 34028236692093846346337460743176821145, high: 1 },
        1000000000000000000,
        false
    );
    assert(delta == 90909090909090909, 'delta');
}

#[test]
fn test_amount0_delta_price_example_up() {
    let delta = amount0_delta(
        u256 { high: 1, low: 0 },
        u256 { low: 34028236692093846346337460743176821145, high: 1 },
        1000000000000000000,
        true
    );
    assert(delta == 90909090909090910, 'delta');
}


#[test]
fn test_amount0_delta_price_up() {
    let delta = amount0_delta(
        u256 { low: 340622989910849312776150758189957120, high: 1 },
        u256 { high: 1, low: 0 },
        1000000,
        false
    );
    assert(delta == 999, 'delta');
}

#[test]
fn test_amount0_delta_price_down_round_up() {
    let delta = amount0_delta(
        u256 { low: 339942424496442021441932674757011200255, high: 0 },
        u256 { high: 1, low: 0 },
        1000000,
        true
    );
    assert(delta == 1001, 'delta');
}

#[test]
fn test_amount0_delta_price_up_round_up() {
    let delta = amount0_delta(
        u256 { low: 340622989910849312776150758189957120, high: 1 },
        u256 { high: 1, low: 0 },
        1000000,
        true
    );
    assert(delta == 1000, 'delta');
}

#[test]
fn test_amount1_delta_price_down() {
    let delta = amount1_delta(
        u256 { low: 339942424496442021441932674757011200255, high: 0 },
        u256 { high: 1, low: 0 },
        1000000,
        false
    );
    assert(delta == 999, 'delta');
}

#[test]
fn test_amount1_delta_price_down_reverse() {
    let delta = amount1_delta(
        u256 { high: 1, low: 0 },
        u256 { low: 339942424496442021441932674757011200255, high: 0 },
        1000000,
        false
    );
    assert(delta == 999, 'delta');
}

#[test]
fn test_amount1_delta_price_up() {
    let delta = amount1_delta(
        u256 { low: 340622989910849312776150758189957120, high: 1 },
        u256 { high: 1, low: 0 },
        1000000,
        false
    );
    assert(delta == 1001, 'delta');
}


#[test]
fn test_amount1_delta_price_example_down() {
    let delta = amount1_delta(
        u256 { high: 1, low: 0 },
        u256 { low: 309347606291762239512158734028880192232, high: 0 },
        1000000000000000000,
        false
    );
    assert(delta == 90909090909090909, 'delta');
}


#[test]
fn test_amount1_delta_price_example_up() {
    let delta = amount1_delta(
        u256 { high: 1, low: 0 },
        u256 { low: 309347606291762239512158734028880192232, high: 0 },
        1000000000000000000,
        true
    );
    assert(delta == 90909090909090910, 'delta');
}


#[test]
fn test_amount1_delta_price_down_round_up() {
    let delta = amount1_delta(
        u256 { low: 339942424496442021441932674757011200255, high: 0 },
        u256 { high: 1, low: 0 },
        1000000,
        true
    );
    assert(delta == 1000, 'delta');
}

#[test]
fn test_amount1_delta_price_up_round_up() {
    let delta = amount1_delta(
        u256 { low: 340622989910849312776150758189957120, high: 1 },
        u256 { high: 1, low: 0 },
        1000000,
        true
    );
    assert(delta == 1002, 'delta');
}

#[test]
#[should_panic(expected: ('OVERFLOW_AMOUNT1_DELTA', ))]
fn test_amount1_delta_overflow_entire_price_range_max_liquidity() {
    amount1_delta(
        sqrt_ratio_a: min_sqrt_ratio(),
        sqrt_ratio_b: max_sqrt_ratio(),
        liquidity: 0xffffffffffffffffffffffffffffffff,
        round_up: false
    );
}

#[test]
fn test_amount1_delta_no_overflow_half_price_range_half_liquidity() {
    assert(
        amount1_delta(
            sqrt_ratio_a: u256 { low: 0, high: 1 },
            sqrt_ratio_b: max_sqrt_ratio(),
            liquidity: 0xffffffffffffffff,
            round_up: false
        ) == 0xfffffc080ed7b4536f352cf617ac4df5,
        'delta'
    );
}
