use starknet::ContractAddress;

#[starknet::interface]
pub trait ILimitOrdersTopUp<TContractState> {
    // Pays this contract's full balance of each listed token into the limit-orders extension's
    // saved balances in Core, crediting
    // `SavedBalanceKey { owner: <limit-orders extension>, token, salt: 0 }` for each one.
    // Owner only. Fund this contract with plain ERC20 transfers before calling; tokens with a
    // zero balance are skipped.
    fn top_up(ref self: TContractState, tokens: Array<ContractAddress>);
    // The Core contract this contract locks when topping up.
    fn get_core(self: @TContractState) -> ContractAddress;
    // The limit-orders extension whose saved balances are credited.
    fn get_limit_orders(self: @TContractState) -> ContractAddress;
}

// A temporary helper for restoring the limit-orders saved-balance pools drained in the April 2026
// exploit (see the `_limit_orders_postmortem.md` gist).
//
// The drained pools are shared balances in Core keyed by
// `SavedBalanceKey { owner: <limit-orders extension>, token, salt: 0 }`, one per bought token.
// Every executed-but-unclosable order draws from them, so each pool is under-collateralized by
// exactly the stolen amount:
//
// - USDC.e: `47123330423` (6 decimals)
// - EKUBO:  `15381290500925225319523` (18 decimals)
// - ETH:    `457141578614531148` (18 decimals)
//
// This contract lets the owner pay those shortfalls back into Core. Because order execution is now
// self-funding (the fixed extension only saves proceeds that a real swap paid in), funding each
// pool with exactly its shortfall makes pool == outstanding liability, and every affected order
// can then be closed normally, in any order, with no surplus left exposed. Transfer exactly the
// shortfall amounts and nothing else; whatever balance is here at call time is swept in full.
//
// Unlike TWAMMRefund, this contract does NOT replace the extension: `Core.save` takes an explicit
// key, so a standalone locker can credit the extension's balance. No extension upgrade is needed;
// declare this class, deploy it, transfer the three shortfall amounts to it, and call `top_up`.
//
// It reads no limit-orders state and writes none.
#[starknet::contract]
pub mod LimitOrdersTopUp {
    use core::num::traits::Zero;
    use starknet::get_contract_address;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use crate::components::owned::{Ownable, Owned as owned_component};
    use crate::components::util::{call_core_with_callback, consume_callback_data, serialize};
    use crate::interfaces::core::{ICoreDispatcher, ICoreDispatcherTrait, ILocker};
    use crate::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use crate::types::keys::SavedBalanceKey;
    use super::{ContractAddress, ILimitOrdersTopUp};

    component!(path: owned_component, storage: owned, event: OwnedEvent);
    #[abi(embed_v0)]
    impl Owned = owned_component::OwnedImpl<ContractState>;
    impl OwnableImpl = owned_component::OwnableImpl<ContractState>;

    #[storage]
    struct Storage {
        core: ICoreDispatcher,
        limit_orders: ContractAddress,
        #[substorage(v0)]
        owned: owned_component::Storage,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner: ContractAddress,
        core: ICoreDispatcher,
        limit_orders: ContractAddress,
    ) {
        self.initialize_owned(owner);
        self.core.write(core);
        self.limit_orders.write(limit_orders);
    }

    #[derive(starknet::Event, Drop)]
    pub struct ToppedUp {
        pub token: ContractAddress,
        pub amount: u128,
        pub saved_balance_next: u128,
    }

    #[derive(starknet::Event, Drop)]
    #[event]
    enum Event {
        #[flat]
        OwnedEvent: owned_component::Event,
        ToppedUp: ToppedUp,
    }

    #[abi(embed_v0)]
    impl LimitOrdersTopUpImpl of ILimitOrdersTopUp<ContractState> {
        fn top_up(ref self: ContractState, tokens: Array<ContractAddress>) {
            self.require_owner();
            call_core_with_callback::<Array<ContractAddress>, ()>(self.core.read(), @tokens)
        }

        fn get_core(self: @ContractState) -> ContractAddress {
            self.core.read().contract_address
        }

        fn get_limit_orders(self: @ContractState) -> ContractAddress {
            self.limit_orders.read()
        }
    }

    #[abi(embed_v0)]
    impl LockerImpl of ILocker<ContractState> {
        fn locked(ref self: ContractState, id: u32, data: Span<felt252>) -> Span<felt252> {
            let core = self.core.read();
            let limit_orders = self.limit_orders.read();
            let tokens = consume_callback_data::<Array<ContractAddress>>(core, data);

            for token in tokens {
                let balance = IERC20Dispatcher { contract_address: token }
                    .balanceOf(get_contract_address());
                // Core's `pay` would reject anything above u128 anyway; fail loudly here.
                assert(balance.high.is_zero(), 'BALANCE_TOO_LARGE');
                let amount = balance.low;

                if (amount.is_non_zero()) {
                    // `pay` pulls the full allowance, so approve exactly the swept balance.
                    assert(
                        IERC20Dispatcher { contract_address: token }
                            .approve(core.contract_address, balance),
                        'APPROVE_FAILED',
                    );
                    core.pay(token);
                    let saved_balance_next = core
                        .save(SavedBalanceKey { owner: limit_orders, token, salt: 0 }, amount);

                    self.emit(ToppedUp { token, amount, saved_balance_next });
                }
            }

            serialize(@()).span()
        }
    }
}
