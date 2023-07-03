use core::math::Oneable;
use starknet::{ContractAddress};
use ekubo::types::bounds::{Bounds};
use ekubo::types::keys::{PoolKey};
use ekubo::types::i129::{i129};

#[derive(Copy, Drop, Serde)]
struct ExercisableAmount {
    strike_price: u256,
    amount: u128,
    tick_cumulative_current: i129,
    seconds_per_liquidity_inside_current: u256,
}

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

    // Get the number of exercisable call options for a given position
    fn get_exercisable_amount(
        self: @TStorage, token_id: u256, pool_key: PoolKey, bounds: Bounds, 
    ) -> ExercisableAmount;

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
    use super::{ContractAddress, IOptionIncentives, PoolKey, Bounds, ExercisableAmount, i129};
    use ekubo::interfaces::positions::{IPositionsDispatcher, IPositionsDispatcherTrait};
    use ekubo::interfaces::erc721::{IERC721Dispatcher, IERC721DispatcherTrait};
    use ekubo::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use ekubo::extensions::oracle::{IOracleDispatcher, IOracleDispatcherTrait};
    use zeroable::{Zeroable};
    use starknet::{get_caller_address, get_contract_address, get_block_timestamp};
    use ekubo::math::utils::{unsafe_sub};
    use ekubo::math::ticks::{tick_to_sqrt_ratio};
    use ekubo::math::muldiv::{muldiv};
    use traits::{Into};

    #[derive(Drop, Copy, storage_access::StorageAccess)]
    struct StakedTokenInfo {
        timestamp_last: u64,
        owner: ContractAddress,
        tick_cumulative_snapshot: i129,
        seconds_per_liquidity_inside_snapshot: u256,
    }

    #[storage]
    struct Storage {
        // constant addresses
        positions: IPositionsDispatcher,
        oracle: IOracleDispatcher,
        // the token that can be purchased
        reward_token: IERC20Dispatcher,
        // the number of option tokens per liquidity-second awarded
        // no decimal because options are expressed in terms of 1 wei of token
        options_per_second: u64,
        // the owner of a staked token
        staked_token_info: LegacyMap<u256, StakedTokenInfo>,
        // the address that receives the executed balance
        benefactor: ContractAddress,
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
        paid: u128,
        purchased: u128,
        recipient: ContractAddress,
    }

    #[derive(starknet::Event, Drop)]
    #[event]
    enum Event {
        Staked: Staked,
        Exercised: Exercised,
        Unstaked: Unstaked,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        positions: IPositionsDispatcher,
        oracle: IOracleDispatcher,
        reward_token: IERC20Dispatcher,
        options_per_second: u64,
        benefactor: ContractAddress,
    ) {
        self.positions.write(positions);
        self.oracle.write(oracle);
        self.reward_token.write(reward_token);
        self.options_per_second.write(options_per_second);

        // for safety of execution
        assert(benefactor != get_contract_address(), 'BENEFACTOR');
        self.benefactor.write(benefactor);
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
            let reward_token = self.reward_token.read();
            assert(
                (pool_key.token0 == reward_token.contract_address)
                    | (pool_key.token1 == reward_token.contract_address),
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
                        timestamp_last: get_block_timestamp(),
                        owner: owner,
                        tick_cumulative_snapshot: oracle.get_tick_cumulative(pool_key),
                        seconds_per_liquidity_inside_snapshot: oracle
                            .get_seconds_per_liquidity_inside(pool_key, bounds),
                    }
                );

            self.emit(Staked { token_id: token_id, owner: owner });
        }

        fn get_exercisable_amount(
            self: @ContractState, token_id: u256, pool_key: PoolKey, bounds: Bounds, 
        ) -> ExercisableAmount {
            let staked_info = self.staked_token_info.read(token_id);

            let oracle = self.oracle.read();

            let seconds_per_liquidity_inside_current = oracle
                .get_seconds_per_liquidity_inside(pool_key, bounds);

            let seconds_per_liquidity_difference = unsafe_sub(
                seconds_per_liquidity_inside_current,
                staked_info.seconds_per_liquidity_inside_snapshot
            );

            let liquidity = self
                .positions
                .read()
                .get_position_info(token_id, pool_key, bounds)
                .liquidity;

            // we know if this overflows the u256 container, the result overflows a u128
            let amount = ((seconds_per_liquidity_difference * u256 { low: liquidity, high: 0 })
                * u256 {
                high: 0, low: self.options_per_second.read().into()
            })
                .high;

            // we do not need to do sub with overflow because we use 64 bits for time

            let tick_cumulative_current = oracle.get_tick_cumulative(pool_key);
            let tick_difference = tick_cumulative_current - staked_info.tick_cumulative_snapshot;

            let average_tick = tick_difference / i129 {
                mag: (get_block_timestamp() - staked_info.timestamp_last).into(), sign: false
            };

            // expressed in terms of reward_token/quote_token so we can just multiply it
            let strike_price = if (pool_key.token1 == self.reward_token.read().contract_address) {
                tick_to_sqrt_ratio(average_tick)
            } else {
                tick_to_sqrt_ratio(-average_tick)
            };

            ExercisableAmount {
                strike_price, amount, tick_cumulative_current, seconds_per_liquidity_inside_current, 
            }
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

            let exercisable = self.get_exercisable_amount(token_id, pool_key, bounds);

            let reward_token = self.reward_token.read();

            let quote_token = if (pool_key.token1 == reward_token.contract_address) {
                IERC20Dispatcher { contract_address: pool_key.token0 }
            } else {
                IERC20Dispatcher { contract_address: pool_key.token1 }
            };

            let address = get_contract_address();

            let paid_amount = quote_token.balance_of(address);

            // strike price is Q128, paid amount is raw, total should not exceed Q128
            let mut purchased = (paid_amount * exercisable.strike_price).high;

            let max_purchase_amount = reward_token.balance_of(address);
            assert(max_purchase_amount.high.is_zero(), 'REWARD_TOKEN_OVERFLOW');

            if (purchased > max_purchase_amount.low) {
                purchased = max_purchase_amount.low;
            }

            // we must be able to purchase at least the given output amount
            assert(purchased >= min_output, 'MIN_OUTPUT');

            // must happen before the calls
            self
                .staked_token_info
                .write(
                    token_id,
                    StakedTokenInfo {
                        timestamp_last: get_block_timestamp(),
                        owner: staked_info.owner,
                        tick_cumulative_snapshot: exercisable.tick_cumulative_current,
                        seconds_per_liquidity_inside_snapshot: exercisable
                            .seconds_per_liquidity_inside_current,
                    }
                );

            reward_token.transfer(recipient, u256 { low: purchased, high: 0 });
            quote_token.transfer(self.benefactor.read(), paid_amount);

            self
                .emit(
                    Event::Exercised(
                        Exercised { token_id, paid: paid_amount.low, purchased, recipient }
                    )
                );

            purchased
        }

        fn unstake(ref self: ContractState, token_id: u256, recipient: ContractAddress) {
            let staked_info = self.staked_token_info.read(token_id);
            assert(staked_info.owner == get_caller_address(), 'NOT_OWNER');

            self
                .staked_token_info
                .write(
                    token_id,
                    StakedTokenInfo {
                        timestamp_last: Zeroable::zero(),
                        owner: Zeroable::zero(),
                        tick_cumulative_snapshot: Zeroable::zero(),
                        seconds_per_liquidity_inside_snapshot: Zeroable::zero(),
                    }
                );

            IERC721Dispatcher {
                contract_address: self.positions.read().contract_address
            }.transfer_from(get_contract_address(), recipient, token_id);

            self.emit(Unstaked { token_id: token_id, recipient: recipient });
        }
    }
}
