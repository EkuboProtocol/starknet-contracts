use core::num::traits::{Zero};
use ekubo::asset_recovery::{IAssetRecoveryDispatcher, IAssetRecoveryDispatcherTrait};
use ekubo::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
use ekubo::owner::{owner};
use ekubo::tests::helper::{deploy_asset_recovery, deploy_mock_token};
use ekubo::tests::mocks::mock_erc20::IMockERC20DispatcherTrait;
use starknet::testing::{set_contract_address};

#[test]
#[should_panic(expected: ('OWNER_ONLY', 'ENTRYPOINT_FAILED',))]
fn test_recover_must_be_called_by_owner() {
    let ar = deploy_asset_recovery();
    let token = deploy_mock_token();
    ar.recover(IERC20Dispatcher { contract_address: token.contract_address });
}


#[test]
fn test_recover_by_owner_no_tokens() {
    let ar = deploy_asset_recovery();
    let token = deploy_mock_token();
    set_contract_address(owner());
    ar.recover(IERC20Dispatcher { contract_address: token.contract_address });
}

#[test]
fn test_recover_by_owner_with_tokens() {
    let ar = deploy_asset_recovery();
    let token = deploy_mock_token();
    token.increase_balance(ar.contract_address, 100);
    set_contract_address(owner());
    let token = IERC20Dispatcher { contract_address: token.contract_address };

    assert(token.balanceOf(owner()).is_zero(), 'transferred');
    assert(token.balanceOf(ar.contract_address) == 100, 'transferred');
    ar.recover(token);
    assert(token.balanceOf(owner()) == 100, 'transferred');
    assert(token.balanceOf(ar.contract_address).is_zero(), 'transferred');
}
