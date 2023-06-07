mod nft {
    use starknet::{contract_address_const};
    use ekubo::tests::helper::{deploy_core, deploy_positions};
    use ekubo::interfaces::positions::{
        IPositionsDispatcher, IPositionsDispatcherTrait, PositionKey
    };
    use ekubo::types::keys::{PoolKey};

    #[test]
    #[available_gas(300000000)]
    fn test_nft_balance_of() {
        let core = deploy_core(contract_address_const::<1>());
        let positions = deploy_positions(core);

        let recipient = contract_address_const::<2>();
        assert(positions.balance_of(recipient) == u256 { low: 0, high: 0 }, 'balance check');
        // note we do not check the validity of the position key, it only comes into play when trying to add liquidity fails
        positions
            .mint(
                recipient,
                PositionKey {
                    pool_key: PoolKey {
                        token0: contract_address_const::<0>(),
                        token1: contract_address_const::<0>(),
                        fee: Default::default(),
                        tick_spacing: Default::default(),
                    }, tick_lower: Default::default(), tick_upper: Default::default(),
                }
            );
        assert(positions.balance_of(recipient) == u256 { low: 1, high: 0 }, 'balance check after');
    }
}
