use core::debug::PrintTrait;
use core::integer::{
    u512, u256_wide_mul, u512_safe_div_rem_by_u256, u256_as_non_zero, u128_safe_divmod,
    u256_safe_divmod, u128_as_non_zero, u256_safe_div_rem, u128_wide_mul, u256_sqrt,
    u512_safe_divmod_by_u256, u256_overflow_mul
};
use core::num::traits::{Zero};
use core::traits::{Into, TryInto};
use ekubo::interfaces::core::{Delta};
use ekubo::math::bits::{msb};
use ekubo::math::exp2::{exp2 as exp2_int};


mod constants {
    const LOG_SCALE_FACTOR: u8 = 4;
    const BITMAP_SPACING: u64 = 16;

    // sale rate is scaled by 2**32
    const X32_u128: u128 = 0x100000000_u128;
    const X32_u256: u256 = 0x100000000_u256;

    // 2**64
    const X64: u128 = 0x10000000000000000_u128;

    // 2**128
    const X128: u256 = 0x100000000000000000000000000000000_u256;

    const LOG2_E_X32: u128 = 6196328018;

    // log_2(e) * 2**64
    const LOG2_E: u256 = 0x171547652B82FE1777D0FFDA0D23A7D12;

    // log_2(e) * 2**128
    const LOG2_E_X128: u256 = 490923683258796565746369346286093237521_u256;
}


fn calculate_sale_rate(amount: u128, end_time: u64, start_time: u64) -> u128 {
    let sale_rate: u128 = ((amount.into() * constants::X32_u256) / (end_time - start_time).into())
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
    ((reward_rate.into() * sale_rate.into()) / constants::X128)
        .try_into()
        .expect('REWARD_AMOUNT_OVERFLOW')
}

fn validate_time(start_time: u64, end_time: u64) {
    assert(end_time > start_time, 'INVALID_END_TIME');

    // calculate the closest timestamp at which an order can expire
    // based on the step of the interval that the order expires in using
    // an approximation of
    // = 16**(floor(log_16(end_time-start_time)))
    // = 2**(4 * (floor(log_2(end_time-start_time)) / 4))
    let step = exp2_int(
        constants::LOG_SCALE_FACTOR
            * (msb((end_time - start_time).into()) / constants::LOG_SCALE_FACTOR)
    );

    assert(step >= constants::BITMAP_SPACING.into(), 'INVALID_SPACING');
    assert(end_time.into() % step == 0, 'INVALID_TIME');
}

fn calculate_next_sqrt_ratio(
    sqrt_ratio: u256,
    liquidity: u128,
    token0_sale_rate: u128,
    token1_sale_rate: u128,
    virtual_order_time_window: u64
) -> u256 {
    // sqrt sell ratio
    let sell_ratio = (u256 { high: token1_sale_rate, low: 0 } / token0_sale_rate.into());
    let sqrt_sell_ratio: u256 = u256_sqrt(sell_ratio).into();

    'liquidity'.print();
    liquidity.print();

    // c
    let (c, sign) = calculate_c(sqrt_ratio, sqrt_sell_ratio * constants::X64.into());

    'c'.print();
    c.print();

    let sqrt_ratio_next = if (c.is_zero()) {
        sqrt_sell_ratio.try_into().expect('SQRT_RATIO_OVERFLOW')
    } else {
        // sqrt_sell_rate
        let sqrt_sell_rate = u256_sqrt(token0_sale_rate.into() * token1_sale_rate.into());

        'sqrt_sell_rate'.print();
        sqrt_sell_rate.print();

        let e = calculate_e(sqrt_sell_rate, virtual_order_time_window, liquidity);

        let term1 = e - c;
        let term2 = e + c;

        let scale: u256 = if (sign) {
            let (high, low) = u128_wide_mul(
                term2.try_into().expect('TERM2_OVERFLOW'), constants::X64
            );
            let (q, r) = u256_safe_div_rem(
                u256 { high: high, low: low }, u256_as_non_zero(term1.into())
            );
            // check remainder
            q
        } else {
            let (high, low) = u128_wide_mul(
                term1.try_into().expect('TERM1_OVERFLOW'), constants::X64
            );
            let (q, r) = u256_safe_div_rem(
                u256 { high: high, low: low }, u256_as_non_zero(term2.into())
            );
            // check remainder
            q
        };

        'scale'.print();
        scale.print();

        (sqrt_sell_ratio * scale)
    };

    sqrt_ratio_next
}

// c = (sqrt_sell_ratio - sqrt_ratio) / (sqrt_sell_ratio + sqrt_ratio)
fn calculate_c(sqrt_ratio: u256, sqrt_sell_ratio: u256) -> (u256, bool) {
    if (sqrt_ratio == sqrt_sell_ratio) {
        return (0, false);
    }

    let (num, sign) = if (sqrt_ratio > sqrt_sell_ratio) {
        (sqrt_ratio - sqrt_sell_ratio, true)
    } else {
        (sqrt_sell_ratio - sqrt_ratio, false)
    };

    // denominator cannot overflow
    let (div, _) = u512_safe_div_rem_by_u256(
        u256_wide_mul(num, constants::X128), u256_as_non_zero(sqrt_sell_ratio + sqrt_ratio)
    );

    // value of c is between 0 and 1 scaled by 2**128, only the upper 256 bits are used
    assert(div.limb2 == 0 && div.limb3 == 0, 'C_DIV_OVERFLOW');

    (u256 { low: div.limb0, high: div.limb1 }, sign)
}

//  e = exp(2 * t * sqrt_sell_rate / liquidity) as 32.64
fn calculate_e(sqrt_sell_rate: u128, t: u64, liquidity: u128) -> u256 {
    // sqrt_sell_rate is 96.32
    // scaled t is 64.32
    // combined is 160.64
    // liquidity is 128
    // exponent is 32.64

    let (high, low) = u128_wide_mul((2 * constants::X32_u128 * t.into()), sqrt_sell_rate);

    'high'.print();
    high.print();
    'low'.print();
    low.print();

    let (exponent, _) = u256_safe_div_rem(
        u256 { high: high, low: low }, u256_as_non_zero(liquidity.into())
    );

    // validate high is 0, integer piece should be < 128
    assert(exponent.high == 0, 'E_MUL_OVERFLOW');

    'exponent'.print();
    exponent.low.print();

    exp_fractional(exponent.low)
}

// calculates exp(x) as 2^(x * log_2(e))
fn exp_fractional(x: u128) -> u256 {
    if (x.is_zero()) {
        return constants::X128;
    }

    let (mul, _) = u512_safe_div_rem_by_u256(
        u256_wide_mul(x.into(), constants::LOG2_E), u256_as_non_zero(constants::X128)
    );

    'mul.limb0'.print();
    mul.limb0.print();
    'mul.limb1'.print();
    mul.limb1.print();
    'mul.limb2'.print();
    mul.limb2.print();
    'mul.limb3'.print();
    mul.limb3.print();

    let (int, frac) = u128_safe_divmod(
        (u256 { high: mul.limb1, low: mul.limb0 }).try_into().expect('EXP_OVERFLOW'),
        u128_as_non_zero(constants::X64.into())
    );

    let res_int = exp2_int(int.try_into().expect('EXP_INT_OVERFLOW'));

    let res_frac = exp2_fractional(frac);

    'int'.print();
    int.print();
    'frac'.print();
    frac.print();
    'res_int'.print();
    res_int.print();
    'res_frac'.print();
    res_frac.print();

    'result'.print();
    (res_int.into() * res_frac).print();

    res_int.into() * res_frac
}

// calculates 2^(.x)
fn exp2_fractional(x: u128) -> u256 {
    assert(x < 0x400000000000000000, 'EXP2_OVERFLOW');

    let mut res = 0x80000000000000000000000000000000;

    if ((x & 0x8000000000000000) > 0) {
        res = unsafe_mul_shift(res, 0x16A09E667F3BCC908B2FB1366EA957D3E);
    }
    if ((x & 0x4000000000000000) > 0) {
        res = unsafe_mul_shift(res, 0x1306FE0A31B7152DE8D5A46305C85EDEC);
    }
    if ((x & 0x2000000000000000) > 0) {
        res = unsafe_mul_shift(res, 0x1172B83C7D517ADCDF7C8C50EB14A791F);
    }
    if ((x & 0x1000000000000000) > 0) {
        res = unsafe_mul_shift(res, 0x10B5586CF9890F6298B92B71842A98363);
    }
    if ((x & 0x800000000000000) > 0) {
        res = unsafe_mul_shift(res, 0x1059B0D31585743AE7C548EB68CA417FD);
    }
    if ((x & 0x400000000000000) > 0) {
        res = unsafe_mul_shift(res, 0x102C9A3E778060EE6F7CACA4F7A29BDE8);
    }
    if ((x & 0x200000000000000) > 0) {
        res = unsafe_mul_shift(res, 0x10163DA9FB33356D84A66AE336DCDFA3F);
    }
    if ((x & 0x100000000000000) > 0) {
        res = unsafe_mul_shift(res, 0x100B1AFA5ABCBED6129AB13EC11DC9543);
    }
    if ((x & 0x80000000000000) > 0) {
        res = unsafe_mul_shift(res, 0x10058C86DA1C09EA1FF19D294CF2F679B);
    }
    if ((x & 0x40000000000000) > 0) {
        res = unsafe_mul_shift(res, 0x1002C605E2E8CEC506D21BFC89A23A00F);
    }
    if ((x & 0x20000000000000) > 0) {
        res = unsafe_mul_shift(res, 0x100162F3904051FA128BCA9C55C31E5DF);
    }
    if ((x & 0x10000000000000) > 0) {
        res = unsafe_mul_shift(res, 0x1000B175EFFDC76BA38E31671CA939725);
    }
    if ((x & 0x8000000000000) > 0) {
        res = unsafe_mul_shift(res, 0x100058BA01FB9F96D6CACD4B180917C3D);
    }
    if ((x & 0x4000000000000) > 0) {
        res = unsafe_mul_shift(res, 0x10002C5CC37DA9491D0985C348C68E7B3);
    }
    if ((x & 0x2000000000000) > 0) {
        res = unsafe_mul_shift(res, 0x1000162E525EE054754457D5995292026);
    }
    if ((x & 0x1000000000000) > 0) {
        res = unsafe_mul_shift(res, 0x10000B17255775C040618BF4A4ADE83FC);
    }
    if ((x & 0x800000000000) > 0) {
        res = unsafe_mul_shift(res, 0x1000058B91B5BC9AE2EED81E9B7D4CFAB);
    }
    if ((x & 0x400000000000) > 0) {
        res = unsafe_mul_shift(res, 0x100002C5C89D5EC6CA4D7C8ACC017B7C9);
    }
    if ((x & 0x200000000000) > 0) {
        res = unsafe_mul_shift(res, 0x10000162E43F4F831060E02D839A9D16D);
    }
    if ((x & 0x100000000000) > 0) {
        res = unsafe_mul_shift(res, 0x100000B1721BCFC99D9F890EA06911763);
    }
    if ((x & 0x80000000000) > 0) {
        res = unsafe_mul_shift(res, 0x10000058B90CF1E6D97F9CA14DBCC1628);
    }
    if ((x & 0x40000000000) > 0) {
        res = unsafe_mul_shift(res, 0x1000002C5C863B73F016468F6BAC5CA2B);
    }
    if ((x & 0x20000000000) > 0) {
        res = unsafe_mul_shift(res, 0x100000162E430E5A18F6119E3C02282A5);
    }
    if ((x & 0x10000000000) > 0) {
        res = unsafe_mul_shift(res, 0x1000000B1721835514B86E6D96EFD1BFE);
    }
    if ((x & 0x8000000000) > 0) {
        res = unsafe_mul_shift(res, 0x100000058B90C0B48C6BE5DF846C5B2EF);
    }
    if ((x & 0x4000000000) > 0) {
        res = unsafe_mul_shift(res, 0x10000002C5C8601CC6B9E94213C72737A);
    }
    if ((x & 0x2000000000) > 0) {
        res = unsafe_mul_shift(res, 0x1000000162E42FFF037DF38AA2B219F06);
    }
    if ((x & 0x1000000000) > 0) {
        res = unsafe_mul_shift(res, 0x10000000B17217FBA9C739AA5819F44F9);
    }
    if ((x & 0x800000000) > 0) {
        res = unsafe_mul_shift(res, 0x1000000058B90BFCDEE5ACD3C1CEDC823);
    }
    if ((x & 0x400000000) > 0) {
        res = unsafe_mul_shift(res, 0x100000002C5C85FE31F35A6A30DA1BE50);
    }
    if ((x & 0x200000000) > 0) {
        res = unsafe_mul_shift(res, 0x10000000162E42FF0999CE3541B9FFFCF);
    }
    if ((x & 0x100000000) > 0) {
        res = unsafe_mul_shift(res, 0x100000000B17217F80F4EF5AADDA45554);
    }
    if ((x & 0x80000000) > 0) {
        res = unsafe_mul_shift(res, 0x10000000058B90BFBF8479BD5A81B51AD);
    }
    if ((x & 0x40000000) > 0) {
        res = unsafe_mul_shift(res, 0x1000000002C5C85FDF84BD62AE30A74CC);
    }
    if ((x & 0x20000000) > 0) {
        res = unsafe_mul_shift(res, 0x100000000162E42FEFB2FED257559BDAA);
    }
    if ((x & 0x10000000) > 0) {
        res = unsafe_mul_shift(res, 0x1000000000B17217F7D5A7716BBA4A9AE);
    }
    if ((x & 0x8000000) > 0) {
        res = unsafe_mul_shift(res, 0x100000000058B90BFBE9DDBAC5E109CCE);
    }
    if ((x & 0x4000000) > 0) {
        res = unsafe_mul_shift(res, 0x10000000002C5C85FDF4B15DE6F17EB0D);
    }
    if ((x & 0x2000000) > 0) {
        res = unsafe_mul_shift(res, 0x1000000000162E42FEFA494F1478FDE05);
    }
    if ((x & 0x1000000) > 0) {
        res = unsafe_mul_shift(res, 0x10000000000B17217F7D20CF927C8E94C);
    }
    if ((x & 0x800000) > 0) {
        res = unsafe_mul_shift(res, 0x1000000000058B90BFBE8F71CB4E4B33D);
    }
    if ((x & 0x400000) > 0) {
        res = unsafe_mul_shift(res, 0x100000000002C5C85FDF477B662B26945);
    }
    if ((x & 0x200000) > 0) {
        res = unsafe_mul_shift(res, 0x10000000000162E42FEFA3AE53369388C);
    }
    if ((x & 0x100000) > 0) {
        res = unsafe_mul_shift(res, 0x100000000000B17217F7D1D351A389D40);
    }
    if ((x & 0x80000) > 0) {
        res = unsafe_mul_shift(res, 0x10000000000058B90BFBE8E8B2D3D4EDE);
    }
    if ((x & 0x40000) > 0) {
        res = unsafe_mul_shift(res, 0x1000000000002C5C85FDF4741BEA6E77E);
    }
    if ((x & 0x20000) > 0) {
        res = unsafe_mul_shift(res, 0x100000000000162E42FEFA39FE95583C2);
    }
    if ((x & 0x10000) > 0) {
        res = unsafe_mul_shift(res, 0x1000000000000B17217F7D1CFB72B45E1);
    }
    if ((x & 0x8000) > 0) {
        res = unsafe_mul_shift(res, 0x100000000000058B90BFBE8E7CC35C3F0);
    }
    if ((x & 0x4000) > 0) {
        res = unsafe_mul_shift(res, 0x10000000000002C5C85FDF473E242EA38);
    }
    if ((x & 0x2000) > 0) {
        res = unsafe_mul_shift(res, 0x1000000000000162E42FEFA39F02B772C);
    }
    if ((x & 0x1000) > 0) {
        res = unsafe_mul_shift(res, 0x10000000000000B17217F7D1CF7D83C1A);
    }
    if ((x & 0x800) > 0) {
        res = unsafe_mul_shift(res, 0x1000000000000058B90BFBE8E7BDCBE2E);
    }
    if ((x & 0x400) > 0) {
        res = unsafe_mul_shift(res, 0x100000000000002C5C85FDF473DEA871F);
    }
    if ((x & 0x200) > 0) {
        res = unsafe_mul_shift(res, 0x10000000000000162E42FEFA39EF44D91);
    }
    if ((x & 0x100) > 0) {
        res = unsafe_mul_shift(res, 0x100000000000000B17217F7D1CF79E949);
    }
    if ((x & 0x80) > 0) {
        res = unsafe_mul_shift(res, 0x10000000000000058B90BFBE8E7BCE544);
    }
    if ((x & 0x40) > 0) {
        res = unsafe_mul_shift(res, 0x1000000000000002C5C85FDF473DE6ECA);
    }
    if ((x & 0x20) > 0) {
        res = unsafe_mul_shift(res, 0x100000000000000162E42FEFA39EF366F);
    }
    if ((x & 0x10) > 0) {
        res = unsafe_mul_shift(res, 0x1000000000000000B17217F7D1CF79AFA);
    }
    if ((x & 0x8) > 0) {
        res = unsafe_mul_shift(res, 0x100000000000000058B90BFBE8E7BCD6D);
    }
    if ((x & 0x4) > 0) {
        res = unsafe_mul_shift(res, 0x10000000000000002C5C85FDF473DE6B2);
    }
    if ((x & 0x2) > 0) {
        res = unsafe_mul_shift(res, 0x1000000000000000162E42FEFA39EF358);
    }
    if ((x & 0x1) > 0) {
        res = unsafe_mul_shift(res, 0x10000000000000000B17217F7D1CF79AB);
    }

    'res'.print();
    (res * 0b10).print();

    res * 0b10
}

fn unsafe_mul_shift(x: u256, mul: u256) -> u256 {
    let (res, _) = u256_overflow_mul(x, mul);
    u256 { low: res.high, high: 0 }
}
