#[starknet::contract]
pub mod Positions {
    use core::array::{ArrayTrait, SpanTrait};
    use core::cmp::{max};
    use core::num::traits::{Zero};
    use core::option::{Option, OptionTrait};
    use core::traits::{Into};
    use ekubo::components::owned::{Owned as owned_component};
    use ekubo::components::upgradeable::{IHasInterface, Upgradeable as upgradeable_component};
    use ekubo::components::util::{
        call_core_with_callback, consume_callback_data, forward_lock, serialize,
    };
    use ekubo::extensions::limit_orders::{
        LimitOrders::{DOUBLE_LIMIT_ORDER_TICK_SPACING, LIMIT_ORDER_TICK_SPACING},
    };
    use ekubo::interfaces::core::{
        ICoreDispatcher, ICoreDispatcherTrait, IForwardeeDispatcher, ILocker, SwapParameters,
        UpdatePositionParameters,
    };
    use ekubo::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use ekubo::interfaces::extensions::limit_orders::{
        CloseOrderForwardCallbackData, CloseOrderForwardCallbackResult,
        ForwardCallbackData as LimitOrderForwardCallbackData,
        GetOrderInfoRequest as GetLimitOrderInfoRequest,
        GetOrderInfoResult as GetLimitOrderInfoResult, ILimitOrdersDispatcher,
        ILimitOrdersDispatcherTrait, OrderKey as LimitOrderKey, PlaceOrderForwardCallbackData,
        PlaceOrderForwardCallbackResult,
    };
    use ekubo::interfaces::extensions::twamm::{
        CollectProceedsCallbackData, ForwardCallbackData, ITWAMMDispatcher, ITWAMMDispatcherTrait,
        OrderInfo, OrderKey, UpdateSaleRateCallbackData,
    };
    use ekubo::interfaces::positions::{GetTokenInfoRequest, GetTokenInfoResult, IPositions};
    use ekubo::interfaces::upgradeable::{IUpgradeableDispatcher, IUpgradeableDispatcherTrait};
    use ekubo::math::liquidity::{liquidity_delta_to_amount_delta};
    use ekubo::math::max_liquidity::{
        max_liquidity, max_liquidity_for_token0, max_liquidity_for_token1,
    };
    use ekubo::math::ticks::{min_sqrt_ratio, tick_to_sqrt_ratio};
    use ekubo::math::time::{to_duration};
    use ekubo::math::twamm::{calculate_sale_rate};
    use ekubo::owned_nft::{IOwnedNFTDispatcher, IOwnedNFTDispatcherTrait, OwnedNFT};
    use ekubo::types::bounds::{Bounds, max_bounds};
    use ekubo::types::delta::{Delta};
    use ekubo::types::i129::{i129};
    use ekubo::types::keys::{PoolKey, PositionKey};
    use ekubo::types::pool_price::{PoolPrice};
    use starknet::storage::StoragePointerReadAccess;
    use starknet::storage::StoragePointerWriteAccess;
    use starknet::{
        ClassHash, ContractAddress, get_block_timestamp, get_caller_address, get_contract_address,
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
        limit_orders: ILimitOrdersDispatcher,
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
        token_uri_base: felt252,
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
                    salt: 0,
                ),
            );
    }

    #[derive(Serde, Copy, Drop)]
    struct DepositCallbackData {
        pool_key: PoolKey,
        salt: felt252,
        bounds: Bounds,
        amount0: u128,
        amount1: u128,
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
    struct IncreaseSaleRateCallbackData {
        order_key: OrderKey,
        salt: felt252,
        sale_rate_delta_mag: u128,
    }

    #[derive(Serde, Copy, Drop)]
    struct DecreaseSaleRateCallbackData {
        order_key: OrderKey,
        salt: felt252,
        sale_rate_delta_mag: u128,
        recipient: ContractAddress,
    }

    #[derive(Serde, Copy, Drop)]
    struct CollectOrderProceedsCallbackData {
        order_key: OrderKey,
        salt: felt252,
        recipient: ContractAddress,
    }

    #[derive(Serde, Copy, Drop)]
    struct MoveToLimitOrderPriceCallbackData {
        order_key: LimitOrderKey,
        amount: u128,
        recipient: ContractAddress,
    }

    #[derive(Serde, Copy, Drop)]
    struct PlaceOrderCallbackData {
        salt: felt252,
        order_key: LimitOrderKey,
        liquidity: u128,
        sell_token: ContractAddress,
    }

    #[derive(Serde, Copy, Drop)]
    struct CloseOrderCallbackData {
        salt: felt252,
        order_key: LimitOrderKey,
        recipient: ContractAddress,
    }

    #[derive(Serde, Copy, Drop)]
    enum LockCallbackData {
        Deposit: DepositCallbackData,
        Withdraw: WithdrawCallbackData,
        CollectFees: CollectFeesCallbackData,
        GetPoolPrice: PoolKey,
        IncreaseSaleRate: IncreaseSaleRateCallbackData,
        DecreaseSaleRate: DecreaseSaleRateCallbackData,
        CollectOrderProceeds: CollectOrderProceedsCallbackData,
        PlaceOrder: PlaceOrderCallbackData,
        MoveToLimitOrderPrice: MoveToLimitOrderPriceCallbackData,
        CloseOrder: CloseOrderCallbackData,
    }

    #[abi(embed_v0)]
    impl PositionsHasInterface of IHasInterface<ContractState> {
        fn get_primary_interface_id(self: @ContractState) -> felt252 {
            return selector!("ekubo::positions::Positions");
        }
    }

    #[generate_trait]
    impl InternalPositionsMethods of InternalPositionsTrait {
        fn check_authorization(
            self: @ContractState, id: u64,
        ) -> (IOwnedNFTDispatcher, ContractAddress) {
            let nft = self.nft.read();
            let caller = get_caller_address();
            assert(nft.is_account_authorized(id, caller), 'UNAUTHORIZED');
            (nft, caller)
        }
    }

    pub(crate) fn amount_to_limit_order_liquidity(
        order_key: LimitOrderKey, amount: u128,
    ) -> (u128, ContractAddress) {
        let sell_token = if (order_key.tick.mag % DOUBLE_LIMIT_ORDER_TICK_SPACING).is_zero() {
            order_key.token0
        } else {
            order_key.token1
        };

        let sqrt_ratio_lower = tick_to_sqrt_ratio(order_key.tick);
        let sqrt_ratio_upper = tick_to_sqrt_ratio(
            order_key.tick + i129 { mag: LIMIT_ORDER_TICK_SPACING, sign: false },
        );

        let liquidity = if sell_token == order_key.token0 {
            max_liquidity_for_token0(sqrt_ratio_lower, sqrt_ratio_upper, amount)
        } else {
            max_liquidity_for_token1(sqrt_ratio_lower, sqrt_ratio_upper, amount)
        };

        (liquidity, sell_token)
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
                                },
                            );
                    }

                    let price = core.get_pool_price(data.pool_key);

                    // compute how much liquidity we can deposit based on token balances
                    let liquidity: u128 = max_liquidity(
                        price.sqrt_ratio,
                        tick_to_sqrt_ratio(data.bounds.lower),
                        tick_to_sqrt_ratio(data.bounds.upper),
                        data.amount0,
                        data.amount1,
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
                                },
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
                            },
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
                    let delta = core.collect_fees(data.pool_key, data.salt, data.bounds);

                    if delta.amount0.is_non_zero() {
                        core.withdraw(data.pool_key.token0, data.recipient, delta.amount0.mag);
                    }

                    if delta.amount1.is_non_zero() {
                        core.withdraw(data.pool_key.token1, data.recipient, delta.amount1.mag);
                    }

                    serialize(@delta).span()
                },
                LockCallbackData::GetPoolPrice(pool_key) => {
                    let price_before = core.get_pool_price(pool_key);

                    let pool_price = if price_before.sqrt_ratio.is_zero() {
                        price_before
                    } else {
                        core
                            .swap(
                                pool_key,
                                SwapParameters {
                                    amount: Zero::zero(),
                                    is_token1: false,
                                    sqrt_ratio_limit: min_sqrt_ratio(),
                                    skip_ahead: Zero::zero(),
                                },
                            );

                        core
                            .update_position(
                                pool_key,
                                UpdatePositionParameters {
                                    salt: 0,
                                    bounds: max_bounds(pool_key.tick_spacing),
                                    liquidity_delta: Zero::zero(),
                                },
                            );

                        core.get_pool_price(pool_key)
                    };

                    serialize(@pool_price).span()
                },
                LockCallbackData::IncreaseSaleRate(data) => {
                    let twamm = self.twamm.read();
                    let amount_delta: i129 = forward_lock(
                        core,
                        IForwardeeDispatcher { contract_address: twamm.contract_address },
                        @ForwardCallbackData::UpdateSaleRate(
                            UpdateSaleRateCallbackData {
                                salt: data.salt,
                                order_key: data.order_key,
                                sale_rate_delta: i129 {
                                    mag: data.sale_rate_delta_mag, sign: false,
                                },
                            },
                        ),
                    );

                    IERC20Dispatcher { contract_address: data.order_key.sell_token }
                        .approve(core.contract_address, amount_delta.mag.into());
                    core.pay(data.order_key.sell_token);

                    serialize(@amount_delta.mag).span()
                },
                LockCallbackData::DecreaseSaleRate(data) => {
                    let twamm = self.twamm.read();
                    let amount_delta: i129 = forward_lock(
                        core,
                        IForwardeeDispatcher { contract_address: twamm.contract_address },
                        @ForwardCallbackData::UpdateSaleRate(
                            UpdateSaleRateCallbackData {
                                salt: data.salt,
                                order_key: data.order_key,
                                sale_rate_delta: i129 { mag: data.sale_rate_delta_mag, sign: true },
                            },
                        ),
                    );

                    core
                        .withdraw(
                            data.order_key.sell_token,
                            recipient: data.recipient,
                            amount: amount_delta.mag,
                        );

                    serialize(@amount_delta.mag).span()
                },
                LockCallbackData::CollectOrderProceeds(data) => {
                    let twamm = self.twamm.read();
                    let proceeds_amount: u128 = forward_lock(
                        core,
                        IForwardeeDispatcher { contract_address: twamm.contract_address },
                        @ForwardCallbackData::CollectProceeds(
                            CollectProceedsCallbackData {
                                salt: data.salt, order_key: data.order_key,
                            },
                        ),
                    );

                    core
                        .withdraw(
                            data.order_key.buy_token,
                            recipient: data.recipient,
                            amount: proceeds_amount,
                        );

                    serialize(@proceeds_amount).span()
                },
                LockCallbackData::PlaceOrder(data) => {
                    let limit_orders = self.limit_orders.read();

                    let amount: PlaceOrderForwardCallbackResult = forward_lock(
                        core,
                        IForwardeeDispatcher { contract_address: limit_orders.contract_address },
                        @LimitOrderForwardCallbackData::PlaceOrder(
                            PlaceOrderForwardCallbackData {
                                salt: data.salt,
                                order_key: data.order_key,
                                liquidity: data.liquidity,
                            },
                        ),
                    );

                    let token = IERC20Dispatcher { contract_address: data.sell_token };
                    token.approve(core.contract_address, amount.into());
                    core.pay(data.sell_token);

                    array![].span()
                },
                LockCallbackData::CloseOrder(data) => {
                    let limit_orders = self.limit_orders.read();

                    let buy_token = if (data.order_key.tick.mag % DOUBLE_LIMIT_ORDER_TICK_SPACING)
                        .is_zero() {
                        data.order_key.token1
                    } else {
                        data.order_key.token0
                    };

                    let order_info = limit_orders
                        .get_order_info(
                            GetLimitOrderInfoRequest {
                                owner: get_contract_address(),
                                salt: data.salt,
                                order_key: data.order_key,
                            },
                        );

                    if order_info.state.liquidity.is_non_zero() {
                        let (amount0, amount1): CloseOrderForwardCallbackResult = forward_lock(
                            core,
                            IForwardeeDispatcher {
                                contract_address: limit_orders.contract_address,
                            },
                            @LimitOrderForwardCallbackData::CloseOrder(
                                CloseOrderForwardCallbackData {
                                    salt: data.salt, order_key: data.order_key,
                                },
                            ),
                        );

                        if amount0 > 0 {
                            core.withdraw(data.order_key.token0, data.recipient, amount0);
                        }
                        if amount1 > 0 {
                            core.withdraw(data.order_key.token1, data.recipient, amount1);
                        }
                    }

                    let (total0, total1) = if buy_token == data.order_key.token0 {
                        (order_info.amount0, order_info.amount1)
                    } else {
                        (order_info.amount0, order_info.amount1)
                    };

                    serialize(@(total0, total1)).span()
                },
                LockCallbackData::MoveToLimitOrderPrice(data) => {
                    let limit_orders = self.limit_orders.read();

                    let pool_key = PoolKey {
                        token0: data.order_key.token0,
                        token1: data.order_key.token1,
                        fee: 0,
                        tick_spacing: LIMIT_ORDER_TICK_SPACING,
                        extension: limit_orders.contract_address,
                    };

                    let pool_price = core.get_pool_price(pool_key);

                    let (sell_token, buy_token) = if (data
                        .order_key
                        .tick
                        .mag % DOUBLE_LIMIT_ORDER_TICK_SPACING)
                        .is_zero() {
                        (data.order_key.token0, data.order_key.token1)
                    } else {
                        (data.order_key.token1, data.order_key.token0)
                    };

                    let sqrt_ratio_lower = tick_to_sqrt_ratio(data.order_key.tick);
                    let sqrt_ratio_upper = tick_to_sqrt_ratio(
                        data.order_key.tick + i129 { mag: LIMIT_ORDER_TICK_SPACING, sign: false },
                    );

                    let (amount_sold, amount_bought) = if pool_price.sqrt_ratio.is_zero() {
                        (0, 0)
                    } else if sell_token == pool_key.token0
                        && pool_price.sqrt_ratio > sqrt_ratio_lower {
                        let delta = core
                            .swap(
                                pool_key,
                                SwapParameters {
                                    amount: i129 { mag: data.amount, sign: false },
                                    is_token1: false,
                                    sqrt_ratio_limit: sqrt_ratio_lower,
                                    skip_ahead: 0,
                                },
                            );
                        (delta.amount0.mag, delta.amount1.mag)
                    } else if sell_token == pool_key.token1
                        && pool_price.sqrt_ratio < sqrt_ratio_upper {
                        let delta = core
                            .swap(
                                pool_key,
                                SwapParameters {
                                    amount: i129 { mag: data.amount, sign: false },
                                    is_token1: true,
                                    sqrt_ratio_limit: sqrt_ratio_upper,
                                    skip_ahead: 0,
                                },
                            );
                        (delta.amount1.mag, delta.amount0.mag)
                    } else {
                        (0, 0)
                    };

                    if amount_sold > 0 {
                        let token = IERC20Dispatcher { contract_address: sell_token };
                        token.approve(core.contract_address, amount_sold.into());
                        core.pay(sell_token);
                    }

                    if amount_bought > 0 {
                        core.withdraw(buy_token, data.recipient, amount_bought);
                    }

                    serialize(@(amount_sold, amount_bought)).span()
                },
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

        fn set_limit_orders(ref self: ContractState, limit_orders_address: ContractAddress) {
            self.require_owner();
            self
                .limit_orders
                .write(ILimitOrdersDispatcher { contract_address: limit_orders_address });
        }

        fn get_twamm_address(self: @ContractState) -> ContractAddress {
            self.twamm.read().contract_address
        }

        fn get_limit_orders_address(self: @ContractState) -> ContractAddress {
            self.limit_orders.read().contract_address
        }

        fn mint(ref self: ContractState, pool_key: PoolKey, bounds: Bounds) -> u64 {
            self.mint_v2(Zero::zero())
        }

        fn mint_with_referrer(
            ref self: ContractState, pool_key: PoolKey, bounds: Bounds, referrer: ContractAddress,
        ) -> u64 {
            self.mint_v2(referrer)
        }

        fn mint_v2(ref self: ContractState, referrer: ContractAddress) -> u64 {
            let id = self.nft.read().mint(get_caller_address());

            if (referrer.is_non_zero()) {
                self.emit(PositionMintedWithReferrer { id, referrer })
            }

            id
        }

        fn check_liquidity_is_zero(
            self: @ContractState, id: u64, pool_key: PoolKey, bounds: Bounds,
        ) {
            let info = self.get_token_info(id, pool_key, bounds);
            assert(info.liquidity.is_zero(), 'LIQUIDITY_IS_NON_ZERO');
        }

        fn unsafe_burn(ref self: ContractState, id: u64) {
            let (nft, _) = self.check_authorization(id);
            nft.burn(id);
        }

        fn get_tokens_info(
            self: @ContractState, mut params: Span<GetTokenInfoRequest>,
        ) -> Span<GetTokenInfoResult> {
            let mut results: Array<GetTokenInfoResult> = array![];

            while let Option::Some(request) = params.pop_front() {
                results
                    .append(self.get_token_info(*request.id, *request.pool_key, *request.bounds));
            };

            results.span()
        }

        fn get_token_info(
            self: @ContractState, id: u64, pool_key: PoolKey, bounds: Bounds,
        ) -> GetTokenInfoResult {
            let core = self.core.read();
            let price = self.get_pool_price(pool_key);
            let get_position_result = core
                .get_position_with_fees(
                    pool_key,
                    PositionKey { owner: get_contract_address(), salt: id.into(), bounds },
                );

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
                fees1: get_position_result.fees1,
            }
        }

        fn get_orders_info_with_block_timestamp(
            self: @ContractState, mut params: Span<(u64, OrderKey)>,
        ) -> (u64, Span<OrderInfo>) {
            (get_block_timestamp(), self.get_orders_info(params))
        }

        fn get_orders_info(
            self: @ContractState, mut params: Span<(u64, OrderKey)>,
        ) -> Span<OrderInfo> {
            let mut results: Array<OrderInfo> = array![];

            while let Option::Some(request) = params.pop_front() {
                let (id, order_key) = request;
                results.append(self.get_order_info(*id, *order_key));
            };

            results.span()
        }

        fn get_order_info(self: @ContractState, id: u64, order_key: OrderKey) -> OrderInfo {
            self.twamm.read().get_order_info(get_contract_address(), id.into(), order_key)
        }

        fn deposit_amounts(
            ref self: ContractState,
            id: u64,
            pool_key: PoolKey,
            bounds: Bounds,
            amount0: u128,
            amount1: u128,
            min_liquidity: u128,
        ) -> u128 {
            self.check_authorization(id);

            let liquidity: u128 = call_core_with_callback(
                self.core.read(),
                @LockCallbackData::Deposit(
                    DepositCallbackData {
                        pool_key, salt: id.into(), bounds, min_liquidity, amount0, amount1,
                    },
                ),
            );

            liquidity
        }

        fn deposit(
            ref self: ContractState,
            id: u64,
            pool_key: PoolKey,
            bounds: Bounds,
            min_liquidity: u128,
        ) -> u128 {
            let address = get_contract_address();

            let amount0 = IERC20Dispatcher { contract_address: pool_key.token0 }
                .balanceOf(address)
                .try_into()
                .expect('AMOUNT0_OVERFLOW_U128');
            let amount1 = IERC20Dispatcher { contract_address: pool_key.token1 }
                .balanceOf(address)
                .try_into()
                .expect('AMOUNT1_OVERFLOW_U128');

            self.deposit_amounts(id, pool_key, bounds, amount0, amount1, min_liquidity)
        }

        fn withdraw(
            ref self: ContractState,
            id: u64,
            pool_key: PoolKey,
            bounds: Bounds,
            liquidity: u128,
            min_token0: u128,
            min_token1: u128,
            collect_fees: bool,
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
            let (_, caller) = self.check_authorization(id);

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
                        recipient: caller,
                    },
                ),
            );

            (delta.amount0.mag, delta.amount1.mag)
        }

        fn collect_fees(
            ref self: ContractState, id: u64, pool_key: PoolKey, bounds: Bounds,
        ) -> (u128, u128) {
            let (_, caller) = self.check_authorization(id);

            let delta: Delta = call_core_with_callback(
                self.core.read(),
                @LockCallbackData::CollectFees(
                    CollectFeesCallbackData {
                        bounds, pool_key, salt: id.into(), recipient: caller,
                    },
                ),
            );

            (delta.amount0.mag, delta.amount1.mag)
        }

        fn deposit_last(
            ref self: ContractState, pool_key: PoolKey, bounds: Bounds, min_liquidity: u128,
        ) -> u128 {
            self.deposit(self.nft.read().get_next_token_id() - 1, pool_key, bounds, min_liquidity)
        }

        fn deposit_amounts_last(
            ref self: ContractState,
            pool_key: PoolKey,
            bounds: Bounds,
            amount0: u128,
            amount1: u128,
            min_liquidity: u128,
        ) -> u128 {
            self
                .deposit_amounts(
                    self.nft.read().get_next_token_id() - 1,
                    pool_key,
                    bounds,
                    amount0,
                    amount1,
                    min_liquidity,
                )
        }

        fn mint_and_deposit(
            ref self: ContractState, pool_key: PoolKey, bounds: Bounds, min_liquidity: u128,
        ) -> (u64, u128) {
            self.mint_and_deposit_with_referrer(pool_key, bounds, min_liquidity, Zero::zero())
        }

        fn mint_and_deposit_with_referrer(
            ref self: ContractState,
            pool_key: PoolKey,
            bounds: Bounds,
            min_liquidity: u128,
            referrer: ContractAddress,
        ) -> (u64, u128) {
            let id = self.mint_v2(referrer);
            let liquidity = self.deposit(id, pool_key, bounds, min_liquidity);
            (id, liquidity)
        }

        fn mint_and_deposit_and_clear_both(
            ref self: ContractState, pool_key: PoolKey, bounds: Bounds, min_liquidity: u128,
        ) -> (u64, u128, u256, u256) {
            let (id, liquidity) = self.mint_and_deposit(pool_key, bounds, min_liquidity);
            let amount0 = self.clear(IERC20Dispatcher { contract_address: pool_key.token0 });
            let amount1 = self.clear(IERC20Dispatcher { contract_address: pool_key.token1 });
            (id, liquidity, amount0, amount1)
        }

        fn get_pool_price(self: @ContractState, pool_key: PoolKey) -> PoolPrice {
            if pool_key.extension.is_zero() {
                self.core.read().get_pool_price(pool_key)
            } else {
                call_core_with_callback::<
                    LockCallbackData, PoolPrice,
                >(self.core.read(), @LockCallbackData::GetPoolPrice(pool_key))
            }
        }

        fn mint_and_increase_sell_amount(
            ref self: ContractState, order_key: OrderKey, amount: u128,
        ) -> (u64, u128) {
            let id = self.mint_v2(Zero::zero());
            (id, self.increase_sell_amount(id, order_key, amount))
        }

        fn increase_sell_amount_last(
            ref self: ContractState, order_key: OrderKey, amount: u128,
        ) -> u128 {
            self.increase_sell_amount(self.nft.read().get_next_token_id() - 1, order_key, amount)
        }

        fn increase_sell_amount(
            ref self: ContractState, id: u64, order_key: OrderKey, amount: u128,
        ) -> u128 {
            self.check_authorization(id);

            let sale_rate = calculate_sale_rate(
                amount: amount,
                duration: to_duration(
                    max(order_key.start_time, get_block_timestamp()), order_key.end_time,
                ),
            );

            call_core_with_callback::<
                LockCallbackData, (),
            >(
                self.core.read(),
                @LockCallbackData::IncreaseSaleRate(
                    IncreaseSaleRateCallbackData {
                        order_key, salt: id.into(), sale_rate_delta_mag: sale_rate,
                    },
                ),
            );

            sale_rate
        }

        fn decrease_sale_rate_to_self(
            ref self: ContractState, id: u64, order_key: OrderKey, sale_rate_delta: u128,
        ) -> u128 {
            self.decrease_sale_rate_to(id, order_key, sale_rate_delta, get_caller_address())
        }

        fn decrease_sale_rate_to(
            ref self: ContractState,
            id: u64,
            order_key: OrderKey,
            sale_rate_delta: u128,
            recipient: ContractAddress,
        ) -> u128 {
            self.check_authorization(id);

            // it's no-op to decrease sale rate of an order that has already ended so we do nothing
            if get_block_timestamp() < order_key.end_time {
                call_core_with_callback(
                    self.core.read(),
                    @LockCallbackData::DecreaseSaleRate(
                        DecreaseSaleRateCallbackData {
                            order_key,
                            salt: id.into(),
                            sale_rate_delta_mag: sale_rate_delta,
                            recipient: recipient,
                        },
                    ),
                )
            } else {
                0
            }
        }

        fn withdraw_proceeds_from_sale_to_self(
            ref self: ContractState, id: u64, order_key: OrderKey,
        ) -> u128 {
            self.withdraw_proceeds_from_sale_to(id, order_key, get_caller_address())
        }

        fn withdraw_proceeds_from_sale_to(
            ref self: ContractState, id: u64, order_key: OrderKey, recipient: ContractAddress,
        ) -> u128 {
            self.check_authorization(id);

            call_core_with_callback(
                self.core.read(),
                @LockCallbackData::CollectOrderProceeds(
                    CollectOrderProceedsCallbackData {
                        order_key, salt: id.into(), recipient: recipient,
                    },
                ),
            )
        }

        fn swap_to_limit_order_price(
            ref self: ContractState,
            order_key: LimitOrderKey,
            amount: u128,
            recipient: ContractAddress,
        ) -> (u128, u128) {
            call_core_with_callback(
                self.core.read(),
                @LockCallbackData::MoveToLimitOrderPrice(
                    MoveToLimitOrderPriceCallbackData { order_key, amount, recipient },
                ),
            )
        }

        fn swap_to_limit_order_price_and_maybe_mint_and_place_limit_order_to(
            ref self: ContractState,
            order_key: LimitOrderKey,
            amount: u128,
            recipient: ContractAddress,
        ) -> (u128, u128, Option<(u64, u128)>) {
            let (amount_sold, amount_bought) = self
                .swap_to_limit_order_price(order_key, amount, recipient);

            let mint_result: Option<(u64, u128)> = if amount != amount_sold {
                self.maybe_mint_and_place_limit_order(order_key, amount - amount_sold)
            } else {
                Option::None
            };

            (amount_sold, amount_bought, mint_result)
        }


        fn swap_to_limit_order_price_and_maybe_mint_and_place_limit_order(
            ref self: ContractState, order_key: LimitOrderKey, amount: u128,
        ) -> (u128, u128, Option<(u64, u128)>) {
            self
                .swap_to_limit_order_price_and_maybe_mint_and_place_limit_order_to(
                    order_key, amount, recipient: get_caller_address(),
                )
        }

        fn place_limit_order(
            ref self: ContractState, id: u64, order_key: LimitOrderKey, amount: u128,
        ) -> u128 {
            self.check_authorization(id);

            let (liquidity, sell_token) = amount_to_limit_order_liquidity(order_key, amount);

            call_core_with_callback::<
                LockCallbackData, (),
            >(
                self.core.read(),
                @LockCallbackData::PlaceOrder(
                    PlaceOrderCallbackData { salt: id.into(), order_key, liquidity, sell_token },
                ),
            );

            liquidity
        }

        fn maybe_mint_and_place_limit_order(
            ref self: ContractState, order_key: LimitOrderKey, amount: u128,
        ) -> Option<(u64, u128)> {
            // Note: this calculation is repeated inside place_limit_order
            //  A refactoring could make this code more efficient, but we are prioritizing
            //  avoiding calling this function in the case where creation of the limit order
            //  will fail
            let (liquidity, _) = amount_to_limit_order_liquidity(order_key, amount);
            if liquidity.is_non_zero() {
                let id = self.mint_v2(Zero::zero());
                let liquidity = self.place_limit_order(id, order_key, amount);
                Option::Some((id, liquidity))
            } else {
                Option::None
            }
        }

        fn mint_and_place_limit_order(
            ref self: ContractState, order_key: LimitOrderKey, amount: u128,
        ) -> (u64, u128) {
            self.maybe_mint_and_place_limit_order(order_key, amount).expect('Insufficient amount')
        }

        fn close_limit_order(
            ref self: ContractState, id: u64, order_key: LimitOrderKey,
        ) -> (u128, u128) {
            self.close_limit_order_to(id, order_key, get_caller_address())
        }

        fn close_limit_order_to(
            ref self: ContractState, id: u64, order_key: LimitOrderKey, recipient: ContractAddress,
        ) -> (u128, u128) {
            self.check_authorization(id);
            call_core_with_callback(
                self.core.read(),
                @LockCallbackData::CloseOrder(
                    CloseOrderCallbackData { salt: id.into(), order_key, recipient },
                ),
            )
        }

        fn get_limit_orders_info(
            self: @ContractState, mut params: Span<(u64, LimitOrderKey)>,
        ) -> Span<GetLimitOrderInfoResult> {
            let mut requests: Array<GetLimitOrderInfoRequest> = array![];

            let this_address = get_contract_address();
            while let Option::Some(request) = params.pop_front() {
                let (id, order_key) = request;
                requests
                    .append(
                        GetLimitOrderInfoRequest {
                            owner: this_address, salt: (*id).into(), order_key: *order_key,
                        },
                    );
            };

            self.limit_orders.read().get_order_infos(requests.span())
        }
    }
}
