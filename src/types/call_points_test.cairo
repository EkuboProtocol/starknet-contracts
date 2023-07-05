use ekubo::types::call_points::{CallPoints, all_call_points};
use traits::Into;

#[test]
fn test_default_call_points_into_u8() {
    assert(Default::<CallPoints>::default().into() == 0_u8, 'empty');
}

#[test]
fn test_all_call_points_into_u8() {
    assert(all_call_points().into() == 248_u8, 'all');
}

#[test]
fn test_u8_empty_into_default_call_points() {
    assert(0_u8.into() == Default::<CallPoints>::default(), 'all');
}

#[test]
fn test_u8_max_into_all_call_points() {
    assert(255_u8.into() == all_call_points(), 'all');
}

#[test]
fn test_u8_into_all_call_points() {
    assert(248_u8.into() == all_call_points(), 'all');
}

#[test]
fn test_lower_bits_are_ignored() {
    assert(7_u8.into() == Default::<CallPoints>::default(), 'none');
    assert(6_u8.into() == Default::<CallPoints>::default(), 'none');
    assert(5_u8.into() == Default::<CallPoints>::default(), 'none');
    assert(4_u8.into() == Default::<CallPoints>::default(), 'none');
    assert(3_u8.into() == Default::<CallPoints>::default(), 'none');
    assert(2_u8.into() == Default::<CallPoints>::default(), 'none');
    assert(1_u8.into() == Default::<CallPoints>::default(), 'none');
    assert(0_u8.into() == Default::<CallPoints>::default(), 'none');
}

#[test]
fn test_u8_into_after_initialize_call_points() {
    assert(
        128_u8.into() == CallPoints {
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
        64_u8.into() == CallPoints {
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
        32_u8.into() == CallPoints {
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
        16_u8.into() == CallPoints {
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
        8_u8.into() == CallPoints {
            after_initialize_pool: false,
            before_swap: false,
            after_swap: false,
            before_update_position: false,
            after_update_position: true,
        },
        'after_initialize_pool'
    );
}

#[test]
#[available_gas(3000000000)]
fn test_conversion_all_possible_values() {
    let mut i: u128 = 0;

    loop {
        if (i == 256) {
            break ();
        };

        let call_points = CallPoints {
            after_initialize_pool: (i & 16) != 0,
            before_swap: (i & 8) != 0,
            after_swap: (i & 4) != 0,
            before_update_position: (i & 2) != 0,
            after_update_position: (i & 1) != 0,
        };

        let mut converted: u8 = call_points.into();
        // these values are ignored but we should try them
        if ((i & 128) != 0) {
            converted += 4;
        }
        if ((i & 64) != 0) {
            converted += 2;
        }
        if ((i & 32) != 0) {
            converted += 1;
        }

        let round_tripped: CallPoints = converted.into();

        assert(round_tripped == call_points, 'round trip');

        i += 1;
    };
}
