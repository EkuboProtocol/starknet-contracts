use core::num::traits::Zero;
use core::option::OptionTrait;
use core::traits::Into;
use starknet::ClassHash;
use starknet::testing::pop_log;
use crate::interfaces::erc721::{IERC721Dispatcher, IERC721DispatcherTrait};
use crate::interfaces::src5::{ISRC5Dispatcher, ISRC5DispatcherTrait};
use crate::interfaces::upgradeable::{IUpgradeableDispatcher, IUpgradeableDispatcherTrait};
use crate::owned_nft::{IOwnedNFTDispatcher, IOwnedNFTDispatcherTrait, OwnedNFT};
use crate::tests::helper::{Deployer, DeployerTrait, default_owner, set_caller_address_global};

fn switch_to_controller() {
    set_caller_address_global(default_owner());
}

fn deploy_default(ref d: Deployer) -> (IOwnedNFTDispatcher, IERC721Dispatcher) {
    d.deploy_owned_nft(default_owner(), 'Ekubo Position', 'EkuPo', 'https://z.ekubo.org/')
}

#[test]
fn test_nft_name_symbol_token_uri() {
    let mut d: Deployer = Default::default();
    let (_, nft) = d
        .deploy_owned_nft(default_owner(), 'Ekubo Position', 'EkuPo', 'https://z.ekubo.org/');
    assert(nft.name() == 'Ekubo Position', 'name');
    assert(nft.symbol() == 'EkuPo', 'symbol');
    assert(nft.tokenURI(1_u256) == array!['https://z.ekubo.org/', '1'], 'tokenURI');
    assert(nft.token_uri(1_u256) == array!['https://z.ekubo.org/', '1'], 'token_uri');
}

#[test]
fn test_nft_supports_interfaces() {
    let mut d: Deployer = Default::default();
    let (_, nft) = deploy_default(ref d);
    let src = ISRC5Dispatcher { contract_address: nft.contract_address };
    assert(!src.supportsInterface(0), '0');
    assert(!src.supportsInterface(1), '1');
    assert(
        !src
            .supportsInterface(
                3618502788666131213697322783095070105623107215331596699973092056135872020480,
            ),
        'max',
    );

    assert(
        src.supportsInterface(0x33eb2f84c309543403fd69f0d0f363781ef06ef6faeb0131ff16ea3175bd943),
        'src5.721',
    );
    assert(
        src.supports_interface(0x33eb2f84c309543403fd69f0d0f363781ef06ef6faeb0131ff16ea3175bd943),
        'src5.721.snake',
    );
    assert(
        src.supportsInterface(0x6069a70848f907fa57668ba1875164eb4dcee693952468581406d131081bbd),
        'src5.721_metadata',
    );
    assert(
        src.supports_interface(0x6069a70848f907fa57668ba1875164eb4dcee693952468581406d131081bbd),
        'src5.721_metadata.snake',
    );
    assert(
        src.supportsInterface(0x3f918d17e5ee77373b56385708f855659a07f75997f365cf87748628532a055),
        'src5.src5',
    );
    assert(
        src.supports_interface(0x3f918d17e5ee77373b56385708f855659a07f75997f365cf87748628532a055),
        'src5.src5.snake',
    );

    assert(src.supportsInterface(0x80ac58cd), 'erc165.721');
    assert(src.supports_interface(0x80ac58cd), 'erc165.721.snake');
    assert(src.supportsInterface(0x5b5e139f), 'erc165.721_metadata');
    assert(src.supports_interface(0x5b5e139f), 'erc165.721_metadata.snake');
    assert(src.supportsInterface(0x01ffc9a7), 'erc165.165');
    assert(src.supports_interface(0x01ffc9a7), 'erc165.165.snake');
}

#[test]
fn test_replace_class_hash_can_be_called_by_owner() {
    let mut d: Deployer = Default::default();
    let (_, nft) = d.deploy_owned_nft(default_owner(), 'abcde', 'def', 'ipfs://abcdef/');
    pop_log::<crate::components::owned::Owned::OwnershipTransferred>(nft.contract_address).unwrap();

    let class_hash: ClassHash = OwnedNFT::TEST_CLASS_HASH.try_into().unwrap();

    set_caller_address_global(default_owner());
    IUpgradeableDispatcher { contract_address: nft.contract_address }
        .replace_class_hash(class_hash);

    let event: crate::components::upgradeable::Upgradeable::ClassHashReplaced = pop_log(
        nft.contract_address,
    )
        .unwrap();
    assert(event.new_class_hash == class_hash, 'event.class_hash');
}

#[test]
fn test_set_metadata_callable_by_owner() {
    let mut d: Deployer = Default::default();
    let (owned_nft, nft) = d.deploy_owned_nft(default_owner(), 'abcde', 'def', 'ipfs://abcdef/');

    set_caller_address_global(default_owner());
    owned_nft.set_metadata('new name', 'new symbol', 'new base');
    assert(nft.name() == 'new name', 'name');
    assert(nft.symbol() == 'new symbol', 'symbol');
    assert(nft.token_uri(1) == array!['new base', '1'], 'token_uri');
}

#[test]
fn test_nft_custom_uri() {
    let mut d: Deployer = Default::default();
    let (_, nft) = d.deploy_owned_nft(default_owner(), 'abcde', 'def', 'ipfs://abcdef/');
    assert(nft.name() == 'abcde', 'name');
    assert(nft.symbol() == 'def', 'symbol');
    assert(nft.tokenURI(1_u256) == array!['ipfs://abcdef/', '1'], 'tokenURI');
    assert(nft.token_uri(1_u256) == array!['ipfs://abcdef/', '1'], 'token_uri');
}

#[test]
fn test_nft_indexing_token_ids() {
    let mut d: Deployer = Default::default();
    let (controller, nft) = d
        .deploy_owned_nft(default_owner(), 'Ekubo Position', 'EkuPo', 'https://z.ekubo.org/');

    switch_to_controller();

    let alice = 912345.try_into().unwrap();
    let bob = 9123456.try_into().unwrap();

    assert(nft.balanceOf(alice) == 0, 'balance start');

    let token_id = controller.mint(alice);

    assert(nft.balanceOf(alice) == 1, 'balance after');
    set_caller_address_global(alice);
    nft.transferFrom(alice, bob, 1);

    assert(nft.balanceOf(alice) == 0, 'balance after transfer');

    assert(nft.balanceOf(bob) == 1, 'balance bob transfer');

    switch_to_controller();
    controller.mint(alice);
    set_caller_address_global(bob);
    nft.transferFrom(bob, alice, token_id.into());
}

#[test]
fn test_nft_indexing_token_ids_not_sorted() {
    let mut d: Deployer = Default::default();
    let (controller, nft) = deploy_default(ref d);

    switch_to_controller();

    let alice = 912345.try_into().unwrap();
    let bob = 9123456.try_into().unwrap();

    controller.mint(alice);
    controller.mint(bob);
    let id_3 = controller.mint(alice);
    let id_4 = controller.mint(bob);
    controller.mint(alice);

    assert(nft.balanceOf(alice) == 3, 'balance alice');
    assert(nft.balanceOf(bob) == 2, 'balance bob');

    set_caller_address_global(alice);
    nft.transferFrom(alice, bob, id_3.into());
    set_caller_address_global(bob);
    nft.transferFrom(bob, alice, id_4.into());

    assert(nft.balanceOf(alice) == 3, 'balance alice after');

    assert(nft.balanceOf(bob) == 2, 'balance bob after');
}

#[test]
fn test_nft_indexing_token_ids_snake_case() {
    let mut d: Deployer = Default::default();
    let (controller, nft) = d
        .deploy_owned_nft(default_owner(), 'Ekubo Position', 'EkuPo', 'https://z.ekubo.org/');

    switch_to_controller();

    let alice = 912345.try_into().unwrap();
    let bob = 9123456.try_into().unwrap();

    assert(nft.balance_of(alice) == 0, 'balance start');
    let token_id = controller.mint(alice);

    assert(nft.balance_of(alice) == 1, 'balance after');
    set_caller_address_global(alice);
    nft.transfer_from(alice, bob, token_id.into());

    assert(nft.balance_of(alice) == 0, 'balance after transfer');
    assert(nft.balance_of(bob) == 1, 'balance bob transfer');

    switch_to_controller();
    controller.mint(alice);
    set_caller_address_global(bob);
    nft.transfer_from(bob, alice, token_id.into());
    assert(nft.balanceOf(alice) == 2, 'alice last');
    assert(nft.balanceOf(bob) == 0, 'bob last');
}

#[test]
fn test_burn_makes_token_non_transferrable() {
    let mut d: Deployer = Default::default();
    let (controller, nft) = d
        .deploy_owned_nft(default_owner(), 'Ekubo Position', 'EkuPo', 'https://z.ekubo.org/');

    switch_to_controller();

    let alice = 912345.try_into().unwrap();
    let bob = 9123456.try_into().unwrap();

    let id = controller.mint(alice);
    set_caller_address_global(alice);
    nft.approve(bob, id.into());
    set_caller_address_global(bob);
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
}


#[test]
fn test_is_account_authorized() {
    let mut d: Deployer = Default::default();
    let (controller, nft) = deploy_default(ref d);

    switch_to_controller();
    let alice = 912345.try_into().unwrap();
    let bob = 12345.try_into().unwrap();
    let id = controller.mint(alice);

    assert(controller.is_account_authorized(id, alice), 'owner is authorized');
    assert(!controller.is_account_authorized(id, 912344.try_into().unwrap()), 'random is not');
    assert(!controller.is_account_authorized(id, default_owner()), 'controller is not');

    set_caller_address_global(alice);
    assert(!controller.is_account_authorized(id, bob), 'bob not auth');
    nft.approve(bob, id.into());
    assert(controller.is_account_authorized(id, bob), 'bob now auth');

    nft.approve(Zero::zero(), id.into());
    assert(!controller.is_account_authorized(id, bob), 'bob not auth');

    nft.set_approval_for_all(bob, true);
    assert(controller.is_account_authorized(id, bob), 'bob now auth');
    nft.set_approval_for_all(bob, false);
    assert(!controller.is_account_authorized(id, bob), 'bob not auth');
}


#[test]
#[should_panic(expected: 'OWNER')]
fn test_burn_makes_token_non_transferrable_error() {
    let mut d: Deployer = Default::default();
    let (controller, nft) = d
        .deploy_owned_nft(default_owner(), 'Ekubo Position', 'EkuPo', 'https://z.ekubo.org/');

    switch_to_controller();

    let alice = 912345.try_into().unwrap();
    let bob = 9123456.try_into().unwrap();

    let id = controller.mint(alice);
    set_caller_address_global(alice);

    nft.approve(bob, id.into());

    switch_to_controller();
    controller.burn(id);

    set_caller_address_global(bob);
    nft.transfer_from(alice, bob, id.into());
}

#[test]
#[should_panic(expected: 'OWNER')]
fn test_nft_approve_fails_id_not_exists() {
    let mut d: Deployer = Default::default();
    let (_, nft) = d.deploy_owned_nft(default_owner(), 'abcde', 'def', 'ipfs://abcdef/');
    set_caller_address_global(1.try_into().unwrap());
    nft.approve(2.try_into().unwrap(), 1);
}

#[test]
fn test_nft_approve_succeeds_after_mint() {
    let mut d: Deployer = Default::default();
    let (controller, nft) = deploy_default(ref d);

    switch_to_controller();
    let token_id = controller.mint(1.try_into().unwrap());

    set_caller_address_global(1.try_into().unwrap());

    nft.approve(2.try_into().unwrap(), token_id.into());
    assert(nft.getApproved(token_id.into()) == 2.try_into().unwrap(), 'getApproved');
    assert(nft.get_approved(token_id.into()) == 2.try_into().unwrap(), 'get_approved');
}

#[test]
fn test_nft_transfer_from() {
    let mut d: Deployer = Default::default();
    let (controller, nft) = deploy_default(ref d);

    switch_to_controller();
    let token_id = controller.mint(1.try_into().unwrap());

    set_caller_address_global(1.try_into().unwrap());
    nft.approve(3.try_into().unwrap(), token_id.into());
    nft.transferFrom(1.try_into().unwrap(), 2.try_into().unwrap(), token_id.into());

    assert(nft.balanceOf(1.try_into().unwrap()) == 0_u256, 'balanceOf(from)');
    assert(nft.balance_of(1.try_into().unwrap()) == 0_u256, 'balance_of(from)');
    assert(nft.balanceOf(2.try_into().unwrap()) == 1_u256, 'balanceOf(to)');
    assert(nft.balance_of(2.try_into().unwrap()) == 1_u256, 'balance_of(to)');
    assert(nft.ownerOf(token_id.into()) == 2.try_into().unwrap(), 'ownerOf');
    assert(nft.owner_of(token_id.into()) == 2.try_into().unwrap(), 'owner_of');
    assert(nft.getApproved(token_id.into()).is_zero(), 'getApproved');
    assert(nft.get_approved(token_id.into()).is_zero(), 'get_approved');
}

#[test]
#[should_panic(expected: 'UNAUTHORIZED')]
fn test_nft_transfer_from_fails_not_from_owner() {
    let mut d: Deployer = Default::default();
    let (controller, nft) = deploy_default(ref d);

    switch_to_controller();
    let token_id = controller.mint(1.try_into().unwrap());

    set_caller_address_global(2.try_into().unwrap());

    nft.transferFrom(1.try_into().unwrap(), 2.try_into().unwrap(), token_id.into());
}

#[test]
fn test_nft_transfer_from_succeeds_from_approved() {
    let mut d: Deployer = Default::default();
    let (controller, nft) = deploy_default(ref d);

    switch_to_controller();
    let token_id = controller.mint(1.try_into().unwrap());

    set_caller_address_global(1.try_into().unwrap());
    nft.approve(2.try_into().unwrap(), token_id.into());

    set_caller_address_global(2.try_into().unwrap());
    nft.transferFrom(1.try_into().unwrap(), 2.try_into().unwrap(), token_id.into());
}

#[test]
fn test_nft_transfer_from_succeeds_from_approved_for_all() {
    let mut d: Deployer = Default::default();
    let (controller, nft) = deploy_default(ref d);

    switch_to_controller();
    let token_id = controller.mint(1.try_into().unwrap());

    set_caller_address_global(1.try_into().unwrap());
    nft.setApprovalForAll(2.try_into().unwrap(), true);

    set_caller_address_global(2.try_into().unwrap());
    nft.transferFrom(1.try_into().unwrap(), 2.try_into().unwrap(), token_id.into());
}

#[test]
fn test_our_uris_fit() {
    assert_eq!(
        'https://mainnet-api.ekubo.org/',
        720921236364732369706534923124483860251178706923075318028571232657631023,
    );
    assert_eq!(
        'https://goerli-api.ekubo.org/',
        2816098579549735819157462870646613929535768190509430455118393030895407,
    );
    assert_eq!(
        'https://sepolia-api.ekubo.org/',
        720921236364732369708785675631036703012891917686160277264444065418733359,
    );
}

#[test]
fn test_nft_token_uri() {
    let mut d: Deployer = Default::default();
    let (_, nft) = deploy_default(ref d);

    assert(nft.tokenURI(1_u256) == array!['https://z.ekubo.org/', '1'], 'token_uri');
    assert(
        nft.tokenURI(u256 { low: 9999999, high: 0 }) == array!['https://z.ekubo.org/', '9999999'],
        'token_uri',
    );
    assert(
        nft
            .tokenURI(
                u256 { low: 239020510, high: 0 },
            ) == array!['https://z.ekubo.org/', '239020510'],
        'token_uri',
    );
    assert(
        nft
            .tokenURI(
                u256 { low: 99999999999, high: 0 },
            ) == array!['https://z.ekubo.org/', '99999999999'],
        'max token_uri',
    );
}

#[test]
#[should_panic(expected: 'INVALID_ID')]
fn test_nft_token_uri_reverts_too_long() {
    let mut d: Deployer = Default::default();
    let (_, nft) = deploy_default(ref d);
    // 2**64 is an invalid id
    nft.token_uri(0x10000000000000000);
}

#[test]
#[should_panic(expected: 'INVALID_ID')]
fn test_nft_token_uri_reverts_token_id_too_big() {
    let mut d: Deployer = Default::default();
    let (_, nft) = deploy_default(ref d);

    nft.tokenURI(u256 { low: 10000000000000000000000000000000, high: 0 });
}

#[test]
#[should_panic(expected: 'OWNER')]
fn test_nft_approve_only_owner_can_approve() {
    let mut d: Deployer = Default::default();
    let (controller, nft) = deploy_default(ref d);

    switch_to_controller();
    let token_id = controller.mint(1.try_into().unwrap());

    set_caller_address_global(2.try_into().unwrap());
    nft.approve(2.try_into().unwrap(), token_id.into());
}

#[test]
fn test_nft_balance_of() {
    let mut d: Deployer = Default::default();
    let (controller, nft) = deploy_default(ref d);

    let recipient = 2.try_into().unwrap();
    assert(nft.balanceOf(recipient).is_zero(), 'balance check');

    switch_to_controller();
    assert(controller.mint(recipient) == 1, 'token id');
    assert(nft.ownerOf(1) == recipient, 'owner');
    assert(nft.owner_of(1) == recipient, 'owner');
    assert(nft.balanceOf(recipient) == 1_u256, 'balance check after');
    assert(nft.balance_of(recipient) == 1_u256, 'balance check after');
}
