use starknet::ContractAddress;

// A single payment out of the TWAMM contract's saved balance in Core.
#[derive(Serde, Drop, Copy, PartialEq, Debug)]
pub struct Refund {
    // The token to load from the TWAMM's saved balance and pay out.
    pub token: ContractAddress,
    // Who receives the tokens, i.e. the owner of the order whose funds were stranded.
    pub recipient: ContractAddress,
    // The exact amount to pay out.
    pub amount: u128,
}

#[starknet::interface]
pub trait ITWAMMRefund<TContractState> {
    // Pays out the given refunds from this contract's saved balance in Core.
    // Owner only.
    fn refund(ref self: TContractState, refunds: Array<Refund>);
}

// A temporary implementation of the TWAMM contract, used to return funds that the TWAMM's order
// accounting can no longer attribute to anyone.
//
// An order sold into a pool with no liquidity fills nothing: virtual order execution swaps against
// zero liquidity, so no reward accrues, while the remaining sell amount is consumed by the passage
// of time regardless. Once the order's end time passes, the sale rate can no longer be updated, so
// the seller can neither collect proceeds (there are none) nor withdraw the unsold amount. The
// tokens stay in Core under the TWAMM's own saved balance, which is keyed only by token and a zero
// salt, so they are shared across every order and every pool and belong to no one in particular.
//
// This contract deliberately implements nothing but the refund. It is intended to be installed with
// `replace_class_hash`, used once, and replaced with the real TWAMM implementation in the same
// transaction, so the TWAMM is never left in this state. It reports the TWAMM's primary interface
// id so that both upgrades pass the id check in `Upgradeable#replace_class_hash`.
//
// It reads no TWAMM state and writes none. Its storage declares only the members it needs, at the
// same names -- and therefore the same addresses -- as the TWAMM's, so `core` and the owner are
// read from the storage the TWAMM already wrote.
#[starknet::contract]
pub mod TWAMMRefund {
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use crate::components::owned::{Ownable, Owned as owned_component};
    use crate::components::upgradeable::{IHasInterface, Upgradeable as upgradeable_component};
    use crate::components::util::{call_core_with_callback, consume_callback_data, serialize};
    use crate::interfaces::core::{ICoreDispatcher, ICoreDispatcherTrait, ILocker};
    use super::{ContractAddress, ITWAMMRefund, Refund};

    component!(path: owned_component, storage: owned, event: OwnedEvent);
    #[abi(embed_v0)]
    impl Owned = owned_component::OwnedImpl<ContractState>;
    impl OwnableImpl = owned_component::OwnableImpl<ContractState>;

    component!(path: upgradeable_component, storage: upgradeable, event: UpgradeableEvent);
    #[abi(embed_v0)]
    impl Upgradeable = upgradeable_component::UpgradeableImpl<ContractState>;

    // Mirrors the corresponding members of the TWAMM's storage. The TWAMM's remaining members are
    // untouched by this implementation and so are omitted.
    #[storage]
    struct Storage {
        core: ICoreDispatcher,
        #[substorage(v0)]
        upgradeable: upgradeable_component::Storage,
        #[substorage(v0)]
        owned: owned_component::Storage,
    }

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress, core: ICoreDispatcher) {
        self.initialize_owned(owner);
        self.core.write(core);
    }

    #[derive(starknet::Event, Drop)]
    pub struct Refunded {
        pub token: ContractAddress,
        pub recipient: ContractAddress,
        pub amount: u128,
    }

    #[derive(starknet::Event, Drop)]
    #[event]
    enum Event {
        #[flat]
        UpgradeableEvent: upgradeable_component::Event,
        OwnedEvent: owned_component::Event,
        Refunded: Refunded,
    }

    // Reports the TWAMM's interface id, not its own, so that this class can replace the TWAMM and
    // then be replaced by it.
    #[abi(embed_v0)]
    impl TWAMMRefundHasInterface of IHasInterface<ContractState> {
        fn get_primary_interface_id(self: @ContractState) -> felt252 {
            return selector!("ekubo::extensions::twamm::TWAMM");
        }
    }

    #[abi(embed_v0)]
    impl TWAMMRefundImpl of ITWAMMRefund<ContractState> {
        fn refund(ref self: ContractState, refunds: Array<Refund>) {
            self.require_owner();
            call_core_with_callback::<Array<Refund>, ()>(self.core.read(), @refunds)
        }
    }

    #[abi(embed_v0)]
    impl LockerImpl of ILocker<ContractState> {
        fn locked(ref self: ContractState, id: u32, data: Span<felt252>) -> Span<felt252> {
            let core = self.core.read();
            let refunds = consume_callback_data::<Array<Refund>>(core, data);

            for refund in refunds {
                // Reverts with INSUFFICIENT_SAVED_BALANCE if the TWAMM does not hold this much,
                // so a refund can never draw on tokens the TWAMM was not already holding.
                core.load(token: refund.token, salt: 0, amount: refund.amount);
                core.withdraw(refund.token, refund.recipient, refund.amount);

                self
                    .emit(
                        Refunded {
                            token: refund.token, recipient: refund.recipient, amount: refund.amount,
                        },
                    );
            }

            serialize(@()).span()
        }
    }
}
