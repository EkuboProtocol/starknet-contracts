use core::math::Oneable;
use starknet::{ContractAddress};
use ekubo::types::bounds::{Bounds};
use ekubo::types::keys::{PoolKey};

#[starknet::interface]
trait IOptionIncentives<TStorage> {
    fn stake(
        ref self: TStorage,
        token_id: u256,
        pool_key: PoolKey,
        bounds: Bounds,
        owner: ContractAddress
    );
    fn unstake(ref self: TStorage, token_id: u256, recipient: ContractAddress);
}

// This contract is used to incentivize users to stake their liquidity position NFT with call options
// The price of the call option is determined by the average price for the pool for the period
// The liquidity position must be on a pool that uses the oracle extension
#[starknet::contract]
mod OptionIncentives {
    use super::{ContractAddress, IOptionIncentives, PoolKey, Bounds};
    use ekubo::interfaces::positions::{IPositionsDispatcher, IPositionsDispatcherTrait};
    use ekubo::extensions::oracle::{IOracleDispatcher, IOracleDispatcherTrait};
    use ekubo::types::i129::{i129};
    use zeroable::{Zeroable};

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
        // the owner of a staked token
        staked_token_info: LegacyMap<u256, StakedTokenInfo>,
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
    #[event]
    enum Event {
        Staked: Staked,
        Unstaked: Unstaked,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState, positions: IPositionsDispatcher, oracle: IOracleDispatcher
    ) {
        self.positions.write(positions);
        self.oracle.write(oracle);
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
        }

        fn unstake(ref self: ContractState, token_id: u256, recipient: ContractAddress) {}
    }
}
