use ekubo::interfaces::erc20::{IERC20Dispatcher};

#[starknet::interface]
trait IAssetRecovery<TStorage> {
    // Send the balance of a given token to the owner
    fn recover(ref self: TStorage, token: IERC20Dispatcher);
}

#[starknet::contract]
mod AssetRecovery {
    use ekubo::interfaces::erc20::{IERC20DispatcherTrait};
    use ekubo::owner::{check_owner_only};
    use starknet::{get_contract_address};
    use super::{IERC20Dispatcher, IAssetRecovery};

    #[storage]
    struct Storage {}

    #[external(v0)]
    impl AssetRecoveryImpl of IAssetRecovery<ContractState> {
        fn recover(ref self: ContractState, token: IERC20Dispatcher) {
            let owner = check_owner_only();
            token.transfer(owner, token.balanceOf(get_contract_address()));
        }
    }
}
