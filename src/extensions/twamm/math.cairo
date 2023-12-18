use ekubo::interfaces::core::{Delta};
use ekubo::math::bits::{msb};
use ekubo::math::exp2::{exp2};

mod constants {
    const LOG_SCALE_FACTOR: u8 = 4;
    const BITMAP_SPACING: u64 = 16;

    // sale rate is scaled by 2**32
    const SALE_RATE_SCALE_FACTOR_u128: u128 = 0x100000000_u128;
    const SALE_RATE_SCALE_FACTOR_u256: u256 = 0x100000000_u256;

    // reward rate is scaled by 2**128
    const REWARD_RATE_SCALE_FACTOR: u256 = 0x100000000000000000000000000000000_u256;
}

fn calculate_sale_rate(amount: u128, expiry_time: u64, current_time: u64) -> u128 {
    let sale_rate: u128 = ((amount.into() * constants::SALE_RATE_SCALE_FACTOR_u256)
        / (expiry_time - current_time).into())
        .try_into()
        .expect('SALE_RATE_OVERFLOW');

    assert(sale_rate > 0, 'SALE_RATE_ZERO');

    sale_rate
}

fn calculate_reward_rate_deltas(sale_rates: (u128, u128), delta: Delta) -> (felt252, felt252) {
    let (token0_sale_rate, token1_sale_rate) = sale_rates;

    let token0_reward_delta: felt252 = if (delta.amount0.mag > 0) {
        if (!delta.amount0.sign || token1_sale_rate == 0) {
            0
        } else {
            (u256 { high: delta.amount0.mag, low: 0 } / token1_sale_rate.into())
                .try_into()
                .expect('REWARD_DELTA_OVERFLOW')
        }
    } else {
        0
    };

    let token1_reward_delta: felt252 = if (delta.amount1.mag > 0) {
        if (!delta.amount1.sign || token0_sale_rate == 0) {
            0
        } else {
            (u256 { high: delta.amount1.mag, low: 0 } / token0_sale_rate.into())
                .try_into()
                .expect('REWARD_DELTA_OVERFLOW')
        }
    } else {
        0
    };

    (token0_reward_delta, token1_reward_delta)
}

fn calculate_reward_amount(reward_rate: felt252, sale_rate: u128) -> u128 {
    // this should never overflow since total_sale_rate <= sale_rate 
    ((reward_rate.into() * sale_rate.into()) / constants::REWARD_RATE_SCALE_FACTOR)
        .try_into()
        .expect('REWARD_AMOUNT_OVERFLOW')
}

fn validate_expiry_time(order_time: u64, expiry_time: u64) {
    assert(expiry_time > order_time, 'INVALID_EXPIRY_TIME');

    // calculate the closest timestamp at which an order can expire
    // based on the step of the interval that the order expires in using
    // an approximation of
    // = 16**(floor(log_16(expiry_time-order_time)))
    // = 2**(4 * (floor(log_2(expiry_time-order_time)) / 4))
    let step = exp2(
        constants::LOG_SCALE_FACTOR
            * (msb((expiry_time - order_time).into()) / constants::LOG_SCALE_FACTOR)
    );
    assert(step >= constants::BITMAP_SPACING.into(), 'INVALID_SPACING');
    assert(expiry_time.into() % step == 0, 'INVALID_EXPIRY_TIME');
}

fn calculate_virtual_order_outputs(
    sqrt_ratio: u256,
    liquidity: u128,
    buy_token_sale_rate: u128,
    sell_token_sale_rate: u128,
    virtual_order_time_window: u64
) -> (u128, u128, u128) {
    // sell ratio
    // let sell_ratio = (u256 { high: sell_token_sale_rate, low: 0 } / buy_token_sale_rate.into());

    // c
    // let (c, sign) = c(sqrt_ratio, sell_ratio);

    // sqrt_sell_rate
    // let sqrt_sell_rate = sqrt(buy_token_sell_rate * sell_token_sell_rate)

    // let mult = e^((2 * sqrt_sale_rate * virtual_order_time_window) / liquidity)
    // let sqrt_ratio_next = sqrt_sell_ratio * ( mult - c ) / (mult + c)
    // prob need to use sign in the above equation

    // let y_out = amount1_delta(sqrt_ratio, sqrt_ratio_next, liquidity);
    // let x_out = amount0_delta(sqrt_ratio, sqrt_ratio_next, liquidity);

    // (x_out, y_out, next_sqrt_ratio)
    (0, 0, 0)
}

fn c(sqrt_ratio: u256, sell_ratio: u256) -> (u256, bool) {
    let sqrt_sell_ratio: u256 = u256_sqrt(sell_ratio).into();

    let (num, sign) = if (sqrt_ratio > sqrt_sell_ratio) {
        (sqrt_ratio - sqrt_sell_ratio, true)
    } else {
        (sqrt_sell_ratio - sqrt_ratio, false)
    };

    (num / (sqrt_sell_ratio + sqrt_ratio), sign)
}
