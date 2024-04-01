use core::num::traits::{Zero};
use core::option::{Option, OptionTrait};
use core::traits::{Into, TryInto};
use ekubo::types::call_points::{CallPoints, all_call_points};

#[test]
fn test_default_call_points_into_u8() {
    assert(Default::<CallPoints>::default().into() == 0_u8, 'empty');
}

#[test]
fn test_all_call_points_into_u8() {
    assert(all_call_points().into() == 254_u8, 'all');
}

#[test]
fn test_u8_empty_into_default_call_points() {
    assert(
        TryInto::<u8, CallPoints>::try_into(0_u8).unwrap() == Default::<CallPoints>::default(),
        'none'
    );
}

#[test]
fn test_u8_max_cannot_convert() {
    assert(TryInto::<u8, CallPoints>::try_into(255_u8).is_none(), 'max value');
}

#[test]
fn test_u8_into_all_call_points() {
    assert(TryInto::<u8, CallPoints>::try_into(254_u8).unwrap() == all_call_points(), 'all');
}

#[test]
fn test_lower_bits_result_in_none() {
    assert(TryInto::<u8, CallPoints>::try_into(1_u8).is_none(), 'lower bits');
}

#[test]
fn test_u8_into_after_initialize_call_points() {
    assert(
        TryInto::<u8, CallPoints>::try_into(128)
            .unwrap() == CallPoints {
                before_initialize_pool: false,
                after_initialize_pool: true,
                before_swap: false,
                after_swap: false,
                before_update_position: false,
                after_update_position: false,
                before_collect_fees: false,
                after_collect_fees: false,
            },
        'after_initialize_pool'
    );
}


#[test]
fn test_u8_into_before_swap_call_points() {
    assert(
        TryInto::<u8, CallPoints>::try_into(64)
            .unwrap() == CallPoints {
                after_initialize_pool: false,
                before_swap: true,
                after_swap: false,
                before_update_position: false,
                after_update_position: false,
                before_collect_fees: false,
                after_collect_fees: false,
            },
        'after_initialize_pool'
    );
}


#[test]
fn test_u8_into_after_swap_call_points() {
    assert(
        TryInto::<u8, CallPoints>::try_into(32)
            .unwrap() == CallPoints {
                after_initialize_pool: false,
                before_swap: false,
                after_swap: true,
                before_update_position: false,
                after_update_position: false,
                before_collect_fees: false,
                after_collect_fees: false,
            },
        'after_initialize_pool'
    );
}

#[test]
fn test_u8_into_before_update_position_call_points() {
    assert(
        TryInto::<u8, CallPoints>::try_into(16)
            .unwrap() == CallPoints {
                after_initialize_pool: false,
                before_swap: false,
                after_swap: false,
                before_update_position: true,
                after_update_position: false,
                before_collect_fees: false,
                after_collect_fees: false,
            },
        'after_initialize_pool'
    );
}

#[test]
fn test_u8_into_after_update_position_call_points() {
    assert(
        TryInto::<u8, CallPoints>::try_into(8)
            .unwrap() == CallPoints {
                after_initialize_pool: false,
                before_swap: false,
                after_swap: false,
                before_update_position: false,
                after_update_position: true,
                before_collect_fees: false,
                after_collect_fees: false,
            },
        'after_initialize_pool'
    );
}

#[test]
fn test_u8_into_before_collect_fees_call_points() {
    assert(
        TryInto::<u8, CallPoints>::try_into(4)
            .unwrap() == CallPoints {
                after_initialize_pool: false,
                before_swap: false,
                after_swap: false,
                before_update_position: false,
                after_update_position: false,
                before_collect_fees: true,
                after_collect_fees: false,
            },
        'after_initialize_pool'
    );
}

#[test]
fn test_u8_into_after_collect_fees_call_points() {
    assert(
        TryInto::<u8, CallPoints>::try_into(2)
            .unwrap() == CallPoints {
                after_initialize_pool: false,
                before_swap: false,
                after_swap: false,
                before_update_position: false,
                after_update_position: false,
                before_collect_fees: false,
                after_collect_fees: true,
            },
        'after_initialize_pool'
    );
}

#[test]
fn test_conversion_all_possible_values() {
    let mut i: u128 = 0;

    while (i != 128) {
        let call_points = CallPoints {
            after_initialize_pool: (i & 64) != 0,
            before_swap: (i & 32) != 0,
            after_swap: (i & 16) != 0,
            before_update_position: (i & 8) != 0,
            after_update_position: (i & 4) != 0,
            before_collect_fees: (i & 2) != 0,
            after_collect_fees: (i & 1) != 0,
        };

        let mut converted: u8 = call_points.into();

        let round_tripped: CallPoints = TryInto::<u8, CallPoints>::try_into(converted).unwrap();

        assert(round_tripped == call_points, 'round trip');

        i += 1;
    };
}
