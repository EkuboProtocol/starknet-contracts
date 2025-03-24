use core::num::traits::Zero;
use ekubo::math::bits::msb;
use ekubo::math::exp2::exp2;

pub(crate) const TIME_SPACING_SIZE: u64 = 16;

// log base 2 of TIME_SPACING_SIZE, used for our calculations in time validation
const LOG_SCALE_FACTOR: u8 = 4;

pub fn to_duration(start: u64, end: u64) -> u32 {
    (end - start).try_into().expect('DURATION_EXCEEDS_MAX_U32')
}

// Timestamps specified in order keys must be a multiple of a base that depends on how close they
// are to now
pub(crate) fn is_time_valid(now: u64, time: u64) -> bool {
    // = 16**(max(1, floor(log_16(time-now))))
    let step = if time <= (now + TIME_SPACING_SIZE) {
        TIME_SPACING_SIZE.into()
    } else {
        exp2(LOG_SCALE_FACTOR * (msb((time - now).into()) / LOG_SCALE_FACTOR))
    };

    (time.into() % step).is_zero()
}

pub(crate) fn validate_time(now: u64, time: u64) {
    assert(is_time_valid(now, time), 'INVALID_TIME');
}
