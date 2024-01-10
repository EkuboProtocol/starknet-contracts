#[starknet::contract]
mod Positions {
    use core::array::{ArrayTrait, SpanTrait};
    use core::num::traits::{Zero};
    use core::option::{Option, OptionTrait};
    use core::serde::{Serde};
    use core::traits::{Into};
    use ekubo::components::owner::{check_owner_only};
    use ekubo::components::shared_locker::{call_core_with_callback, consume_callback_data};
    use ekubo::components::upgradeable::{Upgradeable as upgradeable_component, IHasInterface};
    use ekubo::interfaces::core::{
        ICoreDispatcher, UpdatePositionParameters, ICoreDispatcherTrait, ILocker
    };
    use ekubo::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use ekubo::interfaces::positions::{IPositions, GetTokenInfoResult, GetTokenInfoRequest};
    use ekubo::interfaces::upgradeable::{IUpgradeable};
    use ekubo::math::liquidity::{liquidity_delta_to_amount_delta};
    use ekubo::math::max_liquidity::{max_liquidity};
    use ekubo::math::ticks::{tick_to_sqrt_ratio};
    use ekubo::owned_nft::{OwnedNFT, IOwnedNFTDispatcher, IOwnedNFTDispatcherTrait};
    use ekubo::types::bounds::{Bounds};
    use ekubo::types::delta::{Delta};
    use ekubo::types::i129::{i129};
    use ekubo::types::keys::{PoolKey};
    use ekubo::types::keys::{PositionKey};
    use starknet::{
        ContractAddress, get_caller_address, get_contract_address, ClassHash, replace_class_syscall,
        deploy_syscall
    };

    component!(path: upgradeable_component, storage: upgradeable, event: UpgradeableEvent);

    #[abi(embed_v0)]
    impl Upgradeable = upgradeable_component::UpgradeableImpl<ContractState>;

    #[abi(embed_v0)]
    impl Clear = ekubo::components::clear::ClearImpl<ContractState>;


    #[storage]
    struct Storage {
        core: ICoreDispatcher,
        nft: IOwnedNFTDispatcher,
        #[substorage(v0)]
        upgradeable: upgradeable_component::Storage
    }


    #[derive(starknet::Event, Drop)]
    struct PositionMintedWithReferrer {
        id: u64,
        referrer: ContractAddress,
    }

    #[derive(starknet::Event, Drop)]
    #[event]
    enum Event {
        #[flat]
        UpgradeableEvent: upgradeable_component::Event,
        PositionMintedWithReferrer: PositionMintedWithReferrer,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        core: ICoreDispatcher,
        nft_class_hash: ClassHash,
        token_uri_base: felt252
    ) {
        self.core.write(core);

        self
            .nft
            .write(
                OwnedNFT::deploy(
                    nft_class_hash: nft_class_hash,
                    controller: get_contract_address(),
                    name: 'Ekubo Position',
                    symbol: 'EkuPo',
                    token_uri_base: token_uri_base,
                    salt: 0
                )
            );
    }

    #[derive(Serde, Copy, Drop)]
    struct DepositCallbackData {
        pool_key: PoolKey,
        salt: felt252,
        bounds: Bounds,
        liquidity: u128,
    }

    #[derive(Serde, Copy, Drop)]
    struct WithdrawCallbackData {
        pool_key: PoolKey,
        salt: felt252,
        bounds: Bounds,
        liquidity: u128,
        min_token0: u128,
        min_token1: u128,
        recipient: ContractAddress,
    }

    #[derive(Serde, Copy, Drop)]
    struct CollectFeesCallbackData {
        pool_key: PoolKey,
        salt: felt252,
        bounds: Bounds,
        recipient: ContractAddress,
    }

    #[derive(Serde, Copy, Drop)]
    enum LockCallbackData {
        Deposit: DepositCallbackData,
        Withdraw: WithdrawCallbackData,
        CollectFees: CollectFeesCallbackData,
    }

    #[generate_trait]
    impl Internal of InternalTrait {
        fn balance_of_token(ref self: ContractState, token: ContractAddress) -> u128 {
            let balance = IERC20Dispatcher { contract_address: token }
                .balanceOf(get_contract_address());
            assert(balance.high == 0, 'BALANCE_OVERFLOW');
            balance.low
        }
    }

    #[external(v0)]
    impl PositionsHasInterface of IHasInterface<ContractState> {
        fn get_primary_interface_id(self: @ContractState) -> felt252 {
            return selector!("ekubo::positions::Positions");
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
                                    salt: data.salt,
                                    bounds: data.bounds,
                                    liquidity_delta: i129 { mag: data.liquidity, sign: false },
                                }
                            )
                    } else {
                        Zero::zero()
                    };

                    if delta.amount0.is_non_zero() {
                        let token = IERC20Dispatcher { contract_address: data.pool_key.token0 };
                        token.approve(core.contract_address, delta.amount0.mag.into());
                        core.pay(data.pool_key.token0, delta.amount0.mag);
                    }

                    if delta.amount1.is_non_zero() {
                        let token = IERC20Dispatcher { contract_address: data.pool_key.token1 };
                        token.approve(core.contract_address, delta.amount1.mag.into());
                        core.pay(data.pool_key.token1, delta.amount1.mag);
                    }

                    delta
                },
                LockCallbackData::Withdraw(data) => {
                    let delta = core
                        .update_position(
                            data.pool_key,
                            UpdatePositionParameters {
                                salt: data.salt,
                                bounds: data.bounds,
                                liquidity_delta: i129 { mag: data.liquidity, sign: true },
                            }
                        );

                    assert(delta.amount0.mag >= data.min_token0, 'MIN_TOKEN0');
                    assert(delta.amount1.mag >= data.min_token1, 'MIN_TOKEN1');

                    if delta.amount0.is_non_zero() {
                        core.withdraw(data.pool_key.token0, data.recipient, delta.amount0.mag);
                    }

                    if delta.amount1.is_non_zero() {
                        core.withdraw(data.pool_key.token1, data.recipient, delta.amount1.mag);
                    }

                    delta
                },
                LockCallbackData::CollectFees(data) => {
                    let delta = core.collect_fees(data.pool_key, data.salt, data.bounds,);

                    if delta.amount0.is_non_zero() {
                        core.withdraw(data.pool_key.token0, data.recipient, delta.amount0.mag);
                    }

                    if delta.amount1.is_non_zero() {
                        core.withdraw(data.pool_key.token1, data.recipient, delta.amount1.mag);
                    }

                    delta
                }
            };

            let mut result_data: Array<felt252> = ArrayTrait::new();
            Serde::<Delta>::serialize(@delta, ref result_data);
            result_data
        }
    }

    #[external(v0)]
    impl PositionsImpl of IPositions<ContractState> {
        // Update the token URI base of the owned NFT
        fn update_token_uri_base(ref self: ContractState, token_uri_base: felt252) {
            check_owner_only();
            self.nft.read().set_token_uri_base(token_uri_base);
        }

        fn get_nft_address(self: @ContractState) -> ContractAddress {
            self.nft.read().contract_address
        }

        fn mint(ref self: ContractState, pool_key: PoolKey, bounds: Bounds) -> u64 {
            self.mint_v2(Zero::zero())
        }

        #[inline(always)]
        fn mint_with_referrer(
            ref self: ContractState, pool_key: PoolKey, bounds: Bounds, referrer: ContractAddress
        ) -> u64 {
            self.mint_v2(referrer)
        }

        #[inline(always)]
        fn mint_v2(ref self: ContractState, referrer: ContractAddress) -> u64 {
            let id = self.nft.read().mint(get_caller_address());

            if (referrer.is_non_zero()) {
                self.emit(PositionMintedWithReferrer { id, referrer })
            }

            id
        }

        fn unsafe_burn(ref self: ContractState, id: u64) {
            let nft = self.nft.read();
            assert(nft.is_account_authorized(id, get_caller_address()), 'UNAUTHORIZED');
            nft.burn(id);
        }

        fn get_tokens_info(
            self: @ContractState, params: Array<GetTokenInfoRequest>
        ) -> Array<GetTokenInfoResult> {
            let mut results: Array<GetTokenInfoResult> = ArrayTrait::new();

            let mut params_view = params.span();

            loop {
                match params_view.pop_front() {
                    Option::Some(request) => {
                        results
                            .append(
                                self.get_token_info(*request.id, *request.pool_key, *request.bounds)
                            );
                    },
                    Option::None => { break (); }
                };
            };

            results
        }

        fn get_token_info(
            self: @ContractState, id: u64, pool_key: PoolKey, bounds: Bounds
        ) -> GetTokenInfoResult {
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

            let core = self.core.read();

            // todo: how do we handle before/after update position that changes the price? 
            // https://github.com/EkuboProtocol/contracts/issues/102
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
                    DepositCallbackData { pool_key, bounds, liquidity: liquidity, salt: id.into(), }
                )
            );

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
            let (fees0, fees1) = if collect_fees {
                self.collect_fees(id, pool_key, bounds)
            } else {
                (0, 0)
            };

            let (principal0, principal1) = if liquidity.is_non_zero() {
                self.withdraw_v2(id, pool_key, bounds, liquidity, min_token0, min_token1)
            } else {
                (0, 0)
            };

            (principal0 + fees0, principal1 + fees1)
        }

        fn withdraw_v2(
            ref self: ContractState,
            id: u64,
            pool_key: PoolKey,
            bounds: Bounds,
            liquidity: u128,
            min_token0: u128,
            min_token1: u128,
        ) -> (u128, u128) {
            let nft = self.nft.read();
            let caller = get_caller_address();
            assert(nft.is_account_authorized(id, caller), 'UNAUTHORIZED');

            let delta: Delta = call_core_with_callback(
                self.core.read(),
                @LockCallbackData::Withdraw(
                    WithdrawCallbackData {
                        bounds,
                        pool_key,
                        liquidity,
                        salt: id.into(),
                        min_token0,
                        min_token1,
                        recipient: caller
                    }
                )
            );

            (delta.amount0.mag, delta.amount1.mag)
        }

        fn collect_fees(
            ref self: ContractState, id: u64, pool_key: PoolKey, bounds: Bounds
        ) -> (u128, u128) {
            let nft = self.nft.read();
            let caller = get_caller_address();
            assert(nft.is_account_authorized(id, caller), 'UNAUTHORIZED');

            let delta: Delta = call_core_with_callback(
                self.core.read(),
                @LockCallbackData::CollectFees(
                    CollectFeesCallbackData { bounds, pool_key, salt: id.into(), recipient: caller }
                )
            );

            (delta.amount0.mag, delta.amount1.mag)
        }

        fn deposit_last(
            ref self: ContractState, pool_key: PoolKey, bounds: Bounds, min_liquidity: u128
        ) -> u128 {
            self.deposit(self.nft.read().get_next_token_id() - 1, pool_key, bounds, min_liquidity)
        }

        fn mint_and_deposit(
            ref self: ContractState, pool_key: PoolKey, bounds: Bounds, min_liquidity: u128
        ) -> (u64, u128) {
            self.mint_and_deposit_with_referrer(pool_key, bounds, min_liquidity, Zero::zero())
        }

        #[inline(always)]
        fn mint_and_deposit_with_referrer(
            ref self: ContractState,
            pool_key: PoolKey,
            bounds: Bounds,
            min_liquidity: u128,
            referrer: ContractAddress
        ) -> (u64, u128) {
            let id = self.mint_v2(referrer);
            let liquidity = self.deposit(id, pool_key, bounds, min_liquidity);
            (id, liquidity)
        }

        fn mint_and_deposit_and_clear_both(
            ref self: ContractState, pool_key: PoolKey, bounds: Bounds, min_liquidity: u128
        ) -> (u64, u128, u256, u256) {
            let (id, liquidity) = self.mint_and_deposit(pool_key, bounds, min_liquidity);
            let amount0 = self.clear(IERC20Dispatcher { contract_address: pool_key.token0 });
            let amount1 = self.clear(IERC20Dispatcher { contract_address: pool_key.token1 });
            (id, liquidity, amount0, amount1)
        }
    }
}
