use starknet::ClassHash;

#[starknet::interface]
pub trait IUpgradeable<TContractState> {
    // Update the class hash of the contract.
    fn replace_class_hash(ref self: TContractState, class_hash: ClassHash);
}

