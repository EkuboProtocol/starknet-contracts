use starknet::{ClassHash};

// Mock upgradeable contract. This contract only implements the upgradeable
// component, and does not have any other functionality.
#[starknet::contract]
mod MockUpgradeable {
    use ekubo::components::owned::{Owned as owned_component};
    use ekubo::components::upgradeable::{Upgradeable as upgradeable_component, IHasInterface};

    component!(path: owned_component, storage: owned, event: OwnedEvent);
    #[abi(embed_v0)]
    impl Owned = owned_component::OwnedImpl<ContractState>;

    component!(path: upgradeable_component, storage: upgradeable, event: UpgradeableEvent);
    #[abi(embed_v0)]
    impl Upgradeable = upgradeable_component::UpgradeableImpl<ContractState>;

    #[external(v0)]
    impl MockUpgradeableHasInterface of IHasInterface<ContractState> {
        fn get_primary_interface_id(self: @ContractState) -> felt252 {
            return selector!("ekubo::tests::mocks::mock_upgradeable::MockUpgradeable");
        }
    }

    #[storage]
    struct Storage {
        #[substorage(v0)]
        upgradeable: upgradeable_component::Storage,
        #[substorage(v0)]
        owned: owned_component::Storage,
    }

    #[derive(starknet::Event, Drop)]
    #[event]
    enum Event {
        #[flat]
        UpgradeableEvent: upgradeable_component::Event,
        OwnedEvent: owned_component::Event,
    }
}
