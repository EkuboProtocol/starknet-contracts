use crate::math::time::is_time_valid;

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
