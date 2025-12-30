use crate::math::max_liquidity::max_liquidity;
use crate::math::liquidity::liquidity_delta_to_amount_delta;
use crate::math::ticks::tick_to_sqrt_ratio;
use crate::types::i129::i129;
use crate::types::keys::PoolKey;
use crate::interfaces::positions::IPositionsDispatcher;
use crate::interfaces::positions::IPositionsDispatcherTrait;
use crate::interfaces::positions::IPositionsSafeDispatcherTrait;
use starknet::ContractAddress;
use starknet::contract_address::contract_address_const;
use crate::interfaces::core::{
    ICoreDispatcher, ICoreDispatcherTrait
};

pub fn EKUBO_POSITIONS() -> ContractAddress {
    contract_address_const::<0x02e0af29598b407c8716b17f6d2795eca1b471413fa03fb145a5e33722184067>()
}

#[test]
#[fork(
    url: "https://api.zan.top/public/starknet-mainnet/rpc/v0_8",
    block_tag: latest
)]
fn test_ekubo_liquidity_calc_diff() {
    let XSTRK: ContractAddress = contract_address_const::<0x028d709c875c0ceac3dce7065bec5328186dc89fe254527084d1689910954b0a>();
    let STRK: ContractAddress = contract_address_const::<0x4718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d>();
    let pool_key = PoolKey {
        token0: XSTRK,
        token1: STRK,
        fee: 34028236692093847977029636859101184,
        tick_spacing: 200,
        extension: contract_address_const::<0x00>()
    };
    let position_disp = ICoreDispatcher { contract_address: EKUBO_POSITIONS() };
    let current_sqrt_price = position_disp.get_pool_price(pool_key);
    let current_tick = current_sqrt_price.tick;
    let sqrt_lower = tick_to_sqrt_ratio(i129 { mag: current_tick.try_into().unwrap() - 1000, sign: current_tick.sign });
    let sqrt_upper = tick_to_sqrt_ratio(i129 { mag: current_tick.try_into().unwrap() + 1000, sign: current_tick.sign });
    let liquidity = i129 { mag: 1000_000_000_000_000_000_000, sign: false };
    let amounts_delta = liquidity_delta_to_amount_delta(
                current_sqrt_price.sqrt_ratio,
                liquidity,
                sqrt_lower,
                sqrt_upper
            );
    let amount0 = amounts_delta.amount0;
    let amount1 = amounts_delta.amount1;
    println!("amount0 {:?}", amount0);
    println!("amount1 {:?}", amount1);

    let liquidity_delta = max_liquidity(
        current_sqrt_price.sqrt_ratio,
        sqrt_lower,
        sqrt_upper,
        amount0.mag,
        amount1.mag
    );
    println!("received liquidity delta {:?}", liquidity_delta);
    println!("expected liquidity delta {:?}", liquidity.mag);
    assert(liquidity_delta == liquidity.mag, 'invalid liquidity delta');
}