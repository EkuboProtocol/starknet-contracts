use starknet::{storage_base_address_const, StorageAccess, SyscallResult, SyscallResultTrait};
use ekubo::types::pool::Pool;
use ekubo::types::i129::i129;
use traits::{Into};
use ekubo::types::call_points::CallPoints;
use zeroable::Zeroable;

#[test]
#[available_gas(3000000)]
fn test_storage_access_write_read_empty() {
    let base = storage_base_address_const::<0>();
    let write = StorageAccess::<Pool>::write_at_offset_internal(
        address_domain: 0,
        base: base,
        offset: 0_u8,
        value: Pool {
            sqrt_ratio: Zeroable::zero(),
            tick: Zeroable::zero(),
            call_points: Default::default(),
            liquidity: Zeroable::zero(),
            fee_growth_global_token0: Zeroable::zero(),
            fee_growth_global_token1: Zeroable::zero(),
        }
    )
        .unwrap_syscall();
    let read = StorageAccess::<Pool>::read_at_offset_internal(
        address_domain: 0, base: base, offset: 0_u8
    )
        .unwrap_syscall();

    assert(read.sqrt_ratio.is_zero(), 'sqrt_ratio');
    assert(read.tick.is_zero(), 'tick');
    assert(read.call_points == Default::default(), 'call_points');
    assert(read.liquidity.is_zero(), 'liquidity');
    assert(read.fee_growth_global_token0.is_zero(), 'fggt0');
    assert(read.fee_growth_global_token1.is_zero(), 'fggt1');
}
