#[starknet::contract]
mod Positions {
    use hash::{LegacyHash};
    use traits::{Into};
    use option::{Option, OptionTrait};
    use serde::{Serde};
    use zeroable::{Zeroable};
    use array::{ArrayTrait};
    use starknet::{
        ContractAddress, get_caller_address, get_contract_address, ClassHash, replace_class_syscall,
        deploy_syscall
    };
    use ekubo::types::i129::{i129};
    use ekubo::types::bounds::{Bounds};
    use ekubo::math::ticks::{tick_to_sqrt_ratio};
    use ekubo::math::liquidity::{max_liquidity, liquidity_delta_to_amount_delta};
    use ekubo::types::keys::{PoolKey};
    use ekubo::types::delta::{Delta};
    use ekubo::types::keys::{PositionKey};
    use ekubo::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use ekubo::enumerable_owned_nft::{
        IEnumerableOwnedNFTDispatcher, IEnumerableOwnedNFTDispatcherTrait
    };
    use ekubo::interfaces::core::{
        ICoreDispatcher, UpdatePositionParameters, ICoreDispatcherTrait, ILocker
    };
    use ekubo::interfaces::positions::{IPositions, GetTokenInfoResult};
    use ekubo::interfaces::upgradeable::{IUpgradeable};
    use ekubo::owner::{check_owner_only};
    use ekubo::shared_locker::{call_core_with_callback, consume_callback_data};

    #[storage]
    struct Storage {
        core: ICoreDispatcher,
        nft: IEnumerableOwnedNFTDispatcher,
        token_key_hashes: LegacyMap<u64, felt252>,
    }

    #[derive(starknet::Event, Drop)]
    struct ClassHashReplaced {
        new_class_hash: ClassHash, 
    }

    #[derive(starknet::Event, Drop)]
    struct Deposit {
        id: u64,
        pool_key: PoolKey,
        bounds: Bounds,
        liquidity: u128,
        delta: Delta
    }

    #[derive(starknet::Event, Drop)]
    struct Withdraw {
        id: u64,
        pool_key: PoolKey,
        bounds: Bounds,
        liquidity: u128,
        delta: Delta,
        collect_fees: bool,
        recipient: ContractAddress
    }

    #[derive(starknet::Event, Drop)]
    struct PositionMinted {
        id: u64,
        pool_key: PoolKey,
        bounds: Bounds,
    }

    #[derive(starknet::Event, Drop)]
    #[event]
    enum Event {
        ClassHashReplaced: ClassHashReplaced,
        Deposit: Deposit,
        Withdraw: Withdraw,
        PositionMinted: PositionMinted,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        core: ICoreDispatcher,
        nft_class_hash: ClassHash,
        token_uri_base: felt252
    ) {
        self.core.write(core);

        let mut calldata = ArrayTrait::<felt252>::new();
        Serde::serialize(@get_contract_address(), ref calldata);
        Serde::serialize(@'Ekubo Position NFT', ref calldata);
        Serde::serialize(@'EpNFT', ref calldata);
        Serde::serialize(@token_uri_base, ref calldata);

        let (nft_address, _) = deploy_syscall(
            class_hash: nft_class_hash,
            contract_address_salt: 0,
            calldata: calldata.span(),
            deploy_from_zero: false,
        )
            .unwrap_syscall();

        self.nft.write(IEnumerableOwnedNFTDispatcher { contract_address: nft_address });
    }

    // Compute the hash for a given position key
    fn hash_key(pool_key: PoolKey, bounds: Bounds) -> felt252 {
        LegacyHash::hash(LegacyHash::hash(0, pool_key), bounds)
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
        fn check_key_hash(self: @ContractState, id: u64, pool_key: PoolKey, bounds: Bounds) {
            let key_hash = self.token_key_hashes.read(id);
            assert(key_hash == hash_key(pool_key, bounds), 'POSITION_KEY');
        }

        fn balance_of_token(ref self: ContractState, token: ContractAddress) -> u128 {
            let balance = IERC20Dispatcher {
                contract_address: token
            }.balanceOf(get_contract_address());
            assert(balance.high == 0, 'BALANCE_OVERFLOW');
            balance.low
        }
    }

    #[external(v0)]
    impl ILockerImpl of ILocker<ContractState> {
        fn locked(ref self: ContractState, id: u32, data: Array<felt252>) -> Array<felt252> {
            let core = self.core.read();

            let delta = match consume_callback_data::<LockCallbackData>(core, data) {
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
    impl Upgradeable of IUpgradeable<ContractState> {
        fn replace_class_hash(ref self: ContractState, class_hash: ClassHash) {
            check_owner_only();
            replace_class_syscall(class_hash);
            self.emit(ClassHashReplaced { new_class_hash: class_hash });
        }
    }

    #[external(v0)]
    impl PositionsImpl of IPositions<ContractState> {
        fn get_nft_address(self: @ContractState) -> ContractAddress {
            self.nft.read().contract_address
        }

        fn mint(ref self: ContractState, pool_key: PoolKey, bounds: Bounds) -> u64 {
            let id = self.nft.read().mint(get_caller_address());

            let key_hash = hash_key(pool_key, bounds);
            self.token_key_hashes.write(id, key_hash);

            // contains the associated pool key and bounds which is never stored,
            // so it's important for indexing
            self.emit(PositionMinted { id, pool_key, bounds });

            id
        }

        fn burn(ref self: ContractState, id: u64, pool_key: PoolKey, bounds: Bounds) {
            let nft = self.nft.read();
            assert(nft.is_account_authorized(id, get_caller_address()), 'UNAUTHORIZED');

            self.check_key_hash(id, pool_key, bounds);
            let core = self.core.read();
            let position = core
                .get_position(
                    pool_key, PositionKey { owner: get_contract_address(), salt: id, bounds }
                );

            assert(position.is_zero(), 'LIQUIDITY_MUST_BE_ZERO');

            // delete the storage variables
            self.token_key_hashes.write(id, 0);

            nft.burn(id);
        }

        fn get_token_info(
            self: @ContractState, id: u64, pool_key: PoolKey, bounds: Bounds
        ) -> GetTokenInfoResult {
            self.check_key_hash(id, pool_key, bounds);
            let core = self.core.read();
            let get_position_result = core
                .get_position_with_fees(
                    pool_key, PositionKey { owner: get_contract_address(), salt: id.into(), bounds }
                );
            let price = core.get_pool_price(pool_key);

            let delta = liquidity_delta_to_amount_delta(
                sqrt_ratio: price.sqrt_ratio,
                liquidity_delta: i129 { mag: get_position_result.position.liquidity, sign: true },
                sqrt_ratio_lower: tick_to_sqrt_ratio(bounds.lower),
                sqrt_ratio_upper: tick_to_sqrt_ratio(bounds.upper),
            );

            GetTokenInfoResult {
                pool_price: price,
                liquidity: get_position_result.position.liquidity,
                amount0: delta.amount0.mag,
                amount1: delta.amount1.mag,
                fees0: get_position_result.fees0,
                fees1: get_position_result.fees1
            }
        }

        fn deposit(
            ref self: ContractState,
            id: u64,
            pool_key: PoolKey,
            bounds: Bounds,
            min_liquidity: u128,
        ) -> u128 {
            let nft = self.nft.read();
            assert(nft.is_account_authorized(id, get_caller_address()), 'UNAUTHORIZED');

            self.check_key_hash(id, pool_key, bounds);

            let core = self.core.read();
            let price = core.get_pool_price(pool_key);

            // compute how much liquidity we can deposit based on token balances
            let liquidity: u128 = max_liquidity(
                price.sqrt_ratio,
                tick_to_sqrt_ratio(bounds.lower),
                tick_to_sqrt_ratio(bounds.upper),
                self.balance_of_token(pool_key.token0),
                self.balance_of_token(pool_key.token1)
            );
            assert(liquidity >= min_liquidity, 'MIN_LIQUIDITY');

            let delta: Delta = call_core_with_callback(
                core,
                @LockCallbackData::Deposit(
                    DepositCallbackData {
                        pool_key, bounds, liquidity: liquidity, salt: id.into(), 
                    }
                )
            );

            self.emit(Deposit { id, pool_key, bounds, liquidity, delta });

            liquidity
        }

        fn withdraw(
            ref self: ContractState,
            id: u64,
            pool_key: PoolKey,
            bounds: Bounds,
            liquidity: u128,
            min_token0: u128,
            min_token1: u128,
            collect_fees: bool
        ) -> (u128, u128) {
            let nft = self.nft.read();
            assert(nft.is_account_authorized(id, get_caller_address()), 'UNAUTHORIZED');

            let recipient = get_caller_address();

            let delta: Delta = call_core_with_callback(
                self.core.read(),
                @LockCallbackData::Withdraw(
                    WithdrawCallbackData {
                        bounds,
                        pool_key,
                        liquidity,
                        salt: id.into(),
                        collect_fees,
                        min_token0,
                        min_token1,
                        recipient,
                    }
                )
            );

            self.emit(Withdraw { id, pool_key, bounds, liquidity, delta, collect_fees, recipient });

            (delta.amount0.mag, delta.amount1.mag)
        }

        fn clear(ref self: ContractState, token: ContractAddress) -> u256 {
            let dispatcher = IERC20Dispatcher { contract_address: token };
            let balance = dispatcher.balanceOf(get_contract_address());
            if (balance.is_non_zero()) {
                dispatcher.transfer(get_caller_address(), balance);
            }
            balance
        }

        fn deposit_last(
            ref self: ContractState, pool_key: PoolKey, bounds: Bounds, min_liquidity: u128
        ) -> u128 {
            self.deposit(self.nft.read().get_next_token_id() - 1, pool_key, bounds, min_liquidity)
        }

        fn mint_and_deposit(
            ref self: ContractState, pool_key: PoolKey, bounds: Bounds, min_liquidity: u128
        ) -> (u64, u128) {
            let id = self.mint(pool_key, bounds);
            let liquidity = self.deposit(id, pool_key, bounds, min_liquidity);
            (id, liquidity)
        }
    }
}
