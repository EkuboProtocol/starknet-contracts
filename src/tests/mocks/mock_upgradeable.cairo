use starknet::{ClassHash};

#[starknet::interface]
trait IMockUpgradeable<TStorage> {
    // Update the class hash of the contract.
    fn replace_class_hash(ref self: TStorage, class_hash: ClassHash);
}


// Mock upgradeable contract. This contract only implements the upgradeable
// component, and does not have any other functionality.
#[starknet::contract]
mod MockUpgradeable {
    use ekubo::upgradeable::{Upgradeable as upgradeable_component};

    component!(path: upgradeable_component, storage: upgradeable, event: UpgradeableEvent);

    #[abi(embed_v0)]
    impl Upgradeable = upgradeable_component::UpgradeableImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        upgradeable: upgradeable_component::Storage
    }

    #[derive(starknet::Event, Drop)]
    #[event]
    enum Event {
        #[flat]
        UpgradeableEvent: upgradeable_component::Event,
    }
}
