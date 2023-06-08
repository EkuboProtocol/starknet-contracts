use ekubo::tests::mocks::mock_erc20::IMockERC20DispatcherTrait;
mod nft {
    use starknet::{contract_address_const};
    use starknet::testing::{set_caller_address};
    use ekubo::tests::helper::{deploy_core, setup_pool, deploy_positions, FEE_ONE_PERCENT};
    use ekubo::tests::mocks::mock_erc20::{IMockERC20Dispatcher, IMockERC20DispatcherTrait};
    use ekubo::interfaces::core::{IEkuboDispatcher, IEkuboDispatcherTrait};
    use ekubo::interfaces::positions::{IPositionsDispatcher, IPositionsDispatcherTrait, Bounds};
    use ekubo::types::keys::{PoolKey};
    use ekubo::types::i129::{i129};
    use debug::PrintTrait;

    #[test]
    #[available_gas(300000000)]
    fn test_maybe_initialize_pool_twice() {
        let core = deploy_core(contract_address_const::<1>());
        let positions = deploy_positions(core);
        let pool_key = PoolKey {
            token0: contract_address_const::<1>(),
            token1: contract_address_const::<2>(),
            fee: Default::default(),
            tick_spacing: 1,
        };
        positions.maybe_initialize_pool(pool_key, i129 { mag: 0, sign: false });
        positions.maybe_initialize_pool(pool_key, i129 { mag: 1000, sign: false });

        assert(core.get_pool(pool_key).sqrt_ratio == u256 { low: 0, high: 1 }, 'ratio');
    }


    #[test]
    #[available_gas(300000000)]
    fn test_nft_balance_of() {
        let core = deploy_core(contract_address_const::<1>());
        let positions = deploy_positions(core);

        let recipient = contract_address_const::<2>();
        assert(positions.balance_of(recipient) == u256 { low: 0, high: 0 }, 'balance check');
        // note we do not check the validity of the position key, it only comes into play when trying to add liquidity fails
        assert(
            positions
                .mint(
                    recipient,
                    pool_key: PoolKey {
                        token0: contract_address_const::<0>(),
                        token1: contract_address_const::<0>(),
                        fee: Default::default(),
                        tick_spacing: Default::default(),
                    },
                    bounds: Bounds {
                        tick_lower: Default::default(), tick_upper: Default::default(), 
                    }
                ) == 1,
            'token id'
        );
        assert(positions.balance_of(recipient) == u256 { low: 1, high: 0 }, 'balance check after');
    }

    #[test]
    #[available_gas(20000000)]
    fn test_deposit_liquidity_no_tokens() {
        let caller = contract_address_const::<1>();
        set_caller_address(caller);
        let setup = setup_pool(caller, FEE_ONE_PERCENT, 1, i129 { mag: 0, sign: false });
        let positions = deploy_positions(setup.core);
        let bounds = Bounds {
            tick_lower: i129 { mag: 1000, sign: true }, tick_upper: i129 { mag: 1000, sign: false }, 
        };
        let token_id = positions.mint(caller, pool_key: setup.pool_key, bounds: bounds);
        assert(token_id == 1, 'token id');
        setup.token0.increase_balance(positions.contract_address, 100000000);
        setup.token1.increase_balance(positions.contract_address, 100000000);
        let liquidity = positions
            .deposit_last(pool_key: setup.pool_key, bounds: bounds, min_liquidity: 100);
        assert(liquidity == 200050104166, 'liquidity');
    }
}
