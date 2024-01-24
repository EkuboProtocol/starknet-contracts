use ekubo::interfaces::erc20::{IERC20Dispatcher};

#[starknet::interface]
trait ITokenRegistry<ContractState> {
    fn register_token(ref self: ContractState, token: IERC20Dispatcher);
}


// A simplified interface for a fungible token standard. 
#[starknet::interface]
trait IERC20Metadata<TStorage> {
    fn name(self: @TStorage) -> felt252;
    fn symbol(self: @TStorage) -> felt252;
    fn decimals(self: @TStorage) -> u8;
    fn totalSupply(self: @TStorage) -> u256;
}


#[starknet::contract]
mod TokenRegistry {
    use core::num::traits::{Zero};
    use ekubo::components::shared_locker::{call_core_with_callback, consume_callback_data};
    use ekubo::interfaces::core::{ICoreDispatcher, ICoreDispatcherTrait, ILocker};
    use ekubo::interfaces::erc20::{IERC20DispatcherTrait};
    use starknet::{ContractAddress, get_contract_address, get_caller_address};
    use super::{
        IERC20Dispatcher, ITokenRegistry, IERC20MetadataDispatcher, IERC20MetadataDispatcherTrait
    };

    #[storage]
    struct Storage {
        core: ICoreDispatcher,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Registration: Registration,
    }

    #[derive(starknet::Event, Drop)]
    struct Registration {
        address: ContractAddress,
        name: felt252,
        symbol: felt252,
        decimals: u8,
        total_supply: u128,
    }

    #[constructor]
    fn constructor(ref self: ContractState, core: ICoreDispatcher) {
        self.core.write(core);
    }

    // Computes 10^x
    fn ten_pow(x: u8) -> u128 {
        if (x == 0) {
            1_u128
        } else if (x == 1) {
            10_u128
        } else {
            let half = ten_pow(x / 2);
            half * half * if (x % 2 == 0) {
                1
            } else {
                10
            }
        }
    }

    #[abi(embed_v0)]
    impl TokenRegistryImpl of ITokenRegistry<ContractState> {
        fn register_token(ref self: ContractState, token: IERC20Dispatcher) {
            let metadata = IERC20MetadataDispatcher { contract_address: token.contract_address };

            let balance: u128 = token
                .balanceOf(get_contract_address())
                .try_into()
                .expect('Balance exceeds u128');

            let (name, symbol, decimals, total_supply) = (
                metadata.name(), metadata.symbol(), metadata.decimals(), metadata.totalSupply()
            );

            assert(decimals < 78, 'Decimals too large');
            assert(total_supply.high.is_zero(), 'Total supply exceeds u128');

            let tokens_required_for_test = ten_pow(decimals);

            assert(balance >= tokens_required_for_test.into(), 'Must transfer tokens for test');

            call_core_with_callback::<
                (ContractAddress, IERC20Dispatcher, u128), ()
            >(self.core.read(), @(get_caller_address(), token, balance));

            self
                .emit(
                    Registration {
                        address: token.contract_address,
                        name,
                        symbol,
                        decimals,
                        total_supply: total_supply.low,
                    }
                );
        }
    }

    #[abi(embed_v0)]
    impl LockerImpl of ILocker<ContractState> {
        fn locked(ref self: ContractState, id: u32, data: Array<felt252>) -> Array<felt252> {
            let core = self.core.read();
            let (refund_to, token, amount) = consume_callback_data::<
                (ContractAddress, IERC20Dispatcher, u128)
            >(core, data);

            token.approve(core.contract_address, amount.into());

            core.pay(token.contract_address);

            core.withdraw(token.contract_address, refund_to, amount);

            Default::default()
        }
    }
}
