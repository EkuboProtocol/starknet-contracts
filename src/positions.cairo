#[starknet::contract]
mod Positions {
    use hash::LegacyHash;
    use traits::{Into, TryInto};
    use option::{Option, OptionTrait};
    use serde::Serde;
    use zeroable::Zeroable;
    use array::{ArrayTrait};

    use starknet::{
        ContractAddress, contract_address_const, get_caller_address, get_contract_address,
        StorageAccess, StorageBaseAddress, SyscallResult, storage_read_syscall,
        storage_write_syscall, storage_address_from_base_and_offset
    };

    use ekubo::types::i129::{i129};
    use ekubo::types::bounds::{Bounds};
    use ekubo::math::ticks::{tick_to_sqrt_ratio};
    use ekubo::math::utils::{unsafe_sub};
    use ekubo::math::liquidity::{max_liquidity, liquidity_delta_to_amount_delta};
    use ekubo::math::utils::{add_delta};
    use ekubo::math::string::{to_decimal, append};
    use ekubo::types::keys::{PoolKey};
    use ekubo::types::delta::{Delta};
    use ekubo::types::keys::{PositionKey};
    use ekubo::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use ekubo::interfaces::erc165::{IERC165Dispatcher, IERC165DispatcherTrait};
    use ekubo::interfaces::erc721::{
        IERC721_RECEIVER_INTERFACE_ID, IACCOUNT_INTERFACE_ID, IERC721, IERC721ReceiverDispatcher,
        IERC721ReceiverDispatcherTrait
    };
    use ekubo::interfaces::core::{
        ICoreDispatcher, UpdatePositionParameters, ICoreDispatcherTrait, ILocker
    };
    use ekubo::shared_locker::call_core_with_callback;
    use ekubo::interfaces::positions::{IPositions, TokenInfo, GetPositionInfoResult};

    #[storage]
    struct Storage {
        token_uri_base: felt252,
        core: ICoreDispatcher,
        next_token_id: u64,
        approvals: LegacyMap<u64, ContractAddress>,
        owners: LegacyMap<u64, ContractAddress>,
        // address, id -> next
        // address, 0 contains the first token id
        tokens_by_owner: LegacyMap<(ContractAddress, u64), u64>,
        operators: LegacyMap<(ContractAddress, ContractAddress), bool>,
        token_info: LegacyMap<u64, TokenInfo>,
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
    struct Deposit {
        token_id: u256,
        pool_key: PoolKey,
        bounds: Bounds,
        liquidity: u128,
        delta: Delta
    }

    #[derive(starknet::Event, Drop)]
    struct Withdraw {
        token_id: u256,
        pool_key: PoolKey,
        bounds: Bounds,
        liquidity: u128,
        delta: Delta,
        collect_fees: bool,
        recipient: ContractAddress
    }

    #[derive(starknet::Event, Drop)]
    struct PositionMinted {
        token_id: u256,
        pool_key: PoolKey,
        bounds: Bounds,
    }

    #[derive(starknet::Event, Drop)]
    #[event]
    enum Event {
        Transfer: Transfer,
        Approval: Approval,
        ApprovalForAll: ApprovalForAll,
        Deposit: Deposit,
        Withdraw: Withdraw,
        PositionMinted: PositionMinted,
    }

    #[constructor]
    fn constructor(ref self: ContractState, core: ICoreDispatcher, token_uri_base: felt252) {
        self.token_uri_base.write(token_uri_base);
        self.core.write(core);
        self.next_token_id.write(1);
    }

    fn validate_token_id(token_id: u256) -> u64 {
        assert(token_id.high == 0, 'INVALID_ID');
        token_id.low.try_into().expect('INVALID_ID')
    }

    // Compute the hash for a given position key
    fn hash_key(pool_key: PoolKey, bounds: Bounds) -> felt252 {
        LegacyHash::hash(bounds.into(), pool_key)
    }

    #[derive(Serde, Copy, Drop)]
    struct DepositCallbackData {
        pool_key: PoolKey,
        salt: u64,
        bounds: Bounds,
        liquidity: u128,
    }

    #[derive(Serde, Copy, Drop)]
    struct WithdrawCallbackData {
        pool_key: PoolKey,
        salt: u64,
        bounds: Bounds,
        liquidity: u128,
        collect_fees: bool,
        min_token0: u128,
        min_token1: u128,
        recipient: ContractAddress,
    }

    #[derive(Serde, Copy, Drop)]
    enum LockCallbackData {
        Deposit: DepositCallbackData,
        Withdraw: WithdrawCallbackData,
    }

    #[generate_trait]
    impl Internal of InternalTrait {
        fn check_is_caller_authorized(
            ref self: ContractState, owner: ContractAddress, token_id: u64
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

        fn count_tokens_for_owner(self: @ContractState, owner: ContractAddress) -> u64 {
            let mut count: u64 = 0;

            let mut curr = self.tokens_by_owner.read((owner, 0));

            loop {
                if (curr == 0) {
                    break count;
                };
                count += 1;
                curr = self.tokens_by_owner.read((owner, curr));
            }
        }

        fn tokens_by_owner_insert(ref self: ContractState, owner: ContractAddress, id: u64) {
            let mut curr = self.tokens_by_owner.read((owner, 0));

            loop {
                if (curr < id) {
                    let next = self.tokens_by_owner.read((owner, curr));
                    if (next == 0 || next > id) {
                        self.tokens_by_owner.write((owner, curr), id);
                        self.tokens_by_owner.write((owner, id), next);
                        break ();
                    }
                    curr = next;
                } else {
                    curr = self.tokens_by_owner.read((owner, curr));
                };
            };
        }

        fn tokens_by_owner_remove(ref self: ContractState, owner: ContractAddress, id: u64) {
            let mut curr: u64 = 0;

            loop {
                let next = self.tokens_by_owner.read((owner, curr));
                assert(next <= id, 'TOKEN_NOT_FOUND');

                if (next == id) {
                    self
                        .tokens_by_owner
                        .write((owner, curr), self.tokens_by_owner.read((owner, next)));
                    self.tokens_by_owner.write((owner, next), 0);
                    break ();
                } else {
                    curr = next;
                };
            };
        }

        fn transfer(
            ref self: ContractState, from: ContractAddress, to: ContractAddress, token_id: u256
        ) {
            let id = validate_token_id(token_id);

            let owner = self.owners.read(id);
            assert(owner == from, 'OWNER');

            self.check_is_caller_authorized(owner, id);

            self.owners.write(id, to);
            self.approvals.write(id, Zeroable::zero());
            self.tokens_by_owner_insert(to, id);
            self.tokens_by_owner_remove(from, id);
            self.emit(Transfer { from, to, token_id });
        }

        fn get_token_info(
            self: @ContractState, id: u64, pool_key: PoolKey, bounds: Bounds
        ) -> TokenInfo {
            let info = self.token_info.read(id);
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
    impl ERC721Impl of IERC721<ContractState> {
        fn name(self: @ContractState) -> felt252 {
            'Ekubo Position NFT'
        }

        fn symbol(self: @ContractState) -> felt252 {
            'EpNFT'
        }

        fn approve(ref self: ContractState, to: ContractAddress, token_id: u256) {
            let caller = get_caller_address();
            let id = validate_token_id(token_id);
            assert(caller == self.owners.read(id), 'OWNER');
            self.approvals.write(id, to);
            self.emit(Approval { owner: caller, approved: to, token_id });
        }

        fn balance_of(self: @ContractState, account: ContractAddress) -> u256 {
            u256 { low: self.count_tokens_for_owner(account).into(), high: 0 }
        }

        fn owner_of(self: @ContractState, token_id: u256) -> ContractAddress {
            self.owners.read(validate_token_id(token_id))
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
            if (IERC165Dispatcher {
                contract_address: to
            }.supports_interface(IERC721_RECEIVER_INTERFACE_ID)) {
                // todo add casing fallback mechanism
                assert(
                    IERC721ReceiverDispatcher {
                        contract_address: to
                    }
                        .on_erc721_received(
                            get_caller_address(), from, token_id, data
                        ) == IERC721_RECEIVER_INTERFACE_ID,
                    'CALLBACK_FAILED'
                );
            } else {
                assert(
                    IERC165Dispatcher {
                        contract_address: to
                    }.supports_interface(IACCOUNT_INTERFACE_ID),
                    'SAFE_TRANSFER_TO_NON_ACCOUNT'
                );
            }
        }

        fn set_approval_for_all(
            ref self: ContractState, operator: ContractAddress, approved: bool
        ) {
            let owner = get_caller_address();
            self.operators.write((owner, operator), approved);
            self.emit(ApprovalForAll { owner, operator, approved });
        }

        fn get_approved(self: @ContractState, token_id: u256) -> ContractAddress {
            self.approvals.read(validate_token_id(token_id))
        }

        fn is_approved_for_all(
            self: @ContractState, owner: ContractAddress, operator: ContractAddress
        ) -> bool {
            self.operators.read((owner, operator))
        }

        fn token_uri(self: @ContractState, token_id: u256) -> felt252 {
            let id = validate_token_id(token_id);
            // the prefix takes up 20 characters and leaves 11 for the decimal token id
            // 10^11 == ~2**36 tokens can be supported by this method
            append(self.token_uri_base.read(), to_decimal(id.into()).expect('TOKEN_ID'))
                .expect('URI_LENGTH')
        }
    }

    #[external(v0)]
    impl ILockerImpl of ILocker<ContractState> {
        fn locked(ref self: ContractState, id: u32, data: Array<felt252>) -> Array<felt252> {
            let core = self.core.read();
            assert(core.contract_address == get_caller_address(), 'CORE');

            let mut data_span = data.span();
            let callback_data = Serde::<LockCallbackData>::deserialize(ref data_span)
                .expect('DESERIALIZE_CALLBACK_FAILED');

            let delta = match callback_data {
                LockCallbackData::Deposit(data) => {
                    let delta: Delta = if data.liquidity.is_non_zero() {
                        core
                            .update_position(
                                data.pool_key,
                                UpdatePositionParameters {
                                    salt: data.salt, bounds: data.bounds, liquidity_delta: i129 {
                                        mag: data.liquidity, sign: false
                                    },
                                }
                            )
                    } else {
                        Zeroable::zero()
                    };

                    if delta.amount0.is_non_zero() {
                        IERC20Dispatcher {
                            contract_address: data.pool_key.token0
                        }.transfer(core.contract_address, u256 { low: delta.amount0.mag, high: 0 });
                        core.deposit(data.pool_key.token0);
                    }

                    if delta.amount1.is_non_zero() {
                        IERC20Dispatcher {
                            contract_address: data.pool_key.token1
                        }.transfer(core.contract_address, u256 { low: delta.amount1.mag, high: 0 });
                        core.deposit(data.pool_key.token1);
                    }

                    delta
                },
                LockCallbackData::Withdraw(data) => {
                    let mut delta: Delta = if data.collect_fees {
                        core
                            .collect_fees(
                                pool_key: data.pool_key, salt: data.salt, bounds: data.bounds
                            )
                    } else {
                        Zeroable::zero()
                    };

                    if data.liquidity.is_non_zero() {
                        let update = core
                            .update_position(
                                data.pool_key,
                                UpdatePositionParameters {
                                    salt: data.salt, bounds: data.bounds, liquidity_delta: i129 {
                                        mag: data.liquidity, sign: true
                                    },
                                }
                            );
                        delta += update;

                        assert(update.amount0.mag >= data.min_token0, 'MIN_TOKEN0');
                        assert(update.amount1.mag >= data.min_token1, 'MIN_TOKEN1');
                    }

                    if delta.amount0.is_non_zero() {
                        core.withdraw(data.pool_key.token0, data.recipient, delta.amount0.mag);
                    }

                    if delta.amount1.is_non_zero() {
                        core.withdraw(data.pool_key.token1, data.recipient, delta.amount1.mag);
                    }

                    delta
                },
            };

            let mut result_data: Array<felt252> = ArrayTrait::new();
            Serde::<Delta>::serialize(@delta, ref result_data);
            result_data
        }
    }

    #[external(v0)]
    impl PositionsImpl of IPositions<ContractState> {
        fn mint(
            ref self: ContractState, recipient: ContractAddress, pool_key: PoolKey, bounds: Bounds
        ) -> u256 {
            let id = self.next_token_id.read();
            self.next_token_id.write(id + 1);

            // effect the mint by updating storage
            self.owners.write(id, recipient);
            self.tokens_by_owner_insert(recipient, id);
            self
                .token_info
                .write(
                    id,
                    TokenInfo {
                        key_hash: hash_key(pool_key, bounds), liquidity: Zeroable::zero(), 
                    }
                );

            self
                .emit(
                    Transfer {
                        from: Zeroable::zero(), to: recipient, token_id: u256 {
                            low: id.into(), high: 0
                        }
                    }
                );

            // contains the associated pool key and bounds which is never stored, which is important for indexing
            self
                .emit(
                    PositionMinted {
                        token_id: u256 {
                            low: id.into(), high: 0
                        }, pool_key: pool_key, bounds: bounds,
                    }
                );

            u256 { low: id.into(), high: 0 }
        }

        fn burn(ref self: ContractState, token_id: u256) {
            let id = validate_token_id(token_id);
            let owner = self.owners.read(id);
            self.check_is_caller_authorized(owner, id);

            let info = self.token_info.read(id);
            assert(info.liquidity.is_zero(), 'LIQUIDITY_MUST_BE_ZERO');

            // delete the storage variables
            self.owners.write(id, Zeroable::zero());
            self.tokens_by_owner_remove(owner, id);
            self.token_info.write(id, TokenInfo { key_hash: 0, liquidity: Zeroable::zero() });

            self.emit(Transfer { from: owner, to: Zeroable::zero(), token_id });
        }

        fn get_position_info(
            self: @ContractState, token_id: u256, pool_key: PoolKey, bounds: Bounds
        ) -> GetPositionInfoResult {
            let id = validate_token_id(token_id);

            let info = self.get_token_info(id, pool_key, bounds);
            let core = self.core.read();
            let get_position_result = core
                .get_position(
                    pool_key, PositionKey { owner: get_contract_address(), salt: id.into(), bounds }
                );
            let pool = core.get_pool(pool_key);

            let delta = liquidity_delta_to_amount_delta(
                sqrt_ratio: pool.sqrt_ratio,
                liquidity_delta: i129 { mag: info.liquidity, sign: true },
                sqrt_ratio_lower: tick_to_sqrt_ratio(bounds.lower),
                sqrt_ratio_upper: tick_to_sqrt_ratio(bounds.upper),
            );

            GetPositionInfoResult {
                liquidity: info.liquidity,
                amount0: delta.amount0.mag,
                amount1: delta.amount1.mag,
                fees0: get_position_result.fees0,
                fees1: get_position_result.fees1
            }
        }

        fn deposit(
            ref self: ContractState,
            token_id: u256,
            pool_key: PoolKey,
            bounds: Bounds,
            min_liquidity: u128,
        ) -> u128 {
            let id = validate_token_id(token_id);
            self.check_is_caller_authorized(self.owners.read(id), id);

            let info = self.get_token_info(id, pool_key, bounds);
            let core = self.core.read();
            let pool = core.get_pool(pool_key);

            // compute how much liquidity we can deposit based on token balances
            let liquidity: u128 = max_liquidity(
                pool.sqrt_ratio,
                tick_to_sqrt_ratio(bounds.lower),
                tick_to_sqrt_ratio(bounds.upper),
                self.balance_of_token(pool_key.token0),
                self.balance_of_token(pool_key.token1)
            );
            assert(liquidity >= min_liquidity, 'MIN_LIQUIDITY');

            self
                .token_info
                .write(
                    id,
                    TokenInfo { key_hash: info.key_hash, liquidity: info.liquidity + liquidity,  }
                );

            let delta: Delta = call_core_with_callback(
                core,
                @LockCallbackData::Deposit(
                    DepositCallbackData {
                        pool_key, bounds, liquidity: liquidity, salt: id.into(), 
                    }
                )
            );

            self.emit(Deposit { token_id, pool_key, bounds, liquidity, delta });

            liquidity
        }

        fn withdraw(
            ref self: ContractState,
            token_id: u256,
            pool_key: PoolKey,
            bounds: Bounds,
            liquidity: u128,
            min_token0: u128,
            min_token1: u128,
            collect_fees: bool,
            recipient: ContractAddress
        ) -> (u128, u128) {
            let id = validate_token_id(token_id);
            self.check_is_caller_authorized(self.owners.read(id), id);

            let info = self.get_token_info(id, pool_key, bounds);

            self
                .token_info
                .write(
                    id,
                    TokenInfo { key_hash: info.key_hash, liquidity: info.liquidity - liquidity,  }
                );

            let delta: Delta = call_core_with_callback(
                self.core.read(),
                @LockCallbackData::Withdraw(
                    WithdrawCallbackData {
                        bounds,
                        pool_key,
                        liquidity: liquidity,
                        salt: id.into(),
                        collect_fees,
                        min_token0,
                        min_token1,
                        recipient,
                    }
                )
            );

            self
                .emit(
                    Withdraw {
                        token_id, pool_key, bounds, liquidity, delta, collect_fees, recipient
                    }
                );

            (delta.amount0.mag, delta.amount1.mag)
        }

        fn clear(
            ref self: ContractState, token: ContractAddress, recipient: ContractAddress
        ) -> u256 {
            let dispatcher = IERC20Dispatcher { contract_address: token };
            let balance = dispatcher.balance_of(get_contract_address());
            if (balance.is_non_zero()) {
                dispatcher.transfer(recipient, balance);
            }
            balance
        }

        fn refund(ref self: ContractState, token: ContractAddress) -> u256 {
            self.clear(token, get_caller_address())
        }

        fn maybe_initialize_pool(ref self: ContractState, pool_key: PoolKey, initial_tick: i129) {
            let core = self.core.read();
            let pool = core.get_pool(pool_key);
            if (pool.sqrt_ratio == Zeroable::zero()) {
                core.initialize_pool(pool_key, initial_tick);
            }
        }

        fn deposit_last(
            ref self: ContractState, pool_key: PoolKey, bounds: Bounds, min_liquidity: u128
        ) -> u128 {
            self
                .deposit(
                    u256 { low: (self.next_token_id.read() - 1_u64).into(), high: 0 },
                    pool_key,
                    bounds,
                    min_liquidity
                )
        }
    }
}
