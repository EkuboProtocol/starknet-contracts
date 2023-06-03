use parlay::types::i129::{i129, Felt252IntoI129, i129OptionPartialEq};
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
    // the root tick of the initialized ticks tree
    root_tick: Option<i129>,
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

#[derive(Copy, Drop)]
struct TickTreeNode {
    parent: Option<i129>,
    left: Option<i129>,
    right: Option<i129>
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
    fn read_at_offset_internal(
        address_domain: u32, base: StorageBaseAddress, offset: u8
    ) -> SyscallResult<Pool> {
        let sqrt_ratio: u256 = u256 {
            low: storage_read_syscall(
                address_domain, storage_address_from_base_and_offset(base, offset)
            )?
                .try_into()
                .expect('PSQRTL'),
            high: storage_read_syscall(
                address_domain, storage_address_from_base_and_offset(base, offset + 1_u8)
            )?
                .try_into()
                .expect('PSQRTH')
        };

        let root_tick: Option<i129> = storage_read_syscall(
            address_domain, storage_address_from_base_and_offset(base, offset + 2_u8)
        )?
            .into();

        let tick: i129 = storage_read_syscall(
            address_domain, storage_address_from_base_and_offset(base, offset + 3_u8)
        )?
            .into();

        let liquidity: u128 = storage_read_syscall(
            address_domain, storage_address_from_base_and_offset(base, offset + 4_u8)
        )?
            .try_into()
            .expect('LIQ');

        let fee_growth_global_token0: u256 = u256 {
            low: storage_read_syscall(
                address_domain, storage_address_from_base_and_offset(base, offset + 5_u8)
            )?
                .try_into()
                .expect('FGGT0L'),
            high: storage_read_syscall(
                address_domain, storage_address_from_base_and_offset(base, offset + 6_u8)
            )?
                .try_into()
                .expect('FGGT0H')
        };

        let fee_growth_global_token1: u256 = u256 {
            low: storage_read_syscall(
                address_domain, storage_address_from_base_and_offset(base, offset + 7_u8)
            )?
                .try_into()
                .expect('FGGT1L'),
            high: storage_read_syscall(
                address_domain, storage_address_from_base_and_offset(base, offset + 8_u8)
            )?
                .try_into()
                .expect('FGGT1H')
        };

        SyscallResult::Ok(
            Pool {
                sqrt_ratio: sqrt_ratio,
                root_tick: root_tick,
                tick: tick,
                liquidity: liquidity,
                fee_growth_global_token0: fee_growth_global_token0,
                fee_growth_global_token1: fee_growth_global_token1,
            }
        )
    }
    fn write_at_offset_internal(
        address_domain: u32, base: starknet::StorageBaseAddress, offset: u8, value: Pool
    ) -> starknet::SyscallResult<()> {
        storage_write_syscall(
            address_domain,
            storage_address_from_base_and_offset(base, offset),
            value.sqrt_ratio.low.into()
        )?;
        storage_write_syscall(
            address_domain,
            storage_address_from_base_and_offset(base, offset + 1_u8),
            value.sqrt_ratio.high.into()
        )?;
        storage_write_syscall(
            address_domain,
            storage_address_from_base_and_offset(base, offset + 2_u8),
            value.root_tick.into()
        )?;
        storage_write_syscall(
            address_domain,
            storage_address_from_base_and_offset(base, offset + 3_u8),
            value.tick.into()
        )?;
        storage_write_syscall(
            address_domain,
            storage_address_from_base_and_offset(base, offset + 4_u8),
            value.liquidity.into()
        )?;
        storage_write_syscall(
            address_domain,
            storage_address_from_base_and_offset(base, offset + 5_u8),
            value.fee_growth_global_token0.low.into()
        )?;
        storage_write_syscall(
            address_domain,
            storage_address_from_base_and_offset(base, offset + 6_u8),
            value.fee_growth_global_token0.high.into()
        )?;
        storage_write_syscall(
            address_domain,
            storage_address_from_base_and_offset(base, offset + 7_u8),
            value.fee_growth_global_token1.low.into()
        )?;
        storage_write_syscall(
            address_domain,
            storage_address_from_base_and_offset(base, offset + 8_u8),
            value.fee_growth_global_token1.high.into()
        )?;
        SyscallResult::Ok(())
    }
    fn size_internal(value: Pool) -> u8 {
        9_u8
    }

    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<Pool> {
        StorageAccess::<Pool>::read_at_offset_internal(address_domain, base, 0_u8)
    }
    fn write(address_domain: u32, base: StorageBaseAddress, value: Pool) -> SyscallResult<()> {
        StorageAccess::<Pool>::write_at_offset_internal(address_domain, base, 0_u8, value)
    }
}


impl PositionStorageAccess of StorageAccess<Position> {
    fn read_at_offset_internal(
        address_domain: u32, base: StorageBaseAddress, offset: u8
    ) -> SyscallResult<Position> {
        let liquidity: u128 = storage_read_syscall(
            address_domain, storage_address_from_base_and_offset(base, offset)
        )?
            .try_into()
            .expect('LIQUIDITY');
        let fee_growth_inside_last_token0: u256 = u256 {
            low: storage_read_syscall(
                address_domain, storage_address_from_base_and_offset(base, offset + 1_u8)
            )?
                .try_into()
                .expect('FGILT0_LOW'),
            high: storage_read_syscall(
                address_domain, storage_address_from_base_and_offset(base, offset + 2_u8)
            )?
                .try_into()
                .expect('FGILT0_HIGH')
        };
        let fee_growth_inside_last_token1: u256 = u256 {
            low: storage_read_syscall(
                address_domain, storage_address_from_base_and_offset(base, offset + 3_u8)
            )?
                .try_into()
                .expect('FGILT1_LOW'),
            high: storage_read_syscall(
                address_domain, storage_address_from_base_and_offset(base, offset + 4_u8)
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
    fn write_at_offset_internal(
        address_domain: u32, base: starknet::StorageBaseAddress, offset: u8, value: Position
    ) -> starknet::SyscallResult<()> {
        storage_write_syscall(
            address_domain,
            storage_address_from_base_and_offset(base, offset),
            value.liquidity.into()
        )?;
        storage_write_syscall(
            address_domain,
            storage_address_from_base_and_offset(base, offset + 1_u8),
            value.fee_growth_inside_last_token0.low.into()
        )?;
        storage_write_syscall(
            address_domain,
            storage_address_from_base_and_offset(base, offset + 2_u8),
            value.fee_growth_inside_last_token0.high.into()
        )?;
        storage_write_syscall(
            address_domain,
            storage_address_from_base_and_offset(base, offset + 3_u8),
            value.fee_growth_inside_last_token1.low.into()
        )?;
        storage_write_syscall(
            address_domain,
            storage_address_from_base_and_offset(base, offset + 4_u8),
            value.fee_growth_inside_last_token1.high.into()
        )?;
        SyscallResult::Ok(())
    }

    fn size_internal(value: Position) -> u8 {
        5_u8
    }

    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<Position> {
        StorageAccess::<Position>::read_at_offset_internal(address_domain, base, 0_u8)
    }
    fn write(address_domain: u32, base: StorageBaseAddress, value: Position) -> SyscallResult<()> {
        StorageAccess::<Position>::write_at_offset_internal(address_domain, base, 0_u8, value)
    }
}


impl PoolDefault of Default<Pool> {
    fn default() -> Pool {
        Pool {
            sqrt_ratio: Default::default(),
            root_tick: Option::None(()),
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
    fn read_at_offset_internal(
        address_domain: u32, base: StorageBaseAddress, offset: u8
    ) -> SyscallResult<Tick> {
        let liquidity_delta: i129 = StorageAccess::<i129>::read_at_offset_internal(
            address_domain, base, offset
        )?;
        let liquidity_net: u128 = StorageAccess::<u128>::read_at_offset_internal(
            address_domain, base, offset + 1
        )?;
        let fee_growth_outside_token0: u256 = StorageAccess::<u256>::read_at_offset_internal(
            address_domain, base, offset + 3
        )?;
        let fee_growth_outside_token1: u256 = StorageAccess::<u256>::read_at_offset_internal(
            address_domain, base, offset + 5
        )?;

        SyscallResult::Ok(
            Tick {
                liquidity_delta, liquidity_net, fee_growth_outside_token0, fee_growth_outside_token1
            }
        )
    }
    fn write_at_offset_internal(
        address_domain: u32, base: starknet::StorageBaseAddress, offset: u8, value: Tick
    ) -> starknet::SyscallResult<()> {
        StorageAccess::<i129>::write_at_offset_internal(
            address_domain, base, offset, value.liquidity_delta
        )?;
        StorageAccess::<u128>::write_at_offset_internal(
            address_domain, base, offset + 1, value.liquidity_net
        )?;
        StorageAccess::<u256>::write_at_offset_internal(
            address_domain, base, offset + 3, value.fee_growth_outside_token0
        )?;
        StorageAccess::<u256>::write_at_offset_internal(
            address_domain, base, offset + 5, value.fee_growth_outside_token1
        )?;

        SyscallResult::Ok(())
    }
    fn size_internal(value: Tick) -> u8 {
        6_u8
    }
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<Tick> {
        StorageAccess::<Tick>::read_at_offset_internal(address_domain, base, 0_u8)
    }
    fn write(address_domain: u32, base: StorageBaseAddress, value: Tick) -> SyscallResult<()> {
        StorageAccess::<Tick>::write_at_offset_internal(address_domain, base, 0_u8, value)
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


impl TickTreeNodePartialEq of PartialEq<TickTreeNode> {
    fn eq(lhs: TickTreeNode, rhs: TickTreeNode) -> bool {
        (lhs.left == rhs.left) & (lhs.right == rhs.right)
    }
    fn ne(lhs: TickTreeNode, rhs: TickTreeNode) -> bool {
        !PartialEq::<TickTreeNode>::eq(lhs, rhs)
    }
}


impl TickTreeNodeDefault of Default<TickTreeNode> {
    fn default() -> TickTreeNode {
        TickTreeNode { parent: Option::None(()), left: Option::None(()), right: Option::None(()) }
    }
}

impl TickTreeNodeStorageAccess of StorageAccess<TickTreeNode> {
    fn read_at_offset_internal(
        address_domain: u32, base: StorageBaseAddress, offset: u8
    ) -> SyscallResult<TickTreeNode> {
        // read a u128 out of the slot
        let packed_result: felt252 = StorageAccess::<felt252>::read_at_offset_internal(
            address_domain, base, offset
        )?;

        // not set
        if (packed_result == 0) {
            return SyscallResult::Ok(Default::default());
        }

        let mut parsed: u128 = packed_result.try_into().unwrap();

        let (parent, left_right) = u128_safe_divmod(parsed, u128_as_non_zero(0x10000000000000000));
        let (left, right) = u128_safe_divmod(left_right, u128_as_non_zero(0x100000000));

        SyscallResult::Ok(
            TickTreeNode {
                parent: tick_tree_node_internal::to_tick(parent),
                left: tick_tree_node_internal::to_tick(left),
                right: tick_tree_node_internal::to_tick(right)
            }
        )
    }

    fn write_at_offset_internal(
        address_domain: u32, base: starknet::StorageBaseAddress, offset: u8, value: TickTreeNode
    ) -> starknet::SyscallResult<()> {
        // validation of the tree node being written to storage
        match value.left {
            Option::Some(left_value) => {
                assert(left_value.mag < 0x40000000, 'LEFT');
                match value.right {
                    Option::Some(right_value) => {
                        assert(left_value < right_value, 'ORDER');
                    },
                    Option::None(_) => {}
                }
            },
            Option::None(_) => {
                match value.right {
                    Option::Some(right_value) => {
                        assert(right_value.mag < 0x40000000, 'RIGHT');
                    },
                    Option::None(_) => {},
                }
            }
        }

        StorageAccess::<u128>::write_at_offset_internal(
            address_domain,
            base,
            offset,
            (tick_tree_node_internal::to_u32(value.parent) * 0x10000000000000000)
                + (tick_tree_node_internal::to_u32(value.left) * 0x100000000)
                + tick_tree_node_internal::to_u32(value.right)
        )
    }

    fn size_internal(value: TickTreeNode) -> u8 {
        1_u8
    }
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<TickTreeNode> {
        StorageAccess::<TickTreeNode>::read_at_offset_internal(address_domain, base, 0_u8)
    }
    fn write(
        address_domain: u32, base: StorageBaseAddress, value: TickTreeNode
    ) -> SyscallResult<()> {
        StorageAccess::<TickTreeNode>::write_at_offset_internal(address_domain, base, 0_u8, value)
    }
}

