use ekubo::interfaces::erc20::{IERC20Dispatcher};

#[starknet::interface]
pub trait ITokenRegistry<ContractState> {
    fn register_token(ref self: ContractState, token: IERC20Dispatcher);
    fn get_token_metadata(
        self: @ContractState, token: IERC20Dispatcher,
    ) -> (ByteArray, ByteArray, u8, u256);
}


// A simplified interface for a fungible token standard.
#[starknet::interface]
pub trait IERC20Metadata<TContractState> {
    fn decimals(self: @TContractState) -> u8;
    fn totalSupply(self: @TContractState) -> u256;
}


#[starknet::contract]
pub mod TokenRegistry {
    use core::num::traits::{Zero};
    use ekubo::components::util::{call_core_with_callback, consume_callback_data};
    use ekubo::interfaces::core::{ICoreDispatcher, ICoreDispatcherTrait, ILocker};
    use ekubo::interfaces::erc20::{IERC20DispatcherTrait};
    use ekubo::math::bits::{msb};
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::{
        ContractAddress, get_caller_address, get_contract_address,
        syscalls::{call_contract_syscall},
    };
    use super::{
        IERC20Dispatcher, IERC20MetadataDispatcher, IERC20MetadataDispatcherTrait, ITokenRegistry,
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

    #[derive(starknet::Event, Drop, PartialEq, Debug)]
    pub struct Registration {
        pub address: ContractAddress,
        pub name: ByteArray,
        pub symbol: ByteArray,
        pub decimals: u8,
        pub total_supply: u128,
    }

    #[constructor]
    fn constructor(ref self: ContractState, core: ICoreDispatcher) {
        self.core.write(core);
    }

    // Computes 10^x
    pub(crate) fn ten_pow(x: u8) -> u128 {
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

    pub(crate) impl FeltIntoByteArray of Into<felt252, ByteArray> {
        fn into(self: felt252) -> ByteArray {
            let mut data: u256 = self.into();
            let num_bits = if data.high.is_non_zero() {
                msb(data.high) + 127
            } else if data.low.is_non_zero() {
                msb(data.low)
            } else {
                0
            };

            let length_bytes = (num_bits + 7) / 8;

            let mut res: ByteArray = "";
            res.append_word(self, length_bytes.into());
            res
        }
    }

    // Returns the string representation of the token's symbol/name
    pub(crate) fn get_string_metadata(address: ContractAddress, selector: felt252) -> ByteArray {
        let mut result = call_contract_syscall(address, selector, array![].span())
            .expect('Failed to get metadata');

        let result_len = result.len();
        assert(result_len == 1 || result_len > 2, 'Unexpected metadata len');

        if result.len() == 1 {
            (*result.pop_front().unwrap()).into()
        } else {
            Serde::deserialize(ref result).unwrap()
        }
    }

    #[abi(embed_v0)]
    impl TokenRegistryImpl of ITokenRegistry<ContractState> {
        fn get_token_metadata(
            self: @ContractState, token: IERC20Dispatcher,
        ) -> (ByteArray, ByteArray, u8, u256) {
            let metadata = IERC20MetadataDispatcher { contract_address: token.contract_address };

            (
                get_string_metadata(token.contract_address, selector!("name")),
                get_string_metadata(token.contract_address, selector!("symbol")),
                metadata.decimals(),
                metadata.totalSupply(),
            )
        }

        fn register_token(ref self: ContractState, token: IERC20Dispatcher) {
            let balance: u128 = token
                .balanceOf(get_contract_address())
                .try_into()
                .expect('Balance exceeds u128');

            let (name, symbol, decimals, total_supply) = self.get_token_metadata(token);

            assert(decimals < 78, 'Decimals too large');
            assert(total_supply.high.is_zero(), 'Total supply exceeds u128');

            let tokens_required_for_test = ten_pow(decimals);

            assert(balance >= tokens_required_for_test.into(), 'Must transfer tokens for test');

            call_core_with_callback::<
                (ContractAddress, IERC20Dispatcher, u128), (),
            >(self.core.read(), @(get_caller_address(), token, balance));

            self
                .emit(
                    Registration {
                        address: token.contract_address,
                        name,
                        symbol,
                        decimals,
                        total_supply: total_supply.low,
                    },
                );
        }
    }

    #[abi(embed_v0)]
    impl LockerImpl of ILocker<ContractState> {
        fn locked(ref self: ContractState, id: u32, data: Span<felt252>) -> Span<felt252> {
            let core = self.core.read();
            let (refund_to, token, amount) = consume_callback_data::<
                (ContractAddress, IERC20Dispatcher, u128),
            >(core, data);

            token.approve(core.contract_address, amount.into());

            core.pay(token.contract_address);

            core.withdraw(token.contract_address, refund_to, amount);

            Default::<Array<felt252>>::default().span()
        }
    }
}
