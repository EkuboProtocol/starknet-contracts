use starknet::{
    ContractAddress, contract_address_const, get_caller_address, get_contract_address,
    StorageAccess, StorageBaseAddress, SyscallResult, storage_read_syscall, storage_write_syscall,
    storage_address_from_base_and_offset
};
use ekubo::types::i129::{i129, i129IntoFelt252};
use ekubo::math::ticks::{tick_to_sqrt_ratio};
use ekubo::math::utils::{unsafe_sub};
use array::{ArrayTrait};
use ekubo::interfaces::core::{ICoreDispatcher, UpdatePositionParameters, ICoreDispatcherTrait};
use ekubo::interfaces::positions::{IPositions};
use ekubo::types::keys::{PoolKey};
use core::hash::LegacyHash;
use traits::{Into, TryInto};
use option::{Option, OptionTrait};
use ekubo::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
use ekubo::math::liquidity::{max_liquidity};
use ekubo::interfaces::positions::{Bounds, TokenInfo};
use serde::Serde;


// Compute the hash for a given position key
fn hash_key(pool_key: PoolKey, bounds: Bounds) -> felt252 {
    LegacyHash::hash(
        pedersen(
            Into::<i129, felt252>::into(bounds.tick_lower),
            Into::<i129, felt252>::into(bounds.tick_upper)
        ),
        pool_key
    )
}

#[starknet::contract]
mod Positions {
    use super::{
        ContractAddress, get_caller_address, i129, contract_address_const, ArrayTrait,
        ICoreDispatcher, ICoreDispatcherTrait, PoolKey, Bounds, TokenInfo, hash_key,
        IERC20Dispatcher, IERC20DispatcherTrait, get_contract_address, Serde, Option, OptionTrait,
        max_liquidity, tick_to_sqrt_ratio, UpdatePositionParameters, unsafe_sub, IPositions
    };

    #[storage]
    struct Storage {
        core: ContractAddress,
        next_token_id: u128,
        approvals: LegacyMap<u128, ContractAddress>,
        owners: LegacyMap<u128, ContractAddress>,
        balances: LegacyMap<ContractAddress, u128>,
        operators: LegacyMap<(ContractAddress, ContractAddress), bool>,
        token_info: LegacyMap<u128, TokenInfo>,
    }

    #[derive(starknet::Event, Drop)]
    struct Transfer {
        from: ContractAddress,
        to: ContractAddress,
        token_id: u256
    }

    #[derive(starknet::Event, Drop)]
    struct Approval {
        owner: ContractAddress,
        approved: ContractAddress,
        token_id: u256
    }

    #[derive(starknet::Event, Drop)]
    struct ApprovalForAll {
        owner: ContractAddress,
        operator: ContractAddress,
        approved: bool
    }

    #[derive(starknet::Event, Drop)]
    #[event]
    enum Event {
        Transfer: Transfer,
        Approval: Approval,
        ApprovalForAll: ApprovalForAll,
    }

    #[constructor]
    fn constructor(ref self: ContractState, _core: ContractAddress) {
        self.core.write(_core);
        self.next_token_id.write(1);
    }


    #[derive(Serde, Copy, Drop)]
    struct DepositCallbackData {
        pool_key: PoolKey,
        bounds: Bounds,
        liquidity: u128
    }
    #[derive(Serde, Copy, Drop)]
    struct WithdrawCallbackData {
        bounds: Bounds,
        min_token0: u128,
        min_token1: u128
    }
    #[derive(Serde, Copy, Drop)]
    enum LockCallbackData {
        Deposit: DepositCallbackData,
        Withdraw: WithdrawCallbackData
    }

    #[derive(Serde, Copy, Drop)]
    struct WithdrawCallbackResult {
        token0_amount: u128,
        token1_amount: u128
    }
    #[derive(Serde, Copy, Drop)]
    enum LockCallbackResult {
        Deposit: (),
        Withdraw: WithdrawCallbackResult
    }

    fn validate_token_id(token_id: u256) {
        assert(token_id.high == 0, 'INVALID_ID');
    }

    #[generate_trait]
    impl PositionsInternal of PositionsInternalTrait {
        fn check_is_caller_authorized(
            ref self: ContractState, owner: ContractAddress, token_id: u128
        ) {
            let caller = get_caller_address();
            if (caller != owner) {
                let approved = self.approvals.read(token_id);
                if (caller != approved) {
                    let operator = self.operators.read((owner, caller));
                    assert(operator, 'UNAUTHORIZED');
                }
            }
        }

        fn transfer(
            ref self: ContractState, from: ContractAddress, to: ContractAddress, token_id: u256
        ) {
            validate_token_id(token_id);

            let owner = self.owners.read(token_id.low);
            assert(owner == from, 'OWNER');

            self.check_is_caller_authorized(owner, token_id.low);

            self.owners.write(token_id.low, to);
            self.approvals.write(token_id.low, contract_address_const::<0>());
            self.balances.write(from, self.balances.read(from) - 1);
            self.balances.write(to, self.balances.read(to) + 1);
            self.emit(Event::Transfer(Transfer { from, to, token_id }));
        }

        fn get_token_info(
            ref self: ContractState, token_id: u128, pool_key: PoolKey, bounds: Bounds
        ) -> TokenInfo {
            let info = self.token_info.read(token_id);
            assert(info.key_hash == hash_key(pool_key, bounds), 'POSITION_KEY');
            info
        }

        fn balance_of_token(ref self: ContractState, token: ContractAddress) -> u128 {
            let balance = IERC20Dispatcher {
                contract_address: token
            }.balance_of(get_contract_address());
            assert(balance.high == 0, 'BALANCE_OVERFLOW');
            balance.low
        }
    }

    #[external(v0)]
    impl PositionsExternal of IPositions<ContractState> {
        fn name(self: @ContractState) -> felt252 {
            'Ekubo Position NFT'
        }

        fn symbol(self: @ContractState) -> felt252 {
            'EpNFT'
        }

        fn approve(ref self: ContractState, to: ContractAddress, token_id: u256) {
            let caller = get_caller_address();
            assert(caller == self.owner_of(token_id), 'OWNER');
            self.approvals.write(token_id.low, to);
            self.emit(Event::Approval(Approval { owner: caller, approved: to, token_id }));
        }

        fn balance_of(self: @ContractState, account: ContractAddress) -> u256 {
            u256 { low: self.balances.read(account), high: 0 }
        }

        fn owner_of(self: @ContractState, token_id: u256) -> ContractAddress {
            assert(token_id.high == 0, 'INVALID_ID');
            self.owners.read(token_id.low)
        }


        // Deposits the tokens held by this contract for the given token ID, using the balances transiently held by this contract
        fn deposit(
            ref self: ContractState,
            token_id: u256,
            pool_key: PoolKey,
            bounds: Bounds,
            min_liquidity: u128
        ) -> u128 {
            validate_token_id(token_id);
            self.check_is_caller_authorized(self.owners.read(token_id.low), token_id.low);

            let info = self.get_token_info(token_id.low, pool_key, bounds);
            let pool = ICoreDispatcher { contract_address: self.core.read() }.get_pool(pool_key);

            // compute how much liquidity we can deposit based on token balances
            let liquidity: u128 = max_liquidity(
                pool.sqrt_ratio,
                tick_to_sqrt_ratio(bounds.tick_lower),
                tick_to_sqrt_ratio(bounds.tick_upper),
                self.balance_of_token(pool_key.token0),
                self.balance_of_token(pool_key.token1)
            );
            assert(liquidity >= min_liquidity, 'MIN_LIQUIDITY');

            // first update the position
            {
                let (fee_growth_inside_token0, fee_growth_inside_token1) = ICoreDispatcher {
                    contract_address: self.core.read()
                }.get_pool_fee_growth_inside(pool_key, bounds.tick_lower, bounds.tick_upper);

                let fees0 = (unsafe_sub(
                    fee_growth_inside_token0, info.fee_growth_inside_last_token0
                )
                    * u256 {
                    low: info.liquidity, high: 0
                })
                    .high;
                let fees1 = (unsafe_sub(
                    fee_growth_inside_token1, info.fee_growth_inside_last_token1
                )
                    * u256 {
                    low: info.liquidity, high: 0
                })
                    .high;
            // let token_info_next = TokenInfo {
            //     key_hash: info.key_hash,
            //     liquidity: info.liquidity + liquidity,
            //     fee_growth_inside_last_token0: fee_growth_inside_token0,
            //     fee_growth_inside_last_token1: fee_growth_inside_token1,
            //     fees_token0: info.fees_token0 + fees0,
            //     fees_token1: info.fees_token1 + fees1,
            // };

            // self.token_info.write(token_id.low, token_info_next);
            }

            // do the deposit (never expected to fail because we pre-computed liquidity)
            {
                let mut data: Array<felt252> = ArrayTrait::new();
                // make the deposit to the pool
                Serde::<LockCallbackData>::serialize(
                    @LockCallbackData::Deposit(DepositCallbackData { pool_key, bounds, liquidity }),
                    ref data
                );

                let mut result = ICoreDispatcher {
                    contract_address: self.core.read()
                }.lock(data).span();

                match Serde::<LockCallbackResult>::deserialize(ref result)
                    .expect('CALLBACK_RESULT_DESERIALIZE') {
                    LockCallbackResult::Deposit(_) => {},
                    LockCallbackResult::Withdraw(_) => {
                        assert(false, 'INVALID_DEPOSIT_RESULT');
                    }
                };
            }

            liquidity
        }

        fn withdraw(
            ref self: ContractState,
            token_id: u256,
            pool_key: PoolKey,
            bounds: Bounds,
            liquidity: u128,
            min_token0: u128,
            min_token1: u128
        ) -> (u128, u128) {
            validate_token_id(token_id);
            self.check_is_caller_authorized(self.owners.read(token_id.low), token_id.low);

            let info = self.get_token_info(token_id.low, pool_key, bounds);

            let mut data: Array<felt252> = ArrayTrait::new();
            // make the deposit to the pool
            Serde::<LockCallbackData>::serialize(
                @LockCallbackData::Withdraw(
                    WithdrawCallbackData { bounds, min_token0, min_token1 }
                ),
                ref data
            );

            let mut result = ICoreDispatcher {
                contract_address: self.core.read()
            }.lock(data).span();

            let (token0_amount, token1_amount) =
                match Serde::<LockCallbackResult>::deserialize(ref result)
                    .expect('CALLBACK_RESULT_DESERIALIZE') {
                LockCallbackResult::Deposit(_) => {
                    assert(false, 'INVALID_WITHDRAW_RESULT');
                    (Default::<u128>::default(), Default::<u128>::default())
                },
                LockCallbackResult::Withdraw(result) => {
                    assert(false, 'TODO');
                    (Default::<u128>::default(), Default::<u128>::default())
                }
            };
            // todo: update the position info here

            (token0_amount, token1_amount)
        }

        // This contract only holds tokens for the duration of a transaction.
        fn clear(
            ref self: ContractState, token: ContractAddress, recipient: ContractAddress
        ) -> u256 {
            let dispatcher = IERC20Dispatcher { contract_address: token };
            let balance = dispatcher.balance_of(get_contract_address());
            if (balance != u256 { low: 0, high: 0 }) {
                dispatcher.transfer(recipient, balance);
            }
            balance
        }

        fn locked(ref self: ContractState, id: felt252, data: Array<felt252>) -> Array<felt252> {
            let caller = get_caller_address();
            assert(caller == self.core.read(), 'CORE');

            let mut data_span = data.span();
            let result: LockCallbackResult =
                match Serde::<LockCallbackData>::deserialize(ref data_span)
                    .expect('DESERIALIZE_CALLBACK_FAILED') {
                LockCallbackData::Deposit(deposit) => {
                    let delta = ICoreDispatcher {
                        contract_address: caller
                    }
                        .update_position(
                            deposit.pool_key,
                            UpdatePositionParameters {
                                tick_lower: deposit.bounds.tick_lower,
                                tick_upper: deposit.bounds.tick_upper,
                                liquidity_delta: i129 {
                                    mag: deposit.liquidity, sign: false
                                }
                            }
                        );

                    if delta.amount0_delta.mag != 0 {
                        IERC20Dispatcher {
                            contract_address: deposit.pool_key.token0
                        }.transfer(caller, u256 { low: delta.amount0_delta.mag, high: 0 });
                        ICoreDispatcher {
                            contract_address: caller
                        }.deposit(deposit.pool_key.token0);
                    }
                    if (delta.amount1_delta.mag != 0) {
                        IERC20Dispatcher {
                            contract_address: deposit.pool_key.token1
                        }.transfer(caller, u256 { low: delta.amount1_delta.mag, high: 0 });
                        ICoreDispatcher {
                            contract_address: caller
                        }.deposit(deposit.pool_key.token1);
                    }

                    LockCallbackResult::Deposit(())
                },
                LockCallbackData::Withdraw(withdraw) => {
                    LockCallbackResult::Withdraw(
                        WithdrawCallbackResult {
                            token0_amount: Default::default(), token1_amount: Default::default()
                        }
                    )
                }
            };

            let mut result_data: Array<felt252> = ArrayTrait::new();
            Serde::<LockCallbackResult>::serialize(@result, ref result_data);
            result_data
        }

        // Initializes a pool only if it's not already initialized
        // This is useful as part of a batch of operations, to avoid failing the entire batch because the pool was already initialized
        fn maybe_initialize_pool(ref self: ContractState, pool_key: PoolKey, initial_tick: i129) {
            let core_dispatcher = ICoreDispatcher { contract_address: self.core.read() };
            let pool = core_dispatcher.get_pool(pool_key);
            if (pool.sqrt_ratio == Default::default()) {
                core_dispatcher.initialize_pool(pool_key, initial_tick);
            }
        }

        fn deposit_last(
            ref self: ContractState, pool_key: PoolKey, bounds: Bounds, min_liquidity: u128
        ) -> u128 {
            self
                .deposit(
                    u256 { low: self.next_token_id.read() - 1, high: 0 },
                    pool_key,
                    bounds,
                    min_liquidity
                )
        }


        fn transfer_from(
            ref self: ContractState, from: ContractAddress, to: ContractAddress, token_id: u256
        ) {
            self.transfer(from, to, token_id);
        }

        fn safe_transfer_from(
            ref self: ContractState,
            from: ContractAddress,
            to: ContractAddress,
            token_id: u256,
            data: Span<felt252>
        ) {
            self.transfer(from, to, token_id);
            assert(false, 'todo');
        }

        fn set_approval_for_all(
            ref self: ContractState, operator: ContractAddress, approved: bool
        ) {
            let owner = get_caller_address();
            self.operators.write((owner, operator), approved);
            self.emit(Event::ApprovalForAll(ApprovalForAll { owner, operator, approved }));
        }

        fn get_approved(self: @ContractState, token_id: u256) -> ContractAddress {
            self.approvals.read(token_id.low)
        }

        fn is_approved_for_all(
            self: @ContractState, owner: ContractAddress, operator: ContractAddress
        ) -> bool {
            self.operators.read((owner, operator))
        }

        fn token_uri(self: @ContractState, token_id: u256) -> felt252 {
            'https://nft.ekubo.org/'
        }

        // Creates the NFT and returns the token ID. Does not add any liquidity.
        fn mint(
            ref self: ContractState, recipient: ContractAddress, pool_key: PoolKey, bounds: Bounds
        ) -> u128 {
            let id = self.next_token_id.read();
            self.next_token_id.write(id + 1);

            // effect the mint by updating storage
            self.owners.write(id, recipient);
            self.balances.write(recipient, self.balances.read(recipient) + 1);
            self
                .token_info
                .write(
                    id,
                    TokenInfo {
                        key_hash: hash_key(pool_key, bounds),
                        liquidity: Default::default(),
                        fee_growth_inside_last_token0: Default::default(),
                        fee_growth_inside_last_token1: Default::default(),
                        fees_token0: Default::default(),
                        fees_token1: Default::default(),
                    }
                );

            self
                .emit(
                    Event::Transfer(
                        Transfer {
                            from: contract_address_const::<0>(), to: recipient, token_id: u256 {
                                low: id, high: 0
                            }
                        }
                    )
                );

            id
        }
    }
}
