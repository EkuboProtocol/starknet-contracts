use ekubo::types::i129::{i129, Felt252IntoI129, i129OptionPartialEq};
use starknet::ContractAddress;
use core::starknet::storage_access::{
    StorageAccess, SyscallResult, storage_address_from_base_and_offset, StorageBaseAddress,
    storage_read_syscall, storage_write_syscall
};
use traits::{TryInto, Into};
use option::{Option, OptionTrait};
use integer::{u128_as_non_zero, u128_safe_divmod};

#[derive(Copy, Drop, Serde)]
struct Pool {
    // the current ratio, up to 192 bits
    sqrt_ratio: u256,
    // the current tick, up to 32 bits
    tick: i129,
    // the current liquidity, i.e. between tick_prev and tick_next
    liquidity: u128,
    /// the fee growth, all time fees collected per liquidity, full 128x128
    fee_growth_global_token0: u256,
    fee_growth_global_token1: u256,
}

// Represents a liquidity position
#[derive(Copy, Drop, Serde)]
struct Position {
    // the amount of liquidity owned by the position
    liquidity: u128,
    // the fee growth inside the tick range of the position, the last time it was computed
    fee_growth_inside_last_token0: u256,
    fee_growth_inside_last_token1: u256,
}

// The state that is stored for each active tick
#[derive(Copy, Drop, Serde)]
struct Tick {
    // how liquidity changes when this tick is crossed
    liquidity_delta: i129,
    // the total amount of liquidity associated with the tick, necessary to know whether we should remove it from the linked list
    liquidity_net: u128,
    // the fee growth that is on the other side of the tick, from the current tick
    fee_growth_outside_token0: u256,
    fee_growth_outside_token1: u256,
}

const NOT_PRESENT: felt252 = 0x200000000000000000000000000000000; // 2**129
impl OptionalI129IntoFelt252 of Into<Option<i129>, felt252> {
    fn into(self: Option<i129>) -> felt252 {
        match self {
            Option::Some(value) => {
                value.into()
            },
            Option::None(_) => {
                NOT_PRESENT
            }
        }
    }
}
impl Felt252IntoOptionalI129 of Into<felt252, Option<i129>> {
    fn into(self: felt252) -> Option<i129> {
        if (self == NOT_PRESENT) {
            Option::None(())
        } else {
            Option::Some(self.into())
        }
    }
}

impl PoolStorageAccess of StorageAccess<Pool> {
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<Pool> {
        let sqrt_ratio: u256 = u256 {
            low: storage_read_syscall(
                address_domain, storage_address_from_base_and_offset(base, 0_u8)
            )?
                .try_into()
                .expect('PSQRTL'),
            high: storage_read_syscall(
                address_domain, storage_address_from_base_and_offset(base, 1_u8)
            )?
                .try_into()
                .expect('PSQRTH')
        };

        let tick: i129 = storage_read_syscall(
            address_domain, storage_address_from_base_and_offset(base, 2_u8)
        )?
            .into();

        let liquidity: u128 = storage_read_syscall(
            address_domain, storage_address_from_base_and_offset(base, 3_u8)
        )?
            .try_into()
            .expect('LIQ');

        let fee_growth_global_token0: u256 = u256 {
            low: storage_read_syscall(
                address_domain, storage_address_from_base_and_offset(base, 4_u8)
            )?
                .try_into()
                .expect('FGGT0L'),
            high: storage_read_syscall(
                address_domain, storage_address_from_base_and_offset(base, 5_u8)
            )?
                .try_into()
                .expect('FGGT0H')
        };

        let fee_growth_global_token1: u256 = u256 {
            low: storage_read_syscall(
                address_domain, storage_address_from_base_and_offset(base, 6_u8)
            )?
                .try_into()
                .expect('FGGT1L'),
            high: storage_read_syscall(
                address_domain, storage_address_from_base_and_offset(base, 7_u8)
            )?
                .try_into()
                .expect('FGGT1H')
        };

        SyscallResult::Ok(
            Pool {
                sqrt_ratio: sqrt_ratio,
                tick: tick,
                liquidity: liquidity,
                fee_growth_global_token0: fee_growth_global_token0,
                fee_growth_global_token1: fee_growth_global_token1,
            }
        )
    }
    fn write(
        address_domain: u32, base: starknet::StorageBaseAddress, value: Pool
    ) -> starknet::SyscallResult<()> {
        storage_write_syscall(
            address_domain,
            storage_address_from_base_and_offset(base, 0_u8),
            value.sqrt_ratio.low.into()
        )?;
        storage_write_syscall(
            address_domain,
            storage_address_from_base_and_offset(base, 1_u8),
            value.sqrt_ratio.high.into()
        )?;
        storage_write_syscall(
            address_domain, storage_address_from_base_and_offset(base, 2_u8), value.tick.into()
        )?;
        storage_write_syscall(
            address_domain, storage_address_from_base_and_offset(base, 3_u8), value.liquidity.into()
        )?;
        storage_write_syscall(
            address_domain,
            storage_address_from_base_and_offset(base, 4_u8),
            value.fee_growth_global_token0.low.into()
        )?;
        storage_write_syscall(
            address_domain,
            storage_address_from_base_and_offset(base, 5_u8),
            value.fee_growth_global_token0.high.into()
        )?;
        storage_write_syscall(
            address_domain,
            storage_address_from_base_and_offset(base, 6_u8),
            value.fee_growth_global_token1.low.into()
        )?;
        storage_write_syscall(
            address_domain,
            storage_address_from_base_and_offset(base, 7_u8),
            value.fee_growth_global_token1.high.into()
        )?;
        SyscallResult::Ok(())
    }
}


impl PositionStorageAccess of StorageAccess<Position> {
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<Position> {
        let liquidity: u128 = storage_read_syscall(
            address_domain, storage_address_from_base_and_offset(base, 0_u8)
        )?
            .try_into()
            .expect('LIQUIDITY');
        let fee_growth_inside_last_token0: u256 = u256 {
            low: storage_read_syscall(
                address_domain, storage_address_from_base_and_offset(base, 1_u8)
            )?
                .try_into()
                .expect('FGILT0_LOW'),
            high: storage_read_syscall(
                address_domain, storage_address_from_base_and_offset(base, 2_u8)
            )?
                .try_into()
                .expect('FGILT0_HIGH')
        };
        let fee_growth_inside_last_token1: u256 = u256 {
            low: storage_read_syscall(
                address_domain, storage_address_from_base_and_offset(base, 3_u8)
            )?
                .try_into()
                .expect('FGILT1_LOW'),
            high: storage_read_syscall(
                address_domain, storage_address_from_base_and_offset(base, 4_u8)
            )?
                .try_into()
                .expect('FGILT1_HIGH')
        };

        SyscallResult::Ok(
            Position {
                liquidity: liquidity,
                fee_growth_inside_last_token0: fee_growth_inside_last_token0,
                fee_growth_inside_last_token1: fee_growth_inside_last_token1,
            }
        )
    }
    fn write(
        address_domain: u32, base: starknet::StorageBaseAddress, value: Position
    ) -> starknet::SyscallResult<()> {
        storage_write_syscall(
            address_domain, storage_address_from_base_and_offset(base, 0_u8), value.liquidity.into()
        )?;
        storage_write_syscall(
            address_domain,
            storage_address_from_base_and_offset(base, 1_u8),
            value.fee_growth_inside_last_token0.low.into()
        )?;
        storage_write_syscall(
            address_domain,
            storage_address_from_base_and_offset(base, 2_u8),
            value.fee_growth_inside_last_token0.high.into()
        )?;
        storage_write_syscall(
            address_domain,
            storage_address_from_base_and_offset(base, 3_u8),
            value.fee_growth_inside_last_token1.low.into()
        )?;
        storage_write_syscall(
            address_domain,
            storage_address_from_base_and_offset(base, 4_u8),
            value.fee_growth_inside_last_token1.high.into()
        )?;
        SyscallResult::Ok(())
    }
}


impl PoolDefault of Default<Pool> {
    fn default() -> Pool {
        Pool {
            sqrt_ratio: Default::default(),
            tick: Default::default(),
            liquidity: Default::default(),
            fee_growth_global_token0: Default::default(),
            fee_growth_global_token1: Default::default(),
        }
    }
}

impl PositionDefault of Default<Position> {
    fn default() -> Position {
        Position {
            liquidity: Default::default(),
            fee_growth_inside_last_token0: Default::default(),
            fee_growth_inside_last_token1: Default::default(),
        }
    }
}

impl TickDefault of Default<Tick> {
    fn default() -> Tick {
        Tick {
            liquidity_delta: Default::default(),
            liquidity_net: Default::default(),
            fee_growth_outside_token0: Default::default(),
            fee_growth_outside_token1: Default::default(),
        }
    }
}

impl TickStorageAccess of StorageAccess<Tick> {
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<Tick> {
        let liquidity_delta: i129 = storage_read_syscall(
            address_domain, storage_address_from_base_and_offset(base, 0_u8)
        )?
            .into();

        let liquidity_net: u128 = storage_read_syscall(
            address_domain, storage_address_from_base_and_offset(base, 1_u8)
        )?
            .try_into()
            .expect('LIQUIDITY_NET');

        let fee_growth_outside_token0: u256 = u256 {
            low: storage_read_syscall(
                address_domain, storage_address_from_base_and_offset(base, 2_u8)
            )?
                .try_into()
                .expect('FGOT0_LOW'),
            high: storage_read_syscall(
                address_domain, storage_address_from_base_and_offset(base, 3_u8)
            )?
                .try_into()
                .expect('FGOT0_HIGH')
        };
        let fee_growth_outside_token1: u256 = u256 {
            low: storage_read_syscall(
                address_domain, storage_address_from_base_and_offset(base, 4_u8)
            )?
                .try_into()
                .expect('FGOT1_LOW'),
            high: storage_read_syscall(
                address_domain, storage_address_from_base_and_offset(base, 5_u8)
            )?
                .try_into()
                .expect('FGOT1_HIGH')
        };

        SyscallResult::Ok(
            Tick {
                liquidity_delta, liquidity_net, fee_growth_outside_token0, fee_growth_outside_token1
            }
        )
    }
    fn write(
        address_domain: u32, base: starknet::StorageBaseAddress, value: Tick
    ) -> starknet::SyscallResult<()> {
        storage_write_syscall(
            address_domain,
            storage_address_from_base_and_offset(base, 0_u8),
            value.liquidity_delta.into()
        )?;
        storage_write_syscall(
            address_domain,
            storage_address_from_base_and_offset(base, 1_u8),
            value.liquidity_net.into()
        )?;
        storage_write_syscall(
            address_domain,
            storage_address_from_base_and_offset(base, 2_u8),
            value.fee_growth_outside_token0.low.into()
        )?;
        storage_write_syscall(
            address_domain,
            storage_address_from_base_and_offset(base, 3_u8),
            value.fee_growth_outside_token0.high.into()
        )?;
        storage_write_syscall(
            address_domain,
            storage_address_from_base_and_offset(base, 4_u8),
            value.fee_growth_outside_token1.low.into()
        )?;
        storage_write_syscall(
            address_domain,
            storage_address_from_base_and_offset(base, 5_u8),
            value.fee_growth_outside_token1.high.into()
        )?;

        SyscallResult::Ok(())
    }
}


mod tick_tree_node_internal {
    use super::i129;

    const PRESENT_BIT: u128 = 0x80000000;
    const SIGN_BIT: u128 = 0x40000000;

    fn to_tick(mut x: u128) -> Option<i129> {
        if (x < PRESENT_BIT) {
            Option::None(())
        } else {
            let y = x - PRESENT_BIT;
            if (y >= SIGN_BIT) {
                Option::Some(i129 { mag: y - SIGN_BIT, sign: true })
            } else {
                Option::Some(i129 { mag: y, sign: false })
            }
        }
    }

    fn to_u32(tick: Option<i129>) -> u128 {
        match tick {
            Option::Some(x) => {
                assert(x.mag < 0x40000000, 'OVERFLOW');
                if (x.sign) {
                    x.mag + SIGN_BIT + PRESENT_BIT
                } else {
                    x.mag + PRESENT_BIT
                }
            },
            Option::None(_) => {
                0
            }
        }
    }
}

