use starknet::{ContractAddress};
use ekubo::interfaces::core::{SwapParameters};
use ekubo::types::keys::{PoolKey};
use ekubo::types::delta::{Delta};

#[starknet::interface]
trait ISimpleSwapper<TStorage> {
    fn swap(
        ref self: TStorage,
        pool_key: PoolKey,
        swap_params: SwapParameters,
        recipient: ContractAddress
    ) -> Delta;
}

#[starknet::contract]
mod SimpleSwapper {
    use array::{Array, ArrayTrait, SpanTrait};
    use option::{OptionTrait};
    use result::{ResultTrait};
    use zeroable::{Zeroable};
    use traits::{Into};

    use ekubo::interfaces::core::{ICoreDispatcher, ICoreDispatcherTrait, ILocker};
    use ekubo::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use super::{ContractAddress, PoolKey, Delta, ISimpleSwapper, SwapParameters};
    use ekubo::shared_locker::{consume_callback_data, call_core_with_callback};
    use ekubo::types::i129::{i129Trait};
    use ekubo::math::swap::{is_price_increasing};

    use starknet::{get_caller_address};
    use starknet::syscalls::{call_contract_syscall};

    #[storage]
    struct Storage {
        core: ICoreDispatcher, 
    }


    #[constructor]
    fn constructor(ref self: ContractState, core: ICoreDispatcher) {
        self.core.write(core);
    }

    #[derive(Drop, Copy, Serde)]
    struct SwapCallbackData {
        pool_key: PoolKey,
        swap_params: SwapParameters,
        recipient: ContractAddress,
    }

    #[external(v0)]
    impl QuoterLockerImpl of ILocker<ContractState> {
        fn locked(ref self: ContractState, id: u32, data: Array<felt252>) -> Array<felt252> {
            let core = self.core.read();

            let callback = consume_callback_data::<SwapCallbackData>(core, data);

            let delta = core.swap(callback.pool_key, callback.swap_params);

            let increasing = is_price_increasing(
                callback.swap_params.amount.sign, callback.swap_params.is_token1
            );

            if increasing {
                // if increasing, the amount0 == output
                if delta.amount0.is_non_zero() {
                    core.withdraw(callback.pool_key.token0, callback.recipient, delta.amount0.mag);
                }
                if delta.amount1.is_non_zero() {
                    IERC20Dispatcher {
                        contract_address: callback.pool_key.token1
                    }.transfer(core.contract_address, delta.amount1.mag.into());
                    core.deposit(callback.pool_key.token1);
                }
            } else {
                // if decreasing, the amount0 == input
                if delta.amount0.is_non_zero() {
                    IERC20Dispatcher {
                        contract_address: callback.pool_key.token0
                    }.transfer(core.contract_address, delta.amount0.mag.into());
                    core.deposit(callback.pool_key.token0);
                }
                if delta.amount1.is_non_zero() {
                    core.withdraw(callback.pool_key.token1, callback.recipient, delta.amount1.mag);
                }
            }

            let mut output: Array<felt252> = ArrayTrait::new();
            Serde::serialize(@delta, ref output);
            output
        }
    }


    #[external(v0)]
    impl SimpleSwapperImpl of ISimpleSwapper<ContractState> {
        fn swap(
            ref self: ContractState,
            pool_key: PoolKey,
            swap_params: SwapParameters,
            recipient: ContractAddress
        ) -> Delta {
            call_core_with_callback(
                self.core.read(), @SwapCallbackData { pool_key, swap_params, recipient }
            )
        }
    }
}
