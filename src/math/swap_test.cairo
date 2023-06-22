use ekubo::math::swap::{no_op_swap_result, swap_result, is_price_increasing, SwapResult};
use ekubo::math::ticks::{max_sqrt_ratio, min_sqrt_ratio};
use zeroable::Zeroable;
use ekubo::types::i129::i129;
use ekubo::math::exp2::exp2;
use debug::PrintTrait;

impl SwapResultPrintTrait of PrintTrait<SwapResult> {
    fn print(self: SwapResult) {
        'consumed_amount:'.print();
        self.consumed_amount.print();
        'sqrt_ratio_next:'.print();
        self.sqrt_ratio_next.print();
        'calculated_amount:'.print();
        self.calculated_amount.print();
        'fee_amount:'.print();
        self.fee_amount.print();
    }
}


impl SwapResultEq of PartialEq<SwapResult> {
    fn eq(lhs: @SwapResult, rhs: @SwapResult) -> bool {
        (*lhs.consumed_amount == *rhs.consumed_amount)
            & (*lhs.sqrt_ratio_next == *rhs.sqrt_ratio_next)
            & (*lhs.calculated_amount == *rhs.calculated_amount)
            & (*lhs.fee_amount == *rhs.fee_amount)
    }
    fn ne(lhs: @SwapResult, rhs: @SwapResult) -> bool {
        !PartialEq::<SwapResult>::eq(lhs, rhs)
    }
}

// no-op test cases first

#[test]
fn test_no_op_swap_result() {
    assert(
        no_op_swap_result(u256 { low: 0, high: 0 }) == SwapResult {
            consumed_amount: Zeroable::zero(), sqrt_ratio_next: u256 {
                low: 0, high: 0
            }, calculated_amount: Zeroable::zero(), fee_amount: Zeroable::zero(),
        },
        'no-op'
    );
    assert(
        no_op_swap_result(u256 { low: 1, high: 0 }) == SwapResult {
            consumed_amount: Zeroable::zero(), sqrt_ratio_next: u256 {
                low: 1, high: 0
            }, calculated_amount: Zeroable::zero(), fee_amount: Zeroable::zero(),
        },
        'no-op'
    );
    assert(
        no_op_swap_result(u256 { low: 0, high: 1 }) == SwapResult {
            consumed_amount: Zeroable::zero(), sqrt_ratio_next: u256 {
                low: 0, high: 1
            }, calculated_amount: Zeroable::zero(), fee_amount: Zeroable::zero(),
        },
        'no-op'
    );
    assert(
        no_op_swap_result(u256 { low: 0, high: 0xffffffffffffffffffffffffffffffff }) == SwapResult {
            consumed_amount: Zeroable::zero(), sqrt_ratio_next: u256 {
                low: 0, high: 0xffffffffffffffffffffffffffffffff
            }, calculated_amount: Zeroable::zero(), fee_amount: Zeroable::zero(),
        },
        'no-op'
    );
}

#[test]
fn test_swap_zero_amount_token0() {
    assert(
        swap_result(
            sqrt_ratio: u256 { high: 1, low: 0 },
            liquidity: 100000,
            sqrt_ratio_limit: u256 { high: 0, low: 0 },
            amount: Zeroable::zero(),
            is_token1: false,
            fee: 0,
        ) == SwapResult {
            consumed_amount: Zeroable::zero(), sqrt_ratio_next: u256 {
                high: 1, low: 0
            }, calculated_amount: Zeroable::zero(), fee_amount: Zeroable::zero(),
        },
        'result'
    );
}

#[test]
fn test_swap_zero_amount_token1() {
    let result = swap_result(
        sqrt_ratio: u256 { high: 1, low: 0 },
        liquidity: 100000,
        sqrt_ratio_limit: u256 { high: 2, low: 0 },
        amount: Zeroable::zero(),
        is_token1: true,
        fee: 0,
    );

    assert(result.consumed_amount.is_zero(), 'consumed_amount');
    assert(result.sqrt_ratio_next == u256 { high: 1, low: 0 }, 'sqrt_ratio_next');
    assert(result.calculated_amount == 0, 'calculated_amount');
    assert(result.fee_amount == 0, 'fee');
}

#[test]
fn test_swap_ratio_equal_limit_token0() {
    let result = swap_result(
        sqrt_ratio: u256 { high: 1, low: 0 },
        liquidity: 100000,
        sqrt_ratio_limit: u256 { high: 1, low: 0 },
        amount: i129 { mag: 10000, sign: false },
        is_token1: false,
        fee: 0,
    );

    assert(result.consumed_amount.is_zero(), 'consumed_amount');
    assert(result.sqrt_ratio_next == u256 { high: 1, low: 0 }, 'sqrt_ratio_next');
    assert(result.calculated_amount == 0, 'calculated_amount');
    assert(result.fee_amount == 0, 'fee');
}

#[test]
fn test_swap_ratio_equal_limit_token1() {
    let result = swap_result(
        sqrt_ratio: u256 { high: 1, low: 0 },
        liquidity: 100000,
        sqrt_ratio_limit: u256 { high: 1, low: 0 },
        amount: i129 { mag: 10000, sign: false },
        is_token1: true,
        fee: 0,
    );

    assert(result.consumed_amount.is_zero(), 'consumed_amount');
    assert(result.sqrt_ratio_next == u256 { high: 1, low: 0 }, 'sqrt_ratio_next');
    assert(result.calculated_amount == 0, 'calculated_amount');
    assert(result.fee_amount == 0, 'fee');
}

// wrong direction asserts

#[test]
#[should_panic(expected: ('DIRECTION', ))]
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
#[should_panic(expected: ('DIRECTION', ))]
fn test_swap_ratio_wrong_direction_token0_output() {
    swap_result(
        sqrt_ratio: u256 { high: 2, low: 0 },
        liquidity: 100000,
        sqrt_ratio_limit: u256 { high: 1, low: 0 },
        // output of 10k token0, price increasing
        amount: i129 { mag: 10000, sign: true },
        is_token1: false,
        fee: 0,
    );
}

#[test]
#[should_panic(expected: ('DIRECTION', ))]
fn test_swap_ratio_wrong_direction_token1_input() {
    swap_result(
        sqrt_ratio: u256 { high: 2, low: 0 },
        liquidity: 100000,
        sqrt_ratio_limit: u256 { high: 1, low: 0 },
        // input of 10k token1, price increasing
        amount: i129 { mag: 10000, sign: false },
        is_token1: true,
        fee: 0,
    );
}

#[test]
#[should_panic(expected: ('DIRECTION', ))]
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

// limit not hit

#[test]
fn test_swap_against_liquidity_max_limit_token0_input() {
    let result = swap_result(
        sqrt_ratio: u256 { high: 1, low: 0 },
        liquidity: 100000,
        sqrt_ratio_limit: min_sqrt_ratio(),
        amount: i129 { mag: 10000, sign: false },
        is_token1: false,
        fee: exp2(127), // equal to 0.5
    );

    assert(result.consumed_amount == i129 { mag: 10000, sign: false }, 'consumed_amount');
    assert(
        result.sqrt_ratio_next == u256 { high: 0, low: 324078444686608060441309149935017344244 },
        'sqrt_ratio_next'
    );
    assert(result.calculated_amount == 4761, 'calculated_amount');
    assert(result.fee_amount == 5000, 'fee');
}

#[test]
fn test_swap_against_liquidity_max_limit_token0_minimum_input() {
    let result = swap_result(
        sqrt_ratio: u256 { high: 1, low: 0 },
        liquidity: 100000,
        sqrt_ratio_limit: min_sqrt_ratio(),
        amount: i129 { mag: 1, sign: false },
        is_token1: false,
        fee: exp2(127), // equal to 0.5
    );

    assert(result.consumed_amount == i129 { mag: 1, sign: false }, 'consumed_amount');
    assert(result.sqrt_ratio_next == u256 { high: 1, low: 0 }, 'sqrt_ratio_next');
    assert(result.calculated_amount == 0, 'calculated_amount');
    assert(result.fee_amount == 1, 'fee');
}

#[test]
fn test_swap_against_liquidity_min_limit_token0_output() {
    let result = swap_result(
        sqrt_ratio: u256 { high: 1, low: 0 },
        liquidity: 100000,
        sqrt_ratio_limit: max_sqrt_ratio(),
        amount: i129 { mag: 10000, sign: true },
        is_token1: false,
        fee: exp2(127), // equal to 0.5
    );

    assert(result.consumed_amount == i129 { mag: 10000, sign: true }, 'consumed_amount');
    assert(
        result.sqrt_ratio_next == u256 { high: 1, low: 60049829456636199434713166017370860846 },
        'sqrt_ratio_next'
    );
    assert(result.calculated_amount == 17647, 'calculated_amount');
    assert(result.fee_amount == 5000, 'fee');
}


#[test]
fn test_swap_against_liquidity_min_limit_token0_minimum_output() {
    let result = swap_result(
        sqrt_ratio: u256 { high: 1, low: 0 },
        liquidity: 100000,
        sqrt_ratio_limit: max_sqrt_ratio(),
        amount: i129 { mag: 1, sign: true },
        is_token1: false,
        fee: exp2(127), // equal to 0.5
    );

    assert(result.consumed_amount == i129 { mag: 1, sign: true }, 'consumed_amount');
    assert(
        result.sqrt_ratio_next == u256 { high: 1, low: 6805783454087851026288017908993545 },
        'sqrt_ratio_next'
    );
    assert(result.calculated_amount == 2, 'calculated_amount');
    assert(result.fee_amount == 1, 'fee');
}


#[test]
fn test_swap_against_liquidity_max_limit_token1_input() {
    let result = swap_result(
        sqrt_ratio: u256 { high: 1, low: 0 },
        liquidity: 100000,
        sqrt_ratio_limit: max_sqrt_ratio(),
        amount: i129 { mag: 10000, sign: false },
        is_token1: true,
        fee: exp2(127), // equal to 0.5
    );

    assert(result.consumed_amount == i129 { mag: 10000, sign: false }, 'consumed_amount');
    assert(
        result.sqrt_ratio_next == u256 { high: 1, low: 17014118346046923173168730371588410572 },
        'sqrt_ratio_next'
    );
    assert(result.calculated_amount == 4761, 'calculated_amount');
    assert(result.fee_amount == 5000, 'fee');
}

#[test]
fn test_swap_against_liquidity_max_limit_token1_minimum_input() {
    let result = swap_result(
        sqrt_ratio: u256 { high: 1, low: 0 },
        liquidity: 100000,
        sqrt_ratio_limit: max_sqrt_ratio(),
        amount: i129 { mag: 1, sign: false },
        is_token1: true,
        fee: exp2(127), // equal to 0.5
    );

    assert(result.consumed_amount == i129 { mag: 1, sign: false }, 'consumed_amount');
    assert(result.sqrt_ratio_next == u256 { high: 1, low: 0 }, 'sqrt_ratio_next');
    assert(result.calculated_amount == 0, 'calculated_amount');
    assert(result.fee_amount == 1, 'fee');
}


#[test]
fn test_swap_against_liquidity_min_limit_token1_output() {
    let result = swap_result(
        sqrt_ratio: u256 { high: 1, low: 0 },
        liquidity: 100000,
        sqrt_ratio_limit: min_sqrt_ratio(),
        amount: i129 { mag: 10000, sign: true },
        is_token1: true,
        fee: exp2(127), // equal to 0.5
    );

    assert(result.consumed_amount == i129 { mag: 10000, sign: true }, 'consumed_amount');
    assert(
        result.sqrt_ratio_next == u256 { high: 0, low: 289240011882797693943868416317002979737 },
        'sqrt_ratio_next'
    );
    assert(result.calculated_amount == 17647, 'calculated_amount');
    assert(result.fee_amount == 5000, 'fee');
}


#[test]
fn test_swap_against_liquidity_min_limit_token1_minimum_output() {
    let result = swap_result(
        sqrt_ratio: u256 { high: 1, low: 0 },
        liquidity: 100000,
        sqrt_ratio_limit: min_sqrt_ratio(),
        amount: i129 { mag: 1, sign: true },
        is_token1: true,
        fee: exp2(127), // equal to 0.5
    );

    assert(result.consumed_amount == i129 { mag: 1, sign: true }, 'consumed_amount');
    assert(
        result.sqrt_ratio_next == u256 { high: 0, low: 340275561273600044694105339939619576091 },
        'sqrt_ratio_next'
    );
    assert(result.calculated_amount == 2, 'calculated_amount');
    assert(result.fee_amount == 1, 'fee');
}


// limit hit tests

#[test]
fn test_swap_against_liquidity_hit_limit_token0_input() {
    let result = swap_result(
        sqrt_ratio: u256 { high: 1, low: 0 },
        liquidity: 100000,
        sqrt_ratio_limit: u256 { high: 0, low: 333476719582519694194107115283132847226 },
        amount: i129 { mag: 10000, sign: false },
        is_token1: false,
        fee: exp2(127), // equal to 0.5
    );

    assert(result.consumed_amount == i129 { mag: 2041, sign: false }, 'consumed_amount');
    assert(
        result.sqrt_ratio_next == u256 { high: 0, low: 333476719582519694194107115283132847226 },
        'sqrt_ratio_next'
    );
    assert(result.calculated_amount == 2000, 'calculated_amount');
    assert(result.fee_amount == 1021, 'fee');
}

#[test]
fn test_swap_against_liquidity_hit_limit_token1_input() {
    let result = swap_result(
        sqrt_ratio: u256 { high: 1, low: 0 },
        liquidity: 100000,
        sqrt_ratio_limit: u256 { high: 1, low: 6805647338418769269267492148635364229 },
        amount: i129 { mag: 10000, sign: false },
        is_token1: true,
        fee: exp2(127), // equal to 0.5
    );

    assert(result.consumed_amount == i129 { mag: 2000, sign: false }, 'consumed_amount');
    assert(
        result.sqrt_ratio_next == u256 { high: 1, low: 6805647338418769269267492148635364229 },
        'sqrt_ratio_next'
    );
    assert(result.calculated_amount == 1960, 'calculated_amount');
    assert(result.fee_amount == 1000, 'fee');
}


#[test]
fn test_swap_against_liquidity_hit_limit_token0_output() {
    let result = swap_result(
        sqrt_ratio: u256 { high: 1, low: 0 },
        liquidity: 100000,
        sqrt_ratio_limit: u256 { high: 1, low: 6805647338418769269267492148635364229 },
        amount: i129 { mag: 10000, sign: true },
        is_token1: false,
        fee: exp2(127), // equal to 0.5
    );

    assert(result.consumed_amount == i129 { mag: 1961, sign: true }, 'consumed_amount');
    assert(
        result.sqrt_ratio_next == u256 { high: 1, low: 6805647338418769269267492148635364229 },
        'sqrt_ratio_next'
    );
    assert(result.calculated_amount == 1999, 'calculated_amount');
    assert(result.fee_amount == 981, 'fee');
}

#[test]
fn test_swap_against_liquidity_hit_limit_token1_output() {
    let result = swap_result(
        sqrt_ratio: u256 { high: 1, low: 0 },
        liquidity: 100000,
        sqrt_ratio_limit: u256 { high: 0, low: 333476719582519694194107115283132847226 },
        amount: i129 { mag: 10000, sign: true },
        is_token1: true,
        fee: exp2(127), // equal to 0.5
    );

    assert(result.consumed_amount == i129 { mag: 2001, sign: true }, 'consumed_amount');
    assert(
        result.sqrt_ratio_next == u256 { high: 0, low: 333476719582519694194107115283132847226 },
        'sqrt_ratio_next'
    );
    assert(result.calculated_amount == 2040, 'calculated_amount');
    assert(result.fee_amount == 1001, 'fee');
}
