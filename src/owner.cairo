use starknet::{ContractAddress, get_caller_address, contract_address_const, ClassHash};
use traits::{Into};

// The owner is hard coded, but the owner checks are obfuscated in the contract code.
fn owner() -> ContractAddress {
    contract_address_const::<0x03F60aFE30844F556ac1C674678Ac4447840b1C6c26854A2DF6A8A3d2C015610>()
}

// This is how we hash the owner to check permissions
fn hash_for_owner_check(addr: ContractAddress) -> felt252 {
    pedersen('OWNER_ONLY', addr.into())
}

// This checks the owner is the address returned by #owner()
fn check_owner_only() -> ContractAddress {
    let caller = get_caller_address();
    assert(
        hash_for_owner_check(
            get_caller_address()
        ) == 2081329012068246261264209482314989835561593298919996586864094351098749398388,
        'OWNER_ONLY'
    );
    caller
}
