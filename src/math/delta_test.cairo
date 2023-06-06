use ekubo::types::i129::i129;
use debug::PrintTrait;

use ekubo::math::delta::{
    next_sqrt_ratio_from_amount0, next_sqrt_ratio_from_amount1, amount0_delta, amount1_delta
};

#[test]
fn test_next_sqrt_ratio_from_amount0_add_price_goes_down() {
    // adding amount0 means price goes down
    let next_ratio = next_sqrt_ratio_from_amount0(
        u256 { high: 1, low: 0 }, 1000000, i129 { mag: 1000, sign: false }
    );
    assert(next_ratio == u256 { low: 339942424496442021441932674757011200256, high: 0 }, 'price');
}

#[test]
fn test_next_sqrt_ratio_from_amount0_sub_price_goes_up() {
    // adding amount0 means price goes down
    let next_ratio = next_sqrt_ratio_from_amount0(
        u256 { low: 0, high: 1 }, 100000000000, i129 { mag: 1000, sign: true }
    );
    assert(next_ratio == u256 { low: 3402823703237621667009962744418, high: 1 }, 'price');
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
fn test_next_sqrt_ratio_from_amount1_add_price_goes_up() {
    // adding amount0 means price goes down
    let next_ratio = next_sqrt_ratio_from_amount1(
        u256 { high: 1, low: 0 }, 1000000, i129 { mag: 1000, sign: false }
    );
    assert(next_ratio == u256 { low: 340282366920938463463374607431768211, high: 1 }, 'price');
}

#[test]
fn test_next_sqrt_ratio_from_amount1_sub_price_goes_down() {
    // adding amount0 means price goes down
    let next_ratio = next_sqrt_ratio_from_amount1(
        u256 { low: 0, high: 1 }, 1000000, i129 { mag: 1000, sign: true }
    );
    assert(next_ratio == u256 { low: 339942084554017524999911232824336443245, high: 0 }, 'price');
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
