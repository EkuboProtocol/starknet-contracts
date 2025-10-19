use core::num::traits::Zero;
use crate::math::exp2::exp2;
use crate::math::ticks::{
    by_2_127, constants, log2, max_sqrt_ratio, max_tick, min_sqrt_ratio, min_tick,
    sqrt_ratio_to_tick, tick_to_sqrt_ratio,
};
use crate::types::i129::i129;

#[test]
fn zero_tick() {
    let sqrt_ratio = tick_to_sqrt_ratio(Zero::zero());
    assert(sqrt_ratio == 0x100000000000000000000000000000000_u256, 'sqrt_ratio is 1');
}

#[test]
fn sqrt_ratio_of_max_tick_spacing() {
    let sqrt_ratio = tick_to_sqrt_ratio(i129 { mag: constants::MAX_TICK_SPACING, sign: false });
    assert(sqrt_ratio == u256 { high: 1, low: 0x31b4b265e1423f777a15722778490040 }, 'sqrt_ratio');
}

#[test]
fn sqrt_ratio_of_double_max_tick_spacing() {
    let sqrt_ratio = tick_to_sqrt_ratio(i129 { mag: constants::MAX_TICK_SPACING * 2, sign: false });
    assert(sqrt_ratio == u256 { high: 1, low: 0x6d1010a21e56762f95a886eb89babb3a }, 'sqrt_ratio');
}

#[test]
fn sqrt_ratio_of_max_tick_spacing_negative() {
    let sqrt_ratio = tick_to_sqrt_ratio(i129 { mag: constants::MAX_TICK_SPACING, sign: true });
    assert(sqrt_ratio == u256 { high: 0, low: 0xd660423f1925f68c36dac925648cd720 }, 'sqrt_ratio');
}

#[test]
fn sqrt_ratio_of_double_max_tick_spacing_negative() {
    let sqrt_ratio = tick_to_sqrt_ratio(i129 { mag: constants::MAX_TICK_SPACING * 2, sign: true });
    assert(sqrt_ratio == u256 { high: 0, low: 0xb38512f33e82ed304b270175c43d864c }, 'sqrt_ratio');
}

#[test]
fn negative_zero_tick() {
    let sqrt_ratio = tick_to_sqrt_ratio(i129 { mag: 0, sign: true });
    assert(sqrt_ratio == 0x100000000000000000000000000000000_u256, 'sqrt_ratio is 1');
}

#[test]
fn one_tick() {
    let sqrt_ratio = tick_to_sqrt_ratio(i129 { mag: 1, sign: false });

    assert(
        sqrt_ratio == u256 { high: 1, low: 170141140925194634249019658794763 },
        '~= sqrt(1.000001) * 2**128',
    );
}

#[test]
fn one_hundred_tick() {
    let sqrt_ratio = tick_to_sqrt_ratio(i129 { mag: 100, sign: false });

    assert(
        sqrt_ratio == u256 { high: 1, low: 17014535198616014082186950856589198 },
        '~= sqrt(1.000001)^100 * 2**128',
    );
}


#[test]
fn negative_one_tick() {
    let sqrt_ratio = tick_to_sqrt_ratio(i129 { mag: 1, sign: true });

    assert(
        sqrt_ratio == u256 { high: 0, low: 340282196779882608775400081051345954875 },
        '~= sqrt(1.000001)^-1 * 2**128',
    );
}

#[test]
fn negative_one_hundred_tick() {
    let sqrt_ratio = tick_to_sqrt_ratio(i129 { mag: 100, sign: true });

    assert(
        sqrt_ratio == u256 { high: 0, low: 340265353236444914223731134834256897676 },
        '~= sqrt(1.000001)^-100 * 2**128',
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
#[should_panic(expected: ('TICK_MAGNITUDE',))]
fn tick_magnitude_exceeds_min() {
    tick_to_sqrt_ratio(min_tick() - i129 { mag: 1, sign: false });
}

#[test]
#[should_panic(expected: ('TICK_MAGNITUDE',))]
fn tick_magnitude_exceeds_max() {
    tick_to_sqrt_ratio(max_tick() + i129 { mag: 1, sign: false });
}

#[test]
fn test_log2_2_128() {
    let (log2, sign) = log2(0x100000000000000000000000000000000_u256);
    assert(log2 == 0, 'log2(2**128).mag');
    assert(sign == false, 'log2(2**128).sign');
}

#[test]
fn test_internal_div_by_2_127() {
    assert(
        by_2_127(0x100000000000000000000000000000000_u256) == u256 { low: 2, high: 0 },
        '2n**128n/2n**127n',
    );
    assert(
        by_2_127(u256 { high: 0, low: 0x80000000000000000000000000000000 }) == 1_u256,
        '2n**127n/2n**127n',
    );
    assert(
        by_2_127(u256 { high: 0, low: 0x40000000000000000000000000000000 }) == 0_u256,
        '2n**126n/2n**127n',
    );
    assert(
        by_2_127(
            u256 {
                high: 0xffffffffffffffffffffffffffffffff, low: 0xffffffffffffffffffffffffffffffff,
            },
        ) == u256 { low: 0xffffffffffffffffffffffffffffffff, high: 0x01 },
        'max/2n**127n',
    );
}


#[test]
fn sqrt_ratio_to_tick_zero() {
    let tick = sqrt_ratio_to_tick(0x100000000000000000000000000000000_u256);
    assert(tick.is_zero(), 'tick is 0');
}

#[test]
fn sqrt_ratio_to_tick_one() {
    let expected_tick = i129 { mag: 1, sign: false };
    let tick = sqrt_ratio_to_tick(tick_to_sqrt_ratio(expected_tick));
    assert(tick == expected_tick, 'tick == expected_tick');
}

#[test]
fn sqrt_ratio_to_tick_one_plus_one() {
    let expected_tick = i129 { mag: 1, sign: false };
    let tick = sqrt_ratio_to_tick(tick_to_sqrt_ratio(expected_tick) + 1_u256);
    assert(tick == expected_tick, 'tick == expected_tick');
}

#[test]
fn sqrt_ratio_to_tick_one_minus_one() {
    let tick = sqrt_ratio_to_tick(tick_to_sqrt_ratio(i129 { mag: 1, sign: false }) - 1_u256);
    assert(tick.is_zero(), 'tick == expected_tick - 1');
}

#[test]
fn sqrt_ratio_to_tick_negative_one() {
    let expected_tick = i129 { mag: 1, sign: true };
    let tick = sqrt_ratio_to_tick(tick_to_sqrt_ratio(expected_tick));
    assert(tick == expected_tick, 'tick == expected_tick');
}

#[test]
fn sqrt_ratio_to_tick_within_ticks_example() {
    let sqrt_ratio = 21175949444679574865522613902772161611_u256;
    let tick = sqrt_ratio_to_tick(sqrt_ratio);
    assert(sqrt_ratio >= tick_to_sqrt_ratio(tick), 'lower bound');
    assert(sqrt_ratio < tick_to_sqrt_ratio(tick + i129 { mag: 1, sign: false }), 'upper bound');
}

#[test]
fn sqrt_ratio_to_tick_negative_one_minus_one() {
    let tick = sqrt_ratio_to_tick(tick_to_sqrt_ratio(i129 { mag: 1, sign: true }) - 1_u256);
    assert(tick == i129 { mag: 2, sign: true }, 'tick == expected_tick - 1');
}

#[test]
fn sqrt_ratio_to_tick_negative_one_plus_one() {
    let expected_tick = i129 { mag: 1, sign: true };
    let tick = sqrt_ratio_to_tick(tick_to_sqrt_ratio(expected_tick) + 1_u256);
    assert(tick == expected_tick, 'tick == expected_tick');
}

#[test]
fn sqrt_ratio_to_tick_double() {
    let expected_tick = i129 { mag: constants::MAX_TICK_SPACING, sign: false };
    let tick = sqrt_ratio_to_tick(tick_to_sqrt_ratio(expected_tick));
    assert(tick == expected_tick, 'tick == expected_tick');
}

#[test]
fn sqrt_ratio_to_tick_negative_double() {
    let expected_tick = i129 { mag: constants::MAX_TICK_SPACING, sign: true };
    let tick = sqrt_ratio_to_tick(tick_to_sqrt_ratio(expected_tick));
    assert(tick == expected_tick, 'tick == expected_tick');
}

#[test]
fn sqrt_ratio_to_tick_max_sqrt_ratio() {
    let tick = sqrt_ratio_to_tick(max_sqrt_ratio() - 1_u256);
    assert(tick == max_tick() - i129 { mag: 1, sign: false }, 'max tick minus one');
}

#[test]
fn sqrt_ratio_to_tick_min_sqrt_ratio() {
    let tick = sqrt_ratio_to_tick(min_sqrt_ratio());
    assert(tick == min_tick(), 'tick == min_tick()');
}

#[test]
fn test_min_sqrt_ratio_to_max_sqrt_ratio_size() {
    assert(
        max_sqrt_ratio() - min_sqrt_ratio() < u256 { high: 0x10000000000000000, low: 0 },
        'difference lt 192 bits',
    );
}

#[test]
fn test_max_sqrt_ratio_size() {
    assert(max_sqrt_ratio() < u256 { high: 0x10000000000000000, low: 0 }, 'max is lt 192 bits');
}

#[test]
fn sqrt_ratio_to_tick_powers_of_tick() {
    let mut i: u8 = 0;

    while i < 53 {
        let tick = if i > 26 {
            i129 { sign: true, mag: exp2(i - 26) }
        } else {
            i129 { sign: false, mag: exp2(i) }
        };

        let sqrt_ratio = tick_to_sqrt_ratio(tick);
        let computed_tick = sqrt_ratio_to_tick(sqrt_ratio);
        assert(tick == computed_tick, 'computed tick');
        let computed_tick_ratio_minus_one = sqrt_ratio_to_tick(sqrt_ratio - 1_u256);
        assert(
            computed_tick_ratio_minus_one == (computed_tick - i129 { mag: 1, sign: false }),
            'computed tick minus one',
        );
        let computed_tick_ratio_plus_one = sqrt_ratio_to_tick(sqrt_ratio + 1_u256);
        assert(computed_tick_ratio_plus_one == computed_tick, 'computed tick plus one');
        i += 1;
    }
}

#[test]
#[should_panic(expected: ('SQRT_RATIO_TOO_HIGH',))]
fn sqrt_ratio_to_tick_max_sqrt_ratio_panics() {
    sqrt_ratio_to_tick(max_sqrt_ratio());
}

#[test]
#[should_panic(expected: ('SQRT_RATIO_TOO_LOW',))]
fn sqrt_ratio_to_tick_min_sqrt_ratio_less_one_panics() {
    sqrt_ratio_to_tick(min_sqrt_ratio() - 1_u256);
}
