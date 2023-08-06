use ekubo::tests::helper::{deploy_enumerable_owned_nft};
use ekubo::interfaces::erc721::{IERC721Dispatcher, IERC721DispatcherTrait};
use ekubo::interfaces::src5::{ISRC5Dispatcher, ISRC5DispatcherTrait};
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
fn test_nft_name_symbol_token_uri() {
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
fn test_nft_supports_interfaces() {
    let (_, nft) = deploy_default();
    let src = ISRC5Dispatcher { contract_address: nft.contract_address };
    assert(
        src.supportsInterface(0x33eb2f84c309543403fd69f0d0f363781ef06ef6faeb0131ff16ea3175bd943),
        'src5'
    );
    assert(
        src.supports_interface(0x33eb2f84c309543403fd69f0d0f363781ef06ef6faeb0131ff16ea3175bd943),
        'src5.snake'
    );
    assert(
        src.supportsInterface(0x6069a70848f907fa57668ba1875164eb4dcee693952468581406d131081bbd),
        'src5'
    );
    assert(
        src.supports_interface(0x6069a70848f907fa57668ba1875164eb4dcee693952468581406d131081bbd),
        'src5.snake'
    );
    assert(src.supportsInterface(0x80ac58cd), 'erc165');
    assert(src.supports_interface(0x80ac58cd), 'erc165.snake');
    assert(
        src.supportsInterface(0x3f918d17e5ee77373b56385708f855659a07f75997f365cf87748628532a055),
        'src5'
    );
    assert(
        src.supports_interface(0x3f918d17e5ee77373b56385708f855659a07f75997f365cf87748628532a055),
        'src5.snake'
    );
}

#[test]
#[available_gas(300000000)]
fn test_nft_custom_uri() {
    let (_, nft) = deploy_enumerable_owned_nft(
        default_controller(), 'abcde', 'def', 'ipfs://abcdef/'
    );
    assert(nft.name() == 'abcde', 'name');
    assert(nft.symbol() == 'def', 'symbol');
    assert(nft.tokenUri(u256 { low: 1, high: 0 }) == 'ipfs://abcdef/1', 'tokenUri');
    assert(nft.token_uri(u256 { low: 1, high: 0 }) == 'ipfs://abcdef/1', 'token_uri');
}

#[test]
#[available_gas(300000000)]
fn test_nft_indexing_token_ids() {
    let (controller, nft) = deploy_enumerable_owned_nft(
        default_controller(), 'Ekubo Position NFT', 'EpNFT', 'https://z.ekubo.org/'
    );

    switch_to_controller();

    let alice = contract_address_const::<912345>();
    let bob = contract_address_const::<9123456>();

    assert(nft.balanceOf(alice) == 0, 'balance start');
    let mut all = controller.get_all_owned_tokens(alice);
    assert(all.len() == 0, 'len before');
    let token_id = controller.mint(alice);

    assert(nft.balanceOf(alice) == 1, 'balance after');
    all = controller.get_all_owned_tokens(alice);
    assert(all.len() == 1, 'len after');
    set_contract_address(alice);
    nft.transferFrom(alice, bob, all.pop_front().unwrap().into());

    assert(nft.balanceOf(alice) == 0, 'balance after transfer');
    all = controller.get_all_owned_tokens(alice);
    assert(all.len() == 0, 'len after transfer');

    assert(nft.balanceOf(bob) == 1, 'balance bob transfer');
    all = controller.get_all_owned_tokens(bob);
    assert(all.len() == 1, 'len bob');
    assert(all.pop_front().unwrap().into() == token_id, 'token bob');

    switch_to_controller();
    let token_id_2 = controller.mint(alice);
    set_contract_address(bob);
    nft.transferFrom(bob, alice, token_id.into());

    all = controller.get_all_owned_tokens(alice);
    assert(all.len() == 2, 'len final');
    assert(all.pop_front().unwrap().into() == token_id, 'token1');
    assert(all.pop_front().unwrap().into() == token_id_2, 'token2');
}

#[test]
#[available_gas(300000000)]
fn test_nft_indexing_token_ids_snake_case() {
    let (controller, nft) = deploy_enumerable_owned_nft(
        default_controller(), 'Ekubo Position NFT', 'EpNFT', 'https://z.ekubo.org/'
    );

    switch_to_controller();

    let alice = contract_address_const::<912345>();
    let bob = contract_address_const::<9123456>();

    assert(nft.balance_of(alice) == 0, 'balance start');
    let mut all = controller.get_all_owned_tokens(alice);
    assert(all.len() == 0, 'len before');
    let token_id = controller.mint(alice);

    assert(nft.balance_of(alice) == 1, 'balance after');
    all = controller.get_all_owned_tokens(alice);
    assert(all.len() == 1, 'len after');
    set_contract_address(alice);
    nft.transfer_from(alice, bob, all.pop_front().unwrap().into());

    assert(nft.balance_of(alice) == 0, 'balance after transfer');
    all = controller.get_all_owned_tokens(alice);
    assert(all.len() == 0, 'len after transfer');

    assert(nft.balance_of(bob) == 1, 'balance bob transfer');
    all = controller.get_all_owned_tokens(bob);
    assert(all.len() == 1, 'len bob');
    assert(all.pop_front().unwrap().into() == token_id, 'token bob');

    switch_to_controller();
    let token_id_2 = controller.mint(alice);
    set_contract_address(bob);
    nft.transfer_from(bob, alice, token_id.into());

    all = controller.get_all_owned_tokens(alice);
    assert(all.len() == 2, 'len final');
    assert(all.pop_front().unwrap().into() == token_id, 'token1');
    assert(all.pop_front().unwrap().into() == token_id_2, 'token2');
}

#[test]
#[available_gas(300000000)]
fn test_burn_makes_token_non_transferrable() {
    let (controller, nft) = deploy_enumerable_owned_nft(
        default_controller(), 'Ekubo Position NFT', 'EpNFT', 'https://z.ekubo.org/'
    );

    switch_to_controller();

    let alice = contract_address_const::<912345>();
    let bob = contract_address_const::<9123456>();

    let id = controller.mint(alice);
    set_contract_address(alice);
    nft.approve(bob, id.into());
    set_contract_address(bob);
    nft.transfer_from(alice, bob, id.into());

    nft.approve(alice, id.into());
    assert(nft.get_approved(id.into()) == alice, 'get_approved');
    assert(nft.getApproved(id.into()) == alice, 'get_approved');

    switch_to_controller();
    controller.burn(id);

    assert(nft.balance_of(alice) == 0, 'balance_of(alice)');
    assert(nft.balance_of(bob) == 0, 'balance_of(bob)');
    assert(nft.get_approved(id.into()).is_zero(), 'get_approved after');
    assert(nft.getApproved(id.into()).is_zero(), 'getApproved after');
    assert(controller.get_all_owned_tokens(alice).len() == 0, 'empty');
    assert(controller.get_all_owned_tokens(bob).len() == 0, 'empty');
}


#[test]
#[available_gas(300000000)]
fn test_is_account_authorized() {
    let (controller, nft) = deploy_default();

    switch_to_controller();
    let alice = contract_address_const::<912345>();
    let bob = contract_address_const::<12345>();
    let id = controller.mint(alice);

    assert(controller.is_account_authorized(id, alice), 'owner is authorized');
    assert(
        !controller.is_account_authorized(id, contract_address_const::<912344>()), 'random is not'
    );
    assert(!controller.is_account_authorized(id, default_controller()), 'controller is not');

    set_contract_address(alice);
    assert(!controller.is_account_authorized(id, bob), 'bob not auth');
    nft.approve(bob, id.into());
    assert(controller.is_account_authorized(id, bob), 'bob now auth');

    nft.approve(Zeroable::zero(), id.into());
    assert(!controller.is_account_authorized(id, bob), 'bob not auth');

    nft.set_approval_for_all(bob, true);
    assert(controller.is_account_authorized(id, bob), 'bob now auth');
    nft.set_approval_for_all(bob, false);
    assert(!controller.is_account_authorized(id, bob), 'bob not auth');
}


#[test]
#[available_gas(300000000)]
#[should_panic(expected: ('OWNER', 'ENTRYPOINT_FAILED'))]
fn test_burn_makes_token_non_transferrable_error() {
    let (controller, nft) = deploy_enumerable_owned_nft(
        default_controller(), 'Ekubo Position NFT', 'EpNFT', 'https://z.ekubo.org/'
    );

    switch_to_controller();

    let alice = contract_address_const::<912345>();
    let bob = contract_address_const::<9123456>();

    let id = controller.mint(alice);
    set_contract_address(alice);

    nft.approve(bob, id.into());

    switch_to_controller();
    controller.burn(id);

    set_contract_address(bob);
    nft.transfer_from(alice, bob, id.into());
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

