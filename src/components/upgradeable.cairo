// Any contract that is upgradeable must implement this
#[starknet::interface]
trait IHasInterface<TContractState> {
    fn get_primary_interface_id(self: @TContractState) -> felt252;
}

#[starknet::component]
mod Upgradeable {
    use core::array::SpanTrait;
    use core::num::traits::{Zero};
    use core::result::ResultTrait;
    use ekubo::components::owner::{check_owner_only};
    use ekubo::interfaces::upgradeable::{IUpgradeable};
    use starknet::{ClassHash, replace_class_syscall, get_contract_address, library_call_syscall};
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

            let mut result = library_call_syscall(
                class_hash, selector!("get_primary_interface_id"), array![].span()
            )
                .expect('MISSING_PRIMARY_INTERFACE_ID');

            let next_id = result.pop_front().expect('INVALID_RETURN_DATA');

            assert(@id == next_id, 'UPGRADEABLE_ID_MISMATCH');

            replace_class_syscall(class_hash);

            self.emit(ClassHashReplaced { new_class_hash: class_hash });
        }
    }
}
