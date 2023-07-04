use ekubo::types::i129::{i129};
use ekubo::types::call_points::{CallPoints};
use starknet::{StorageAccess, StorageBaseAddress, SyscallResult};
use zeroable::Zeroable;
use traits::{Into, TryInto};
use option::{OptionTrait, Option};
use integer::{u256_as_non_zero, u128_safe_divmod, u128_as_non_zero};
use ekubo::math::ticks::{min_sqrt_ratio, max_sqrt_ratio, constants as tick_constants};
use ekubo::math::muldiv::{u256_safe_divmod_audited};

#[derive(Copy, Drop, Serde)]
struct Pool {
    // the current ratio, up to 192 bits
    sqrt_ratio: u256,
    // the current tick, up to 32 bits
    tick: i129,
    // the places where specified extension should be called
    call_points: CallPoints,
    // the current liquidity, i.e. between tick_prev and tick_next
    liquidity: u128,
    /// the fee growth, all time fees collected per liquidity, full 128x128
    fee_growth_global_token0: u256,
    fee_growth_global_token1: u256,
}

impl PoolStorageAccess of StorageAccess<Pool> {
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<Pool> {
        StorageAccess::<Pool>::read_at_offset_internal(address_domain, base, 0_u8)
    }
    fn write(address_domain: u32, base: StorageBaseAddress, value: Pool) -> SyscallResult<()> {
        StorageAccess::<Pool>::write_at_offset_internal(address_domain, base, 0_u8, value)
    }
    fn read_at_offset_internal(
        address_domain: u32, base: StorageBaseAddress, offset: u8
    ) -> SyscallResult<Pool> {
        let packed_first_slot: felt252 = StorageAccess::read_at_offset_internal(
            address_domain, base, offset
        )?;
        let packed_first_slot_u256: u256 = packed_first_slot.into();

        // quotient, remainder
        let (tick_call_points, sqrt_ratio) = u256_safe_divmod_audited(
            packed_first_slot_u256,
            u256_as_non_zero(0x1000000000000000000000000000000000000000000000000) // 2n ** 192n
        );

        let (tick_raw, call_points_raw) = u128_safe_divmod(
            tick_call_points.low, u128_as_non_zero(0x100)
        );

        let tick = if (tick_raw >= 0x100000000) {
            i129 { mag: tick_raw - 0x100000000, sign: (tick_raw != 0x100000000) }
        } else {
            i129 { mag: tick_raw, sign: false }
        };

        let call_points: CallPoints = TryInto::<u128, u8>::try_into(call_points_raw)
            .unwrap()
            .into();

        let liquidity = StorageAccess::<u128>::read_at_offset_internal(
            address_domain, base, offset + 1_u8
        )?;

        let fee_growth_global_token0 = StorageAccess::<u256>::read_at_offset_internal(
            address_domain, base, offset + 2_u8
        )?;
        let fee_growth_global_token1 = StorageAccess::<u256>::read_at_offset_internal(
            address_domain, base, offset + 4_u8
        )?;

        Result::Ok(
            Pool {
                sqrt_ratio: sqrt_ratio,
                tick: tick,
                call_points: call_points,
                liquidity: liquidity,
                fee_growth_global_token0: fee_growth_global_token0,
                fee_growth_global_token1: fee_growth_global_token1,
            }
        )
    }

    fn write_at_offset_internal(
        address_domain: u32, base: StorageBaseAddress, offset: u8, value: Pool
    ) -> SyscallResult<()> {
        if (value.sqrt_ratio.is_non_zero()) {
            assert(
                (value.sqrt_ratio >= min_sqrt_ratio()) & (value.sqrt_ratio <= max_sqrt_ratio()),
                'SQRT_RATIO'
            );
        }

        // todo: when trading to the minimum tick, the tick is crossed and the pool tick is set to the minimum tick minus one
        // thus the value stored in pool.tick is between min_tick() - 1 and max_tick()
        assert(
            value
                .tick
                .mag <= (tick_constants::MAX_TICK_MAGNITUDE
                    + if (value.tick.sign) {
                        1
                    } else {
                        0
                    }),
            'TICK_MAGNITUDE'
        );

        let tick_raw_shifted: u128 = if (value.tick.sign & (value.tick.mag != 0)) {
            (value.tick.mag + 0x100000000) * 0x100
        } else {
            value.tick.mag * 0x100
        };

        let packed = value.sqrt_ratio
            + ((u256 {
                low: tick_raw_shifted, high: 0
            } + Into::<u8, u256>::into(value.call_points.into()))
                * 0x1000000000000000000000000000000000000000000000000);

        let packed_felt: felt252 = packed.try_into().unwrap();

        StorageAccess::<felt252>::write_at_offset_internal(
            address_domain, base, offset, packed_felt
        )?;

        StorageAccess::<u128>::write_at_offset_internal(
            address_domain, base, offset + 1, value.liquidity
        )?;

        StorageAccess::<u256>::write_at_offset_internal(
            address_domain, base, offset + 2, value.fee_growth_global_token0
        )?;
        StorageAccess::<u256>::write_at_offset_internal(
            address_domain, base, offset + 4, value.fee_growth_global_token1
        )?;

        SyscallResult::Ok(())
    }

    fn size_internal(value: Pool) -> u8 {
        6
    }
}
