use core::array::SpanTrait;
use starknet::ContractAddress;
use ekubo::types::storage::{Tick, Position, Pool, TickTreeNode};
use ekubo::types::keys::{PositionKey, PoolKey};
use ekubo::types::i129::{i129};


#[derive(Copy, Drop, Serde)]
struct UpdatePositionParameters {
    tick_lower: i129,
    tick_upper: i129,
    liquidity_delta: i129,
}

#[derive(Copy, Drop, Serde)]
struct SwapParameters {
    amount: i129,
    is_token1: bool,
    sqrt_ratio_limit: u256,
}

// from the perspective of the core contract, the change in balances
#[derive(Copy, Drop, Serde)]
struct Delta {
    amount0_delta: i129,
    amount1_delta: i129,
}

impl DefaultDelta of Default<Delta> {
    fn default() -> Delta {
        Delta { amount0_delta: Default::default(), amount1_delta: Default::default(),  }
    }
}

#[abi]
trait IEkubo {
    #[view]
    fn get_owner() -> ContractAddress;

    #[view]
    fn get_pool(pool_key: PoolKey) -> Pool;

    #[view]
    fn get_tick(pool_key: PoolKey, index: i129) -> Tick;

    #[view]
    fn get_position(pool_key: PoolKey, position_key: PositionKey) -> Position;

    #[view]
    fn get_reserves(token: ContractAddress) -> u256;

    #[view]
    fn get_saved_balance(owner: ContractAddress, token: ContractAddress) -> u128;

    #[external]
    fn set_owner(new_owner: ContractAddress);

    #[external]
    fn withdraw_fees_collected(recipient: ContractAddress, token: ContractAddress, amount: u128);

    #[external]
    fn lock(data: Array<felt252>) -> Array<felt252>;

    #[external]
    fn withdraw(token_address: ContractAddress, recipient: ContractAddress, amount: u128);

    #[external]
    fn save(token_address: ContractAddress, recipient: ContractAddress, amount: u128);

    #[external]
    fn deposit(token_address: ContractAddress) -> u128;

    #[external]
    fn load(token_address: ContractAddress, amount: u128);

    #[external]
    fn initialize_pool(pool_key: PoolKey, initial_tick: i129);

    #[external]
    fn update_position(pool_key: PoolKey, params: UpdatePositionParameters) -> Delta;

    #[external]
    fn swap(pool_key: PoolKey, params: SwapParameters) -> Delta;
}
