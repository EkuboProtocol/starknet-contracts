#[starknet::component]
mod Upgradeable {
    use ekubo::interfaces::upgradeable::{IUpgradeable};
    use ekubo::owner::{check_owner_only};
    use starknet::{ClassHash, replace_class_syscall};
    use core::zeroable::{Zeroable};

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
        TContractState, +HasComponent<TContractState>
    > of IUpgradeable<ComponentState<TContractState>> {
        fn replace_class_hash(ref self: ComponentState<TContractState>, class_hash: ClassHash) {
            assert(!class_hash.is_zero(), 'INVALID_CLASS_HASH');
            check_owner_only();
            replace_class_syscall(class_hash);
            self.emit(ClassHashReplaced { new_class_hash: class_hash });
        }
    }
}
