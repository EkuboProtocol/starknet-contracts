use core::num::traits::Zero;
use crate::types::delta::Delta;
use crate::types::i129::i129;

#[test]
fn test_delta_zeroable() {
    let delta: Delta = Zero::zero();
    assert(delta.amount0 == Zero::zero(), 'amount0');
    assert(delta.amount1 == Zero::zero(), 'amount1');
    assert(delta.is_zero(), 'is_zero');
    assert(!delta.is_non_zero(), 'is_non_zero');
}

#[test]
fn test_delta_add() {
    let delta1 = Delta {
        amount0: i129 { mag: 100, sign: false }, amount1: i129 { mag: 150, sign: true },
    };
    let delta2 = Delta {
        amount0: i129 { mag: 50, sign: true }, amount1: i129 { mag: 75, sign: false },
    };
    let delta3 = delta1 + delta2;
    assert(delta3.amount0 == i129 { mag: 50, sign: false }, 'sum0');
    assert(delta3.amount1 == i129 { mag: 75, sign: true }, 'sum1');
}

#[test]
fn test_delta_addeq() {
    let mut delta1 = Delta {
        amount0: i129 { mag: 100, sign: false }, amount1: i129 { mag: 150, sign: true },
    };
    let delta2 = Delta {
        amount0: i129 { mag: 50, sign: true }, amount1: i129 { mag: 75, sign: false },
    };
    delta1 += delta2;
    assert(delta1.amount0 == i129 { mag: 50, sign: false }, 'sum0');
    assert(delta1.amount1 == i129 { mag: 75, sign: true }, 'sum1');
}
