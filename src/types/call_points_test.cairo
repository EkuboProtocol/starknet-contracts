use ekubo::types::call_points::{CallPoints, all_call_points};
use traits::Into;

#[test]
fn test_default_call_points_into_u8() {
    assert(Default::<CallPoints>::default().into() == 0_u8, 'empty');
}

#[test]
fn test_all_call_points_into_u8() {
    assert(all_call_points().into() == 31_u8, 'all');
}

#[test]
fn test_u8_empty_into_default_call_points() {
    assert(0_u8.into() == Default::<CallPoints>::default(), 'all');
}

#[test]
fn test_u8_into_all_call_points() {
    assert(31_u8.into() == all_call_points(), 'all');
}

#[test]
fn test_u8_into_after_initialize_call_points() {
    assert(
        16_u8.into() == CallPoints {
            after_initialize_pool: true,
            before_swap: false,
            after_swap: false,
            before_update_position: false,
            after_update_position: false,
        },
        'after_initialize_pool'
    );
}


#[test]
fn test_u8_into_before_swap_call_points() {
    assert(
        8_u8.into() == CallPoints {
            after_initialize_pool: false,
            before_swap: true,
            after_swap: false,
            before_update_position: false,
            after_update_position: false,
        },
        'after_initialize_pool'
    );
}


#[test]
fn test_u8_into_after_swap_call_points() {
    assert(
        4_u8.into() == CallPoints {
            after_initialize_pool: false,
            before_swap: false,
            after_swap: true,
            before_update_position: false,
            after_update_position: false,
        },
        'after_initialize_pool'
    );
}

#[test]
fn test_u8_into_before_update_position_call_points() {
    assert(
        2_u8.into() == CallPoints {
            after_initialize_pool: false,
            before_swap: false,
            after_swap: false,
            before_update_position: true,
            after_update_position: false,
        },
        'after_initialize_pool'
    );
}

#[test]
fn test_u8_into_after_update_position_call_points() {
    assert(
        1_u8.into() == CallPoints {
            after_initialize_pool: false,
            before_swap: false,
            after_swap: false,
            before_update_position: false,
            after_update_position: true,
        },
        'after_initialize_pool'
    );
}
