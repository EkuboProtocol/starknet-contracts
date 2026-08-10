//! Stateless STRK20 helper for exact-input Ekubo swaps.
//!
//! The privacy contract withdraws the public input amount to this contract, calls
//! `privacy_invoke`, and consumes the returned `OpenNoteDeposit`. Routes may contain
//! multiple hops and the input may be split across multiple routes.

use ekubo::types::keys::PoolKey;
use privacy::objects::OpenNoteDeposit;
use starknet::ContractAddress;

pub mod errors {
    pub const ZERO_ROUTER: felt252 = 'ZERO_ROUTER';
    pub const ZERO_IN_TOKEN: felt252 = 'ZERO_IN_TOKEN';
    pub const ZERO_OUT_TOKEN: felt252 = 'ZERO_OUT_TOKEN';
    pub const SAME_TOKEN: felt252 = 'SAME_TOKEN';
    pub const ZERO_IN_AMOUNT: felt252 = 'ZERO_IN_AMOUNT';
    pub const EMPTY_SWAPS: felt252 = 'EMPTY_SWAPS';
    pub const ZERO_SPLIT_AMOUNT: felt252 = 'ZERO_SPLIT_AMOUNT';
    pub const EMPTY_ROUTE: felt252 = 'EMPTY_ROUTE';
    pub const ROUTE_TOKEN_MISMATCH: felt252 = 'ROUTE_TOKEN_MISMATCH';
    pub const ROUTE_OUTPUT_MISMATCH: felt252 = 'ROUTE_OUTPUT_MISMATCH';
    pub const SPLIT_AMOUNT_MISMATCH: felt252 = 'SPLIT_AMOUNT_MISMATCH';
    pub const TOKEN_TRANSFER_FAILED: felt252 = 'TOKEN_TRANSFER_FAILED';
    pub const IN_TOKEN_NOT_CLEARED: felt252 = 'IN_TOKEN_NOT_CLEARED';
    pub const RECEIVED_AMOUNT_OVERFLOW: felt252 = 'RECEIVED_AMOUNT_OVERFLOW';
    pub const ZERO_OUT_AMOUNT: felt252 = 'ZERO_OUT_AMOUNT';
    pub const TOKEN_APPROVE_FAILED: felt252 = 'TOKEN_APPROVE_FAILED';
}

#[derive(Drop, Serde)]
pub struct PrivateRouteNode {
    pub pool_key: PoolKey,
    pub skip_ahead: u128,
}

#[derive(Drop, Serde)]
pub struct PrivateSwap {
    pub input_amount: u128,
    pub route: Array<PrivateRouteNode>,
}

#[starknet::interface]
pub trait IEkuboSwapAnonymizer<T> {
    fn privacy_invoke(
        ref self: T,
        router_addr: ContractAddress,
        in_token: ContractAddress,
        out_token: ContractAddress,
        in_amount: u128,
        swaps: Array<PrivateSwap>,
        minimum_received: u256,
        note_id: felt252,
    ) -> Span<OpenNoteDeposit>;
}

#[starknet::contract]
pub mod EkuboSwapAnonymizer {
    use core::num::traits::Zero;
    use ekubo::components::clear::{IClearDispatcher, IClearDispatcherTrait};
    use ekubo::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use ekubo::interfaces::router::{
        IRouterDispatcher, IRouterDispatcherTrait, RouteNode, Swap, TokenAmount,
    };
    use ekubo::types::i129::i129;
    use privacy::objects::OpenNoteDeposit;
    use starknet::{ContractAddress, get_caller_address, get_contract_address};
    use super::{IEkuboSwapAnonymizer, PrivateRouteNode, PrivateSwap, errors};

    #[storage]
    struct Storage {}

    #[constructor]
    fn constructor(ref self: ContractState) {}

    #[abi(embed_v0)]
    impl EkuboSwapAnonymizerImpl of IEkuboSwapAnonymizer<ContractState> {
        fn privacy_invoke(
            ref self: ContractState,
            router_addr: ContractAddress,
            in_token: ContractAddress,
            out_token: ContractAddress,
            in_amount: u128,
            mut swaps: Array<PrivateSwap>,
            minimum_received: u256,
            note_id: felt252,
        ) -> Span<OpenNoteDeposit> {
            assert(router_addr.is_non_zero(), errors::ZERO_ROUTER);
            assert(in_token.is_non_zero(), errors::ZERO_IN_TOKEN);
            assert(out_token.is_non_zero(), errors::ZERO_OUT_TOKEN);
            assert(in_token != out_token, errors::SAME_TOKEN);
            assert(in_amount.is_non_zero(), errors::ZERO_IN_AMOUNT);
            assert(!swaps.is_empty(), errors::EMPTY_SWAPS);

            let mut total_input: u128 = 0;
            let mut router_swaps: Array<Swap> = array![];

            while let Option::Some(PrivateSwap { input_amount, mut route }) = swaps.pop_front() {
                assert(input_amount.is_non_zero(), errors::ZERO_SPLIT_AMOUNT);
                assert(!route.is_empty(), errors::EMPTY_ROUTE);
                total_input += input_amount;

                let mut current_token = in_token;
                let mut router_route: Array<RouteNode> = array![];

                while let Option::Some(PrivateRouteNode {
                    pool_key, skip_ahead,
                }) = route.pop_front() {
                    current_token =
                        if current_token == pool_key.token0 {
                            pool_key.token1
                        } else {
                            assert(current_token == pool_key.token1, errors::ROUTE_TOKEN_MISMATCH);
                            pool_key.token0
                        };
                    router_route.append(RouteNode { pool_key, sqrt_ratio_limit: 0, skip_ahead });
                }

                assert(current_token == out_token, errors::ROUTE_OUTPUT_MISMATCH);
                router_swaps
                    .append(
                        Swap {
                            route: router_route,
                            token_amount: TokenAmount {
                                token: in_token, amount: i129 { mag: input_amount, sign: false },
                            },
                        },
                    );
            }

            assert(total_input == in_amount, errors::SPLIT_AMOUNT_MISMATCH);

            let self_addr = get_contract_address();
            let privacy_addr = get_caller_address();
            let in_erc20 = IERC20Dispatcher { contract_address: in_token };
            let out_erc20 = IERC20Dispatcher { contract_address: out_token };

            assert(
                in_erc20.transfer(recipient: router_addr, amount: in_amount.into()),
                errors::TOKEN_TRANSFER_FAILED,
            );

            IRouterDispatcher { contract_address: router_addr }
                .multi_multihop_swap(swaps: router_swaps);

            let clear = IClearDispatcher { contract_address: router_addr };
            let in_token_remaining = clear.clear(token: in_erc20);
            assert(in_token_remaining.is_zero(), errors::IN_TOKEN_NOT_CLEARED);

            let balance_before = out_erc20.balanceOf(account: self_addr);
            clear.clear_minimum(token: out_erc20, minimum: minimum_received);
            let balance_after = out_erc20.balanceOf(account: self_addr);

            let out_amount: u128 = (balance_after - balance_before)
                .try_into()
                .expect(errors::RECEIVED_AMOUNT_OVERFLOW);
            assert(out_amount.is_non_zero(), errors::ZERO_OUT_AMOUNT);
            assert(
                out_erc20.approve(spender: privacy_addr, amount: out_amount.into()),
                errors::TOKEN_APPROVE_FAILED,
            );

            [OpenNoteDeposit { note_id, token: out_token, amount: out_amount }].span()
        }
    }
}
