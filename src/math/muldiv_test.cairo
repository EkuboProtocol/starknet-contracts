use debug::PrintTrait;
use parlay::math::muldiv::muldiv;


#[test]
#[should_panic(expected: ('MULDIV_OVERFLOW_OR_DBZ', ))]
fn test_muldiv_div_by_zero() {
    let x = muldiv(
        u256 { low: 0, high: 1 }, u256 { low: 0, high: 1 }, u256 { low: 0, high: 0 }, false
    );
}

#[test]
#[should_panic(expected: ('MULDIV_OVERFLOW_OR_DBZ', ))]
fn test_muldiv_up_div_by_zero() {
    let x = muldiv(
        u256 { low: 0, high: 1 }, u256 { low: 0, high: 1 }, u256 { low: 0, high: 0 }, false
    );
}

#[test]
#[should_panic(expected: ('u256 is 0', ))]
fn test_muldiv_up_div_by_zero_no_overflow() {
    let x = muldiv(
        u256 { low: 0, high: 1 }, u256 { low: 1, high: 0 }, u256 { low: 0, high: 0 }, false
    );
}

#[test]
#[should_panic(expected: ('MULDIV_OVERFLOW_OR_DBZ', ))]
fn test_muldiv_overflows() {
    // 2**128 * 2**128 / 2 = 2**256 / 1 = 2**256
    muldiv(u256 { low: 0, high: 1 }, u256 { low: 0, high: 1 }, u256 { low: 1, high: 0 }, false);
}

#[test]
fn test_muldiv_fits() {
    // 2**128 * 2**128 / 2 = 2**256 / 2 = 2**255
    let x = muldiv(
        u256 { low: 0, high: 1 }, u256 { low: 0, high: 1 }, u256 { low: 2, high: 0 }, false
    );
    assert(x == u256 { low: 0, high: 0x80000000000000000000000000000000 }, 'result');
}


#[test]
fn test_muldiv_up_fits_no_rounding() {
    // 2**128 * 2**128 / 2 = 2**256 / 2 = 2**255
    let x = muldiv(
        u256 { low: 0, high: 1 }, u256 { low: 0, high: 1 }, u256 { low: 2, high: 0 }, true
    );
    assert(x == u256 { low: 0, high: 0x80000000000000000000000000000000 }, 'result');
}


#[test]
fn test_muldiv_max_inputs() {
    let x = muldiv(
        u256 { low: 0xffffffffffffffffffffffffffffffff, high: 0xffffffffffffffffffffffffffffffff },
        u256 { low: 0xffffffffffffffffffffffffffffffff, high: 0xffffffffffffffffffffffffffffffff },
        u256 { low: 0xffffffffffffffffffffffffffffffff, high: 0xffffffffffffffffffffffffffffffff },
        false
    );
    assert(
        x == u256 {
            low: 0xffffffffffffffffffffffffffffffff, high: 0xffffffffffffffffffffffffffffffff
        },
        'result'
    );
}

#[test]
fn test_muldiv_up_max_inputs_no_rounding() {
    let x = muldiv(
        u256 { low: 0xffffffffffffffffffffffffffffffff, high: 0xffffffffffffffffffffffffffffffff },
        u256 { low: 0xffffffffffffffffffffffffffffffff, high: 0xffffffffffffffffffffffffffffffff },
        u256 { low: 0xffffffffffffffffffffffffffffffff, high: 0xffffffffffffffffffffffffffffffff },
        false
    );
    assert(
        x == u256 {
            low: 0xffffffffffffffffffffffffffffffff, high: 0xffffffffffffffffffffffffffffffff
        },
        'result'
    );
}

#[test]
fn test_muldiv_phantom_overflow() {
    let x = muldiv(
        u256 { low: 0, high: 5 }, u256 { low: 0, high: 10 }, u256 { low: 0, high: 2 }, false
    );
    assert(x == u256 { low: 0, high: 25 }, 'result');
}

#[test]
fn test_muldiv_up_phantom_overflow_no_rounding() {
    let x = muldiv(
        u256 { low: 0, high: 5 }, u256 { low: 0, high: 10 }, u256 { low: 0, high: 2 }, true
    );
    assert(x == u256 { low: 0, high: 25 }, 'result');
}


#[test]
fn test_muldiv_up_no_overflow_rounding_min() {
    let x = muldiv(
        u256 { low: 1, high: 0 }, u256 { low: 1, high: 0 }, u256 { low: 2, high: 0 }, true
    );
    assert(x == u256 { low: 1, high: 0 }, 'result');
}


#[test]
#[should_panic(expected: ('u256_add Overflow', ))]
fn test_muldiv_up_overflow_with_rounding() {
    muldiv(
        u256 { low: 535006138814359, high: 0 },
        u256 { low: 51446759824697641887992017603606601689, high: 1272069018404338518389130 },
        u256 { low: 2, high: 0 },
        true
    );
}
