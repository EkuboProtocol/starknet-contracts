use starknet::ContractAddress;

/// Interface for the Privacy Extension
/// This extension enables privacy-preserving swaps by only allowing authorized
/// Privacy Pool Accounts to interact with privacy-enabled pools.
#[starknet::interface]
pub trait IPrivacyExtension<TContractState> {
    /// Register a Privacy Pool Account as authorized to use privacy pools
    /// Only callable by the contract owner
    fn register_account(ref self: TContractState, account: ContractAddress);

    /// Unregister a Privacy Pool Account
    /// Only callable by the contract owner
    fn unregister_account(ref self: TContractState, account: ContractAddress);

    /// Check if an account is authorized to use privacy pools
    fn is_authorized(self: @TContractState, account: ContractAddress) -> bool;

    /// Get the number of swaps executed through this extension
    fn get_swap_count(self: @TContractState) -> u64;

    /// Updates the call points for the latest version of this extension
    fn set_call_points(ref self: TContractState);
}

/// Events emitted by the Privacy Extension
#[derive(Drop, starknet::Event)]
pub struct AccountRegistered {
    #[key]
    pub account: ContractAddress,
}

#[derive(Drop, starknet::Event)]
pub struct AccountUnregistered {
    #[key]
    pub account: ContractAddress,
}

#[derive(Drop, starknet::Event)]
pub struct PrivateSwapExecuted {
    #[key]
    pub pool_key_hash: felt252,
    pub swap_index: u64,
}

