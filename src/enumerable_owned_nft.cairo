use starknet::{ContractAddress};

#[starknet::interface]
trait IEnumerableOwnedNFT<TStorage> {
    // Get the full list of tokens owned by an account
    fn get_all_owned_tokens(self: @TStorage, account: ContractAddress) -> Array<u64>;

    // Create a new token, only callable by the controller
    fn mint(ref self: TStorage, owner: ContractAddress) -> u64;
    // Burn the token with the given ID
    fn burn(ref self: TStorage, id: u64);

    // Returns whether the account is authorized to act on the given token ID
    fn is_account_authorized(self: @TStorage, id: u64, account: ContractAddress) -> bool;

    // Returns the next token ID, 
    // i.e. the ID of the token that will be minted on the next call to mint from the controller
    fn get_next_token_id(self: @TStorage) -> u64;
}

#[starknet::contract]
mod EnumerableOwnedNFT {
    use super::{IEnumerableOwnedNFT, ContractAddress};
    use traits::{Into, TryInto};
    use option::{OptionTrait};
    use zeroable::{Zeroable};
    use array::{ArrayTrait};
    use starknet::{
        contract_address_const, get_caller_address, get_contract_address, ClassHash,
        replace_class_syscall
    };

    use ekubo::types::i129::{i129};
    use ekubo::math::ticks::{tick_to_sqrt_ratio};
    use ekubo::math::string::{to_decimal, append};
    use ekubo::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use ekubo::interfaces::src5::{ISRC5Dispatcher, ISRC5DispatcherTrait};
    use ekubo::interfaces::erc721::{
        IERC721_RECEIVER_INTERFACE_ID, IACCOUNT_INTERFACE_ID, IERC721, IERC721ReceiverDispatcher,
        IERC721ReceiverDispatcherTrait
    };
    use ekubo::interfaces::upgradeable::{IUpgradeable};
    use ekubo::owner::{check_owner_only};

    #[storage]
    struct Storage {
        controller: ContractAddress,
        token_uri_base: felt252,
        name: felt252,
        symbol: felt252,
        next_token_id: u64,
        approvals: LegacyMap<u64, ContractAddress>,
        owners: LegacyMap<u64, ContractAddress>,
        // address, id -> next
        // address, 0 contains the first token id
        tokens_by_owner: LegacyMap<(ContractAddress, u64), u64>,
        operators: LegacyMap<(ContractAddress, ContractAddress), bool>,
    }

    #[derive(starknet::Event, Drop)]
    struct Transfer {
        from: ContractAddress,
        to: ContractAddress,
        token_id: u256
    }

    #[derive(starknet::Event, Drop)]
    struct Approval {
        owner: ContractAddress,
        approved: ContractAddress,
        token_id: u256
    }

    #[derive(starknet::Event, Drop)]
    struct ApprovalForAll {
        owner: ContractAddress,
        operator: ContractAddress,
        approved: bool
    }

    #[derive(starknet::Event, Drop)]
    #[event]
    enum Event {
        Transfer: Transfer,
        Approval: Approval,
        ApprovalForAll: ApprovalForAll,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        controller: ContractAddress,
        name: felt252,
        symbol: felt252,
        token_uri_base: felt252
    ) {
        self.controller.write(controller);
        self.name.write(name);
        self.symbol.write(symbol);
        self.token_uri_base.write(token_uri_base);
        self.next_token_id.write(1);
    }

    fn validate_token_id(token_id: u256) -> u64 {
        assert(token_id.high == 0, 'INVALID_ID');
        token_id.low.try_into().expect('INVALID_ID')
    }

    #[generate_trait]
    impl Internal of InternalTrait {
        fn require_controller(self: @ContractState) {
            assert(get_caller_address() == self.controller.read(), 'CONTROLLER_ONLY');
        }

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

        fn count_tokens_for_owner(self: @ContractState, owner: ContractAddress) -> u64 {
            let mut count: u64 = 0;

            let mut curr = self.tokens_by_owner.read((owner, 0));

            loop {
                if (curr == 0) {
                    break count;
                };
                count += 1;
                curr = self.tokens_by_owner.read((owner, curr));
            }
        }

        fn tokens_by_owner_insert(ref self: ContractState, owner: ContractAddress, id: u64) {
            let mut curr = self.tokens_by_owner.read((owner, 0));

            loop {
                if (curr < id) {
                    let next = self.tokens_by_owner.read((owner, curr));
                    if (next == 0 || next > id) {
                        self.tokens_by_owner.write((owner, curr), id);
                        self.tokens_by_owner.write((owner, id), next);
                        break ();
                    }
                    curr = next;
                } else {
                    curr = self.tokens_by_owner.read((owner, curr));
                };
            };
        }

        fn tokens_by_owner_remove(ref self: ContractState, owner: ContractAddress, id: u64) {
            let mut curr: u64 = 0;

            loop {
                let next = self.tokens_by_owner.read((owner, curr));
                assert(next <= id, 'TOKEN_NOT_FOUND');

                if (next == id) {
                    self
                        .tokens_by_owner
                        .write((owner, curr), self.tokens_by_owner.read((owner, next)));
                    self.tokens_by_owner.write((owner, next), 0);
                    break ();
                } else {
                    curr = next;
                };
            };
        }

        fn transfer(
            ref self: ContractState, from: ContractAddress, to: ContractAddress, token_id: u256
        ) {
            let id = validate_token_id(token_id);

            let (authorized, owner) = self.is_account_authorized_internal(id, get_caller_address());
            assert(owner == from, 'OWNER');
            assert(authorized, 'UNAUTHORIZED');

            self.owners.write(id, to);
            self.approvals.write(id, Zeroable::zero());
            self.tokens_by_owner_insert(to, id);
            self.tokens_by_owner_remove(from, id);
            self.emit(Transfer { from, to, token_id });
        }
    }

    #[external(v0)]
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
            u256 { low: self.count_tokens_for_owner(account).into(), high: 0 }
        }

        fn ownerOf(self: @ContractState, token_id: u256) -> ContractAddress {
            self.owners.read(validate_token_id(token_id))
        }

        fn transferFrom(
            ref self: ContractState, from: ContractAddress, to: ContractAddress, token_id: u256
        ) {
            self.transfer(from, to, token_id);
        }

        fn safeTransferFrom(
            ref self: ContractState,
            from: ContractAddress,
            to: ContractAddress,
            token_id: u256,
            data: Span<felt252>
        ) {
            self.transfer(from, to, token_id);
            if (ISRC5Dispatcher {
                contract_address: to
            }.supports_interface(IERC721_RECEIVER_INTERFACE_ID.into())) {
                // todo add casing fallback mechanism
                assert(
                    IERC721ReceiverDispatcher {
                        contract_address: to
                    }
                        .on_erc721_received(
                            get_caller_address(), from, token_id, data
                        ) == IERC721_RECEIVER_INTERFACE_ID,
                    'CALLBACK_FAILED'
                );
            } else {
                assert(
                    ISRC5Dispatcher {
                        contract_address: to
                    }.supports_interface(IACCOUNT_INTERFACE_ID),
                    'SAFE_TRANSFER_TO_NON_ACCOUNT'
                );
            }
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

        fn tokenUri(self: @ContractState, token_id: u256) -> felt252 {
            let id = validate_token_id(token_id);
            // the prefix takes up 20 characters and leaves 11 for the decimal token id
            // 10^11 == ~2**36 tokens can be supported by this method
            append(self.token_uri_base.read(), to_decimal(id.into()).expect('TOKEN_ID'))
                .expect('URI_LENGTH')
        }
        fn supportsInterface(self: @ContractState, interfaceId: felt252) -> bool {
            // 721
            interfaceId == 0x33eb2f84c309543403fd69f0d0f363781ef06ef6faeb0131ff16ea3175bd943
                // 721 metadata
                || interfaceId == 0x6069a70848f907fa57668ba1875164eb4dcee693952468581406d131081bbd
                // cairo 0 interface id?
                || interfaceId == 0x80ac58cd
                // SRC5 interface ID 
                // https://github.com/starknet-io/SNIPs/blob/main/SNIPS/snip-5.md#how-to-detect-if-a-contract-implements-src-5
                || interfaceId == 0x3f918d17e5ee77373b56385708f855659a07f75997f365cf87748628532a055
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
        fn safe_transfer_from(
            ref self: ContractState,
            from: ContractAddress,
            to: ContractAddress,
            token_id: u256,
            data: Span<felt252>
        ) {
            self.safeTransferFrom(from, to, token_id, data)
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
        fn token_uri(self: @ContractState, token_id: u256) -> felt252 {
            self.tokenUri(token_id)
        }
        fn supports_interface(self: @ContractState, interface_id: felt252) -> bool {
            self.supportsInterface(interface_id)
        }
    }

    #[external(v0)]
    impl EnumerableOwnedNFTImpl of IEnumerableOwnedNFT<ContractState> {
        fn get_all_owned_tokens(self: @ContractState, account: ContractAddress) -> Array<u64> {
            let mut arr: Array<u64> = ArrayTrait::new();

            let mut curr = self.tokens_by_owner.read((account, 0));
            loop {
                if (curr == 0) {
                    break ();
                }

                arr.append(curr);

                curr = self.tokens_by_owner.read((account, curr));
            };

            arr
        }

        fn mint(ref self: ContractState, owner: ContractAddress) -> u64 {
            self.require_controller();

            let id = self.next_token_id.read();
            self.next_token_id.write(id + 1);

            // effect the mint by updating storage
            self.owners.write(id, owner);
            self.tokens_by_owner_insert(owner, id);

            self
                .emit(
                    Transfer {
                        from: Zeroable::zero(), to: owner, token_id: u256 {
                            low: id.into(), high: 0
                        }
                    }
                );

            id
        }

        fn burn(ref self: ContractState, id: u64) {
            self.require_controller();

            let owner = self.owners.read(id);

            // delete the storage variables
            self.owners.write(id, Zeroable::zero());
            self.tokens_by_owner_remove(owner, id);

            self.emit(Transfer { from: owner, to: Zeroable::zero(), token_id: id.into() });
        }

        fn get_next_token_id(self: @ContractState) -> u64 {
            self.next_token_id.read()
        }

        fn is_account_authorized(self: @ContractState, id: u64, account: ContractAddress) -> bool {
            let (authorized, _) = self.is_account_authorized_internal(id, account);
            authorized
        }
    }
}
