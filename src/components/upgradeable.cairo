// Any contract that is upgradeable must implement this
#[starknet::interface]
trait IHasInterface<TContractState> {
    fn get_primary_interface_id(self: @TContractState) -> felt252;
}

#[starknet::component]
mod Upgradeable {
    use core::num::traits::{Zero};
    use ekubo::components::owner::{check_owner_only};
    use ekubo::interfaces::upgradeable::{IUpgradeable};
    use starknet::{ClassHash, replace_class_syscall, get_contract_address};
    use super::{IHasInterface, IHasInterfaceDispatcher, IHasInterfaceDispatcherTrait};

    #[storage]
    struct Storage {}

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        ClassHashReplaced: ClassHashReplaced
    }

    #[derive(starknet::Event, Drop)]
    struct ClassHashReplaced {
        new_class_hash: ClassHash,
    }

    #[embeddable_as(UpgradeableImpl)]
    impl Upgradeable<
        TContractState, +HasComponent<TContractState>, +IHasInterface<TContractState>
    > of IUpgradeable<ComponentState<TContractState>> {
        fn replace_class_hash(ref self: ComponentState<TContractState>, class_hash: ClassHash) {
            assert(!class_hash.is_zero(), 'INVALID_CLASS_HASH');
            check_owner_only();

            let has_interface_dispatcher = IHasInterfaceDispatcher {
                contract_address: get_contract_address()
            };

            let id = has_interface_dispatcher.get_primary_interface_id();

            replace_class_syscall(class_hash);

            assert(
                id == has_interface_dispatcher.get_primary_interface_id(), 'UPGRADEABLE_ID_MISMATCH'
            );

            self.emit(ClassHashReplaced { new_class_hash: class_hash });
        }
    }
}
