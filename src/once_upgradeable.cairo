use starknet::{ClassHash, ContractAddress};

#[starknet::interface]
trait IOnceUpgradeable<TStorage> {
    fn replace(ref self: TStorage, class_hash: ClassHash);
}

#[starknet::contract]
mod OnceUpgradeable {
    use ekubo::core::Core::{Event, OwnerChanged};
    use super::{IOnceUpgradeable, ContractAddress, ClassHash};
    use starknet::{get_caller_address};
    use starknet::syscalls::{replace_class_syscall};

    #[storage]
    struct Storage {
        owner: ContractAddress, 
    }

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress) {
        self.owner.write(owner);
        self.emit(Event::OwnerChanged(OwnerChanged { new_owner: owner }));
    }

    #[external(v0)]
    impl OnceUpgradeableImpl of IOnceUpgradeable<ContractState> {
        fn replace(ref self: ContractState, class_hash: ClassHash) {
            assert(get_caller_address() == self.owner.read(), 'ONLY_OWNER');
            replace_class_syscall(class_hash);
        }
    }
}
