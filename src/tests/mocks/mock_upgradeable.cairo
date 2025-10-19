// Mock upgradeable contract. This contract only implements the upgradeable
// component, and does not have any other functionality.
#[starknet::contract]
pub mod MockUpgradeable {
    use starknet::ContractAddress;
    use crate::components::owned::Owned as owned_component;
    use crate::components::upgradeable::{IHasInterface, Upgradeable as upgradeable_component};

    component!(path: owned_component, storage: owned, event: OwnedEvent);
    #[abi(embed_v0)]
    impl Owned = owned_component::OwnedImpl<ContractState>;
    impl OwnableImpl = owned_component::OwnableImpl<ContractState>;

    component!(path: upgradeable_component, storage: upgradeable, event: UpgradeableEvent);
    #[abi(embed_v0)]
    impl Upgradeable = upgradeable_component::UpgradeableImpl<ContractState>;

    #[abi(embed_v0)]
    impl MockUpgradeableHasInterface of IHasInterface<ContractState> {
        fn get_primary_interface_id(self: @ContractState) -> felt252 {
            return selector!("ekubo::tests::mocks::mock_upgradeable::MockUpgradeable");
        }
    }

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress) {
        self.initialize_owned(owner);
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
