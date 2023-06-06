use ekubo::types::i129::i129;
use ekubo::math::ticks::{
    tick_to_sqrt_ratio, sqrt_ratio_to_tick, max_sqrt_ratio, min_sqrt_ratio, max_tick, min_tick,
    constants, internal as ticks_internal
};
use ekubo::math::exp2::exp2;

#[test]
fn zero_tick() {
    let sqrt_ratio = tick_to_sqrt_ratio(i129 { mag: 0, sign: false });
    assert(sqrt_ratio == u256 { high: 1, low: 0 }, 'sqrt_ratio is 1');
}

#[test]
fn sqrt_ratio_of_two_sqrt_ratio_tick() {
    let sqrt_ratio = tick_to_sqrt_ratio(
        i129 { mag: constants::TICKS_IN_DOUBLE_SQRT_RATIO, sign: false }
    );
    assert(
        sqrt_ratio == u256 { high: 1, low: 340282348454859831384279095459210930051 },
        'sqrt_ratio is ~= 2'
    );
}

#[test]
fn sqrt_ratio_of_four_sqrt_ratio_tick() {
    let sqrt_ratio = tick_to_sqrt_ratio(
        i129 { mag: constants::TICKS_IN_DOUBLE_SQRT_RATIO * 2, sign: false }
    );
    assert(
        sqrt_ratio == u256 { high: 3, low: 340282293056624937244348151744516807171 },
        'sqrt_ratio is ~= 4'
    );
}

#[test]
fn sqrt_ratio_of_one_half_sqrt_ratio_tick() {
    let sqrt_ratio = tick_to_sqrt_ratio(
        i129 { mag: constants::TICKS_IN_DOUBLE_SQRT_RATIO, sign: true }
    );
    assert(
        sqrt_ratio == u256 { high: 0, low: 170141188076989015013634029531039680095 },
        'sqrt_ratio is ~= 1/2'
    );
}

#[test]
fn sqrt_ratio_of_one_quarter_sqrt_ratio_tick() {
    let sqrt_ratio = tick_to_sqrt_ratio(
        i129 { mag: constants::TICKS_IN_DOUBLE_SQRT_RATIO * 2, sign: true }
    );
    assert(
        sqrt_ratio == u256 { high: 0, low: 85070596346754461778878500982473884228 },
        'sqrt_ratio is ~= 1/4'
    );
}

#[test]
fn negative_zero_tick() {
    let sqrt_ratio = tick_to_sqrt_ratio(i129 { mag: 0, sign: true });
    assert(sqrt_ratio == u256 { high: 1, low: 0 }, 'sqrt_ratio is 1');
}

#[test]
fn one_tick() {
    let sqrt_ratio = tick_to_sqrt_ratio(i129 { mag: 1, sign: false });

    assert(
        sqrt_ratio == u256 { high: 1, low: 170141140925194634249019658794763 },
        '~= sqrt(1.000001) * 2**128'
    );
}

#[test]
fn one_hundred_tick() {
    let sqrt_ratio = tick_to_sqrt_ratio(i129 { mag: 100, sign: false });

    assert(
        sqrt_ratio == u256 { high: 1, low: 17014535198616014082186950856589198 },
        '~= sqrt(1.000001)^100 * 2**128'
    );
}


#[test]
fn negative_one_tick() {
    let sqrt_ratio = tick_to_sqrt_ratio(i129 { mag: 1, sign: true });

    assert(
        sqrt_ratio == u256 { high: 0, low: 340282196779882608775400081051345954875 },
        '~= sqrt(1.000001)^-1 * 2**128'
    );
}

#[test]
fn negative_one_hundred_tick() {
    let sqrt_ratio = tick_to_sqrt_ratio(i129 { mag: 100, sign: true });

    assert(
        sqrt_ratio == u256 { high: 0, low: 340265353236444914223731134834256897676 },
        '~= sqrt(1.000001)^-100 * 2**128'
    );
}

#[test]
fn test_max_tick() {
    let sqrt_ratio = tick_to_sqrt_ratio(max_tick());

    assert(sqrt_ratio == max_sqrt_ratio(), 'sqrt_ratio ~= 2**64');
}


#[test]
fn test_min_tick() {
    let sqrt_ratio = tick_to_sqrt_ratio(min_tick());

    assert(sqrt_ratio == min_sqrt_ratio(), 'sqrt_ratio ~= 2**-64');
}

#[test]
fn diff_between_min_tick_tick_plus_one() {
    let sqrt_ratio = tick_to_sqrt_ratio(min_tick());
    let sqrt_ratio_next = tick_to_sqrt_ratio(min_tick() + i129 { sign: false, mag: 1 });
    let diff = sqrt_ratio_next - sqrt_ratio;

    // this test shows the benefit of precision of 2**128
    assert(diff == u256 { high: 0, low: 9223371912732 }, 'sqrt_ratio diff at low end');
}

#[test]
#[should_panic(expected: ('TICK_MAGNITUDE', ))]
fn tick_magnitude_exceeds_min() {
    tick_to_sqrt_ratio(min_tick() - i129 { mag: 1, sign: false });
}

#[test]
#[should_panic(expected: ('TICK_MAGNITUDE', ))]
fn tick_magnitude_exceeds_max() {
    tick_to_sqrt_ratio(max_tick() + i129 { mag: 1, sign: false });
}

#[test]
#[available_gas(1600000)]
fn test_log2_2_128() {
    let (log2, sign) = ticks_internal::log2(u256 { high: 1, low: 0 });
    assert(log2 == 0, 'log2(2**128).mag');
    assert(sign == false, 'log2(2**128).sign');
}

#[test]
#[available_gas(7000000)]
fn sqrt_ratio_to_tick_zero() {
    let tick = sqrt_ratio_to_tick(u256 { high: 1, low: 0 });
    assert(tick == i129 { mag: 0, sign: false }, 'tick is 0');
}

#[test]
#[available_gas(7000000)]
fn sqrt_ratio_to_tick_one() {
    let expected_tick = i129 { mag: 1, sign: false };
    let tick = sqrt_ratio_to_tick(tick_to_sqrt_ratio(expected_tick));
    assert(tick == expected_tick, 'tick == expected_tick');
}

#[test]
#[available_gas(7000000)]
fn sqrt_ratio_to_tick_one_plus_one() {
    let expected_tick = i129 { mag: 1, sign: false };
    let tick = sqrt_ratio_to_tick(tick_to_sqrt_ratio(expected_tick) + u256 { low: 1, high: 0 });
    assert(tick == expected_tick, 'tick == expected_tick');
}

#[test]
#[available_gas(7000000)]
fn sqrt_ratio_to_tick_one_minus_one() {
    let tick = sqrt_ratio_to_tick(
        tick_to_sqrt_ratio(i129 { mag: 1, sign: false }) - u256 { low: 1, high: 0 }
    );
    assert(tick == i129 { mag: 0, sign: false }, 'tick == expected_tick - 1');
}

#[test]
#[available_gas(7000000)]
fn sqrt_ratio_to_tick_negative_one() {
    let expected_tick = i129 { mag: 1, sign: true };
    let tick = sqrt_ratio_to_tick(tick_to_sqrt_ratio(expected_tick));
    assert(tick == expected_tick, 'tick == expected_tick');
}

#[test]
#[available_gas(7000000)]
fn sqrt_ratio_to_tick_negative_one_minus_one() {
    let tick = sqrt_ratio_to_tick(
        tick_to_sqrt_ratio(i129 { mag: 1, sign: true }) - u256 { low: 1, high: 0 }
    );
    assert(tick == i129 { mag: 2, sign: true }, 'tick == expected_tick - 1');
}

#[test]
#[available_gas(7000000)]
fn sqrt_ratio_to_tick_negative_one_plus_one() {
    let expected_tick = i129 { mag: 1, sign: true };
    let tick = sqrt_ratio_to_tick(tick_to_sqrt_ratio(expected_tick) + u256 { low: 1, high: 0 });
    assert(tick == expected_tick, 'tick == expected_tick');
}

#[test]
#[available_gas(7000000)]
fn sqrt_ratio_to_tick_double() {
    let expected_tick = i129 { mag: constants::TICKS_IN_DOUBLE_SQRT_RATIO, sign: false };
    let tick = sqrt_ratio_to_tick(tick_to_sqrt_ratio(expected_tick));
    assert(tick == expected_tick, 'tick == expected_tick');
}

#[test]
#[available_gas(7000000)]
fn sqrt_ratio_to_tick_negative_double() {
    let expected_tick = i129 { mag: constants::TICKS_IN_DOUBLE_SQRT_RATIO, sign: true };
    let tick = sqrt_ratio_to_tick(tick_to_sqrt_ratio(expected_tick));
    assert(tick == expected_tick, 'tick == expected_tick');
}

#[test]
#[available_gas(7000000)]
fn sqrt_ratio_to_tick_max_sqrt_ratio() {
    let tick = sqrt_ratio_to_tick(max_sqrt_ratio() - u256 { high: 0, low: 1 });
    assert(tick == max_tick() - i129 { mag: 1, sign: false }, 'max tick minus one');
}

#[test]
#[available_gas(7000000)]
fn sqrt_ratio_to_tick_min_sqrt_ratio() {
    let tick = sqrt_ratio_to_tick(min_sqrt_ratio());
    assert(tick == min_tick(), 'tick == min_tick()');
}


#[test]
#[available_gas(70000000000000)]
fn sqrt_ratio_to_tick_powers_of_tick() {
    let mut sign = false;
    let mut pow: u8 = 0;
    loop {
        if (pow == 27) {
            if (sign) {
                break ();
            }
            sign = true;
            pow = 1;
        }
        let tick = i129 { mag: exp2(pow).low, sign };
        let sqrt_ratio = tick_to_sqrt_ratio(tick);
        let computed_tick = sqrt_ratio_to_tick(sqrt_ratio);
        assert(tick == computed_tick, 'computed tick');
        let computed_tick_ratio_minus_one = sqrt_ratio_to_tick(
            sqrt_ratio - u256 { low: 1, high: 0 }
        );
        assert(
            computed_tick_ratio_minus_one == (computed_tick - i129 { mag: 1, sign: false }),
            'computed tick minus one'
        );
        let computed_tick_ratio_plus_one = sqrt_ratio_to_tick(
            sqrt_ratio + u256 { low: 1, high: 0 }
        );
        assert(computed_tick_ratio_plus_one == computed_tick, 'computed tick plus one');
        pow += 1;
    }
}

#[test]
#[should_panic(expected: ('SQRT_RATIO_TOO_HIGH', ))]
fn sqrt_ratio_to_tick_max_sqrt_ratio_panics() {
    sqrt_ratio_to_tick(max_sqrt_ratio());
}

#[test]
#[should_panic(expected: ('SQRT_RATIO_TOO_LOW', ))]
fn sqrt_ratio_to_tick_min_sqrt_ratio_less_one_panics() {
    sqrt_ratio_to_tick(min_sqrt_ratio() - u256 { high: 0, low: 1 });
}
