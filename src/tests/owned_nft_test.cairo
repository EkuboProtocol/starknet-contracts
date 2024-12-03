use core::num::traits::{Zero};
use core::option::{OptionTrait};
use core::traits::{Into};
use ekubo::interfaces::erc721::{IERC721Dispatcher, IERC721DispatcherTrait};
use ekubo::interfaces::src5::{ISRC5Dispatcher, ISRC5DispatcherTrait};
use ekubo::interfaces::upgradeable::{IUpgradeableDispatcher, IUpgradeableDispatcherTrait};
use ekubo::owned_nft::{IOwnedNFTDispatcher, IOwnedNFTDispatcherTrait, OwnedNFT};
use ekubo::tests::helper::{Deployer, DeployerTrait, default_owner};
use starknet::{ClassHash, contract_address_const};
use starknet::{testing::{pop_log, set_contract_address}};

fn switch_to_controller() {
    set_contract_address(default_owner());
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
    pop_log::<ekubo::components::owned::Owned::OwnershipTransferred>(nft.contract_address).unwrap();

    let class_hash: ClassHash = OwnedNFT::TEST_CLASS_HASH.try_into().unwrap();

    set_contract_address(default_owner());
    IUpgradeableDispatcher { contract_address: nft.contract_address }
        .replace_class_hash(class_hash);

    let event: ekubo::components::upgradeable::Upgradeable::ClassHashReplaced = pop_log(
        nft.contract_address,
    )
        .unwrap();
    assert(event.new_class_hash == class_hash, 'event.class_hash');
}

#[test]
fn test_set_metadata_callable_by_owner() {
    let mut d: Deployer = Default::default();
    let (owned_nft, nft) = d.deploy_owned_nft(default_owner(), 'abcde', 'def', 'ipfs://abcdef/');

    set_contract_address(default_owner());
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

    let alice = contract_address_const::<912345>();
    let bob = contract_address_const::<9123456>();

    assert(nft.balanceOf(alice) == 0, 'balance start');

    let token_id = controller.mint(alice);

    assert(nft.balanceOf(alice) == 1, 'balance after');
    set_contract_address(alice);
    nft.transferFrom(alice, bob, 1);

    assert(nft.balanceOf(alice) == 0, 'balance after transfer');

    assert(nft.balanceOf(bob) == 1, 'balance bob transfer');

    switch_to_controller();
    controller.mint(alice);
    set_contract_address(bob);
    nft.transferFrom(bob, alice, token_id.into());
}

#[test]
fn test_nft_indexing_token_ids_not_sorted() {
    let mut d: Deployer = Default::default();
    let (controller, nft) = deploy_default(ref d);

    switch_to_controller();

    let alice = contract_address_const::<912345>();
    let bob = contract_address_const::<9123456>();

    controller.mint(alice);
    controller.mint(bob);
    let id_3 = controller.mint(alice);
    let id_4 = controller.mint(bob);
    controller.mint(alice);

    assert(nft.balanceOf(alice) == 3, 'balance alice');
    assert(nft.balanceOf(bob) == 2, 'balance bob');

    set_contract_address(alice);
    nft.transferFrom(alice, bob, id_3.into());
    set_contract_address(bob);
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

    let alice = contract_address_const::<912345>();
    let bob = contract_address_const::<9123456>();

    assert(nft.balance_of(alice) == 0, 'balance start');
    let token_id = controller.mint(alice);

    assert(nft.balance_of(alice) == 1, 'balance after');
    set_contract_address(alice);
    nft.transfer_from(alice, bob, token_id.into());

    assert(nft.balance_of(alice) == 0, 'balance after transfer');
    assert(nft.balance_of(bob) == 1, 'balance bob transfer');

    switch_to_controller();
    controller.mint(alice);
    set_contract_address(bob);
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
}


#[test]
fn test_is_account_authorized() {
    let mut d: Deployer = Default::default();
    let (controller, nft) = deploy_default(ref d);

    switch_to_controller();
    let alice = contract_address_const::<912345>();
    let bob = contract_address_const::<12345>();
    let id = controller.mint(alice);

    assert(controller.is_account_authorized(id, alice), 'owner is authorized');
    assert(
        !controller.is_account_authorized(id, contract_address_const::<912344>()), 'random is not',
    );
    assert(!controller.is_account_authorized(id, default_owner()), 'controller is not');

    set_contract_address(alice);
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
#[should_panic(expected: ('OWNER', 'ENTRYPOINT_FAILED'))]
fn test_burn_makes_token_non_transferrable_error() {
    let mut d: Deployer = Default::default();
    let (controller, nft) = d
        .deploy_owned_nft(default_owner(), 'Ekubo Position', 'EkuPo', 'https://z.ekubo.org/');

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
#[should_panic(expected: ('OWNER', 'ENTRYPOINT_FAILED'))]
fn test_nft_approve_fails_id_not_exists() {
    let mut d: Deployer = Default::default();
    let (_, nft) = d.deploy_owned_nft(default_owner(), 'abcde', 'def', 'ipfs://abcdef/');
    set_contract_address(contract_address_const::<1>());
    nft.approve(contract_address_const::<2>(), 1);
}

#[test]
fn test_nft_approve_succeeds_after_mint() {
    let mut d: Deployer = Default::default();
    let (controller, nft) = deploy_default(ref d);

    switch_to_controller();
    let token_id = controller.mint(contract_address_const::<1>());

    set_contract_address(contract_address_const::<1>());

    nft.approve(contract_address_const::<2>(), token_id.into());
    assert(nft.getApproved(token_id.into()) == contract_address_const::<2>(), 'getApproved');
    assert(nft.get_approved(token_id.into()) == contract_address_const::<2>(), 'get_approved');
}

#[test]
fn test_nft_transfer_from() {
    let mut d: Deployer = Default::default();
    let (controller, nft) = deploy_default(ref d);

    switch_to_controller();
    let token_id = controller.mint(contract_address_const::<1>());

    set_contract_address(contract_address_const::<1>());
    nft.approve(contract_address_const::<3>(), token_id.into());
    nft.transferFrom(contract_address_const::<1>(), contract_address_const::<2>(), token_id.into());

    assert(nft.balanceOf(contract_address_const::<1>()) == 0_u256, 'balanceOf(from)');
    assert(nft.balance_of(contract_address_const::<1>()) == 0_u256, 'balance_of(from)');
    assert(nft.balanceOf(contract_address_const::<2>()) == 1_u256, 'balanceOf(to)');
    assert(nft.balance_of(contract_address_const::<2>()) == 1_u256, 'balance_of(to)');
    assert(nft.ownerOf(token_id.into()) == contract_address_const::<2>(), 'ownerOf');
    assert(nft.owner_of(token_id.into()) == contract_address_const::<2>(), 'owner_of');
    assert(nft.getApproved(token_id.into()).is_zero(), 'getApproved');
    assert(nft.get_approved(token_id.into()).is_zero(), 'get_approved');
}

#[test]
#[should_panic(expected: ('UNAUTHORIZED', 'ENTRYPOINT_FAILED'))]
fn test_nft_transfer_from_fails_not_from_owner() {
    let mut d: Deployer = Default::default();
    let (controller, nft) = deploy_default(ref d);

    switch_to_controller();
    let token_id = controller.mint(contract_address_const::<1>());

    set_contract_address(contract_address_const::<2>());

    nft.transferFrom(contract_address_const::<1>(), contract_address_const::<2>(), token_id.into());
}

#[test]
fn test_nft_transfer_from_succeeds_from_approved() {
    let mut d: Deployer = Default::default();
    let (controller, nft) = deploy_default(ref d);

    switch_to_controller();
    let token_id = controller.mint(contract_address_const::<1>());

    set_contract_address(contract_address_const::<1>());
    nft.approve(contract_address_const::<2>(), token_id.into());

    set_contract_address(contract_address_const::<2>());
    nft.transferFrom(contract_address_const::<1>(), contract_address_const::<2>(), token_id.into());
}

#[test]
fn test_nft_transfer_from_succeeds_from_approved_for_all() {
    let mut d: Deployer = Default::default();
    let (controller, nft) = deploy_default(ref d);

    switch_to_controller();
    let token_id = controller.mint(contract_address_const::<1>());

    set_contract_address(contract_address_const::<1>());
    nft.setApprovalForAll(contract_address_const::<2>(), true);

    set_contract_address(contract_address_const::<2>());
    nft.transferFrom(contract_address_const::<1>(), contract_address_const::<2>(), token_id.into());
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
#[should_panic(expected: ('INVALID_ID', 'ENTRYPOINT_FAILED'))]
fn test_nft_token_uri_reverts_too_long() {
    let mut d: Deployer = Default::default();
    let (_, nft) = deploy_default(ref d);
    // 2**64 is an invalid id
    nft.token_uri(0x10000000000000000);
}

#[test]
#[should_panic(expected: ('INVALID_ID', 'ENTRYPOINT_FAILED'))]
fn test_nft_token_uri_reverts_token_id_too_big() {
    let mut d: Deployer = Default::default();
    let (_, nft) = deploy_default(ref d);

    nft.tokenURI(u256 { low: 10000000000000000000000000000000, high: 0 });
}

#[test]
#[should_panic(expected: ('OWNER', 'ENTRYPOINT_FAILED'))]
fn test_nft_approve_only_owner_can_approve() {
    let mut d: Deployer = Default::default();
    let (controller, nft) = deploy_default(ref d);

    switch_to_controller();
    let token_id = controller.mint(contract_address_const::<1>());

    set_contract_address(contract_address_const::<2>());
    nft.approve(contract_address_const::<2>(), token_id.into());
}

#[test]
fn test_nft_balance_of() {
    let mut d: Deployer = Default::default();
    let (controller, nft) = deploy_default(ref d);

    let recipient = contract_address_const::<2>();
    assert(nft.balanceOf(recipient).is_zero(), 'balance check');

    switch_to_controller();
    assert(controller.mint(recipient) == 1, 'token id');
    assert(nft.ownerOf(1) == recipient, 'owner');
    assert(nft.owner_of(1) == recipient, 'owner');
    assert(nft.balanceOf(recipient) == 1_u256, 'balance check after');
    assert(nft.balance_of(recipient) == 1_u256, 'balance check after');
}

