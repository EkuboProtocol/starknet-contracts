use starknet::{ContractAddress};

#[starknet::interface]
trait IOwned<TContractState> {
    // Returns the current owner of the contract
    fn get_owner(self: @TContractState) -> ContractAddress;
    // Transfers the ownership to a new address
    fn transfer_ownership(ref self: TContractState, new_owner: ContractAddress);
}

trait Ownable<TContractState> {
    // Any ownable contract can require that the owner is calling a particular method
    fn require_owner(self: @TContractState) -> ContractAddress;
}

#[starknet::component]
mod Owned {
    use core::num::traits::{Zero};
    use starknet::{get_caller_address, contract_address_const};
    use super::{ContractAddress, IOwned, Ownable};

    // The owner is hard coded, but the owner checks are obfuscated in the contract code.
    fn default_owner() -> ContractAddress {
        contract_address_const::<
            0x03F60aFE30844F556ac1C674678Ac4447840b1C6c26854A2DF6A8A3d2C015610
        >()
    }

    #[storage]
    struct Storage {
        owner: ContractAddress,
    }

    #[derive(starknet::Event, Drop)]
    struct OwnershipTransferred {
        old_owner: ContractAddress,
        new_owner: ContractAddress,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        OwnershipTransferred: OwnershipTransferred
    }

    impl OwnableImpl<
        TContractState, +HasComponent<TContractState>
    > of Ownable<ComponentState<TContractState>> {
        fn require_owner(self: @ComponentState<TContractState>) -> ContractAddress {
            let owner = self.get_owner();
            assert(get_caller_address() == owner, 'OWNER_ONLY');
            return owner;
        }
    }

    #[embeddable_as(OwnedImpl)]
    impl Owned<
        TContractState, +HasComponent<TContractState>
    > of IOwned<ComponentState<TContractState>> {
        fn get_owner(self: @ComponentState<TContractState>) -> ContractAddress {
            let owner = self.owner.read();
            // remove after ownership is transferred
            if (owner.is_zero()) {
                default_owner()
            } else {
                owner
            }
        }

        fn transfer_ownership(
            ref self: ComponentState<TContractState>, new_owner: ContractAddress
        ) {
            let old_owner = self.require_owner();
            self.owner.write(new_owner);
            self.emit(OwnershipTransferred { old_owner, new_owner });
        }
    }
}
