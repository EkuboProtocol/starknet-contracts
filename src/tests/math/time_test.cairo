use crate::math::time::{TIME_SPACING_SIZE, is_time_valid};

#[test]
#[fuzzer]
fn fuzz_past_and_near_times_are_aligned_to_base_spacing(now: u64, time_seed: u64) {
    let now = now % (0xffffffffffffffff - TIME_SPACING_SIZE);
    let time = if time_seed <= now {
        time_seed
    } else {
        now + (time_seed % (TIME_SPACING_SIZE + 1))
    };

    assert_eq!(is_time_valid(now, time), (time % TIME_SPACING_SIZE) == 0);
}

#[test]
#[fuzzer]
fn fuzz_time_validity_is_stable_within_step_window(now_seed: u32, exponent_seed: u8) {
    // For future distances in [16**k, 16**(k+1)), the required step is 16**k.
    let exponent = (exponent_seed % 6) + 1;
    let step: u64 = crate::math::exp2::exp2(4 * exponent).try_into().unwrap();
    let now: u64 = now_seed.into();
    let time = ((now + step) / step) * step;

    assert(is_time_valid(now, time), 'aligned time valid');
    if time > (now + TIME_SPACING_SIZE) {
        assert(!is_time_valid(now, time + 1), 'unaligned time invalid');
    }
}

#[test]
fn test_is_time_valid_past_or_close_time() {
    assert_eq!(is_time_valid(now: 0, time: 16), true);
    assert_eq!(is_time_valid(now: 8, time: 16), true);
    assert_eq!(is_time_valid(now: 9, time: 16), true);
    assert_eq!(is_time_valid(now: 15, time: 16), true);
    assert_eq!(is_time_valid(now: 16, time: 16), true);
    assert_eq!(is_time_valid(now: 17, time: 16), true);
    assert_eq!(is_time_valid(now: 12345678, time: 16), true);
    assert_eq!(is_time_valid(now: 12345678, time: 32), true);
    assert_eq!(is_time_valid(now: 12345678, time: 0), true);
}

#[test]
fn test_is_time_valid_future_times_near() {
    assert_eq!(is_time_valid(now: 0, time: 16), true);
    assert_eq!(is_time_valid(now: 8, time: 16), true);
    assert_eq!(is_time_valid(now: 9, time: 16), true);
    assert_eq!(is_time_valid(now: 0, time: 32), true);
    assert_eq!(is_time_valid(now: 31, time: 32), true);

    assert_eq!(is_time_valid(now: 0, time: 256), true);
    assert_eq!(is_time_valid(now: 0, time: 240), true);
    assert_eq!(is_time_valid(now: 0, time: 272), false);
    assert_eq!(is_time_valid(now: 16, time: 256), true);
    assert_eq!(is_time_valid(now: 16, time: 240), true);
    assert_eq!(is_time_valid(now: 16, time: 272), false);

    assert_eq!(is_time_valid(now: 0, time: 512), true);
    assert_eq!(is_time_valid(now: 0, time: 496), false);
    assert_eq!(is_time_valid(now: 0, time: 528), false);
    assert_eq!(is_time_valid(now: 16, time: 512), true);
    assert_eq!(is_time_valid(now: 16, time: 496), false);
    assert_eq!(is_time_valid(now: 16, time: 528), false);
}

#[test]
fn test_is_time_valid_future_times_near_second_boundary() {
    assert_eq!(is_time_valid(now: 0, time: 4096), true);
    assert_eq!(is_time_valid(now: 0, time: 3840), true);
    assert_eq!(is_time_valid(now: 0, time: 4352), false);
    assert_eq!(is_time_valid(now: 16, time: 4096), true);
    assert_eq!(is_time_valid(now: 16, time: 3840), true);
    assert_eq!(is_time_valid(now: 16, time: 4352), false);

    assert_eq!(is_time_valid(now: 256, time: 4096), true);
    assert_eq!(is_time_valid(now: 256, time: 3840), true);
    assert_eq!(is_time_valid(now: 256, time: 4352), false);
    assert_eq!(is_time_valid(now: 257, time: 4352), true);
}
