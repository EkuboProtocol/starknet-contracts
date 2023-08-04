use starknet::{storage_base_address_const, Store, StorePacking, SyscallResult, SyscallResultTrait};
use ekubo::types::pool_price::{PoolPrice};
use ekubo::types::i129::i129;
use traits::{Into};
use ekubo::types::call_points::{CallPoints, all_call_points};
use zeroable::Zeroable;
use ekubo::math::ticks::{min_tick, max_tick, min_sqrt_ratio, max_sqrt_ratio};
use ekubo::tests::store_packing_test::{assert_round_trip};

impl PoolPricePartialEq of PartialEq<PoolPrice> {
    fn eq(lhs: @PoolPrice, rhs: @PoolPrice) -> bool {
        (lhs.sqrt_ratio == rhs.sqrt_ratio)
            & (lhs.tick == rhs.tick)
            & (lhs.call_points == rhs.call_points)
    }
    fn ne(lhs: @PoolPrice, rhs: @PoolPrice) -> bool {
        !PartialEq::eq(lhs, rhs)
    }
}

#[test]
fn test_packing_round_trip_many_values() {
    assert_round_trip(
        PoolPrice {
            sqrt_ratio: Zeroable::zero(), tick: Zeroable::zero(), call_points: Default::default()
        }
    );
    assert_round_trip(
        PoolPrice { sqrt_ratio: min_sqrt_ratio(), tick: min_tick(), call_points: all_call_points() }
    );
    assert_round_trip(
        PoolPrice { sqrt_ratio: max_sqrt_ratio(), tick: max_tick(), call_points: all_call_points() }
    );
    assert_round_trip(
        PoolPrice {
            sqrt_ratio: min_sqrt_ratio(), tick: min_tick() - i129 {
                mag: 1, sign: false
            }, call_points: all_call_points()
        }
    );
    assert_round_trip(
        PoolPrice {
            sqrt_ratio: u256 {
                low: 0, high: 123456
                }, tick: i129 {
                mag: 0, sign: false
                }, call_points: CallPoints {
                after_initialize_pool: false,
                before_swap: true,
                after_swap: false,
                before_update_position: true,
                after_update_position: false,
            }
        }
    );
}

#[test]
fn test_store_packing_pool_price() {
    let price = StorePacking::<PoolPrice,
    felt252>::unpack(
        StorePacking::<PoolPrice,
        felt252>::pack(
            PoolPrice {
                sqrt_ratio: u256 {
                    low: 0, high: 123456
                    }, tick: i129 {
                    mag: 100, sign: false
                    }, call_points: CallPoints {
                    after_initialize_pool: false,
                    before_swap: true,
                    after_swap: false,
                    before_update_position: true,
                    after_update_position: false,
                }
            }
        )
    );
    assert(price.sqrt_ratio == u256 { low: 0, high: 123456 }, 'sqrt_ratio');
    assert(price.tick == i129 { mag: 100, sign: false }, 'tick');
    assert(
        price.call_points == CallPoints {
            after_initialize_pool: false,
            before_swap: true,
            after_swap: false,
            before_update_position: true,
            after_update_position: false,
        },
        'call_points'
    );
}
