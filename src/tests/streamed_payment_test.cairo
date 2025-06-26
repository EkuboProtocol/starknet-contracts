use ekubo::streamed_payment::IStreamedPaymentDispatcherTrait;
use ekubo::tests::helper::{Deployer, DeployerTrait};
use starknet::testing::set_block_timestamp;
use starknet::{ContractAddress, get_block_timestamp, get_contract_address};
use super::mock_erc20::MockERC20IERC20ImplTrait;

fn recipient() -> ContractAddress {
    0x12345678.try_into().unwrap()
}

#[test]
fn test_streamed_payment_create_payment_regular_flow() {
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
fn test_streamed_payment_start_in_past() {
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
fn test_streamed_payment_cancel_in_middle() {
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
fn test_streamed_payment_cancel_before_start() {
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

