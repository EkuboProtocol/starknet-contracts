#[starknet::contract]
mod MathLib {
    use ekubo::interfaces::mathlib::{IMathLib};
    use ekubo::types::delta::{Delta};
    use ekubo::types::i129::{i129};

    #[storage]
    struct Storage {}

    #[abi(embed_v0)]
    impl MathLibImpl of IMathLib<ContractState> {
        fn amount0_delta(
            self: @ContractState,
            sqrt_ratio_a: u256,
            sqrt_ratio_b: u256,
            liquidity: u128,
            round_up: bool
        ) -> u128 {
            ekubo::math::delta::amount0_delta(sqrt_ratio_a, sqrt_ratio_b, liquidity, round_up)
        }
        fn amount1_delta(
            self: @ContractState,
            sqrt_ratio_a: u256,
            sqrt_ratio_b: u256,
            liquidity: u128,
            round_up: bool
        ) -> u128 {
            ekubo::math::delta::amount1_delta(sqrt_ratio_a, sqrt_ratio_b, liquidity, round_up)
        }

        fn liquidity_delta_to_amount_delta(
            self: @ContractState,
            sqrt_ratio: u256,
            liquidity_delta: i129,
            sqrt_ratio_lower: u256,
            sqrt_ratio_upper: u256
        ) -> Delta {
            ekubo::math::liquidity::liquidity_delta_to_amount_delta(
                sqrt_ratio, liquidity_delta, sqrt_ratio_lower, sqrt_ratio_upper
            )
        }
        fn max_liquidity_for_token0(
            self: @ContractState, sqrt_ratio_lower: u256, sqrt_ratio_upper: u256, amount: u128
        ) -> u128 {
            ekubo::math::max_liquidity::max_liquidity_for_token0(
                sqrt_ratio_lower, sqrt_ratio_upper, amount
            )
        }
        fn max_liquidity_for_token1(
            self: @ContractState, sqrt_ratio_lower: u256, sqrt_ratio_upper: u256, amount: u128
        ) -> u128 {
            ekubo::math::max_liquidity::max_liquidity_for_token1(
                sqrt_ratio_lower, sqrt_ratio_upper, amount
            )
        }
        fn max_liquidity(
            self: @ContractState,
            sqrt_ratio: u256,
            sqrt_ratio_lower: u256,
            sqrt_ratio_upper: u256,
            amount0: u128,
            amount1: u128
        ) -> u128 {
            ekubo::math::max_liquidity::max_liquidity(
                sqrt_ratio, sqrt_ratio_lower, sqrt_ratio_upper, amount0, amount1
            )
        }

        fn next_sqrt_ratio_from_amount0(
            self: @ContractState, sqrt_ratio: u256, liquidity: u128, amount: i129
        ) -> Option<u256> {
            ekubo::math::sqrt_ratio::next_sqrt_ratio_from_amount0(sqrt_ratio, liquidity, amount)
        }
        fn next_sqrt_ratio_from_amount1(
            self: @ContractState, sqrt_ratio: u256, liquidity: u128, amount: i129
        ) -> Option<u256> {
            ekubo::math::sqrt_ratio::next_sqrt_ratio_from_amount1(sqrt_ratio, liquidity, amount)
        }

        fn tick_to_sqrt_ratio(self: @ContractState, tick: i129) -> u256 {
            ekubo::math::ticks::tick_to_sqrt_ratio(tick)
        }

        fn sqrt_ratio_to_tick(self: @ContractState, sqrt_ratio: u256) -> i129 {
            ekubo::math::ticks::sqrt_ratio_to_tick(sqrt_ratio)
        }
    }
}
