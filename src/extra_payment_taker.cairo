use starknet::{ContractAddress};

#[starknet::interface]
trait IExtraPaymentTaker<TStorage> {
    fn take_extra(ref self: TStorage, token: ContractAddress);
}

#[starknet::contract]
mod ExtraPaymentTaker {
    use array::{Array, ArrayTrait, SpanTrait};

    use ekubo::interfaces::core::{ICoreDispatcher, ICoreDispatcherTrait, ILocker};
    use ekubo::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use ekubo::math::swap::{is_price_increasing};
    use ekubo::shared_locker::{consume_callback_data, call_core_with_callback};
    use ekubo::types::i129::{i129Trait};
    use option::{OptionTrait};
    use result::{ResultTrait};
    use starknet::syscalls::{call_contract_syscall};

    use starknet::{get_caller_address, get_contract_address};
    use super::{ContractAddress, IExtraPaymentTaker};
    use traits::{Into};
    use zeroable::{Zeroable};

    #[storage]
    struct Storage {
        core: ICoreDispatcher,
    }

    #[constructor]
    fn constructor(ref self: ContractState, core: ICoreDispatcher) {
        self.core.write(core);
    }

    #[derive(Drop, Copy, Serde)]
    struct CallbackData {
        recipient: ContractAddress,
        token: ContractAddress
    }

    #[external(v0)]
    impl LockerImpl of ILocker<ContractState> {
        fn locked(ref self: ContractState, id: u32, data: Array<felt252>) -> Array<felt252> {
            let core = self.core.read();

            let callback = consume_callback_data::<CallbackData>(core, data);

            let amount = core.deposit(callback.token);
            if (amount > 0) {
                core.withdraw(callback.token, callback.recipient, amount);
            }

            let mut output: Array<felt252> = ArrayTrait::new();
            output
        }
    }


    #[external(v0)]
    impl ExtraPaymentTakerImpl of IExtraPaymentTaker<ContractState> {
        fn take_extra(ref self: ContractState, token: ContractAddress) {
            call_core_with_callback(
                self.core.read(), @CallbackData { recipient: get_caller_address(), token }
            )
        }
    }
}
