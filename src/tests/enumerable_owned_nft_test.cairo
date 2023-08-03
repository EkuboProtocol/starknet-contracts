use ekubo::tests::helper::{deploy_enumerable_owned_nft};
use ekubo::interfaces::erc721::{IERC721Dispatcher, IERC721DispatcherTrait};
use ekubo::enumerable_owned_nft::{
    IEnumerableOwnedNFTDispatcher, IEnumerableOwnedNFTDispatcherTrait
};
use starknet::{contract_address_const};
use array::{ArrayTrait};
use starknet::testing::{ContractAddress, set_contract_address};
use option::{OptionTrait};
use traits::{Into};
use zeroable::{Zeroable};

fn default_controller() -> ContractAddress {
    contract_address_const::<12345678>()
}

fn switch_to_controller() {
    set_contract_address(default_controller());
}

fn deploy_default() -> (IEnumerableOwnedNFTDispatcher, IERC721Dispatcher) {
    deploy_enumerable_owned_nft(
        default_controller(), 'Ekubo Position NFT', 'EpNFT', 'https://z.ekubo.org/'
    )
}

#[test]
#[available_gas(300000000)]
fn test_nft_name_symbol() {
    let (_, nft) = deploy_enumerable_owned_nft(
        default_controller(), 'Ekubo Position NFT', 'EpNFT', 'https://z.ekubo.org/'
    );
    assert(nft.name() == 'Ekubo Position NFT', 'name');
    assert(nft.symbol() == 'EpNFT', 'symbol');
    assert(nft.tokenUri(u256 { low: 1, high: 0 }) == 'https://z.ekubo.org/1', 'tokenUri');
    assert(nft.token_uri(u256 { low: 1, high: 0 }) == 'https://z.ekubo.org/1', 'token_uri');
}

#[test]
#[available_gas(300000000)]
fn test_nft_indexing_token_ids() {
    let (controller, nft) = deploy_enumerable_owned_nft(
        default_controller(), 'Ekubo Position NFT', 'EpNFT', 'https://z.ekubo.org/'
    );

    switch_to_controller();

    let owner = contract_address_const::<912345>();
    let other = contract_address_const::<9123456>();

    assert(nft.balanceOf(owner) == 0, 'balance start');
    let mut all = controller.get_all_owned_tokens(owner);
    assert(all.len() == 0, 'len before');
    let token_id = controller.mint(owner);

    assert(nft.balanceOf(owner) == 1, 'balance after');
    all = controller.get_all_owned_tokens(owner);
    assert(all.len() == 1, 'len after');
    set_contract_address(owner);
    nft.transferFrom(owner, other, all.pop_front().unwrap().into());

    assert(nft.balanceOf(owner) == 0, 'balance after transfer');
    all = controller.get_all_owned_tokens(owner);
    assert(all.len() == 0, 'len after transfer');

    assert(nft.balanceOf(other) == 1, 'balance other transfer');
    all = controller.get_all_owned_tokens(other);
    assert(all.len() == 1, 'len other');
    assert(all.pop_front().unwrap().into() == token_id, 'token other');

    switch_to_controller();
    let token_id_2 = controller.mint(owner);
    set_contract_address(other);
    nft.transferFrom(other, owner, token_id.into());

    all = controller.get_all_owned_tokens(owner);
    assert(all.len() == 2, 'len final');
    assert(all.pop_front().unwrap().into() == token_id, 'token1');
    assert(all.pop_front().unwrap().into() == token_id_2, 'token2');
}
#[test]
#[available_gas(300000000)]
fn test_nft_custom_uri() {
    let (_, nft) = deploy_enumerable_owned_nft(
        default_controller(), 'abcde', 'def', 'ipfs://abcdef/'
    );
    assert(nft.tokenUri(u256 { low: 1, high: 0 }) == 'ipfs://abcdef/1', 'token_uri');
}

#[test]
#[available_gas(300000000)]
#[should_panic(expected: ('OWNER', 'ENTRYPOINT_FAILED', ))]
fn test_nft_approve_fails_id_not_exists() {
    let (_, nft) = deploy_enumerable_owned_nft(
        default_controller(), 'abcde', 'def', 'ipfs://abcdef/'
    );
    set_contract_address(contract_address_const::<1>());
    nft.approve(contract_address_const::<2>(), 1);
}

#[test]
#[available_gas(300000000)]
fn test_nft_approve_succeeds_after_mint() {
    let (controller, nft) = deploy_default();

    switch_to_controller();
    let token_id = controller.mint(contract_address_const::<1>());

    set_contract_address(contract_address_const::<1>());

    nft.approve(contract_address_const::<2>(), token_id.into());
    assert(nft.getApproved(token_id.into()) == contract_address_const::<2>(), 'getApproved');
    assert(nft.get_approved(token_id.into()) == contract_address_const::<2>(), 'get_approved');
}

#[test]
#[available_gas(300000000)]
fn test_nft_transfer_from() {
    let (controller, nft) = deploy_default();

    switch_to_controller();
    let token_id = controller.mint(contract_address_const::<1>());

    set_contract_address(contract_address_const::<1>());
    nft.approve(contract_address_const::<3>(), token_id.into());
    nft.transferFrom(contract_address_const::<1>(), contract_address_const::<2>(), token_id.into());

    assert(
        nft.balanceOf(contract_address_const::<1>()) == u256 { low: 0, high: 0 }, 'balanceOf(from)'
    );
    assert(
        nft.balance_of(contract_address_const::<1>()) == u256 { low: 0, high: 0 },
        'balance_of(from)'
    );
    assert(
        nft.balanceOf(contract_address_const::<2>()) == u256 { low: 1, high: 0 }, 'balanceOf(to)'
    );
    assert(
        nft.balance_of(contract_address_const::<2>()) == u256 { low: 1, high: 0 }, 'balance_of(to)'
    );
    assert(nft.ownerOf(token_id.into()) == contract_address_const::<2>(), 'ownerOf');
    assert(nft.owner_of(token_id.into()) == contract_address_const::<2>(), 'owner_of');
    assert(nft.getApproved(token_id.into()).is_zero(), 'getApproved');
    assert(nft.get_approved(token_id.into()).is_zero(), 'get_approved');
}

#[test]
#[available_gas(300000000)]
#[should_panic(expected: ('UNAUTHORIZED', 'ENTRYPOINT_FAILED'))]
fn test_nft_transfer_from_fails_not_from_owner() {
    let (controller, nft) = deploy_default();

    switch_to_controller();
    let token_id = controller.mint(contract_address_const::<1>());

    set_contract_address(contract_address_const::<2>());

    nft.transferFrom(contract_address_const::<1>(), contract_address_const::<2>(), token_id.into());
}

#[test]
#[available_gas(300000000)]
fn test_nft_transfer_from_succeeds_from_approved() {
    let (controller, nft) = deploy_default();

    switch_to_controller();
    let token_id = controller.mint(contract_address_const::<1>());

    set_contract_address(contract_address_const::<1>());
    nft.approve(contract_address_const::<2>(), token_id.into());

    set_contract_address(contract_address_const::<2>());
    nft.transferFrom(contract_address_const::<1>(), contract_address_const::<2>(), token_id.into());
}

#[test]
#[available_gas(300000000)]
fn test_nft_transfer_from_succeeds_from_approved_for_all() {
    let (controller, nft) = deploy_default();

    switch_to_controller();
    let token_id = controller.mint(contract_address_const::<1>());

    set_contract_address(contract_address_const::<1>());
    nft.setApprovalForAll(contract_address_const::<2>(), true);

    set_contract_address(contract_address_const::<2>());
    nft.transferFrom(contract_address_const::<1>(), contract_address_const::<2>(), token_id.into());
}

#[test]
#[available_gas(300000000)]
fn test_nft_token_uri() {
    let (controller, nft) = deploy_default();

    assert(nft.tokenUri(u256 { low: 1, high: 0 }) == 'https://z.ekubo.org/1', 'token_uri');
    assert(
        nft.tokenUri(u256 { low: 9999999, high: 0 }) == 'https://z.ekubo.org/9999999', 'token_uri'
    );
    assert(
        nft.tokenUri(u256 { low: 239020510, high: 0 }) == 'https://z.ekubo.org/239020510',
        'token_uri'
    );
    assert(
        nft.tokenUri(u256 { low: 99999999999, high: 0 }) == 'https://z.ekubo.org/99999999999',
        'max token_uri'
    );
}

#[test]
#[available_gas(300000000)]
#[should_panic(expected: ('URI_LENGTH', 'ENTRYPOINT_FAILED'))]
fn test_nft_token_uri_reverts_too_long() {
    let (controller, nft) = deploy_default();

    nft.tokenUri(u256 { low: 999999999999, high: 0 });
}

#[test]
#[available_gas(300000000)]
#[should_panic(expected: ('INVALID_ID', 'ENTRYPOINT_FAILED'))]
fn test_nft_token_uri_reverts_token_id_too_big() {
    let (controller, nft) = deploy_default();

    nft.tokenUri(u256 { low: 10000000000000000000000000000000, high: 0 });
}

#[test]
#[available_gas(300000000)]
#[should_panic(expected: ('OWNER', 'ENTRYPOINT_FAILED', ))]
fn test_nft_approve_only_owner_can_approve() {
    let (controller, nft) = deploy_default();

    switch_to_controller();
    let token_id = controller.mint(contract_address_const::<1>());

    set_contract_address(contract_address_const::<2>());
    nft.approve(contract_address_const::<2>(), token_id.into());
}

#[test]
#[available_gas(300000000)]
fn test_nft_balance_of() {
    let (controller, nft) = deploy_default();

    let recipient = contract_address_const::<2>();
    assert(nft.balanceOf(recipient).is_zero(), 'balance check');

    switch_to_controller();
    assert(controller.mint(recipient) == 1, 'token id');
    assert(nft.ownerOf(1) == recipient, 'owner');
    assert(nft.owner_of(1) == recipient, 'owner');
    assert(nft.balanceOf(recipient) == u256 { low: 1, high: 0 }, 'balance check after');
    assert(nft.balance_of(recipient) == u256 { low: 1, high: 0 }, 'balance check after');
}

