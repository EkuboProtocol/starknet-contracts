use core::num::traits::Zero;
use core::option::OptionTrait;
use crate::math::muldiv::{div, muldiv};

#[test]
fn test_muldiv_div_by_zero() {
    assert(
        muldiv(
            0x100000000000000000000000000000000_u256,
            0x100000000000000000000000000000000_u256,
            0_u256,
            false,
        )
            .is_none(),
        'div by zero',
    );
}

#[test]
fn test_muldiv_up_div_by_zero() {
    assert(
        muldiv(
            0x100000000000000000000000000000000_u256,
            0x100000000000000000000000000000000_u256,
            0_u256,
            false,
        )
            .is_none(),
        'div by zero',
    );
}

#[test]
fn test_muldiv_up_div_by_zero_no_overflow() {
    assert(
        muldiv(0x100000000000000000000000000000000_u256, 1_u256, 0_u256, false).is_none(),
        'div by zero',
    );
}

#[test]
fn test_muldiv_overflows_exactly() {
    // 2**128 * 2**128 / 2 = 2**256 / 1 = 2**256
    let result = muldiv(
        0x100000000000000000000000000000000_u256,
        0x100000000000000000000000000000000_u256,
        1_u256,
        false,
    );
    assert(result.is_none(), 'result');
}


#[test]
fn test_muldiv_overflows_round_up() {
    assert(
        muldiv(
            535006138814359,
            432862656469423142931042426214547535783388063929571229938474969,
            2,
            true,
        )
            .is_none(),
        'none',
    );
}

#[test]
fn test_muldiv_no_overflows_round_down() {
    assert(
        muldiv(
            535006138814359,
            432862656469423142931042426214547535783388063929571229938474969,
            2,
            false,
        )
            .unwrap() == 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff,
        'max u256',
    );
}

#[test]
fn test_muldiv_overflows_by_more() {
    // 2**128 * 2**128 / 2 = 2**256 / 1 = 2**256
    let result = muldiv(
        u256 { low: 1, high: 1 }, 0x100000000000000000000000000000000_u256, 1_u256, false,
    );
    assert(result.is_none(), 'result');
}

#[test]
fn test_muldiv_fits() {
    // 2**128 * 2**128 / 2 = 2**256 / 2 = 2**255
    let x = muldiv(
        0x100000000000000000000000000000000_u256,
        0x100000000000000000000000000000000_u256,
        u256 { low: 2, high: 0 },
        false,
    );
    assert(x.unwrap() == u256 { low: 0, high: 0x80000000000000000000000000000000 }, 'result');
}


#[test]
fn test_muldiv_up_fits_no_rounding() {
    // 2**128 * 2**128 / 2 = 2**256 / 2 = 2**255
    let x = muldiv(
        0x100000000000000000000000000000000_u256,
        0x100000000000000000000000000000000_u256,
        u256 { low: 2, high: 0 },
        true,
    );
    assert(x.unwrap() == u256 { low: 0, high: 0x80000000000000000000000000000000 }, 'result');
}


#[test]
fn test_muldiv_max_inputs() {
    let x = muldiv(
        u256 { low: 0xffffffffffffffffffffffffffffffff, high: 0xffffffffffffffffffffffffffffffff },
        u256 { low: 0xffffffffffffffffffffffffffffffff, high: 0xffffffffffffffffffffffffffffffff },
        u256 { low: 0xffffffffffffffffffffffffffffffff, high: 0xffffffffffffffffffffffffffffffff },
        false,
    );
    assert(
        x
            .unwrap() == u256 {
                low: 0xffffffffffffffffffffffffffffffff, high: 0xffffffffffffffffffffffffffffffff,
            },
        'result',
    );
}

#[test]
fn test_muldiv_up_max_inputs_no_rounding() {
    let x = muldiv(
        u256 { low: 0xffffffffffffffffffffffffffffffff, high: 0xffffffffffffffffffffffffffffffff },
        u256 { low: 0xffffffffffffffffffffffffffffffff, high: 0xffffffffffffffffffffffffffffffff },
        u256 { low: 0xffffffffffffffffffffffffffffffff, high: 0xffffffffffffffffffffffffffffffff },
        false,
    );
    assert(
        x
            .unwrap() == u256 {
                low: 0xffffffffffffffffffffffffffffffff, high: 0xffffffffffffffffffffffffffffffff,
            },
        'result',
    );
}

#[test]
fn test_muldiv_phantom_overflow() {
    let x = muldiv(
        u256 { low: 0, high: 5 }, u256 { low: 0, high: 10 }, u256 { low: 0, high: 2 }, false,
    );
    assert(x.unwrap() == u256 { low: 0, high: 25 }, 'result');
}

#[test]
fn test_muldiv_up_phantom_overflow_no_rounding() {
    let x = muldiv(
        u256 { low: 0, high: 5 }, u256 { low: 0, high: 10 }, u256 { low: 0, high: 2 }, true,
    );
    assert(x.unwrap() == u256 { low: 0, high: 25 }, 'result');
}


#[test]
fn test_muldiv_up_no_overflow_rounding_min() {
    let x = muldiv(1_u256, 1_u256, u256 { low: 2, high: 0 }, true);
    assert(x.unwrap() == 1_u256, 'result');
}


#[test]
fn test_muldiv_up_overflow_with_rounding() {
    let x = muldiv(
        u256 { low: 535006138814359, high: 0 },
        u256 { low: 51446759824697641887992017603606601689, high: 1272069018404338518389130 },
        u256 { low: 2, high: 0 },
        true,
    );
    assert(x.is_none(), 'overflows');
}


#[test]
fn test_div() {
    let TWO: NonZero<u256> = 2_u256.try_into().unwrap();
    assert(div(0_u256, TWO, false).is_zero(), 'floor(0/2)');
    assert(div(0_u256, TWO, true).is_zero(), 'ceil(0/2)');

    assert(div(1_u256, TWO, false).is_zero(), 'floor(1/2)');
    assert(div(1_u256, TWO, true) == 1_u256, 'ceil(1/2)');

    assert(div(2, TWO, false) == 1_u256, 'floor(2/2)');
    assert(div(2, TWO, true) == 1_u256, 'ceil(2/2)');
}
