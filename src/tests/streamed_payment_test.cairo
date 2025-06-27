use ekubo::streamed_payment::IStreamedPaymentDispatcherTrait;
use ekubo::tests::helper::{Deployer, DeployerTrait};
use starknet::testing::{set_block_timestamp, set_contract_address};
use starknet::{ContractAddress, get_block_timestamp, get_contract_address};
use super::mock_erc20::MockERC20IERC20ImplTrait;

fn recipient() -> ContractAddress {
    0x12345678.try_into().unwrap()
}

#[test]
fn test_create_payment_regular_flow() {
    let mut d: Deployer = Default::default();
    let streamed_payment = d.deploy_streamed_payment();
    let token = d.deploy_mock_token_with_balance(get_contract_address(), 1000);
    let start = get_block_timestamp();
    token.approve(streamed_payment.contract_address, 100);
    let id = streamed_payment
        .create_stream(
            token_address: token.contract_address,
            amount: 100,
            recipient: recipient(),
            start_time: start + 1,
            end_time: start + 24,
        );
    assert_eq!(streamed_payment.collect(id), 0);
    set_block_timestamp(start + 11);
    assert_eq!(streamed_payment.collect(id), 43);
    assert_eq!(streamed_payment.collect(id), 0);
    set_block_timestamp(start + 17);
    assert_eq!(streamed_payment.collect(id), 26);
    assert_eq!(streamed_payment.collect(id), 0);
    set_block_timestamp(start + 22);
    assert_eq!(streamed_payment.collect(id), 22);
    assert_eq!(streamed_payment.collect(id), 0);
    set_block_timestamp(start + 24);
    assert_eq!(streamed_payment.collect(id), 9);
    assert_eq!(streamed_payment.collect(id), 0);
}

#[test]
fn test_start_in_past() {
    let mut d: Deployer = Default::default();
    let streamed_payment = d.deploy_streamed_payment();
    let token = d.deploy_mock_token_with_balance(get_contract_address(), 1000);
    let start = 100;
    set_block_timestamp(start + 1);
    token.approve(streamed_payment.contract_address, 100);
    let id = streamed_payment
        .create_stream(
            token_address: token.contract_address,
            amount: 100,
            recipient: recipient(),
            start_time: start,
            end_time: start + 15,
        );
    assert_eq!(streamed_payment.collect(id), 6);
    assert_eq!(streamed_payment.collect(id), 0);
    set_block_timestamp(start + 10);
    assert_eq!(streamed_payment.collect(id), 60);
    assert_eq!(streamed_payment.collect(id), 0);
    set_block_timestamp(start + 14);
    assert_eq!(streamed_payment.collect(id), 27);
    assert_eq!(streamed_payment.collect(id), 0);
    set_block_timestamp(start + 15);
    assert_eq!(streamed_payment.collect(id), 7);
    assert_eq!(streamed_payment.collect(id), 0);
}


#[test]
fn test_cancel_in_middle() {
    let mut d: Deployer = Default::default();
    let streamed_payment = d.deploy_streamed_payment();
    let token = d.deploy_mock_token_with_balance(get_contract_address(), 1000);
    let start = 100;
    set_block_timestamp(start + 1);
    token.approve(streamed_payment.contract_address, 100);
    let id = streamed_payment
        .create_stream(
            token_address: token.contract_address,
            amount: 100,
            recipient: recipient(),
            start_time: start,
            end_time: start + 15,
        );
    assert_eq!(streamed_payment.collect(id), 6);
    assert_eq!(streamed_payment.collect(id), 0);
    set_block_timestamp(start + 10);
    assert_eq!(streamed_payment.cancel(id), 34);
    assert_eq!(token.balanceOf(recipient()), 66);
    assert_eq!(streamed_payment.collect(id), 0);
    set_block_timestamp(start + 14);
    assert_eq!(streamed_payment.collect(id), 0);
    set_block_timestamp(start + 15);
    assert_eq!(streamed_payment.collect(id), 0);
}


#[test]
fn test_cancel_before_start() {
    let mut d: Deployer = Default::default();
    let streamed_payment = d.deploy_streamed_payment();
    let token = d.deploy_mock_token_with_balance(get_contract_address(), 1000);
    let start = 100;
    set_block_timestamp(start - 1);
    token.approve(streamed_payment.contract_address, 100);
    let id = streamed_payment
        .create_stream(
            token_address: token.contract_address,
            amount: 100,
            recipient: recipient(),
            start_time: start,
            end_time: start + 15,
        );
    assert_eq!(streamed_payment.cancel(id), 100);
    set_block_timestamp(start);
    assert_eq!(streamed_payment.collect(id), 0);
    set_block_timestamp(start + 1);
    assert_eq!(streamed_payment.collect(id), 0);
    set_block_timestamp(start + 14);
    assert_eq!(streamed_payment.collect(id), 0);
    set_block_timestamp(start + 15);
    assert_eq!(streamed_payment.collect(id), 0);
}


#[test]
fn test_cancel_after_end() {
    let mut d: Deployer = Default::default();
    let streamed_payment = d.deploy_streamed_payment();
    let token = d.deploy_mock_token_with_balance(get_contract_address(), 1000);
    let start = 100;
    set_block_timestamp(start + 15);
    token.approve(streamed_payment.contract_address, 100);
    let id = streamed_payment
        .create_stream(
            token_address: token.contract_address,
            amount: 100,
            recipient: recipient(),
            start_time: start,
            end_time: start + 15,
        );
    assert_eq!(streamed_payment.cancel(id), 0);
    assert_eq!(streamed_payment.collect(id), 0);
}


#[test]
#[should_panic(expected: ('Only owner can cancel', 'ENTRYPOINT_FAILED'))]
fn test_cancel_by_non_owner() {
    let mut d: Deployer = Default::default();
    let streamed_payment = d.deploy_streamed_payment();
    let token = d.deploy_mock_token_with_balance(get_contract_address(), 1000);
    let start = 100;
    set_block_timestamp(start + 15);
    token.approve(streamed_payment.contract_address, 100);
    let id = streamed_payment
        .create_stream(
            token_address: token.contract_address,
            amount: 100,
            recipient: recipient(),
            start_time: start,
            end_time: start + 15,
        );

    set_contract_address(recipient());
    assert_eq!(streamed_payment.cancel(id), 0);
}


#[test]
#[should_panic(expected: ('End time < start time', 'ENTRYPOINT_FAILED'))]
fn test_create_stream_end_time_gt_start_time() {
    let mut d: Deployer = Default::default();
    let streamed_payment = d.deploy_streamed_payment();
    let token = d.deploy_mock_token_with_balance(get_contract_address(), 1000);
    token.approve(streamed_payment.contract_address, 100);
    streamed_payment
        .create_stream(
            token_address: token.contract_address,
            amount: 100,
            recipient: recipient(),
            start_time: 3,
            end_time: 1,
        );
}


#[test]
fn test_stream_ownership_transfer() {
    let mut d: Deployer = Default::default();
    let streamed_payment = d.deploy_streamed_payment();
    let token = d.deploy_mock_token_with_balance(get_contract_address(), 1000);
    token.approve(streamed_payment.contract_address, 100);
    let id = streamed_payment
        .create_stream(
            token_address: token.contract_address,
            amount: 100,
            recipient: recipient(),
            start_time: 3,
            end_time: 5,
        );

    assert_eq!(streamed_payment.get_stream_info(id).owner, get_contract_address());
    let new_owner: ContractAddress = 0x4567.try_into().unwrap();
    streamed_payment.transfer_stream_ownership(id, new_owner);
    assert_eq!(streamed_payment.get_stream_info(id).owner, new_owner);
}

#[test]
#[should_panic(expected: ('Only owner can transfer', 'ENTRYPOINT_FAILED'))]
fn test_stream_ownership_transfer_fails_if_not_owner() {
    let mut d: Deployer = Default::default();
    let streamed_payment = d.deploy_streamed_payment();
    let token = d.deploy_mock_token_with_balance(get_contract_address(), 1000);
    token.approve(streamed_payment.contract_address, 100);
    let id = streamed_payment
        .create_stream(
            token_address: token.contract_address,
            amount: 100,
            recipient: recipient(),
            start_time: 3,
            end_time: 5,
        );

    set_contract_address(recipient());
    let new_owner: ContractAddress = 0x4567.try_into().unwrap();
    streamed_payment.transfer_stream_ownership(id, new_owner);
}


#[test]
fn test_stream_recipient_transfer() {
    let mut d: Deployer = Default::default();
    let streamed_payment = d.deploy_streamed_payment();
    let token = d.deploy_mock_token_with_balance(get_contract_address(), 1000);
    token.approve(streamed_payment.contract_address, 100);
    let id = streamed_payment
        .create_stream(
            token_address: token.contract_address,
            amount: 100,
            recipient: recipient(),
            start_time: 3,
            end_time: 5,
        );

    assert_eq!(streamed_payment.get_stream_info(id).recipient, recipient());
    let new_recipient: ContractAddress = 0x8901.try_into().unwrap();
    streamed_payment.change_stream_recipient(id, new_recipient);
    assert_eq!(streamed_payment.get_stream_info(id).recipient, new_recipient);
}


#[test]
fn test_stream_recipient_transfer_by_recipient() {
    let mut d: Deployer = Default::default();
    let streamed_payment = d.deploy_streamed_payment();
    let token = d.deploy_mock_token_with_balance(get_contract_address(), 1000);
    token.approve(streamed_payment.contract_address, 100);
    let id = streamed_payment
        .create_stream(
            token_address: token.contract_address,
            amount: 100,
            recipient: recipient(),
            start_time: 3,
            end_time: 5,
        );

    assert_eq!(streamed_payment.get_stream_info(id).recipient, recipient());
    let new_recipient: ContractAddress = 0x8901.try_into().unwrap();
    set_contract_address(recipient());
    streamed_payment.change_stream_recipient(id, new_recipient);
    assert_eq!(streamed_payment.get_stream_info(id).recipient, new_recipient);
}


#[test]
#[should_panic(expected: ('Only owner/recipient can change', 'ENTRYPOINT_FAILED'))]
fn test_stream_recipient_transfer_fails_if_not_owner_or_recipient() {
    let mut d: Deployer = Default::default();
    let streamed_payment = d.deploy_streamed_payment();
    let token = d.deploy_mock_token_with_balance(get_contract_address(), 1000);
    token.approve(streamed_payment.contract_address, 100);
    let id = streamed_payment
        .create_stream(
            token_address: token.contract_address,
            amount: 100,
            recipient: recipient(),
            start_time: 3,
            end_time: 5,
        );

    let new_recipient: ContractAddress = 0x8901.try_into().unwrap();
    set_contract_address(new_recipient);
    streamed_payment.change_stream_recipient(id, new_recipient);
}

