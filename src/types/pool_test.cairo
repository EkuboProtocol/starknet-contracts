use starknet::{storage_base_address_const, Store, StorePacking, SyscallResult, SyscallResultTrait};
use ekubo::types::pool::{PoolPrice};
use ekubo::types::i129::i129;
use traits::{Into};
use ekubo::types::call_points::CallPoints;
use zeroable::Zeroable;
use ekubo::math::ticks::{min_tick, max_tick, min_sqrt_ratio, max_sqrt_ratio};


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
