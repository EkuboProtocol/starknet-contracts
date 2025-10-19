use core::num::traits::Zero;
use crate::math::exp2::exp2;
use crate::math::mask::mask;
use crate::math::swap::{SwapResult, is_price_increasing, no_op_swap_result, swap_result};
use crate::math::ticks::{max_sqrt_ratio, min_sqrt_ratio};
use crate::types::i129::i129;

#[test]
fn test_is_price_increasing_cases() {
    assert(!is_price_increasing(exact_output: false, is_token1: false), 'input token0');
    assert(is_price_increasing(exact_output: true, is_token1: false), 'output token0');
    assert(is_price_increasing(exact_output: false, is_token1: true), 'input token1');
    assert(!is_price_increasing(exact_output: true, is_token1: true), 'output token1');
}

// no-op test cases first

#[test]
fn test_no_op_swap_result() {
    assert(
        no_op_swap_result(
            0_u256,
        ) == SwapResult {
            consumed_amount: Zero::zero(),
            sqrt_ratio_next: 0_u256,
            calculated_amount: Zero::zero(),
            fee_amount: Zero::zero(),
        },
        'no-op',
    );
    assert(
        no_op_swap_result(
            1_u256,
        ) == SwapResult {
            consumed_amount: Zero::zero(),
            sqrt_ratio_next: 1_u256,
            calculated_amount: Zero::zero(),
            fee_amount: Zero::zero(),
        },
        'no-op',
    );
    assert(
        no_op_swap_result(
            0x100000000000000000000000000000000_u256,
        ) == SwapResult {
            consumed_amount: Zero::zero(),
            sqrt_ratio_next: 0x100000000000000000000000000000000_u256,
            calculated_amount: Zero::zero(),
            fee_amount: Zero::zero(),
        },
        'no-op',
    );
    assert(
        no_op_swap_result(
            u256 { low: 0, high: 0xffffffffffffffffffffffffffffffff },
        ) == SwapResult {
            consumed_amount: Zero::zero(),
            sqrt_ratio_next: u256 { low: 0, high: 0xffffffffffffffffffffffffffffffff },
            calculated_amount: Zero::zero(),
            fee_amount: Zero::zero(),
        },
        'no-op',
    );
}

#[test]
fn test_swap_zero_amount_token0() {
    assert(
        swap_result(
            sqrt_ratio: 0x100000000000000000000000000000000_u256,
            liquidity: 100000,
            sqrt_ratio_limit: u256 { high: 0, low: 0 },
            amount: Zero::zero(),
            is_token1: false,
            fee: 0,
        ) == SwapResult {
            consumed_amount: Zero::zero(),
            sqrt_ratio_next: 0x100000000000000000000000000000000_u256,
            calculated_amount: Zero::zero(),
            fee_amount: Zero::zero(),
        },
        'result',
    );
}

#[test]
fn test_swap_zero_amount_token1() {
    let result = swap_result(
        sqrt_ratio: 0x100000000000000000000000000000000_u256,
        liquidity: 100000,
        sqrt_ratio_limit: u256 { high: 2, low: 0 },
        amount: Zero::zero(),
        is_token1: true,
        fee: 0,
    );

    assert(result.consumed_amount.is_zero(), 'consumed_amount');
    assert(result.sqrt_ratio_next == 0x100000000000000000000000000000000_u256, 'sqrt_ratio_next');
    assert(result.calculated_amount.is_zero(), 'calculated_amount');
    assert(result.fee_amount.is_zero(), 'fee');
}

#[test]
fn test_swap_ratio_equal_limit_token0() {
    let result = swap_result(
        sqrt_ratio: 0x100000000000000000000000000000000_u256,
        liquidity: 100000,
        sqrt_ratio_limit: 0x100000000000000000000000000000000_u256,
        amount: i129 { mag: 10000, sign: false },
        is_token1: false,
        fee: 0,
    );

    assert(result.consumed_amount.is_zero(), 'consumed_amount');
    assert(result.sqrt_ratio_next == 0x100000000000000000000000000000000_u256, 'sqrt_ratio_next');
    assert(result.calculated_amount.is_zero(), 'calculated_amount');
    assert(result.fee_amount.is_zero(), 'fee');
}

#[test]
fn test_swap_ratio_equal_limit_token1() {
    let result = swap_result(
        sqrt_ratio: 0x100000000000000000000000000000000_u256,
        liquidity: 100000,
        sqrt_ratio_limit: 0x100000000000000000000000000000000_u256,
        amount: i129 { mag: 10000, sign: false },
        is_token1: true,
        fee: 0,
    );

    assert(result.consumed_amount.is_zero(), 'consumed_amount');
    assert(result.sqrt_ratio_next == 0x100000000000000000000000000000000_u256, 'sqrt_ratio_next');
    assert(result.calculated_amount.is_zero(), 'calculated_amount');
    assert(result.fee_amount.is_zero(), 'fee');
}

// wrong direction asserts

#[test]
#[should_panic(expected: ('DIRECTION',))]
fn test_swap_ratio_wrong_direction_token0_input() {
    swap_result(
        sqrt_ratio: u256 { high: 2, low: 0 },
        liquidity: 100000,
        sqrt_ratio_limit: u256 { high: 2, low: 1 },
        // input of 10k token0, price decreasing
        amount: i129 { mag: 10000, sign: false },
        is_token1: false,
        fee: 0,
    );
}
#[test]
#[should_panic(expected: ('DIRECTION',))]
fn test_swap_ratio_wrong_direction_token0_input_zero_liquidity() {
    swap_result(
        sqrt_ratio: u256 { high: 2, low: 0 },
        liquidity: 0,
        sqrt_ratio_limit: u256 { high: 2, low: 1 },
        // input of 10k token0, price decreasing
        amount: i129 { mag: 10000, sign: false },
        is_token1: false,
        fee: 0,
    );
}
#[test]
fn test_swap_ratio_wrong_direction_token0_zero_input_and_liquidity() {
    assert(
        swap_result(
            sqrt_ratio: u256 { high: 2, low: 0 },
            liquidity: 0,
            sqrt_ratio_limit: u256 { high: 2, low: 1 },
            // input of 10k token0, price decreasing
            amount: i129 { mag: 0, sign: false },
            is_token1: false,
            fee: 0,
        ) == no_op_swap_result(u256 { high: 2, low: 0 }),
        'starting_price',
    );
}
#[test]
#[should_panic(expected: ('DIRECTION',))]
fn test_swap_ratio_wrong_direction_token0_output() {
    swap_result(
        sqrt_ratio: u256 { high: 2, low: 0 },
        liquidity: 100000,
        sqrt_ratio_limit: 0x100000000000000000000000000000000_u256,
        // output of 10k token0, price increasing
        amount: i129 { mag: 10000, sign: true },
        is_token1: false,
        fee: 0,
    );
}
#[test]
#[should_panic(expected: ('DIRECTION',))]
fn test_swap_ratio_wrong_direction_token0_output_zero_liquidity() {
    swap_result(
        sqrt_ratio: u256 { high: 2, low: 0 },
        liquidity: 0,
        sqrt_ratio_limit: 0x100000000000000000000000000000000_u256,
        // output of 10k token0, price increasing
        amount: i129 { mag: 10000, sign: true },
        is_token1: false,
        fee: 0,
    );
}
#[test]
fn test_swap_ratio_wrong_direction_token0_zero_output_and_liquidity() {
    assert(
        swap_result(
            sqrt_ratio: u256 { high: 2, low: 0 },
            liquidity: 0,
            sqrt_ratio_limit: 0x100000000000000000000000000000000_u256,
            // output of 10k token0, price increasing
            amount: i129 { mag: 0, sign: true },
            is_token1: false,
            fee: 0,
        ) == no_op_swap_result(u256 { high: 2, low: 0 }),
        'starting_price',
    );
}

#[test]
#[should_panic(expected: ('DIRECTION',))]
fn test_swap_ratio_wrong_direction_token1_input() {
    swap_result(
        sqrt_ratio: u256 { high: 2, low: 0 },
        liquidity: 100000,
        sqrt_ratio_limit: 0x100000000000000000000000000000000_u256,
        // input of 10k token1, price increasing
        amount: i129 { mag: 10000, sign: false },
        is_token1: true,
        fee: 0,
    );
}
#[test]
#[should_panic(expected: ('DIRECTION',))]
fn test_swap_ratio_wrong_direction_token1_input_zero_liquidity() {
    swap_result(
        sqrt_ratio: u256 { high: 2, low: 0 },
        liquidity: 0,
        sqrt_ratio_limit: 0x100000000000000000000000000000000_u256,
        // input of 10k token1, price increasing
        amount: i129 { mag: 10000, sign: false },
        is_token1: true,
        fee: 0,
    );
}

#[test]
fn test_swap_ratio_wrong_direction_token1_zero_input_and_liquidity() {
    assert(
        swap_result(
            sqrt_ratio: u256 { high: 2, low: 0 },
            liquidity: 0,
            sqrt_ratio_limit: 0x100000000000000000000000000000000_u256,
            // input of 10k token1, price increasing
            amount: i129 { mag: 0, sign: false },
            is_token1: true,
            fee: 0,
        ) == no_op_swap_result(u256 { high: 2, low: 0 }),
        'starting_price',
    );
}

#[test]
#[should_panic(expected: ('DIRECTION',))]
fn test_swap_ratio_wrong_direction_token1_output() {
    swap_result(
        sqrt_ratio: u256 { high: 2, low: 0 },
        liquidity: 100000,
        sqrt_ratio_limit: u256 { high: 2, low: 1 },
        // input of 10k token1, price increasing
        amount: i129 { mag: 10000, sign: true },
        is_token1: true,
        fee: 0,
    );
}
#[test]
#[should_panic(expected: ('DIRECTION',))]
fn test_swap_ratio_wrong_direction_token1_output_zero_liquidity() {
    swap_result(
        sqrt_ratio: u256 { high: 2, low: 0 },
        liquidity: 0,
        sqrt_ratio_limit: u256 { high: 2, low: 1 },
        // input of 10k token1, price increasing
        amount: i129 { mag: 10000, sign: true },
        is_token1: true,
        fee: 0,
    );
}


#[test]
fn test_swap_ratio_wrong_direction_token1_zero_output_and_liquidity() {
    assert(
        swap_result(
            sqrt_ratio: u256 { high: 2, low: 0 },
            liquidity: 0,
            sqrt_ratio_limit: u256 { high: 2, low: 1 },
            // input of 10k token1, price increasing
            amount: i129 { mag: 0, sign: true },
            is_token1: true,
            fee: 0,
        ) == no_op_swap_result(u256 { high: 2, low: 0 }),
        'starting_price',
    );
}

// limit not hit

#[test]
fn test_swap_against_liquidity_max_limit_token0_input() {
    let result = swap_result(
        sqrt_ratio: 0x100000000000000000000000000000000_u256,
        liquidity: 100000,
        sqrt_ratio_limit: min_sqrt_ratio(),
        amount: i129 { mag: 10000, sign: false },
        is_token1: false,
        fee: exp2(127) // equal to 0.5
    );

    assert(result.consumed_amount == i129 { mag: 10000, sign: false }, 'consumed_amount');
    assert(
        result.sqrt_ratio_next == u256 { high: 0, low: 324078444686608060441309149935017344244 },
        'sqrt_ratio_next',
    );
    assert(result.calculated_amount == 4761, 'calculated_amount');
    assert(result.fee_amount == 5000, 'fee');
}

#[test]
fn test_swap_against_liquidity_max_limit_token0_minimum_input() {
    let result = swap_result(
        sqrt_ratio: 0x100000000000000000000000000000000_u256,
        liquidity: 100000,
        sqrt_ratio_limit: min_sqrt_ratio(),
        amount: i129 { mag: 1, sign: false },
        is_token1: false,
        fee: exp2(127) // equal to 0.5
    );

    assert(result.consumed_amount == i129 { mag: 1, sign: false }, 'consumed_amount');
    assert(result.sqrt_ratio_next == 0x100000000000000000000000000000000_u256, 'sqrt_ratio_next');
    assert(result.calculated_amount.is_zero(), 'calculated_amount');
    assert(result.fee_amount == 1, 'fee');
}

#[test]
fn test_swap_against_liquidity_min_limit_token0_output() {
    let result = swap_result(
        sqrt_ratio: 0x100000000000000000000000000000000_u256,
        liquidity: 100000,
        sqrt_ratio_limit: max_sqrt_ratio(),
        amount: i129 { mag: 10000, sign: true },
        is_token1: false,
        fee: exp2(127) // equal to 0.5
    );

    assert(result.consumed_amount == i129 { mag: 10000, sign: true }, 'consumed_amount');
    assert(
        result.sqrt_ratio_next == u256 { high: 1, low: 0x1c71c71c71c71c71c71c71c71c71c71d },
        'sqrt_ratio_next',
    );
    assert(result.calculated_amount == 22224, 'calculated_amount');
    assert(result.fee_amount == 11112, 'fee');
}


#[test]
fn test_swap_against_liquidity_min_limit_token0_minimum_output() {
    let result = swap_result(
        sqrt_ratio: 0x100000000000000000000000000000000_u256,
        liquidity: 100000,
        sqrt_ratio_limit: max_sqrt_ratio(),
        amount: i129 { mag: 1, sign: true },
        is_token1: false,
        fee: exp2(127) // equal to 0.5
    );

    assert(result.consumed_amount == i129 { mag: 1, sign: true }, 'consumed_amount');
    assert(
        result.sqrt_ratio_next == u256 { high: 1, low: 0xa7c61a3ae2bdd0cef9133bc4d7cb },
        'sqrt_ratio_next',
    );
    assert(result.calculated_amount == 4, 'calculated_amount');
    assert(result.fee_amount == 2, 'fee');
}


#[test]
fn test_swap_against_liquidity_max_limit_token1_input() {
    let result = swap_result(
        sqrt_ratio: 0x100000000000000000000000000000000_u256,
        liquidity: 100000,
        sqrt_ratio_limit: max_sqrt_ratio(),
        amount: i129 { mag: 10000, sign: false },
        is_token1: true,
        fee: exp2(127) // equal to 0.5
    );

    assert(result.consumed_amount == i129 { mag: 10000, sign: false }, 'consumed_amount');
    assert(
        result.sqrt_ratio_next == u256 { high: 1, low: 17014118346046923173168730371588410572 },
        'sqrt_ratio_next',
    );
    assert(result.calculated_amount == 4761, 'calculated_amount');
    assert(result.fee_amount == 5000, 'fee');
}

#[test]
fn test_swap_against_liquidity_max_limit_token1_minimum_input() {
    let result = swap_result(
        sqrt_ratio: 0x100000000000000000000000000000000_u256,
        liquidity: 100000,
        sqrt_ratio_limit: max_sqrt_ratio(),
        amount: i129 { mag: 1, sign: false },
        is_token1: true,
        fee: exp2(127) // equal to 0.5
    );

    assert(result.consumed_amount == i129 { mag: 1, sign: false }, 'consumed_amount');
    assert(result.sqrt_ratio_next == 0x100000000000000000000000000000000_u256, 'sqrt_ratio_next');
    assert(result.calculated_amount.is_zero(), 'calculated_amount');
    assert(result.fee_amount == 1, 'fee');
}


#[test]
fn test_swap_against_liquidity_min_limit_token1_output() {
    let result = swap_result(
        sqrt_ratio: 0x100000000000000000000000000000000_u256,
        liquidity: 100000,
        sqrt_ratio_limit: min_sqrt_ratio(),
        amount: i129 { mag: 10000, sign: true },
        is_token1: true,
        fee: exp2(127) // equal to 0.5
    );

    assert(result.consumed_amount == i129 { mag: 10000, sign: true }, 'consumed_amount');
    assert(
        result.sqrt_ratio_next == u256 { high: 0, low: 0xe6666666666666666666666666666666 },
        'sqrt_ratio_next',
    );
    assert(result.calculated_amount == 22224, 'calculated_amount');
    assert(result.fee_amount == 11112, 'fee');
}


#[test]
fn test_swap_against_liquidity_min_limit_token1_minimum_output() {
    let result = swap_result(
        sqrt_ratio: 0x100000000000000000000000000000000_u256,
        liquidity: 100000,
        sqrt_ratio_limit: min_sqrt_ratio(),
        amount: i129 { mag: 1, sign: true },
        is_token1: true,
        fee: exp2(127) // equal to 0.5
    );

    assert(result.consumed_amount == i129 { mag: 1, sign: true }, 'consumed_amount');
    assert(
        result.sqrt_ratio_next == u256 { high: 0, low: 0xffff583a53b8e4b87bdcf0307f23cc8d },
        'sqrt_ratio_next',
    );
    assert(result.calculated_amount == 0x4, 'calculated_amount');
    assert(result.fee_amount == 2, 'fee');
}


// limit hit tests

#[test]
fn test_swap_against_liquidity_hit_limit_token0_input() {
    let result = swap_result(
        sqrt_ratio: 0x100000000000000000000000000000000_u256,
        liquidity: 100000,
        sqrt_ratio_limit: u256 { high: 0, low: 333476719582519694194107115283132847226 },
        amount: i129 { mag: 10000, sign: false },
        is_token1: false,
        fee: exp2(127) // equal to 0.5
    );

    assert(
        result == SwapResult {
            consumed_amount: i129 { mag: 4082, sign: false },
            sqrt_ratio_next: u256 { high: 0, low: 333476719582519694194107115283132847226 },
            calculated_amount: 2000,
            fee_amount: 2041,
        },
        'result',
    );
}

#[test]
fn test_swap_against_liquidity_hit_limit_token1_input() {
    let result = swap_result(
        sqrt_ratio: 0x100000000000000000000000000000000_u256,
        liquidity: 100000,
        sqrt_ratio_limit: u256 { high: 1, low: 0x51eb851eb851eb851eb851eb851eb85 },
        amount: i129 { mag: 10000, sign: false },
        is_token1: true,
        fee: exp2(127) // equal to 0.5
    );

    assert(
        result == SwapResult {
            consumed_amount: i129 { mag: 4000, sign: false },
            sqrt_ratio_next: u256 { high: 1, low: 0x51eb851eb851eb851eb851eb851eb85 },
            calculated_amount: 1960,
            fee_amount: 2000,
        },
        'result',
    );
}


#[test]
fn test_swap_against_liquidity_hit_limit_token0_output() {
    let result = swap_result(
        sqrt_ratio: 0x100000000000000000000000000000000_u256,
        liquidity: 100000,
        sqrt_ratio_limit: u256 { high: 1, low: 0x51eb851eb851eb851eb851eb851eb85 },
        amount: i129 { mag: 10000, sign: true },
        is_token1: false,
        fee: exp2(127) // equal to 0.5
    );

    assert(
        result == SwapResult {
            consumed_amount: i129 { mag: 1960, sign: true },
            sqrt_ratio_next: u256 { high: 1, low: 0x51eb851eb851eb851eb851eb851eb85 },
            calculated_amount: 4000,
            fee_amount: 2000,
        },
        'result',
    );
}

#[test]
fn test_swap_against_liquidity_hit_limit_token1_output() {
    let result = swap_result(
        sqrt_ratio: 0x100000000000000000000000000000000_u256,
        liquidity: 100000,
        sqrt_ratio_limit: u256 { high: 0, low: 333476719582519694194107115283132847226 },
        amount: i129 { mag: 10000, sign: true },
        is_token1: true,
        fee: exp2(127) // equal to 0.5
    );

    assert(
        result == SwapResult {
            consumed_amount: i129 { mag: 2000, sign: true },
            sqrt_ratio_next: u256 { high: 0, low: 333476719582519694194107115283132847226 },
            calculated_amount: 4082,
            fee_amount: 2041,
        },
        'result',
    );
}


#[test]
fn test_swap_max_amount_token0() {
    let amount = i129 { mag: 0xffffffffffffffffffffffffffffffff, sign: false };
    let result = swap_result(
        sqrt_ratio: 0x100000000000000000000000000000000_u256,
        liquidity: 100000,
        sqrt_ratio_limit: min_sqrt_ratio(),
        amount: amount,
        is_token1: false,
        fee: 0,
    );

    assert(
        result == SwapResult {
            consumed_amount: i129 { mag: 0x1869ff9f1cba5e3895631, sign: false },
            sqrt_ratio_next: u256 { low: 0x1000003f7f1380b75, high: 0 },
            calculated_amount: 0x1869f,
            fee_amount: 0x0,
        },
        'result',
    );
}

#[test]
fn test_swap_min_amount_token0() {
    let result = swap_result(
        sqrt_ratio: 0x100000000000000000000000000000000_u256,
        liquidity: 100000,
        sqrt_ratio_limit: min_sqrt_ratio(),
        amount: i129 { mag: 1, sign: false },
        is_token1: false,
        fee: 0,
    );

    assert(
        result == SwapResult {
            consumed_amount: i129 { mag: 1, sign: false },
            sqrt_ratio_next: u256 { low: 0xffff583ac1ac1c114b9160ddeb4791b8, high: 0 },
            calculated_amount: 0,
            fee_amount: 0x0,
        },
        'result',
    );
}

#[test]
fn test_swap_min_amount_token0_very_high_price() {
    assert(
        swap_result(
            sqrt_ratio: max_sqrt_ratio(),
            liquidity: 100000,
            sqrt_ratio_limit: min_sqrt_ratio(),
            amount: i129 { mag: 1, sign: false },
            is_token1: false,
            fee: 0,
        ) == SwapResult {
            consumed_amount: i129 { mag: 1, sign: false },
            sqrt_ratio_next: u256 { low: 0, high: 0x186a0 },
            calculated_amount: 0x1869ff9f1cba38f7ef8d0,
            fee_amount: 0x0,
        },
        'result',
    );
}

#[test]
fn test_swap_max_amount_token1() {
    assert(
        swap_result(
            sqrt_ratio: 0x100000000000000000000000000000000_u256,
            liquidity: 100000,
            sqrt_ratio_limit: max_sqrt_ratio(),
            amount: i129 { mag: 0xffffffffffffffffffffffffffffffff, sign: false },
            is_token1: true,
            fee: 0,
        ) == SwapResult {
            consumed_amount: i129 { mag: 0x1869ff9f1cba5e3895631, sign: false },
            sqrt_ratio_next: u256 {
                low: 0x6f3528fe26840249f4b191ef6dff7928, high: 0xfffffc080ed7b455,
            },
            calculated_amount: 0x1869f,
            fee_amount: 0,
        },
        'result',
    );
}

#[test]
fn test_swap_min_amount_token1() {
    assert(
        swap_result(
            sqrt_ratio: 0x100000000000000000000000000000000_u256,
            liquidity: 100000,
            sqrt_ratio_limit: max_sqrt_ratio(),
            amount: i129 { mag: 1, sign: false },
            is_token1: true,
            fee: 0,
        ) == SwapResult {
            consumed_amount: i129 { mag: 1, sign: false },
            sqrt_ratio_next: u256 { low: 0xa7c5ac471b4784230fcf80dc3372, high: 1 },
            calculated_amount: 0,
            fee_amount: 0x0,
        },
        'result',
    );
}


#[test]
fn test_swap_min_amount_token1_very_high_price() {
    assert(
        swap_result(
            sqrt_ratio: min_sqrt_ratio(),
            liquidity: 100000,
            sqrt_ratio_limit: max_sqrt_ratio(),
            amount: i129 { mag: 1, sign: false },
            is_token1: true,
            fee: 0,
        ) == SwapResult {
            consumed_amount: i129 { mag: 1, sign: false },
            sqrt_ratio_next: u256 { low: 0xa7c5ac471b48842313c772143ee7, high: 0 },
            calculated_amount: 0x1869ff9f1cba38f7ef8d0,
            fee_amount: 0x0,
        },
        'result',
    );
}

#[test]
fn test_swap_max_fee() {
    assert(
        swap_result(
            sqrt_ratio: 0x100000000000000000000000000000000_u256,
            liquidity: 100000,
            sqrt_ratio_limit: min_sqrt_ratio(),
            amount: i129 { mag: 1000, sign: false },
            is_token1: false,
            fee: 0xffffffffffffffffffffffffffffffff,
        ) == SwapResult {
            consumed_amount: i129 { mag: 1000, sign: false },
            sqrt_ratio_next: 0x100000000000000000000000000000000_u256,
            calculated_amount: 0,
            fee_amount: 0x3e8,
        },
        'result',
    );
}

#[test]
fn test_swap_min_fee() {
    assert(
        swap_result(
            sqrt_ratio: 0x100000000000000000000000000000000_u256,
            liquidity: 100000,
            sqrt_ratio_limit: min_sqrt_ratio(),
            amount: i129 { mag: 1000, sign: false },
            is_token1: false,
            fee: 1,
        ) == SwapResult {
            consumed_amount: i129 { mag: 1000, sign: false },
            sqrt_ratio_next: u256 { low: 0xfd77c56b2369787351572278168739a1, high: 0 },
            calculated_amount: 989,
            fee_amount: 0x1,
        },
        'result',
    );
}

#[test]
fn test_swap_all_max_inputs() {
    assert(
        swap_result(
            sqrt_ratio: max_sqrt_ratio(),
            liquidity: 0xffffffffffffffffffffffffffffffff,
            sqrt_ratio_limit: min_sqrt_ratio(),
            amount: i129 { mag: 0xffffffffffffffffffffffffffffffff, sign: false },
            is_token1: false,
            fee: 0xffffffffffffffffffffffffffffffff,
        ) == SwapResult {
            consumed_amount: i129 { mag: 0xffffffffffffffffffffffffffffffff, sign: false },
            sqrt_ratio_next: max_sqrt_ratio(),
            calculated_amount: 0,
            fee_amount: 0xffffffffffffffffffffffffffffffff,
        },
        'result',
    );
}


#[test]
#[should_panic(expected: ('OVERFLOW_AMOUNT1_DELTA',))]
fn test_swap_all_max_inputs_no_fee() {
    swap_result(
        sqrt_ratio: max_sqrt_ratio(),
        liquidity: 0xffffffffffffffffffffffffffffffff,
        sqrt_ratio_limit: min_sqrt_ratio(),
        amount: i129 { mag: 0xffffffffffffffffffffffffffffffff, sign: false },
        is_token1: false,
        fee: 0,
    );
}

#[test]
fn test_swap_result_example_usdc_wbtc() {
    let result = swap_result(
        sqrt_ratio: 21175949444679574865522613902772161611,
        liquidity: 717193642384,
        sqrt_ratio_limit: min_sqrt_ratio(),
        amount: i129 { mag: 9995000000, sign: false },
        is_token1: false,
        fee: 1020847100762815411640772995208708096,
    );

    assert(
        result == SwapResult {
            consumed_amount: i129 { mag: 9995000000, sign: false },
            sqrt_ratio_next: u256 { low: 0xfead0f195a1008a61a0a6a34c2b5410, high: 0 },
            calculated_amount: 38557555,
            fee_amount: 29985001,
        },
        'calculated_amount',
    );
}


#[test]
#[should_panic(expected: ('AMOUNT_BEFORE_FEE_OVERFLOW',))]
fn test_exact_output_swap_max_fee_token0() {
    assert(
        swap_result(
            sqrt_ratio: 0x100000000000000000000000000000000_u256,
            liquidity: 79228162514264337593543950336,
            sqrt_ratio_limit: max_sqrt_ratio(),
            amount: i129 { mag: 1, sign: true },
            is_token1: false,
            fee: mask(127),
        ) == SwapResult {
            consumed_amount: i129 { mag: 1, sign: true },
            sqrt_ratio_next: u256 { low: 0x200000001, high: 1 },
            calculated_amount: 3,
            fee_amount: 1,
        },
        'result',
    );
}

#[test]
#[should_panic(expected: ('AMOUNT_BEFORE_FEE_OVERFLOW',))]
fn test_exact_output_swap_max_fee_large_amount_token0() {
    let result = swap_result(
        sqrt_ratio: 0x100000000000000000000000000000000_u256,
        liquidity: 79228162514264337593543950336,
        sqrt_ratio_limit: max_sqrt_ratio(),
        amount: i129 { mag: 10000, sign: true },
        is_token1: false,
        fee: mask(127),
    );

    assert(
        result == SwapResult {
            consumed_amount: i129 { mag: 10000, sign: true },
            sqrt_ratio_next: u256 { low: 0x271000000001, high: 1 },
            calculated_amount: 10002,
            fee_amount: 0x1,
        },
        'result',
    );
}

#[test]
#[should_panic(expected: ('AMOUNT_BEFORE_FEE_OVERFLOW',))]
fn test_exact_output_swap_max_fee_token0_limit_reached() {
    let result = swap_result(
        sqrt_ratio: 0x100000000000000000000000000000000_u256,
        liquidity: 79228162514264337593543950336,
        sqrt_ratio_limit: u256 { high: 1, low: 0x200000000 },
        amount: i129 { mag: 1, sign: true },
        is_token1: false,
        fee: mask(127),
    );
    assert(
        result == SwapResult {
            consumed_amount: i129 { mag: 0, sign: true },
            sqrt_ratio_next: u256 { high: 1, low: 0x200000000 },
            calculated_amount: 2,
            fee_amount: 1,
        },
        'result',
    );
}

#[test]
#[should_panic(expected: ('AMOUNT_BEFORE_FEE_OVERFLOW',))]
fn test_exact_output_swap_max_fee_token1() {
    let result = swap_result(
        sqrt_ratio: 0x100000000000000000000000000000000_u256,
        liquidity: 79228162514264337593543950336,
        sqrt_ratio_limit: min_sqrt_ratio(),
        amount: i129 { mag: 1, sign: true },
        is_token1: true,
        fee: mask(127),
    );
    assert(
        result == SwapResult {
            consumed_amount: i129 { mag: 1, sign: true },
            sqrt_ratio_next: u256 { low: 0xfffffffffffffffffffffffe00000000, high: 0 },
            calculated_amount: 3,
            fee_amount: 1,
        },
        'result',
    );
}

#[test]
#[should_panic(expected: ('AMOUNT_BEFORE_FEE_OVERFLOW',))]
fn test_exact_output_swap_max_fee_token1_limit_reached() {
    let result = swap_result(
        sqrt_ratio: 0x100000000000000000000000000000000_u256,
        liquidity: 79228162514264337593543950336,
        sqrt_ratio_limit: u256 { low: 0xffffffffffffffffffffffff00000000, high: 0 },
        amount: i129 { mag: 1, sign: true },
        is_token1: true,
        fee: mask(127),
    );
    assert(
        result == SwapResult {
            consumed_amount: i129 { mag: 0, sign: true },
            sqrt_ratio_next: u256 { low: 0xffffffffffffffffffffffff00000000, high: 0 },
            calculated_amount: 2,
            fee_amount: 1,
        },
        'result',
    );
}

#[test]
fn test_exact_input_swap_max_fee_token0() {
    assert(
        swap_result(
            sqrt_ratio: 0x100000000000000000000000000000000_u256,
            liquidity: 79228162514264337593543950336,
            sqrt_ratio_limit: min_sqrt_ratio(),
            amount: i129 { mag: 1, sign: false },
            is_token1: false,
            fee: mask(127),
        ) == SwapResult {
            consumed_amount: i129 { mag: 1, sign: false },
            sqrt_ratio_next: 0x100000000000000000000000000000000_u256,
            calculated_amount: 0,
            fee_amount: 1,
        },
        'result',
    );
}

#[test]
fn test_exact_input_swap_max_fee_token1() {
    assert(
        swap_result(
            sqrt_ratio: 0x100000000000000000000000000000000_u256,
            liquidity: 79228162514264337593543950336,
            sqrt_ratio_limit: max_sqrt_ratio(),
            amount: i129 { mag: 1, sign: false },
            is_token1: true,
            fee: mask(127),
        ) == SwapResult {
            consumed_amount: i129 { mag: 1, sign: false },
            sqrt_ratio_next: 0x100000000000000000000000000000000_u256,
            calculated_amount: 0,
            fee_amount: 1,
        },
        'result',
    );
}

