use starknet::{storage_base_address_const, Store, SyscallResult, SyscallResultTrait};
use ekubo::types::pool::Pool;
use ekubo::types::i129::i129;
use traits::{Into};
use ekubo::types::call_points::CallPoints;
use zeroable::Zeroable;
use ekubo::math::ticks::{min_tick, max_tick, min_sqrt_ratio, max_sqrt_ratio};

#[test]
#[available_gas(3000000)]
fn test_storage_access_write_read_empty() {
    let base = storage_base_address_const::<0>();
    let write = Store::<Pool>::write_at_offset(
        address_domain: 0,
        base: base,
        offset: 0_u8,
        value: Pool {
            sqrt_ratio: Zeroable::zero(),
            tick: Zeroable::zero(),
            call_points: Default::default(),
            liquidity: Zeroable::zero(),
            fee_growth_global_token0: Zeroable::zero(),
            fee_growth_global_token1: Zeroable::zero(),
        }
    )
        .unwrap_syscall();
    let read = Store::<Pool>::read_at_offset(address_domain: 0, base: base, offset: 0_u8)
        .unwrap_syscall();

    assert(read.sqrt_ratio.is_zero(), 'sqrt_ratio');
    assert(read.tick.is_zero(), 'tick');
    assert(read.call_points == Default::default(), 'call_points');
    assert(read.liquidity.is_zero(), 'liquidity');
    assert(read.fee_growth_global_token0.is_zero(), 'fggt0');
    assert(read.fee_growth_global_token1.is_zero(), 'fggt1');
}


#[test]
#[available_gas(3000000)]
fn test_storage_access_write_read_valid_example_at_random_base_address_plus_offset() {
    let base = storage_base_address_const::<123456>();
    let call_points = CallPoints {
        after_initialize_pool: false,
        before_swap: true,
        after_swap: false,
        before_update_position: true,
        after_update_position: false,
    };
    let write = Store::<Pool>::write_at_offset(
        address_domain: 0,
        base: base,
        offset: 8_u8,
        value: Pool {
            sqrt_ratio: min_sqrt_ratio(),
            tick: min_tick(),
            call_points: call_points,
            liquidity: 123456789,
            fee_growth_global_token0: 45678,
            fee_growth_global_token1: 910234,
        }
    )
        .unwrap_syscall();
    let read = Store::<Pool>::read_at_offset(address_domain: 0, base: base, offset: 8_u8)
        .unwrap_syscall();

    assert(read.sqrt_ratio == min_sqrt_ratio(), 'sqrt_ratio');
    assert(read.tick == min_tick(), 'tick');
    assert(read.call_points == call_points, 'call_points');
    assert(read.liquidity == 123456789, 'liquidity');
    assert(read.fee_growth_global_token0 == 45678, 'fggt0');
    assert(read.fee_growth_global_token1 == 910234, 'fggt1');
}

#[test]
#[available_gas(3000000)]
#[should_panic(expected: ('u8_add Overflow', ))]
fn test_write_fails_if_offset_too_large_to_fit() {
    let base = storage_base_address_const::<123456>();
    let call_points = CallPoints {
        after_initialize_pool: false,
        before_swap: true,
        after_swap: false,
        before_update_position: true,
        after_update_position: false,
    };
    Store::<Pool>::write_at_offset(
        address_domain: 0,
        base: base,
        offset: 253_u8,
        value: Pool {
            sqrt_ratio: min_sqrt_ratio(),
            tick: min_tick(),
            call_points: call_points,
            liquidity: 123456789,
            fee_growth_global_token0: 45678,
            fee_growth_global_token1: 910234,
        }
    )
        .unwrap_syscall();
}

#[test]
#[available_gas(3000000)]
#[should_panic(expected: ('TICK_MAGNITUDE', ))]
fn test_storage_access_write_error_if_tick_less_than_min_by_2() {
    let base = storage_base_address_const::<123456>();
    let write = Store::<Pool>::write_at_offset(
        address_domain: 0,
        base: base,
        offset: 8_u8,
        value: Pool {
            sqrt_ratio: min_sqrt_ratio(), tick: min_tick() - i129 {
                mag: 2, sign: false
            },
            call_points: Default::default(),
            liquidity: 123456789,
            fee_growth_global_token0: 45678,
            fee_growth_global_token1: 910234,
        }
    );
}

#[test]
#[available_gas(3000000)]
#[should_panic(expected: ('TICK_MAGNITUDE', ))]
fn test_storage_access_write_error_if_tick_greater_than_max_by_1() {
    let base = storage_base_address_const::<123456>();
    let write = Store::<Pool>::write_at_offset(
        address_domain: 0,
        base: base,
        offset: 8_u8,
        value: Pool {
            sqrt_ratio: min_sqrt_ratio(), tick: max_tick() + i129 {
                mag: 1, sign: false
            },
            call_points: Default::default(),
            liquidity: 123456789,
            fee_growth_global_token0: 45678,
            fee_growth_global_token1: 910234,
        }
    );
}

#[test]
#[available_gas(3000000)]
#[should_panic(expected: ('SQRT_RATIO', ))]
fn test_storage_access_write_error_if_sqrt_ratio_less_than_min() {
    let base = storage_base_address_const::<123456>();
    let write = Store::<Pool>::write_at_offset(
        address_domain: 0,
        base: base,
        offset: 8_u8,
        value: Pool {
            sqrt_ratio: min_sqrt_ratio() - 1,
            tick: min_tick(),
            call_points: Default::default(),
            liquidity: 123456789,
            fee_growth_global_token0: 45678,
            fee_growth_global_token1: 910234,
        }
    );
}

#[test]
#[available_gas(3000000)]
#[should_panic(expected: ('SQRT_RATIO', ))]
fn test_storage_access_write_error_if_sqrt_ratio_gt_max() {
    let base = storage_base_address_const::<123456>();
    let write = Store::<Pool>::write_at_offset(
        address_domain: 0,
        base: base,
        offset: 8_u8,
        value: Pool {
            sqrt_ratio: max_sqrt_ratio() + 1,
            tick: max_tick(),
            call_points: Default::default(),
            liquidity: 123456789,
            fee_growth_global_token0: 45678,
            fee_growth_global_token1: 910234,
        }
    );
}
