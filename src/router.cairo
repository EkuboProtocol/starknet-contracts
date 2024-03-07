use ekubo::types::delta::{Delta};
use ekubo::types::i129::{i129};
use ekubo::types::keys::{PoolKey};
use starknet::{ContractAddress};

#[derive(Serde, Copy, Drop)]
pub struct RouteNode {
    pub pool_key: PoolKey,
    pub sqrt_ratio_limit: u256,
    pub skip_ahead: u128,
}

#[derive(Serde, Copy, Drop)]
pub struct TokenAmount {
    pub token: ContractAddress,
    pub amount: i129,
}

#[derive(Serde, Drop)]
pub struct Swap {
    pub route: Array<RouteNode>,
    pub token_amount: TokenAmount,
}

#[derive(Serde, Copy, Drop, PartialEq, Debug)]
pub struct Depth {
    pub token0: u128,
    pub token1: u128,
}

#[starknet::interface]
pub trait IRouter<TContractState> {
    // Does a single swap against a single node using tokens held by this contract, and receives the output to this contract
    fn swap(ref self: TContractState, node: RouteNode, token_amount: TokenAmount) -> Delta;

    // Does a multihop swap, where the output/input of each hop is passed as input/output of the next swap
    // Note to do exact output swaps, the route must be given in reverse
    fn multihop_swap(
        ref self: TContractState, route: Array<RouteNode>, token_amount: TokenAmount
    ) -> Array<Delta>;

    // Does multiple multihop swaps
    fn multi_multihop_swap(ref self: TContractState, swaps: Array<Swap>) -> Array<Array<Delta>>;

    // Quote the given token amount against the route in the swap
    fn quote(ref self: TContractState, swaps: Array<Swap>) -> Array<Array<Delta>>;

    // Returns the delta for swapping a pool to the given price
    fn get_delta_to_sqrt_ratio(self: @TContractState, pool_key: PoolKey, sqrt_ratio: u256) -> Delta;

    // Returns the amount available for purchase for swapping +/- the given percent, expressed as a 0.128 number
    // Note this is a square root of the percent
    // e.g. if you want to get the 2% market depth, you'd pass FLOOR((sqrt(1.02) - 1) * 2**128) = 3385977594616997568912048723923598803
    fn get_market_depth(self: @TContractState, pool_key: PoolKey, sqrt_percent: u128) -> Depth;

    // Same return value as above, but the percent is expressed simply as a 64.64 number, e.g. 1% is FLOOR(0.01 * 2**64)
    fn get_market_depth_v2(self: @TContractState, pool_key: PoolKey, percent_64x64: u128) -> Depth;

    // Same as above, but starting from the given price
    fn get_market_depth_at_sqrt_ratio(
        self: @TContractState, pool_key: PoolKey, sqrt_ratio: u256, percent_64x64: u128
    ) -> Depth;
}

#[starknet::contract]
pub mod Router {
    use core::array::{Array, ArrayTrait, SpanTrait};
    use core::cmp::{min, max};
    use core::integer::{u256_sqrt};
    use core::num::traits::{Zero};
    use core::option::{OptionTrait};
    use core::result::{ResultTrait};
    use core::traits::{Into};
    use ekubo::components::clear::{ClearImpl};
    use ekubo::components::shared_locker::{
        consume_callback_data, handle_delta, call_core_with_callback
    };
    use ekubo::interfaces::core::{ICoreDispatcher, ICoreDispatcherTrait, ILocker, SwapParameters};
    use ekubo::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use ekubo::math::muldiv::{muldiv};
    use ekubo::math::swap::{is_price_increasing};
    use ekubo::math::ticks::{max_sqrt_ratio, min_sqrt_ratio, sqrt_ratio_to_tick};
    use ekubo::types::i129::{i129, i129Trait};
    use starknet::syscalls::{call_contract_syscall};

    use starknet::{get_caller_address, get_contract_address};

    use super::{ContractAddress, PoolKey, Delta, IRouter, RouteNode, TokenAmount, Swap, Depth};

    #[abi(embed_v0)]
    impl Clear = ekubo::components::clear::ClearImpl<ContractState>;

    #[abi(embed_v0)]
    impl Expires = ekubo::components::expires::ExpiresImpl<ContractState>;

    #[storage]
    struct Storage {
        core: ICoreDispatcher,
    }

    #[constructor]
    fn constructor(ref self: ContractState, core: ICoreDispatcher) {
        self.core.write(core);
    }

    #[derive(Drop, Serde)]
    enum CallbackParameters {
        Swap: (Array<Swap>, bool),
        GetDeltaToSqrtRatio: (PoolKey, u256),
        GetMarketDepth: (PoolKey, u256, u128),
    }

    pub const FUNCTION_DID_NOT_ERROR_FLAG: felt252 = selector!("function_did_not_error");

    #[abi(embed_v0)]
    impl LockerImpl of ILocker<ContractState> {
        fn locked(ref self: ContractState, id: u32, data: Span<felt252>) -> Span<felt252> {
            let core = self.core.read();

            match consume_callback_data::<CallbackParameters>(core, data) {
                CallbackParameters::Swap((
                    mut swaps, simulate
                )) => {
                    let mut outputs: Array<Array<Delta>> = ArrayTrait::new();

                    while let Option::Some(swap) = swaps
                        .pop_front() {
                            let mut route = swap.route;
                            let mut token_amount = swap.token_amount;

                            let mut deltas: Array<Delta> = ArrayTrait::new();
                            // we track this to know how much to pay in the case of exact input and how much to pull in the case of exact output
                            let mut first_swap_amount: Option<TokenAmount> = Option::None;

                            while let Option::Some(node) = route
                                .pop_front() {
                                    let is_token1 = token_amount.token == node.pool_key.token1;

                                    let mut sqrt_ratio_limit = node.sqrt_ratio_limit;
                                    if (sqrt_ratio_limit.is_zero()) {
                                        sqrt_ratio_limit =
                                            if is_price_increasing(
                                                token_amount.amount.sign, is_token1
                                            ) {
                                                max_sqrt_ratio()
                                            } else {
                                                min_sqrt_ratio()
                                            };
                                    }

                                    let delta = core
                                        .swap(
                                            node.pool_key,
                                            SwapParameters {
                                                amount: token_amount.amount,
                                                is_token1: is_token1,
                                                sqrt_ratio_limit,
                                                skip_ahead: node.skip_ahead,
                                            }
                                        );

                                    deltas.append(delta);

                                    if first_swap_amount.is_none() {
                                        first_swap_amount =
                                            if is_token1 {
                                                Option::Some(
                                                    TokenAmount {
                                                        token: node.pool_key.token1,
                                                        amount: delta.amount1
                                                    }
                                                )
                                            } else {
                                                Option::Some(
                                                    TokenAmount {
                                                        token: node.pool_key.token0,
                                                        amount: delta.amount0
                                                    }
                                                )
                                            }
                                    }

                                    token_amount =
                                        if (is_token1) {
                                            TokenAmount {
                                                amount: -delta.amount0, token: node.pool_key.token0
                                            }
                                        } else {
                                            TokenAmount {
                                                amount: -delta.amount1, token: node.pool_key.token1
                                            }
                                        };
                                };

                            let recipient = get_contract_address();

                            outputs.append(deltas);

                            // execute deltas now if it's not a simulation
                            if (!simulate) {
                                let first = first_swap_amount.unwrap();
                                handle_delta(
                                    core, token_amount.token, -token_amount.amount, recipient
                                );
                                handle_delta(core, first.token, first.amount, recipient);
                            }
                        };

                    let mut serialized: Array<felt252> = array![];

                    if (simulate) {
                        Serde::serialize(@FUNCTION_DID_NOT_ERROR_FLAG, ref serialized);
                        Serde::serialize(@outputs, ref serialized);
                        panic(serialized);
                    } else {
                        Serde::serialize(@outputs, ref serialized);
                    }

                    serialized.span()
                },
                CallbackParameters::GetDeltaToSqrtRatio((
                    pool_key, sqrt_ratio
                )) => {
                    let current_pool_price = core.get_pool_price(pool_key);
                    let skip_ahead: u128 = ((current_pool_price.tick
                        - sqrt_ratio_to_tick(sqrt_ratio))
                        .mag
                        / (pool_key.tick_spacing * 127_u128))
                        .try_into()
                        .expect('TICK_DIFF_TOO_LARGE');

                    let delta = core
                        .swap(
                            pool_key,
                            SwapParameters {
                                amount: i129 {
                                    mag: 0xffffffffffffffffffffffffffffffff, sign: true
                                },
                                is_token1: sqrt_ratio <= current_pool_price.sqrt_ratio,
                                sqrt_ratio_limit: sqrt_ratio,
                                skip_ahead,
                            }
                        );

                    let mut output: Array<felt252> = ArrayTrait::new();

                    Serde::serialize(@FUNCTION_DID_NOT_ERROR_FLAG, ref output);
                    Serde::serialize(@delta, ref output);
                    panic(output);

                    // this isn't actually used, but we have to return it because panic is not recognized as end of execution
                    ArrayTrait::new().span()
                },
                CallbackParameters::GetMarketDepth((
                    pool_key, sqrt_ratio, percent_64x64
                )) => {
                    // takes the 64x64 percent, shifts it left 64 and sqrts it to get a 32.64. we add 1 so the sqrt always makes it smaller
                    let sqrt_percent: u256 = u256_sqrt(
                        0x100000000000000000000000000000000
                            + (percent_64x64.into() * 0x10000000000000000)
                    )
                        .into()
                        - 0x10000000000000000;
                    // this is 2**64, or the value 1 as a 1.64 number
                    let denom = 0x10000000000000000_u256;
                    let num = denom + sqrt_percent;

                    let mut current_pool_price = core.get_pool_price(pool_key);

                    // swap to the specified starting price
                    if current_pool_price.sqrt_ratio != sqrt_ratio {
                        let tick_start = sqrt_ratio_to_tick(sqrt_ratio);
                        core
                            .swap(
                                pool_key,
                                SwapParameters {
                                    amount: i129 {
                                        mag: 0xffffffffffffffffffffffffffffffff, sign: true
                                    },
                                    is_token1: sqrt_ratio < current_pool_price.sqrt_ratio,
                                    sqrt_ratio_limit: sqrt_ratio,
                                    skip_ahead: ((current_pool_price.tick - tick_start).mag
                                        / (pool_key.tick_spacing * 127_u128))
                                        .try_into()
                                        .expect('TICK_DIFF_TOO_LARGE'),
                                }
                            );

                        current_pool_price.sqrt_ratio = sqrt_ratio;
                        current_pool_price.tick = tick_start;
                    }

                    let price_high = min(
                        muldiv(current_pool_price.sqrt_ratio, num, denom, false)
                            .unwrap_or(max_sqrt_ratio()),
                        max_sqrt_ratio()
                    );
                    let price_low = max(
                        muldiv(current_pool_price.sqrt_ratio, denom, num, true)
                            .unwrap_or(min_sqrt_ratio()),
                        min_sqrt_ratio()
                    );

                    let skip_ahead: u128 = ((current_pool_price.tick
                        - sqrt_ratio_to_tick(price_low))
                        .mag
                        / (pool_key.tick_spacing * 127_u128))
                        .try_into()
                        .expect('TICK_DIFF_TOO_LARGE');

                    let delta_high = if current_pool_price.sqrt_ratio == price_high {
                        Zero::zero()
                    } else {
                        core
                            .swap(
                                pool_key,
                                SwapParameters {
                                    amount: i129 {
                                        mag: 0xffffffffffffffffffffffffffffffff, sign: true
                                    },
                                    is_token1: false,
                                    sqrt_ratio_limit: price_high,
                                    skip_ahead,
                                }
                            )
                    };

                    // swap back to starting price
                    if current_pool_price.sqrt_ratio != price_high {
                        core
                            .swap(
                                pool_key,
                                SwapParameters {
                                    amount: i129 {
                                        mag: 0xffffffffffffffffffffffffffffffff, sign: true
                                    },
                                    is_token1: true,
                                    sqrt_ratio_limit: current_pool_price.sqrt_ratio,
                                    skip_ahead,
                                }
                            );
                    }

                    let delta_low = if current_pool_price.sqrt_ratio == price_low {
                        Zero::zero()
                    } else {
                        core
                            .swap(
                                pool_key,
                                SwapParameters {
                                    amount: i129 {
                                        mag: 0xffffffffffffffffffffffffffffffff, sign: true
                                    },
                                    is_token1: true,
                                    sqrt_ratio_limit: price_low,
                                    skip_ahead,
                                }
                            )
                    };

                    let mut output: Array<felt252> = ArrayTrait::new();

                    Serde::serialize(@FUNCTION_DID_NOT_ERROR_FLAG, ref output);

                    let depth = Depth {
                        token0: delta_high.amount0.mag, token1: delta_low.amount1.mag,
                    };

                    Serde::serialize(@depth, ref output);
                    panic(output);

                    // this isn't actually used, but we have to return it because panic is not recognized as end of execution
                    ArrayTrait::new().span()
                },
            }
        }
    }

    fn call_core_with_reverting_callback<TInput, TOutput, +Serde<TInput>, +Serde<TOutput>>(
        core: ICoreDispatcher, input: @TInput
    ) -> TOutput {
        let mut input_data: Array<felt252> = ArrayTrait::new();
        Serde::serialize(input, ref input_data);

        // todo: we can do a little better by just appending the length of the array to input before serializing params to input instead of another round of serialization
        let mut lock_call_arguments: Array<felt252> = ArrayTrait::new();
        Serde::<Array<felt252>>::serialize(@input_data, ref lock_call_arguments);

        let output = call_contract_syscall(
            core.contract_address, selector!("lock"), lock_call_arguments.span()
        )
            .unwrap_err();

        let mut output_span = output.span();
        let first_value = output_span.pop_front().expect('No return data');

        if (*first_value != FUNCTION_DID_NOT_ERROR_FLAG) {
            // whole output is an internal panic
            panic(output);
        }

        let mut result: TOutput = Serde::deserialize(ref output_span)
            .expect('DESERIALIZE_RESULT_FAILED');
        result
    }

    #[abi(embed_v0)]
    impl RouterImpl of IRouter<ContractState> {
        fn swap(ref self: ContractState, node: RouteNode, token_amount: TokenAmount) -> Delta {
            let mut deltas: Array<Delta> = self.multihop_swap(array![node], token_amount);
            deltas.pop_front().unwrap()
        }

        fn multihop_swap(
            ref self: ContractState, route: Array<RouteNode>, token_amount: TokenAmount
        ) -> Array<Delta> {
            let mut result = self.multi_multihop_swap(array![Swap { route, token_amount }]);

            result.pop_front().unwrap()
        }

        fn multi_multihop_swap(ref self: ContractState, swaps: Array<Swap>) -> Array<Array<Delta>> {
            call_core_with_callback(self.core.read(), @CallbackParameters::Swap((swaps, false)))
        }

        // Quote the given token amount against the route in the swap
        fn quote(ref self: ContractState, swaps: Array<Swap>) -> Array<Array<Delta>> {
            call_core_with_reverting_callback(
                self.core.read(), @CallbackParameters::Swap((swaps, true))
            )
        }

        // Returns the delta for swapping a pool to the given price
        fn get_delta_to_sqrt_ratio(
            self: @ContractState, pool_key: PoolKey, sqrt_ratio: u256
        ) -> Delta {
            call_core_with_reverting_callback(
                self.core.read(), @CallbackParameters::GetDeltaToSqrtRatio((pool_key, sqrt_ratio))
            )
        }

        fn get_market_depth(self: @ContractState, pool_key: PoolKey, sqrt_percent: u128) -> Depth {
            // we add 1 so that squaring it doesn't make it smaller
            let p_plus_one = u256 { high: 1, low: sqrt_percent };
            let percent_64x64_plus_one = muldiv(
                p_plus_one, p_plus_one, 0x1000000000000000000000000000000000000000000000000, false
            )
                .unwrap();

            self
                .get_market_depth_v2(
                    pool_key, (percent_64x64_plus_one - 0x10000000000000000).try_into().unwrap()
                )
        }

        fn get_market_depth_v2(
            self: @ContractState, pool_key: PoolKey, percent_64x64: u128
        ) -> Depth {
            self
                .get_market_depth_at_sqrt_ratio(
                    pool_key, self.core.read().get_pool_price(pool_key).sqrt_ratio, percent_64x64
                )
        }

        fn get_market_depth_at_sqrt_ratio(
            self: @ContractState, pool_key: PoolKey, sqrt_ratio: u256, percent_64x64: u128
        ) -> Depth {
            call_core_with_reverting_callback(
                self.core.read(),
                @CallbackParameters::GetMarketDepth((pool_key, sqrt_ratio, percent_64x64))
            )
        }
    }
}
