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
    use ekubo::math::liquidity::{max_liquidity};
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
    use ekubo::interfaces::positions::{IPositions, TokenInfo, GetPositionInfoResult};

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
    struct Deposit {
        token_id: u256,
        pool_key: PoolKey,
        bounds: Bounds,
        liquidity: u128,
        delta: Delta
    }

    #[derive(starknet::Event, Drop)]
    #[event]
    enum Event {
        Transfer: Transfer,
        Approval: Approval,
        ApprovalForAll: ApprovalForAll,
        Deposit: Deposit,
    }

    #[constructor]
    fn constructor(ref self: ContractState, core: ContractAddress) {
        self.core.write(core);
        self.next_token_id.write(1);
    }

    fn validate_token_id(token_id: u256) {
        assert(token_id.high == 0, 'INVALID_ID');
    }

    // Compute the hash for a given position key
    fn hash_key(pool_key: PoolKey, bounds: Bounds) -> felt252 {
        LegacyHash::hash(bounds.into(), pool_key)
    }

    #[derive(Serde, Copy, Drop)]
    struct LockCallbackData {
        pool_key: PoolKey,
        salt: u32,
        bounds: Bounds,
        liquidity_delta: i129,
        collect_fees: bool,
        min_token0: u128,
        min_token1: u128,
    }

    #[generate_trait]
    impl Internal of InternalTrait {
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
            self.approvals.write(token_id.low, Zeroable::zero());
            self.balances.write(from, self.balances.read(from) - 1);
            self.balances.write(to, self.balances.read(to) + 1);
            self.emit(Event::Transfer(Transfer { from, to, token_id }));
        }

        fn get_token_info(
            self: @ContractState, token_id: u128, pool_key: PoolKey, bounds: Bounds
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
    impl ERC721Impl of IERC721<ContractState> {
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
            validate_token_id(token_id);
            // the prefix takes up 20 characters and leaves 11 for the decimal token id
            // 10^11 == ~2**36 tokens can be supported by this method
            append('https://z.ekubo.org/', to_decimal(token_id.low).expect('TOKEN_ID'))
                .expect('URI_LENGTH')
        }
    }

    #[external(v0)]
    impl ILockerImpl of ILocker<ContractState> {
        fn locked(ref self: ContractState, id: u32, data: Array<felt252>) -> Array<felt252> {
            let caller = get_caller_address();
            assert(caller == self.core.read(), 'CORE');

            let mut data_span = data.span();
            let callback_data = Serde::<LockCallbackData>::deserialize(ref data_span)
                .expect('DESERIALIZE_CALLBACK_FAILED');

            let mut delta: Delta = Zeroable::zero();
            if callback_data.collect_fees {
                delta += ICoreDispatcher {
                    contract_address: caller
                }
                    .collect_fees(
                        pool_key: callback_data.pool_key,
                        salt: callback_data.salt,
                        bounds: callback_data.bounds
                    );
            }

            if callback_data.liquidity_delta != Zeroable::zero() {
                let update = ICoreDispatcher {
                    contract_address: caller
                }
                    .update_position(
                        callback_data.pool_key,
                        UpdatePositionParameters {
                            salt: callback_data.salt,
                            bounds: callback_data.bounds,
                            liquidity_delta: callback_data.liquidity_delta
                        }
                    );
                delta += update;

                if (callback_data.liquidity_delta.sign) {
                    assert(update.amount0.mag >= callback_data.min_token0, 'MIN_TOKEN0');
                    assert(update.amount1.mag >= callback_data.min_token1, 'MIN_TOKEN1');
                }
            }

            if delta.amount0.mag != 0 {
                if (delta.amount0.sign) {
                    // withdrawn to the contract to be returned to caller via #clear
                    ICoreDispatcher {
                        contract_address: caller
                    }
                        .withdraw(
                            callback_data.pool_key.token0, get_contract_address(), delta.amount0.mag
                        );
                } else {
                    IERC20Dispatcher {
                        contract_address: callback_data.pool_key.token0
                    }.transfer(caller, u256 { low: delta.amount0.mag, high: 0 });
                    ICoreDispatcher {
                        contract_address: caller
                    }.deposit(callback_data.pool_key.token0);
                }
            }
            if (delta.amount1.mag != 0) {
                // withdrawn to the contract to be returned to caller via #clear
                if (delta.amount0.sign) {
                    ICoreDispatcher {
                        contract_address: caller
                    }
                        .withdraw(
                            callback_data.pool_key.token1, get_contract_address(), delta.amount1.mag
                        );
                } else {
                    IERC20Dispatcher {
                        contract_address: callback_data.pool_key.token1
                    }.transfer(caller, u256 { low: delta.amount1.mag, high: 0 });
                    ICoreDispatcher {
                        contract_address: caller
                    }.deposit(callback_data.pool_key.token1);
                }
            }

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
            self.balances.write(recipient, self.balances.read(recipient) + 1);
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
                    Event::Transfer(
                        Transfer {
                            from: Zeroable::zero(), to: recipient, token_id: u256 {
                                low: id, high: 0
                            }
                        }
                    )
                );

            u256 { low: id, high: 0 }
        }

        fn burn(ref self: ContractState, token_id: u256) {
            validate_token_id(token_id);
            let owner = self.owners.read(token_id.low);
            self.check_is_caller_authorized(owner, token_id.low);

            let info = self.token_info.read(token_id.low);
            assert(info.liquidity.is_zero(), 'LIQUIDITY_MUST_BE_ZERO');

            // delete the storage variables
            self.owners.write(token_id.low, Zeroable::zero());
            self.balances.write(owner, self.balances.read(owner) - 1);
            self
                .token_info
                .write(token_id.low, TokenInfo { key_hash: 0, liquidity: Zeroable::zero() });

            self.emit(Event::Transfer(Transfer { from: owner, to: Zeroable::zero(), token_id }));
        }

        fn get_position_info(
            self: @ContractState, token_id: u256, pool_key: PoolKey, bounds: Bounds
        ) -> GetPositionInfoResult {
            validate_token_id(token_id);

            let info = self.get_token_info(token_id.low, pool_key, bounds);
            let get_position_result = ICoreDispatcher {
                contract_address: self.core.read()
            }
                .get_position(
                    pool_key,
                    PositionKey {
                        owner: get_contract_address(),
                        salt: token_id.low.try_into().unwrap(),
                        bounds
                    }
                );

            GetPositionInfoResult {
                liquidity: info.liquidity,
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
            collect_fees: bool
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

            let liquidity_delta = i129 { mag: liquidity, sign: false };

            self
                .token_info
                .write(
                    token_id.low,
                    TokenInfo {
                        key_hash: info.key_hash,
                        liquidity: add_delta(info.liquidity, liquidity_delta),
                    }
                );

            // do the deposit (never expected to fail because we pre-computed liquidity)
            let mut data: Array<felt252> = ArrayTrait::new();
            Serde::<LockCallbackData>::serialize(
                @LockCallbackData {
                    pool_key,
                    bounds,
                    liquidity_delta,
                    salt: token_id.low.try_into().unwrap(),
                    collect_fees,
                    min_token0: 0,
                    min_token1: 0
                },
                ref data
            );

            let mut result = ICoreDispatcher {
                contract_address: self.core.read()
            }.lock(data).span();

            let delta = Serde::<Delta>::deserialize(ref result)
                .expect('CALLBACK_RESULT_DESERIALIZE');

            self.emit(Event::Deposit(Deposit { token_id, pool_key, bounds, liquidity, delta }));

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
        ) -> (u128, u128) {
            validate_token_id(token_id);
            self.check_is_caller_authorized(self.owners.read(token_id.low), token_id.low);

            let info = self.get_token_info(token_id.low, pool_key, bounds);

            let liquidity_delta: i129 = i129 { mag: liquidity, sign: true };

            self
                .token_info
                .write(
                    token_id.low,
                    TokenInfo {
                        key_hash: info.key_hash,
                        liquidity: add_delta(info.liquidity, liquidity_delta),
                    }
                );

            let mut data: Array<felt252> = ArrayTrait::new();
            Serde::<LockCallbackData>::serialize(
                @LockCallbackData {
                    bounds,
                    pool_key,
                    liquidity_delta,
                    salt: token_id.low.try_into().unwrap(),
                    collect_fees,
                    min_token0,
                    min_token1
                },
                ref data
            );

            let mut result = ICoreDispatcher {
                contract_address: self.core.read()
            }.lock(data).span();

            let delta = Serde::<Delta>::deserialize(ref result)
                .expect('CALLBACK_RESULT_DESERIALIZE');

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

        fn maybe_initialize_pool(ref self: ContractState, pool_key: PoolKey, initial_tick: i129) {
            let core_dispatcher = ICoreDispatcher { contract_address: self.core.read() };
            let pool = core_dispatcher.get_pool(pool_key);
            if (pool.sqrt_ratio == Zeroable::zero()) {
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
                    min_liquidity,
                    false
                )
        }
    }
}
