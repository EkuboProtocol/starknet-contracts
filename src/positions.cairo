#[starknet::contract]
pub mod Positions {
    use core::array::{ArrayTrait, SpanTrait};
    use core::cmp::{max};
    use core::num::traits::{Zero};
    use core::option::{Option, OptionTrait};
    use core::serde::{Serde};
    use core::traits::{Into};
    use ekubo::components::owned::{Owned as owned_component};
    use ekubo::components::shared_locker::{call_core_with_callback, consume_callback_data};
    use ekubo::components::upgradeable::{Upgradeable as upgradeable_component, IHasInterface};
    use ekubo::components::util::{serialize};
    use ekubo::extensions::interfaces::twamm::{OrderKey, ITWAMMDispatcher, ITWAMMDispatcherTrait};
    use ekubo::extensions::twamm::math::{calculate_sale_rate, time::{to_duration}};
    use ekubo::interfaces::core::{
        ICoreDispatcher, UpdatePositionParameters, ICoreDispatcherTrait, ILocker
    };
    use ekubo::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use ekubo::interfaces::positions::{IPositions, GetTokenInfoResult, GetTokenInfoRequest};
    use ekubo::interfaces::upgradeable::{
        IUpgradeable, IUpgradeableDispatcher, IUpgradeableDispatcherTrait
    };
    use ekubo::math::liquidity::{liquidity_delta_to_amount_delta};
    use ekubo::math::max_liquidity::{max_liquidity};
    use ekubo::math::ticks::{tick_to_sqrt_ratio};
    use ekubo::owned_nft::{OwnedNFT, IOwnedNFTDispatcher, IOwnedNFTDispatcherTrait};
    use ekubo::types::bounds::{Bounds, max_bounds};
    use ekubo::types::delta::{Delta};
    use ekubo::types::i129::{i129};
    use ekubo::types::keys::{PoolKey};
    use ekubo::types::keys::{PositionKey};
    use ekubo::types::pool_price::{PoolPrice};
    use starknet::{
        ContractAddress, get_caller_address, get_contract_address, ClassHash, get_block_timestamp,
    };

    component!(path: owned_component, storage: owned, event: OwnedEvent);
    #[abi(embed_v0)]
    impl Owned = owned_component::OwnedImpl<ContractState>;
    impl OwnableImpl = owned_component::OwnableImpl<ContractState>;

    component!(path: upgradeable_component, storage: upgradeable, event: UpgradeableEvent);
    #[abi(embed_v0)]
    impl Upgradeable = upgradeable_component::UpgradeableImpl<ContractState>;

    #[abi(embed_v0)]
    impl Clear = ekubo::components::clear::ClearImpl<ContractState>;

    #[abi(embed_v0)]
    impl Expires = ekubo::components::expires::ExpiresImpl<ContractState>;

    #[storage]
    struct Storage {
        core: ICoreDispatcher,
        nft: IOwnedNFTDispatcher,
        twamm: ITWAMMDispatcher,
        #[substorage(v0)]
        upgradeable: upgradeable_component::Storage,
        #[substorage(v0)]
        owned: owned_component::Storage,
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
        OwnedEvent: owned_component::Event,
        PositionMintedWithReferrer: PositionMintedWithReferrer,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner: ContractAddress,
        core: ICoreDispatcher,
        nft_class_hash: ClassHash,
        token_uri_base: felt252
    ) {
        self.initialize_owned(owner);
        self.core.write(core);

        self
            .nft
            .write(
                OwnedNFT::deploy(
                    nft_class_hash: nft_class_hash,
                    owner: get_contract_address(),
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
        min_liquidity: u128,
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
        GetPoolPrice: PoolKey,
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

    #[abi(embed_v0)]
    impl PositionsHasInterface of IHasInterface<ContractState> {
        fn get_primary_interface_id(self: @ContractState) -> felt252 {
            return selector!("ekubo::positions::Positions");
        }
    }

    #[abi(embed_v0)]
    impl ILockerImpl of ILocker<ContractState> {
        fn locked(ref self: ContractState, id: u32, data: Span<felt252>) -> Span<felt252> {
            let core = self.core.read();

            match consume_callback_data::<LockCallbackData>(core, data) {
                LockCallbackData::Deposit(data) => {
                    // pools with extensions could update the price, perform a zero liquidity
                    // update and get the most up to date price
                    if (data.pool_key.extension.is_non_zero()) {
                        core
                            .update_position(
                                data.pool_key,
                                UpdatePositionParameters {
                                    salt: 0,
                                    bounds: max_bounds(data.pool_key.tick_spacing),
                                    liquidity_delta: Zero::zero(),
                                }
                            );
                    }

                    let price = core.get_pool_price(data.pool_key);

                    // compute how much liquidity we can deposit based on token balances
                    let liquidity: u128 = max_liquidity(
                        price.sqrt_ratio,
                        tick_to_sqrt_ratio(data.bounds.lower),
                        tick_to_sqrt_ratio(data.bounds.upper),
                        self.balance_of_token(data.pool_key.token0),
                        self.balance_of_token(data.pool_key.token1)
                    );

                    assert(liquidity >= data.min_liquidity, 'MIN_LIQUIDITY');

                    let delta: Delta = if liquidity.is_non_zero() {
                        core
                            .update_position(
                                data.pool_key,
                                UpdatePositionParameters {
                                    salt: data.salt,
                                    bounds: data.bounds,
                                    liquidity_delta: i129 { mag: liquidity, sign: false },
                                }
                            )
                    } else {
                        Zero::zero()
                    };

                    if delta.amount0.is_non_zero() {
                        let token = IERC20Dispatcher { contract_address: data.pool_key.token0 };
                        token.approve(core.contract_address, delta.amount0.mag.into());
                        core.pay(data.pool_key.token0);
                    }

                    if delta.amount1.is_non_zero() {
                        let token = IERC20Dispatcher { contract_address: data.pool_key.token1 };
                        token.approve(core.contract_address, delta.amount1.mag.into());
                        core.pay(data.pool_key.token1);
                    }

                    serialize(@liquidity).span()
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

                    serialize(@delta).span()
                },
                LockCallbackData::CollectFees(data) => {
                    let delta = core.collect_fees(data.pool_key, data.salt, data.bounds,);

                    if delta.amount0.is_non_zero() {
                        core.withdraw(data.pool_key.token0, data.recipient, delta.amount0.mag);
                    }

                    if delta.amount1.is_non_zero() {
                        core.withdraw(data.pool_key.token1, data.recipient, delta.amount1.mag);
                    }

                    serialize(@delta).span()
                },
                LockCallbackData::GetPoolPrice(pool_key) => {
                    core
                        .update_position(
                            pool_key,
                            UpdatePositionParameters {
                                salt: 0,
                                bounds: max_bounds(pool_key.tick_spacing),
                                liquidity_delta: Zero::zero(),
                            }
                        );

                    let pool_price = core.get_pool_price(pool_key);

                    serialize(@pool_price).span()
                }
            }
        }
    }

    #[abi(embed_v0)]
    impl PositionsImpl of IPositions<ContractState> {
        fn get_nft_address(self: @ContractState) -> ContractAddress {
            self.nft.read().contract_address
        }

        fn upgrade_nft(ref self: ContractState, class_hash: ClassHash) {
            self.require_owner();
            IUpgradeableDispatcher { contract_address: self.nft.read().contract_address }
                .replace_class_hash(class_hash);
        }

        fn set_twamm(ref self: ContractState, twamm_address: ContractAddress) {
            self.require_owner();
            self.twamm.write(ITWAMMDispatcher { contract_address: twamm_address });
        }

        fn get_twamm_address(self: @ContractState) -> ContractAddress {
            self.twamm.read().contract_address
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

        fn check_liquidity_is_zero(
            self: @ContractState, id: u64, pool_key: PoolKey, bounds: Bounds
        ) {
            let info = self.get_token_info(id, pool_key, bounds);
            assert(info.liquidity.is_zero(), 'LIQUIDITY_IS_NON_ZERO');
        }

        fn unsafe_burn(ref self: ContractState, id: u64) {
            let nft = self.nft.read();
            assert(nft.is_account_authorized(id, get_caller_address()), 'UNAUTHORIZED');
            nft.burn(id);
        }

        fn get_tokens_info(
            self: @ContractState, mut params: Span<GetTokenInfoRequest>
        ) -> Span<GetTokenInfoResult> {
            let mut results: Array<GetTokenInfoResult> = ArrayTrait::new();

            loop {
                match params.pop_front() {
                    Option::Some(request) => {
                        results
                            .append(
                                self.get_token_info(*request.id, *request.pool_key, *request.bounds)
                            );
                    },
                    Option::None => { break (); }
                };
            };

            results.span()
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

            let liquidity: u128 = call_core_with_callback(
                self.core.read(),
                @LockCallbackData::Deposit(
                    DepositCallbackData {
                        pool_key, salt: id.into(), bounds, min_liquidity: min_liquidity
                    }
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

        fn get_pool_price(self: @ContractState, pool_key: PoolKey) -> PoolPrice {
            call_core_with_callback::<
                LockCallbackData, PoolPrice
            >(self.core.read(), @LockCallbackData::GetPoolPrice(pool_key))
        }

        // Mint a twamm position and set sale rate.
        fn mint_and_increase_sell_amount(
            ref self: ContractState, order_key: OrderKey, amount: u128
        ) -> (u64, u128) {
            let id = self.mint_v2(Zero::zero());
            (id, self.increase_sell_amount(id, order_key, amount))
        }

        fn increase_sell_amount_last(
            ref self: ContractState, order_key: OrderKey, amount: u128
        ) -> u128 {
            self.increase_sell_amount(self.nft.read().get_next_token_id() - 1, order_key, amount)
        }

        fn increase_sell_amount(
            ref self: ContractState, id: u64, order_key: OrderKey, amount: u128
        ) -> u128 {
            let nft = self.nft.read();
            let caller = get_caller_address();
            assert(nft.is_account_authorized(id, caller), 'UNAUTHORIZED');

            let twamm = self.twamm.read();

            // if increasing sale rate, transfer additional funds to twamm
            IERC20Dispatcher { contract_address: order_key.sell_token }
                .transfer(twamm.contract_address, amount.into());

            let sale_rate = calculate_sale_rate(
                amount: amount,
                duration: to_duration(
                    max(order_key.start_time, get_block_timestamp()), order_key.end_time
                ),
            );

            twamm.update_order(id.into(), order_key, i129 { mag: sale_rate, sign: false });

            sale_rate
        }

        fn decrease_sale_rate(
            ref self: ContractState, id: u64, order_key: OrderKey, sale_rate_delta: u128
        ) {
            let nft = self.nft.read();
            let caller = get_caller_address();
            assert(nft.is_account_authorized(id, caller), 'UNAUTHORIZED');

            self
                .twamm
                .read()
                .update_order(id.into(), order_key, i129 { mag: sale_rate_delta, sign: true });
        }

        // Withdraws proceeds from a twamm position
        fn withdraw_proceeds_from_sale(ref self: ContractState, id: u64, order_key: OrderKey) {
            let nft = self.nft.read();
            let caller = get_caller_address();
            assert(nft.is_account_authorized(id, caller), 'UNAUTHORIZED');

            let twamm = self.twamm.read();

            twamm.collect_proceeds(id.into(), order_key);
        }
    }
}
