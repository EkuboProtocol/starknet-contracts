use starknet::{ContractAddress, contract_address_const, get_caller_address};
use ekubo::types::i129::i129;
use serde::{Serde};
use array::{ArrayTrait};

#[abi]
trait NFT {
    #[view]
    fn name() -> felt252;
    #[view]
    fn symbol() -> felt252;
    #[external]
    fn approve(to: ContractAddress, token_id: u256);
    #[view]
    fn balance_of(account: ContractAddress) -> u256;
    #[view]
    fn owner_of(token_id: u256) -> ContractAddress;
    #[external]
    fn transfer_from(from: ContractAddress, to: ContractAddress, token_id: u256);
    // #[external]
    // fn safe_transfer_from(
    //     from: ContractAddress, to: ContractAddress, token_id: u256, data: Span<felt252>
    // );
    #[external]
    fn set_approval_for_all(operator: ContractAddress, approved: bool);
    #[view]
    fn get_approved(token_id: u256) -> ContractAddress;
    #[view]
    fn is_approved_for_all(owner: ContractAddress, operator: ContractAddress) -> bool;
    #[view]
    fn token_uri(token_id: u256) -> felt252;
}

#[contract]
mod Nft {
    use super::{
        ContractAddress, get_caller_address, i129, contract_address_const, Serde, ArrayTrait
    };
    use array::{Span, SpanTrait};

    struct Storage {
        core: ContractAddress,
        approvals: LegacyMap<u128, ContractAddress>,
        owners: LegacyMap<u128, ContractAddress>,
        balances: LegacyMap<ContractAddress, u128>,
        operators: LegacyMap<(ContractAddress, ContractAddress), bool>,
    }

    #[event]
    fn Transfer(from: ContractAddress, to: ContractAddress, token_id: u256) {}

    #[event]
    fn Approval(owner: ContractAddress, approved: ContractAddress, token_id: u256) {}

    #[event]
    fn ApprovalForAll(owner: ContractAddress, operator: ContractAddress, approved: bool) {}

    #[constructor]
    fn constructor(_core: ContractAddress) {
        core::write(_core);
    }

    #[view]
    fn name() -> felt252 {
        'Ekubo Position NFT'
    }

    #[view]
    fn symbol() -> felt252 {
        'EpNFT'
    }

    #[external]
    fn approve(to: ContractAddress, token_id: u256) {
        let caller = get_caller_address();
        assert(caller == owner_of(token_id), 'OWNER');
        approvals::write(token_id.low, to);
        Approval(caller, to, token_id);
    }

    #[view]
    fn balance_of(account: ContractAddress) -> u256 {
        u256 { low: balances::read(account), high: 0 }
    }

    #[view]
    fn owner_of(token_id: u256) -> ContractAddress {
        assert(token_id.high == 0, 'INVALID ID');
        owners::read(token_id.low)
    }

    #[internal]
    fn transfer(from: ContractAddress, to: ContractAddress, token_id: u256) {
        assert(token_id.high == 0, 'INVALID ID');
        let owner = owners::read(token_id.low);
        assert(owner == from, 'OWNER');

        let caller = get_caller_address();
        if (caller != owner) {
            let approved = approvals::read(token_id.low);
            if (caller != approved) {
                let operator = operators::read((owner, caller));
                assert(operator, 'UNAUTHORIZED');
            }
        }

        owners::write(token_id.low, to);
        approvals::write(token_id.low, contract_address_const::<0>());
        balances::write(from, balances::read(from) - 1);
        balances::write(to, balances::read(to) + 1);
        Transfer(from, to, token_id);
    }

    #[external]
    fn transfer_from(from: ContractAddress, to: ContractAddress, token_id: u256) {
        transfer(from, to, token_id);
    }

    // #[external]
    // fn safe_transfer_from(
    //     from: ContractAddress, to: ContractAddress, token_id: u256, data: Span<felt252>
    // ) {
    //     transfer(from, to, token_id);
    //     assert(false, 'todo');
    // }

    #[external]
    fn set_approval_for_all(operator: ContractAddress, approved: bool) {
        let owner = get_caller_address();
        operators::write((owner, operator), approved);
        ApprovalForAll(owner, operator, approved);
    }

    #[view]
    fn get_approved(token_id: u256) -> ContractAddress {
        approvals::read(token_id.low)
    }

    #[view]
    fn is_approved_for_all(owner: ContractAddress, operator: ContractAddress) -> bool {
        operators::read((owner, operator))
    }

    #[view]
    fn token_uri(token_id: u256) -> felt252 {
        'https://nft.ekubo.org/'
    }


    #[external]
    fn locked(id: felt252, data: Array<felt252>) -> Array<felt252> {
        let caller = get_caller_address();
        assert(caller == core::read(), 'CORE');

        assert(false, 'todo');

        ArrayTrait::new()
    }
}
