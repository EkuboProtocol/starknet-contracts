use core::option::{OptionTrait};
use ekubo::interfaces::erc20::{IERC20Dispatcher};
use ekubo::lens::token_registry::{
    ITokenRegistryDispatcherTrait,
    TokenRegistry::{FeltIntoByteArray, Registration, get_string_metadata, ten_pow},
};
use ekubo::tests::helper::{Deployer, DeployerTrait};
use ekubo::tests::mock_erc20::{MockERC20IERC20ImplTrait};
use starknet::{
    ContractAddress, get_contract_address, syscalls::{deploy_syscall}, testing::{pop_log},
};

#[test]
fn test_ten_pow() {
    assert_eq!(ten_pow(0), 1);
    assert_eq!(ten_pow(1), 10);
    assert_eq!(ten_pow(2), 100);
    assert_eq!(ten_pow(3), 1_000);
    assert_eq!(ten_pow(4), 10_000);
    assert_eq!(ten_pow(5), 100_000);
    assert_eq!(ten_pow(6), 1_000_000);
    assert_eq!(ten_pow(18), 1_000_000_000_000_000_000);
}

#[starknet::interface]
trait ITestTarget<T> {
    fn a(self: @T) -> felt252;
    fn b(self: @T) -> ByteArray;
}

#[starknet::contract]
mod TestTarget {
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};

    #[storage]
    struct Storage {
        a: felt252,
        b: ByteArray,
    }

    #[constructor]
    fn constructor(ref self: ContractState, a: felt252, b: ByteArray) {
        self.a.write(a);
        self.b.write(b);
    }

    #[abi(embed_v0)]
    impl TestTargetImpl of super::ITestTarget<ContractState> {
        fn a(self: @ContractState) -> felt252 {
            self.a.read()
        }

        fn b(self: @ContractState) -> ByteArray {
            self.b.read()
        }
    }
}


fn deploy_test_target(a: felt252, b: ByteArray) -> ContractAddress {
    let mut args: Array<felt252> = array![];
    Serde::serialize(@a, ref args);
    Serde::serialize(@b, ref args);

    let (address, _) = deploy_syscall(
        TestTarget::TEST_CLASS_HASH.try_into().unwrap(), 0, args.span(), true,
    )
        .expect('test target deploy');

    address
}


#[test]
fn test_felt252_into_byte_array() {
    assert_eq!(FeltIntoByteArray::into('abc'), "abc");
    assert_eq!(FeltIntoByteArray::into(''), "");
    assert_eq!(
        FeltIntoByteArray::into('1234567890123456789012345678901'),
        "1234567890123456789012345678901",
    );
}

#[test]
fn test_get_string_metadata() {
    let tt = deploy_test_target('abc', "abc");
    assert_eq!(get_string_metadata(tt, selector!("a")), get_string_metadata(tt, selector!("b")));
    // max length
    let tt = deploy_test_target(
        '1234567890123456789012345678901', "1234567890123456789012345678901",
    );
    assert_eq!(get_string_metadata(tt, selector!("a")), get_string_metadata(tt, selector!("b")));
    // longer than max length
    let tt = deploy_test_target('', "12345678901234567890123456789012345678901234567890");
    assert_eq!(
        get_string_metadata(tt, selector!("b")),
        "12345678901234567890123456789012345678901234567890",
    )
}

#[test]
fn test_register() {
    let mut d: Deployer = Default::default();

    let core = d.deploy_core();
    let erc20 = d
        .deploy_mock_token_with_balance(get_contract_address(), 0xffffffffffffffffffffffffffffffff);
    let registry = d.deploy_token_registry(core);
    // 1e18
    erc20.transfer(registry.contract_address, 1_000_000_000_000_000_000);
    assert_eq!(erc20.balanceOf(registry.contract_address), 1_000_000_000_000_000_000_u256);
    registry.register_token(IERC20Dispatcher { contract_address: erc20.contract_address });
    let registration: Registration = pop_log(registry.contract_address).unwrap();
    assert_eq!(
        registration,
        Registration {
            address: erc20.contract_address,
            name: "",
            symbol: "",
            decimals: 18,
            total_supply: 0xffffffffffffffffffffffffffffffff,
        },
    )
}
