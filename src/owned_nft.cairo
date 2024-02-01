use starknet::{ContractAddress};

#[starknet::interface]
pub trait IOwnedNFT<TStorage> {
    // Create a new token, only callable by the owner
    fn mint(ref self: TStorage, owner: ContractAddress) -> u64;

    // Burn the token with the given ID
    fn burn(ref self: TStorage, id: u64);

    // Returns whether the account is authorized to act on the given token ID
    fn is_account_authorized(self: @TStorage, id: u64, account: ContractAddress) -> bool;

    // Returns the next token ID, 
    // i.e. the ID of the token that will be minted on the next call to mint from the owner
    fn get_next_token_id(self: @TStorage) -> u64;

    // Allows the owner to update the metadata
    fn set_metadata(ref self: TStorage, name: felt252, symbol: felt252, token_uri_base: felt252);
}

#[starknet::contract]
pub mod OwnedNFT {
    use core::array::{Array, ArrayTrait, SpanTrait};
    use core::num::traits::{Zero};
    use core::option::{OptionTrait};
    use core::traits::{Into, TryInto};
    use ekubo::components::owned::{Owned as owned_component};
    use ekubo::components::upgradeable::{Upgradeable as upgradeable_component, IHasInterface};

    use ekubo::components::util::{serialize};
    use ekubo::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use ekubo::interfaces::erc721::{IERC721};
    use ekubo::interfaces::src5::{
        ISRC5, SRC5_SRC5_ID, SRC5_ERC721_ID, SRC5_ERC721_METADATA_ID, ERC165_ERC721_METADATA_ID,
        ERC165_ERC721_ID, ERC165_ERC165_ID
    };
    use ekubo::interfaces::upgradeable::{IUpgradeable};
    use ekubo::math::string::{to_decimal};
    use ekubo::math::ticks::{tick_to_sqrt_ratio};

    use ekubo::types::i129::{i129};
    use starknet::{
        contract_address_const, get_caller_address, get_contract_address, ClassHash,
        syscalls::{replace_class_syscall, deploy_syscall}
    };
    use starknet::{SyscallResultTrait};
    use super::{IOwnedNFT, ContractAddress};

    component!(path: owned_component, storage: owned, event: OwnedEvent);
    #[abi(embed_v0)]
    impl Owned = owned_component::OwnedImpl<ContractState>;
    impl OwnableImpl = owned_component::OwnableImpl<ContractState>;

    component!(path: upgradeable_component, storage: upgradeable, event: UpgradeableEvent);
    #[abi(embed_v0)]
    impl Upgradeable = upgradeable_component::UpgradeableImpl<ContractState>;

    #[storage]
    struct Storage {
        token_uri_base: felt252,
        name: felt252,
        symbol: felt252,
        next_token_id: u64,
        approvals: LegacyMap<u64, ContractAddress>,
        owners: LegacyMap<u64, ContractAddress>,
        balances: LegacyMap<ContractAddress, u64>,
        operators: LegacyMap<(ContractAddress, ContractAddress), bool>,
        #[substorage(v0)]
        upgradeable: upgradeable_component::Storage,
        #[substorage(v0)]
        owned: owned_component::Storage,
    }


    #[derive(starknet::Event, Drop)]
    pub struct Transfer {
        pub from: ContractAddress,
        pub to: ContractAddress,
        pub token_id: u256
    }

    #[derive(starknet::Event, Drop)]
    pub struct Approval {
        pub owner: ContractAddress,
        pub approved: ContractAddress,
        pub token_id: u256
    }

    #[derive(starknet::Event, Drop)]
    pub struct ApprovalForAll {
        pub owner: ContractAddress,
        pub operator: ContractAddress,
        pub approved: bool
    }

    #[derive(starknet::Event, Drop)]
    #[event]
    enum Event {
        #[flat]
        UpgradeableEvent: upgradeable_component::Event,
        OwnedEvent: owned_component::Event,
        Transfer: Transfer,
        Approval: Approval,
        ApprovalForAll: ApprovalForAll,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner: ContractAddress,
        name: felt252,
        symbol: felt252,
        token_uri_base: felt252
    ) {
        self.initialize_owned(owner);
        self.name.write(name);
        self.symbol.write(symbol);
        self.token_uri_base.write(token_uri_base);
        self.next_token_id.write(1);
    }

    pub fn deploy(
        nft_class_hash: ClassHash,
        owner: ContractAddress,
        name: felt252,
        symbol: felt252,
        token_uri_base: felt252,
        salt: felt252
    ) -> super::IOwnedNFTDispatcher {
        let calldata = serialize(@(owner, name, symbol, token_uri_base)).span();

        let (address, _) = deploy_syscall(
            class_hash: nft_class_hash,
            contract_address_salt: salt,
            calldata: calldata,
            deploy_from_zero: false,
        )
            .unwrap_syscall();
        super::IOwnedNFTDispatcher { contract_address: address }
    }

    fn validate_token_id(token_id: u256) -> u64 {
        assert(token_id.high == 0, 'INVALID_ID');
        token_id.low.try_into().expect('INVALID_ID')
    }

    #[generate_trait]
    impl Internal of InternalTrait {
        fn is_account_authorized_internal(
            self: @ContractState, id: u64, account: ContractAddress
        ) -> (bool, ContractAddress) {
            let owner = self.owners.read(id);
            if (account != owner) {
                if (account != self.approvals.read(id)) {
                    return (self.operators.read((owner, account)), owner);
                }
            }
            return (true, owner);
        }
    }

    #[abi(embed_v0)]
    impl OwnedNFTHasInterface of IHasInterface<ContractState> {
        fn get_primary_interface_id(self: @ContractState) -> felt252 {
            return selector!("ekubo::owned_nft::OwnedNFT");
        }
    }

    #[abi(embed_v0)]
    impl ERC721Impl of IERC721<ContractState> {
        fn name(self: @ContractState) -> felt252 {
            self.name.read()
        }

        fn symbol(self: @ContractState) -> felt252 {
            self.symbol.read()
        }

        fn approve(ref self: ContractState, to: ContractAddress, token_id: u256) {
            let caller = get_caller_address();
            let id = validate_token_id(token_id);
            assert(caller == self.owners.read(id), 'OWNER');
            self.approvals.write(id, to);
            self.emit(Approval { owner: caller, approved: to, token_id });
        }

        fn balanceOf(self: @ContractState, account: ContractAddress) -> u256 {
            u256 { low: self.balances.read(account).into(), high: 0 }
        }

        fn ownerOf(self: @ContractState, token_id: u256) -> ContractAddress {
            self.owners.read(validate_token_id(token_id))
        }

        fn transferFrom(
            ref self: ContractState, from: ContractAddress, to: ContractAddress, token_id: u256
        ) {
            let id = validate_token_id(token_id);

            let (authorized, owner) = self.is_account_authorized_internal(id, get_caller_address());
            assert(owner == from, 'OWNER');
            assert(authorized, 'UNAUTHORIZED');

            self.owners.write(id, to);
            self.approvals.write(id, Zero::zero());

            self.balances.write(to, self.balances.read(to) + 1);
            self.balances.write(from, self.balances.read(from) - 1);

            self.emit(Transfer { from, to, token_id });
        }

        fn setApprovalForAll(ref self: ContractState, operator: ContractAddress, approved: bool) {
            let owner = get_caller_address();
            self.operators.write((owner, operator), approved);
            self.emit(ApprovalForAll { owner, operator, approved });
        }

        fn getApproved(self: @ContractState, token_id: u256) -> ContractAddress {
            self.approvals.read(validate_token_id(token_id))
        }

        fn isApprovedForAll(
            self: @ContractState, owner: ContractAddress, operator: ContractAddress
        ) -> bool {
            self.operators.read((owner, operator))
        }

        fn tokenURI(self: @ContractState, token_id: u256) -> Array<felt252> {
            let id = validate_token_id(token_id);
            // the prefix takes up 20 characters and leaves 11 for the decimal token id
            // 10^11 == ~2**36 tokens can be supported by this method
            array![self.token_uri_base.read(), to_decimal(id)]
        }

        fn balance_of(self: @ContractState, account: ContractAddress) -> u256 {
            self.balanceOf(account)
        }
        fn owner_of(self: @ContractState, token_id: u256) -> ContractAddress {
            self.ownerOf(token_id)
        }
        fn transfer_from(
            ref self: ContractState, from: ContractAddress, to: ContractAddress, token_id: u256
        ) {
            self.transferFrom(from, to, token_id)
        }
        fn set_approval_for_all(
            ref self: ContractState, operator: ContractAddress, approved: bool
        ) {
            self.setApprovalForAll(operator, approved)
        }
        fn get_approved(self: @ContractState, token_id: u256) -> ContractAddress {
            self.getApproved(token_id)
        }
        fn is_approved_for_all(
            self: @ContractState, owner: ContractAddress, operator: ContractAddress
        ) -> bool {
            self.isApprovedForAll(owner, operator)
        }
        fn token_uri(self: @ContractState, token_id: u256) -> Array<felt252> {
            self.tokenURI(token_id)
        }
    }

    #[abi(embed_v0)]
    impl SRC5Impl of ISRC5<ContractState> {
        fn supportsInterface(self: @ContractState, interfaceId: felt252) -> bool {
            interfaceId == SRC5_SRC5_ID
                || interfaceId == SRC5_ERC721_ID
                || interfaceId == SRC5_ERC721_METADATA_ID
                || interfaceId == ERC165_ERC721_ID
                || interfaceId == ERC165_ERC721_METADATA_ID
                || interfaceId == ERC165_ERC165_ID
        }

        fn supports_interface(self: @ContractState, interface_id: felt252) -> bool {
            self.supportsInterface(interface_id)
        }
    }

    #[abi(embed_v0)]
    impl OwnedNFTImpl of IOwnedNFT<ContractState> {
        fn mint(ref self: ContractState, owner: ContractAddress) -> u64 {
            self.require_owner();

            let id = self.next_token_id.read();
            self.next_token_id.write(id + 1);

            // effect the mint by updating storage
            self.owners.write(id, owner);
            self.balances.write(owner, self.balances.read(owner) + 1);

            self
                .emit(
                    Transfer {
                        from: Zero::zero(), to: owner, token_id: u256 { low: id.into(), high: 0 }
                    }
                );

            id
        }

        fn burn(ref self: ContractState, id: u64) {
            self.require_owner();

            let owner = self.owners.read(id);

            // delete the storage variables
            self.owners.write(id, Zero::zero());
            self.approvals.write(id, Zero::zero());
            self.balances.write(owner, self.balances.read(owner) - 1);

            self.emit(Transfer { from: owner, to: Zero::zero(), token_id: id.into() });
        }

        fn get_next_token_id(self: @ContractState) -> u64 {
            self.next_token_id.read()
        }

        fn is_account_authorized(self: @ContractState, id: u64, account: ContractAddress) -> bool {
            let (authorized, _) = self.is_account_authorized_internal(id, account);
            authorized
        }

        fn set_metadata(
            ref self: ContractState, name: felt252, symbol: felt252, token_uri_base: felt252
        ) {
            self.require_owner();
            self.token_uri_base.write(token_uri_base);
            self.name.write(name);
            self.symbol.write(symbol);
        }
    }
}
