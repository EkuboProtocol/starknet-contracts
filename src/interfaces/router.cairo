use starknet::ContractAddress;
use crate::types::delta::Delta;
use crate::types::i129::i129;
use crate::types::keys::PoolKey;

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
    // Does a single swap against a single node using tokens held by this contract, and receives the
    // output to this contract
    fn swap(ref self: TContractState, node: RouteNode, token_amount: TokenAmount) -> Delta;

    // Does a multihop swap, where the output/input of each hop is passed as input/output of the
    // next swap Note to do exact output swaps, the route must be given in reverse
    fn multihop_swap(
        ref self: TContractState, route: Array<RouteNode>, token_amount: TokenAmount,
    ) -> Array<Delta>;

    // Does multiple multihop swaps
    fn multi_multihop_swap(ref self: TContractState, swaps: Array<Swap>) -> Array<Array<Delta>>;

    // Quote the given token amount against the route in the swap
    fn quote_multi_multihop_swap(self: @TContractState, swaps: Array<Swap>) -> Array<Array<Delta>>;
    fn quote_multihop_swap(
        self: @TContractState, route: Array<RouteNode>, token_amount: TokenAmount,
    ) -> Array<Delta>;
    fn quote_swap(self: @TContractState, node: RouteNode, token_amount: TokenAmount) -> Delta;

    // Returns the delta for swapping a pool to the given price
    fn get_delta_to_sqrt_ratio(self: @TContractState, pool_key: PoolKey, sqrt_ratio: u256) -> Delta;

    // Returns the amount available for purchase for swapping +/- the given percent, expressed as a
    // 0.128 number Note this is a square root of the percent
    // e.g. if you want to get the 2% market depth, you'd pass FLOOR((sqrt(1.02) - 1) * 2**128) =
    // 3385977594616997568912048723923598803
    fn get_market_depth(self: @TContractState, pool_key: PoolKey, sqrt_percent: u128) -> Depth;

    // Same return value as above, but the percent is expressed simply as a 64.64 number, e.g. 1% is
    // FLOOR(0.01 * 2**64)
    fn get_market_depth_v2(self: @TContractState, pool_key: PoolKey, percent_64x64: u128) -> Depth;

    // Same as above, but starting from the given price
    fn get_market_depth_at_sqrt_ratio(
        self: @TContractState, pool_key: PoolKey, sqrt_ratio: u256, percent_64x64: u128,
    ) -> Depth;
}
