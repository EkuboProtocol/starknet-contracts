mod nft {
    use starknet::{contract_address_const};
    use ekubo::tests::helper::{deploy_core, deploy_positions};
    use ekubo::interfaces::erc721::{IERC721Dispatcher, IERC721DispatcherTrait};

    #[test]
    #[available_gas(300000000)]
    fn test_nft() {
        let core = deploy_core(contract_address_const::<1>());
        let positions = deploy_positions(core);

        assert(
            positions.balance_of(contract_address_const::<1>()) == u256 { low: 0, high: 0 },
            'balance check'
        );
    }
}
