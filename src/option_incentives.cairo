use core::math::Oneable;
use starknet::{ContractAddress};
use ekubo::types::bounds::{Bounds};
use ekubo::types::keys::{PoolKey};

#[starknet::interface]
trait IOptionIncentives<TStorage> {
    // Stake a token from the positions NFT contract. The token must already be transferred to the contract but not staked
    fn stake(
        ref self: TStorage,
        token_id: u256,
        pool_key: PoolKey,
        bounds: Bounds,
        owner: ContractAddress
    );
    // Exercise options for a given staked position NFT. The quote token must already be transferred to the contract, and the
    // reward token will be transferred to the given recipient.
    // Because the price can move, user must specify a minimum output amount to avoid slippage.
    // When this is exercised successfully, it clears any unexercised options.
    fn exercise(
        ref self: TStorage,
        token_id: u256,
        pool_key: PoolKey,
        bounds: Bounds,
        min_output: u128,
        recipient: ContractAddress
    ) -> u128;
    // Unstake a token ID and send it to the specified recipient. This action forfeits any unexercised options.
    fn unstake(ref self: TStorage, token_id: u256, recipient: ContractAddress);
}

// This contract is used to incentivize users to stake their liquidity position NFT with call options
// The price of the call option is determined by the average price for the pool for the period
// The liquidity position must be on a pool that uses the oracle extension
#[starknet::contract]
mod OptionIncentives {
    use super::{ContractAddress, IOptionIncentives, PoolKey, Bounds};
    use ekubo::interfaces::positions::{IPositionsDispatcher, IPositionsDispatcherTrait};
    use ekubo::interfaces::erc721::{IERC721Dispatcher, IERC721DispatcherTrait};
    use ekubo::extensions::oracle::{IOracleDispatcher, IOracleDispatcherTrait};
    use ekubo::types::i129::{i129};
    use zeroable::{Zeroable};
    use starknet::{get_caller_address, get_contract_address};
    use ekubo::math::utils::{unsafe_sub};

    #[derive(Drop, Copy, storage_access::StorageAccess)]
    struct StakedTokenInfo {
        owner: ContractAddress,
        tick_cumulative_snapshot: i129,
        seconds_per_liquidity_inside_snapshot: u256,
    }

    #[storage]
    struct Storage {
        // constant addresses
        positions: IPositionsDispatcher,
        oracle: IOracleDispatcher,
        // the number of option tokens per liquidity-second awarded
        // no decimal because options are expressed in terms of 1 wei of token
        options_per_second: u64,
        // the token that is used for the strike of the option
        quote_token: ContractAddress,
        // the token that can be purchased
        reward_token: ContractAddress,
        // the owner of a staked token
        staked_token_info: LegacyMap<u256, StakedTokenInfo>,
        // the amount of quote token the last time the exercise function was called, this is how payments are tracked
        quote_token_reserves: u128,
    }

    #[derive(starknet::Event, Drop)]
    struct Staked {
        token_id: u256,
        owner: ContractAddress,
    }

    #[derive(starknet::Event, Drop)]
    struct Unstaked {
        token_id: u256,
        recipient: ContractAddress,
    }

    #[derive(starknet::Event, Drop)]
    struct Exercised {
        token_id: u256,
        sqrt_ratio: u256,
        recipient: ContractAddress,
    }

    #[derive(starknet::Event, Drop)]
    #[event]
    enum Event {
        Staked: Staked,
        Unstaked: Unstaked,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        positions: IPositionsDispatcher,
        oracle: IOracleDispatcher,
        options_per_second: u64,
    ) {
        self.positions.write(positions);
        self.oracle.write(oracle);
        self.options_per_second.write(options_per_second);
    }

    #[external(v0)]
    impl OptionIncentivesImpl of IOptionIncentives<ContractState> {
        fn stake(
            ref self: ContractState,
            token_id: u256,
            pool_key: PoolKey,
            bounds: Bounds,
            owner: ContractAddress
        ) {
            let oracle = self.oracle.read();
            assert(pool_key.extension == oracle.contract_address, 'NO_ORACLE_STAKE');
            let quote_token = self.quote_token.read();
            let reward_token = self.reward_token.read();
            assert(
                ((pool_key.token0 == quote_token) & (pool_key.token1 == reward_token))
                    | ((pool_key.token0 == reward_token) & (pool_key.token1 == quote_token)),
                'WRONG_TOKENS'
            );

            let positions = self.positions.read();
            let info = positions.get_position_info(token_id, pool_key, bounds);

            assert(info.liquidity.is_non_zero(), 'ZERO_LIQUIDITY_STAKE');

            let staked_info = self.staked_token_info.read(token_id);
            assert(staked_info.owner.is_zero(), 'ALREADY_STAKED');

            self
                .staked_token_info
                .write(
                    token_id,
                    StakedTokenInfo {
                        owner: owner,
                        tick_cumulative_snapshot: oracle.get_tick_cumulative(pool_key),
                        seconds_per_liquidity_inside_snapshot: oracle
                            .get_seconds_per_liquidity_inside(pool_key, bounds),
                    }
                );

            self.emit(Event::Staked(Staked { token_id: token_id, owner: owner }));
        }

        fn exercise(
            ref self: ContractState,
            token_id: u256,
            pool_key: PoolKey,
            bounds: Bounds,
            min_output: u128,
            recipient: ContractAddress
        ) -> u128 {
            let staked_info = self.staked_token_info.read(token_id);
            assert(staked_info.owner == get_caller_address(), 'NOT_OWNER');

            let oracle = self.oracle.read();
            // todo: sub with overflow/underflow needs to be implemented here.
            // it's tricky because we use an i129. this problem might go away with native i128
            let tick_cumulative_current = oracle.get_tick_cumulative(pool_key);
            let tick_difference = tick_cumulative_current - staked_info.tick_cumulative_snapshot;

            let seconds_per_liquidity_inside_current = oracle
                .get_seconds_per_liquidity_inside(pool_key, bounds);

            let seconds_per_liquidity_difference = unsafe_sub(
                seconds_per_liquidity_inside_current,
                staked_info.seconds_per_liquidity_inside_snapshot
            );

            // todo: compute the amount of exercisable options
            // todo: compute the average price
            // todo: compute the amount of reward tokens
            // todo: max the reward tokens by the amount of tokens held by this contract
            // todo: check it exceeds max output

            self
                .staked_token_info
                .write(
                    token_id,
                    StakedTokenInfo {
                        owner: staked_info.owner,
                        tick_cumulative_snapshot: tick_cumulative_current,
                        seconds_per_liquidity_inside_snapshot: seconds_per_liquidity_inside_current,
                    }
                );

            Zeroable::zero()
        }

        fn unstake(ref self: ContractState, token_id: u256, recipient: ContractAddress) {
            let staked_info = self.staked_token_info.read(token_id);
            assert(staked_info.owner == get_caller_address(), 'NOT_OWNER');

            self
                .staked_token_info
                .write(
                    token_id,
                    StakedTokenInfo {
                        owner: Zeroable::zero(),
                        tick_cumulative_snapshot: Zeroable::zero(),
                        seconds_per_liquidity_inside_snapshot: Zeroable::zero(),
                    }
                );

            IERC721Dispatcher {
                contract_address: self.positions.read().contract_address
            }.transfer_from(get_contract_address(), recipient, token_id);

            self.emit(Event::Unstaked(Unstaked { token_id: token_id, recipient: recipient }));
        }
    }
}
