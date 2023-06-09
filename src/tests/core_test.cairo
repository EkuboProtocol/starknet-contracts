use ekubo::core::{Core};
use ekubo::interfaces::core::{ICoreDispatcher, ICoreDispatcherTrait, Delta};
use starknet::contract_address_const;
use starknet::ContractAddress;
use starknet::testing::{set_caller_address, set_contract_address};
use integer::u256;
use integer::u256_from_felt252;
use integer::BoundedInt;
use traits::Into;
use ekubo::types::keys::PoolKey;
use ekubo::types::storage::{Pool};
use ekubo::types::i129::i129;
use ekubo::math::ticks::{max_sqrt_ratio, min_sqrt_ratio, min_tick, max_tick};
use array::{ArrayTrait};
use option::OptionTrait;
use option::Option;
use ekubo::tests::mocks::mock_erc20::{MockERC20, IMockERC20Dispatcher, IMockERC20DispatcherTrait};

use ekubo::tests::helper::{FEE_ONE_PERCENT, setup_pool, swap, update_position, SetupPoolResult};

use ekubo::tests::mocks::locker::{
    CoreLocker, Action, ActionResult, ICoreLockerDispatcher, ICoreLockerDispatcherTrait,
    UpdatePositionParameters, SwapParameters
};

mod owner_tests {
    use super::{PoolKey, Core, i129, contract_address_const, set_caller_address};
    #[test]
    #[available_gas(2000000)]
    fn test_constructor_sets_owner() {
        assert(Core::get_owner() == contract_address_const::<0>(), 'not set');
        Core::constructor(contract_address_const::<1>());
        let owner_read = Core::get_owner();
        assert(owner_read == contract_address_const::<1>(), 'owner');
    }

    #[test]
    #[available_gas(2000000)]
    fn test_owner_can_be_changed_by_owner() {
        Core::constructor(contract_address_const::<1>());
        set_caller_address(contract_address_const::<1>());
        Core::set_owner(contract_address_const::<42>());
        assert(Core::get_owner() == contract_address_const::<42>(), 'owner');
    }

    #[test]
    #[available_gas(2000000)]
    #[should_panic(expected: ('OWNER_ONLY', ))]
    fn test_owner_cannot_be_changed_by_caller() {
        set_caller_address(contract_address_const::<1>());
        Core::set_owner(contract_address_const::<42>());
    }
}

mod ticks_bitmap_tests {
    use super::{i129, Core};
    use debug::PrintTrait;

    #[test]
    fn test_word_and_bit_index_0_tick_spacing_1() {
        let (word, bit) = Core::tick_to_word_and_bit_index(
            tick: i129 { mag: 0, sign: false }, tick_spacing: 1
        );
        assert(word == 0, 'word');
        assert(bit == 127, 'bit');

        assert(
            Core::word_and_bit_index_to_tick((0, 127), tick_spacing: 1) == i129 {
                mag: 0, sign: false
            },
            'reverse'
        );
    }

    #[test]
    fn test_word_and_bit_index_negative_0_tick_spacing_1() {
        let (word, bit) = Core::tick_to_word_and_bit_index(
            tick: i129 { mag: 0, sign: true }, tick_spacing: 1
        );
        assert(word == 0, 'word');
        assert(bit == 127, 'bit');

        assert(
            Core::word_and_bit_index_to_tick((0, 127), tick_spacing: 100) == i129 {
                mag: 0, sign: false
            },
            'reverse'
        );
    }

    #[test]
    fn test_word_and_bit_index_0_tick_spacing_100() {
        let (word, bit) = Core::tick_to_word_and_bit_index(
            tick: i129 { mag: 0, sign: false }, tick_spacing: 100
        );
        assert(word == 0, 'word');
        assert(bit == 127, 'bit');

        assert(
            Core::word_and_bit_index_to_tick((0, 127), tick_spacing: 100) == i129 {
                mag: 0, sign: false
            },
            'reverse'
        );
    }

    #[test]
    fn test_word_and_bit_index_negative_0_tick_spacing_100() {
        let (word, bit) = Core::tick_to_word_and_bit_index(
            tick: i129 { mag: 0, sign: true }, tick_spacing: 100
        );
        assert(word == 0, 'word');
        assert(bit == 127, 'bit');

        assert(
            Core::word_and_bit_index_to_tick((0, 127), tick_spacing: 100) == i129 {
                mag: 0, sign: false
            },
            'reverse'
        );
    }

    #[test]
    fn test_word_and_bit_index_50_tick_spacing_100() {
        let (word, bit) = Core::tick_to_word_and_bit_index(
            tick: i129 { mag: 50, sign: false }, tick_spacing: 100
        );
        assert(word == 0, 'word');
        assert(bit == 127, 'bit');

        assert(
            Core::word_and_bit_index_to_tick((0, 127), tick_spacing: 100) == i129 {
                mag: 0, sign: false
            },
            'reverse'
        );
    }

    #[test]
    fn test_word_and_bit_index_99_tick_spacing_100() {
        let (word, bit) = Core::tick_to_word_and_bit_index(
            tick: i129 { mag: 99, sign: false }, tick_spacing: 100
        );
        assert(word == 0, 'word');
        assert(bit == 127, 'bit');

        assert(
            Core::word_and_bit_index_to_tick((0, 127), 100) == i129 { mag: 0, sign: false },
            'reverse'
        )
    }

    #[test]
    fn test_word_and_bit_index_100_tick_spacing_100() {
        let (word, bit) = Core::tick_to_word_and_bit_index(
            tick: i129 { mag: 100, sign: false }, tick_spacing: 100
        );
        assert(word == 0, 'word');
        assert(bit == 126, 'bit');

        assert(
            Core::word_and_bit_index_to_tick((0, 126), 100) == i129 { mag: 100, sign: false },
            'reverse'
        )
    }

    #[test]
    fn test_word_and_bit_index_100_tick_spacing_2() {
        let (word, bit) = Core::tick_to_word_and_bit_index(
            tick: i129 { mag: 100, sign: false }, tick_spacing: 2
        );
        assert(word == 0, 'word');
        assert(bit == 77, 'bit');

        assert(
            Core::word_and_bit_index_to_tick((0, 77), tick_spacing: 2) == i129 {
                mag: 100, sign: false
            },
            'reverse'
        );
    }

    #[test]
    fn test_word_and_bit_index_127_tick_spacing_1() {
        let (word, bit) = Core::tick_to_word_and_bit_index(
            tick: i129 { mag: 127, sign: false }, tick_spacing: 1
        );
        assert(word == 0, 'word');
        assert(bit == 0, 'bit');

        assert(
            Core::word_and_bit_index_to_tick((0, 0), tick_spacing: 1) == i129 {
                mag: 127, sign: false
            },
            'reverse'
        );
    }

    #[test]
    fn test_word_and_bit_index_128_tick_spacing_1() {
        let (word, bit) = Core::tick_to_word_and_bit_index(
            tick: i129 { mag: 128, sign: false }, tick_spacing: 1
        );
        assert(word == 1, 'word');
        assert(bit == 127, 'bit')
    }

    #[test]
    fn test_word_and_bit_index_384_tick_spacing_3() {
        let (word, bit) = Core::tick_to_word_and_bit_index(
            tick: i129 { mag: 384, sign: false }, tick_spacing: 3
        );
        assert(word == 1, 'word');
        assert(bit == 127, 'bit');

        assert(
            Core::word_and_bit_index_to_tick((1, 127), tick_spacing: 3) == i129 {
                mag: 384, sign: false
            },
            'reverse'
        );
    }

    #[test]
    fn test_word_and_bit_index_383_tick_spacing_3() {
        let (word, bit) = Core::tick_to_word_and_bit_index(
            tick: i129 { mag: 383, sign: false }, tick_spacing: 3
        );
        assert(word == 0, 'word');
        assert(bit == 0, 'bit');

        assert(
            Core::word_and_bit_index_to_tick((0, 0), tick_spacing: 3) == i129 {
                mag: 381, sign: false
            },
            'reverse'
        );
    }

    #[test]
    fn test_word_and_bit_index_385_tick_spacing_3() {
        let (word, bit) = Core::tick_to_word_and_bit_index(
            tick: i129 { mag: 385, sign: false }, tick_spacing: 3
        );
        assert(word == 1, 'word');
        assert(bit == 127, 'bit');

        assert(
            Core::word_and_bit_index_to_tick((1, 127), tick_spacing: 3) == i129 {
                mag: 384, sign: false
            },
            'reverse'
        );
    }

    #[test]
    fn test_word_and_bit_index_388_tick_spacing_3() {
        let (word, bit) = Core::tick_to_word_and_bit_index(
            tick: i129 { mag: 388, sign: false }, tick_spacing: 3
        );
        assert(word == 1, 'word');
        assert(bit == 126, 'bit');

        assert(
            Core::word_and_bit_index_to_tick((1, 126), tick_spacing: 3) == i129 {
                mag: 387, sign: false
            },
            'reverse'
        );
    }

    #[test]
    fn test_word_and_bit_index_negative_1_tick_spacing_3() {
        let (word, bit) = Core::tick_to_word_and_bit_index(
            tick: i129 { mag: 1, sign: true }, tick_spacing: 3
        );
        assert(word == 0x100000000, 'word');
        assert(bit == 0, 'bit');

        assert(
            Core::word_and_bit_index_to_tick((0x100000000, 0), tick_spacing: 3) == i129 {
                mag: 3, sign: true
            },
            'reverse'
        );
    }

    #[test]
    fn test_word_and_bit_index_negative_3_tick_spacing_3() {
        let (word, bit) = Core::tick_to_word_and_bit_index(
            tick: i129 { mag: 3, sign: true }, tick_spacing: 3
        );
        assert(word == 0x100000000, 'word');
        assert(bit == 0, 'bit');

        assert(
            Core::word_and_bit_index_to_tick((0x100000000, 0), tick_spacing: 3) == i129 {
                mag: 3, sign: true
            },
            'reverse'
        );
    }

    #[test]
    fn test_word_and_bit_index_negative_4_tick_spacing_3() {
        let (word, bit) = Core::tick_to_word_and_bit_index(
            tick: i129 { mag: 4, sign: true }, tick_spacing: 3
        );
        assert(word == 0x100000000, 'word');
        assert(bit == 1, 'bit');

        assert(
            Core::word_and_bit_index_to_tick((0x100000000, 1), tick_spacing: 3) == i129 {
                mag: 6, sign: true
            },
            'reverse'
        );
    }

    #[test]
    fn test_word_and_bit_index_negative_2_tick_spacing_3() {
        let (word, bit) = Core::tick_to_word_and_bit_index(
            tick: i129 { mag: 2, sign: true }, tick_spacing: 3
        );
        assert(word == 0x100000000, 'word');
        assert(bit == 0, 'bit');

        assert(
            Core::word_and_bit_index_to_tick((0x100000000, 0), tick_spacing: 3) == i129 {
                mag: 3, sign: true
            },
            'reverse'
        );
    }


    #[test]
    fn test_word_and_bit_index_negative_1_tick_spacing_1() {
        let (word, bit) = Core::tick_to_word_and_bit_index(
            tick: i129 { mag: 1, sign: true }, tick_spacing: 1
        );
        assert(word == 0x100000000, 'word');
        assert(bit == 0, 'bit');

        assert(
            Core::word_and_bit_index_to_tick((0x100000000, 0), tick_spacing: 1) == i129 {
                mag: 1, sign: true
            },
            'reverse'
        );
    }

    #[test]
    fn test_word_and_bit_index_negative_3_tick_spacing_1() {
        let (word, bit) = Core::tick_to_word_and_bit_index(
            tick: i129 { mag: 3, sign: true }, tick_spacing: 1
        );
        assert(word == 0x100000000, 'word');
        assert(bit == 2, 'bit');

        assert(
            Core::word_and_bit_index_to_tick((0x100000000, 2), tick_spacing: 1) == i129 {
                mag: 3, sign: true
            },
            'reverse'
        );
    }

    #[test]
    fn test_word_and_bit_index_negative_128_tick_spacing_1() {
        let (word, bit) = Core::tick_to_word_and_bit_index(
            tick: i129 { mag: 128, sign: true }, tick_spacing: 1
        );
        assert(word == 0x100000000, 'word');
        assert(bit == 127, 'bit');

        assert(
            Core::word_and_bit_index_to_tick((0x100000000, 127), tick_spacing: 1) == i129 {
                mag: 128, sign: true
            },
            'reverse'
        );
    }

    #[test]
    fn test_word_and_bit_index_negative_129_tick_spacing_1() {
        let (word, bit) = Core::tick_to_word_and_bit_index(
            tick: i129 { mag: 129, sign: true }, tick_spacing: 1
        );
        assert(word == 0x100000001, 'word');
        assert(bit == 0, 'bit');

        assert(
            Core::word_and_bit_index_to_tick((0x100000001, 0), tick_spacing: 1) == i129 {
                mag: 129, sign: true
            },
            'reverse'
        );
    }

    #[test]
    fn test_word_and_bit_index_negative_386_tick_spacing_3() {
        let (word, bit) = Core::tick_to_word_and_bit_index(
            tick: i129 { mag: 386, sign: true }, tick_spacing: 3
        );
        assert(word == 0x100000001, 'word');
        assert(bit == 0, 'bit');

        assert(
            Core::word_and_bit_index_to_tick((0x100000001, 0), tick_spacing: 3) == i129 {
                mag: 387, sign: true
            },
            'reverse'
        );
    }

    #[test]
    fn test_word_and_bit_index_negative_385_tick_spacing_3() {
        let (word, bit) = Core::tick_to_word_and_bit_index(
            tick: i129 { mag: 384, sign: true }, tick_spacing: 3
        );
        assert(word == 0x100000000, 'word');
        assert(bit == 127, 'bit');
        
        assert(
            Core::word_and_bit_index_to_tick((0x100000000, 127), tick_spacing: 3) == i129 {
                mag: 384, sign: true
            },
            'reverse'
        );
    }

    #[test]
    fn test_word_and_bit_index_negative_384_tick_spacing_3() {
        let (word, bit) = Core::tick_to_word_and_bit_index(
            tick: i129 { mag: 384, sign: true }, tick_spacing: 3
        );
        assert(word == 0x100000000, 'word');
        assert(bit == 127, 'bit');
        
        assert(
            Core::word_and_bit_index_to_tick((0x100000000, 127), tick_spacing: 3) == i129 {
                mag: 384, sign: true
            },
            'reverse'
        );
    }

    
}

mod initialize_pool_tests {
    use super::{PoolKey, Core, i129, contract_address_const};
    #[test]
    #[available_gas(2000000)]
    fn test_initialize_pool_works_uninitialized() {
        let pool_key = PoolKey {
            token0: contract_address_const::<1>(),
            token1: contract_address_const::<2>(),
            fee: 0,
            tick_spacing: 1,
        };
        Core::initialize_pool(pool_key, i129 { mag: 1000, sign: true });
        let pool = Core::get_pool(pool_key);
        assert(
            pool.sqrt_ratio == u256 { low: 340112268350713539826535022315348447443, high: 0 },
            'sqrt_ratio'
        );
        assert(pool.tick == i129 { mag: 1000, sign: true }, 'tick');
        assert(pool.liquidity == 0, 'tick');
        assert(pool.fee_growth_global_token0 == u256 { low: 0, high: 0 }, 'fggt0');
        assert(pool.fee_growth_global_token1 == u256 { low: 0, high: 0 }, 'fggt1');
    }

    #[test]
    #[available_gas(3000000)]
    #[should_panic(expected: ('TOKEN_ORDER', ))]
    fn test_initialize_pool_fails_token_order_same_token() {
        let pool_key = PoolKey {
            token0: contract_address_const::<1>(),
            token1: contract_address_const::<1>(),
            fee: 0,
            tick_spacing: 1,
        };
        Core::initialize_pool(pool_key, i129 { mag: 0, sign: false });
    }

    #[test]
    #[available_gas(3000000)]
    #[should_panic(expected: ('TOKEN_ORDER', ))]
    fn test_initialize_pool_fails_token_order_wrong_order() {
        let pool_key = PoolKey {
            token0: contract_address_const::<2>(),
            token1: contract_address_const::<1>(),
            fee: 0,
            tick_spacing: 1,
        };
        Core::initialize_pool(pool_key, i129 { mag: 0, sign: false });
    }

    #[test]
    #[available_gas(3000000)]
    #[should_panic(expected: ('TOKEN_ZERO', ))]
    fn test_initialize_pool_fails_token_order_zero_token() {
        let pool_key = PoolKey {
            token0: contract_address_const::<0>(),
            token1: contract_address_const::<1>(),
            fee: 0,
            tick_spacing: 1,
        };
        Core::initialize_pool(pool_key, i129 { mag: 0, sign: false });
    }

    #[test]
    #[available_gas(3000000)]
    #[should_panic(expected: ('TICK_SPACING', ))]
    fn test_initialize_pool_fails_zero_tick_spacing() {
        let pool_key = PoolKey {
            token0: contract_address_const::<1>(),
            token1: contract_address_const::<2>(),
            fee: 0,
            tick_spacing: 0,
        };
        Core::initialize_pool(pool_key, i129 { mag: 0, sign: false });
    }

    #[test]
    #[available_gas(3000000)]
    fn test_initialize_pool_succeeds_max_tick_spacing_minus_one() {
        let pool_key = PoolKey {
            token0: contract_address_const::<1>(),
            token1: contract_address_const::<2>(),
            fee: 0,
            tick_spacing: 1386294,
        };
        Core::initialize_pool(pool_key, i129 { mag: 0, sign: false });
    }

    #[test]
    #[available_gas(3000000)]
    #[should_panic(expected: ('TICK_SPACING', ))]
    fn test_initialize_pool_fails_max_tick_spacing() {
        let pool_key = PoolKey {
            token0: contract_address_const::<1>(),
            token1: contract_address_const::<2>(),
            fee: 0,
            tick_spacing: 1386295,
        };
        Core::initialize_pool(pool_key, i129 { mag: 0, sign: false });
    }

    #[test]
    #[available_gas(4000000)]
    #[should_panic(expected: ('ALREADY_INITIALIZED', ))]
    fn test_initialize_pool_fails_already_initialized() {
        let pool_key = PoolKey {
            token0: contract_address_const::<1>(),
            token1: contract_address_const::<2>(),
            fee: 0,
            tick_spacing: 1,
        };
        Core::initialize_pool(pool_key, i129 { mag: 1000, sign: true });
        Core::initialize_pool(pool_key, i129 { mag: 1000, sign: true });
    }
}

mod locks {
    use debug::PrintTrait;

    use super::{setup_pool, FEE_ONE_PERCENT, swap, update_position, SetupPoolResult};
    use ekubo::types::i129::{i129OptionPartialEq};
    use super::{
        contract_address_const, Action, ActionResult, ICoreLockerDispatcher,
        ICoreLockerDispatcherTrait, i129, UpdatePositionParameters, SwapParameters,
        IMockERC20Dispatcher, IMockERC20DispatcherTrait, min_sqrt_ratio, max_sqrt_ratio, min_tick,
        max_tick, ICoreDispatcherTrait, ContractAddress, Delta
    };

    #[test]
    #[available_gas(500000000)]
    fn test_assert_locker_id_call() {
        let setup = setup_pool(
            contract_address_const::<1>(), FEE_ONE_PERCENT, 1, Default::default()
        );
        setup.locker.call(Action::AssertLockerId(0));
    }

    #[test]
    #[available_gas(500000000)]
    fn test_relock_call() {
        let setup = setup_pool(
            contract_address_const::<1>(), FEE_ONE_PERCENT, 1, Default::default()
        );
        setup.locker.call(Action::Relock((0, 5)));
    }

    #[test]
    #[available_gas(500000000)]
    #[should_panic(
        expected: (
            'INVALID_LOCKER_ID', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED'
        )
    )]
    fn test_assert_locker_id_call_wrong() {
        let setup = setup_pool(
            contract_address_const::<1>(), FEE_ONE_PERCENT, 1, Default::default()
        );
        setup.locker.call(Action::AssertLockerId(1));
    }

    #[test]
    #[available_gas(500000000)]
    #[should_panic(
        expected: (
            'RL_INVALID_LOCKER_ID', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED'
        )
    )]
    fn test_relock_call_fails_invalid_id() {
        let setup = setup_pool(
            contract_address_const::<1>(), FEE_ONE_PERCENT, 1, Default::default()
        );
        setup.locker.call(Action::Relock((1, 5)));
    }

    #[test]
    #[available_gas(500000000)]
    fn test_zero_liquidity_add() {
        let setup = setup_pool(
            contract_address_const::<1>(), FEE_ONE_PERCENT, 1, Default::default()
        );
        update_position(
            setup,
            i129 { mag: 10, sign: true },
            i129 { mag: 10, sign: false },
            Default::default(),
            contract_address_const::<42>()
        );
    }

    #[test]
    #[available_gas(500000000)]
    #[should_panic(
        expected: (
            'TICK_SPACING',
            'ENTRYPOINT_FAILED',
            'ENTRYPOINT_FAILED',
            'ENTRYPOINT_FAILED',
            'ENTRYPOINT_FAILED'
        )
    )]
    fn test_small_amount_liquidity_add_tick_spacing_not_divisible_lower() {
        let setup = setup_pool(
            contract_address_const::<1>(), FEE_ONE_PERCENT, 3, Default::default()
        );

        update_position(
            setup: setup,
            tick_lower: i129 { mag: 10, sign: true },
            tick_upper: i129 { mag: 12, sign: false },
            liquidity_delta: i129 { mag: 100, sign: false },
            recipient: contract_address_const::<42>()
        );
    }

    #[test]
    #[available_gas(500000000)]
    #[should_panic(
        expected: (
            'TICK_SPACING',
            'ENTRYPOINT_FAILED',
            'ENTRYPOINT_FAILED',
            'ENTRYPOINT_FAILED',
            'ENTRYPOINT_FAILED'
        )
    )]
    fn test_small_amount_liquidity_add_tick_spacing_not_divisible_upper() {
        let setup = setup_pool(
            contract_address_const::<1>(), FEE_ONE_PERCENT, 3, Default::default()
        );

        update_position(
            setup: setup,
            tick_lower: i129 { mag: 12, sign: true },
            tick_upper: i129 { mag: 10, sign: false },
            liquidity_delta: i129 { mag: 100, sign: false },
            recipient: contract_address_const::<42>()
        );
    }


    #[test]
    #[available_gas(500000000)]
    #[should_panic(
        expected: (
            'TICK_SPACING',
            'ENTRYPOINT_FAILED',
            'ENTRYPOINT_FAILED',
            'ENTRYPOINT_FAILED',
            'ENTRYPOINT_FAILED'
        )
    )]
    fn test_small_amount_liquidity_add_no_tokens() {
        let setup = setup_pool(
            contract_address_const::<1>(), FEE_ONE_PERCENT, 3, Default::default()
        );

        let delta = update_position(
            setup: setup,
            tick_lower: i129 { mag: 10, sign: true },
            tick_upper: i129 { mag: 10, sign: false },
            liquidity_delta: i129 { mag: 0, sign: false },
            recipient: contract_address_const::<42>()
        );
        assert(delta.amount0_delta == Default::default(), 'amount0');
        assert(delta.amount1_delta == Default::default(), 'amount1');
    }


    #[test]
    #[available_gas(500000000)]
    fn test_small_amount_liquidity_add() {
        let setup = setup_pool(
            contract_address_const::<1>(), FEE_ONE_PERCENT, 1, Default::default()
        );

        setup.token0.increase_balance(setup.locker.contract_address, 10000000);
        setup.token1.increase_balance(setup.locker.contract_address, 10000000);

        let delta = update_position(
            setup: setup,
            tick_lower: i129 { mag: 10, sign: true },
            tick_upper: i129 { mag: 10, sign: false },
            liquidity_delta: i129 { mag: 10000000, sign: false },
            recipient: contract_address_const::<42>()
        );

        assert(delta.amount0_delta == i129 { mag: 50, sign: false }, 'amount0_delta');
        assert(delta.amount1_delta == i129 { mag: 50, sign: false }, 'amount1_delta');
    }

    #[test]
    #[available_gas(500000000)]
    fn test_larger_amount_liquidity_add() {
        let setup = setup_pool(
            contract_address_const::<1>(), FEE_ONE_PERCENT, 1, Default::default()
        );

        setup.token0.increase_balance(setup.locker.contract_address, 10000000);
        setup.token1.increase_balance(setup.locker.contract_address, 10000000);

        let delta = update_position(
            setup,
            tick_lower: i129 { mag: 10, sign: true },
            tick_upper: i129 { mag: 10, sign: false },
            liquidity_delta: i129 { mag: 1000000000, sign: false },
            recipient: contract_address_const::<42>()
        );

        assert(delta.amount0_delta == i129 { mag: 5000, sign: false }, 'amount0_delta');
        assert(delta.amount1_delta == i129 { mag: 5000, sign: false }, 'amount1_delta');
    }

    #[test]
    #[available_gas(500000000)]
    fn test_full_range_liquidity_add() {
        let setup = setup_pool(
            contract_address_const::<1>(), FEE_ONE_PERCENT, 1, Default::default()
        );

        setup
            .token0
            .increase_balance(setup.locker.contract_address, 0xffffffffffffffffffffffffffffffff);
        setup
            .token1
            .increase_balance(setup.locker.contract_address, 0xffffffffffffffffffffffffffffffff);

        let delta = update_position(
            setup,
            tick_lower: min_tick(),
            tick_upper: max_tick(),
            liquidity_delta: i129 { mag: 1000000000, sign: false },
            recipient: contract_address_const::<42>()
        );

        assert(delta.amount0_delta == i129 { mag: 1000000000, sign: false }, 'amount0_delta');
        assert(delta.amount1_delta == i129 { mag: 1000000000, sign: false }, 'amount1_delta');
    }

    #[test]
    #[available_gas(500000000)]
    fn test_full_range_liquidity_add_and_half_burn() {
        let setup = setup_pool(
            contract_address_const::<1>(), FEE_ONE_PERCENT, 1, Default::default()
        );

        setup
            .token0
            .increase_balance(setup.locker.contract_address, 0xffffffffffffffffffffffffffffffff);
        setup
            .token1
            .increase_balance(setup.locker.contract_address, 0xffffffffffffffffffffffffffffffff);

        update_position(
            setup,
            tick_lower: min_tick(),
            tick_upper: max_tick(),
            liquidity_delta: i129 { mag: 1000000000, sign: false },
            recipient: contract_address_const::<42>()
        );

        let delta = update_position(
            setup,
            tick_lower: min_tick(),
            tick_upper: max_tick(),
            liquidity_delta: i129 { mag: 500000000, sign: true },
            recipient: contract_address_const::<42>()
        );

        assert(delta.amount0_delta == i129 { mag: 494999999, sign: true }, 'amount0_delta');
        assert(delta.amount1_delta == i129 { mag: 494999999, sign: true }, 'amount1_delta');
    }

    #[test]
    #[available_gas(500000000)]
    fn test_full_range_liquidity_add_and_full_burn() {
        let setup = setup_pool(
            contract_address_const::<1>(), FEE_ONE_PERCENT, 1, Default::default()
        );

        setup
            .token0
            .increase_balance(setup.locker.contract_address, 0xffffffffffffffffffffffffffffffff);
        setup
            .token1
            .increase_balance(setup.locker.contract_address, 0xffffffffffffffffffffffffffffffff);

        update_position(
            setup,
            tick_lower: min_tick(),
            tick_upper: max_tick(),
            liquidity_delta: i129 { mag: 1000000000, sign: false },
            recipient: contract_address_const::<42>()
        );

        let delta = update_position(
            setup,
            tick_lower: min_tick(),
            tick_upper: max_tick(),
            liquidity_delta: i129 { mag: 1000000000, sign: true },
            recipient: contract_address_const::<42>()
        );

        assert(delta.amount0_delta == i129 { mag: 989999999, sign: true }, 'amount0_delta');
        assert(delta.amount1_delta == i129 { mag: 989999999, sign: true }, 'amount1_delta');
    }

    #[test]
    #[available_gas(8000000)]
    fn test_swap_token0_zero_amount_zero_liquidity() {
        let setup = setup_pool(
            contract_address_const::<1>(), FEE_ONE_PERCENT, 1, Default::default()
        );

        let delta = swap(
            setup,
            amount: Default::default(), // input 0 token0, price decreasing
            is_token1: false,
            sqrt_ratio_limit: min_sqrt_ratio(),
            recipient: contract_address_const::<42>(),
        );

        assert(delta.amount0_delta == Default::default(), 'amount0_delta');
        assert(delta.amount1_delta == Default::default(), 'amount1_delta');

        let pool = setup.core.get_pool(setup.pool_key);
        assert(pool.sqrt_ratio == u256 { low: 0, high: 1 }, 'price did not move');
        assert(pool.liquidity == 0, 'liquidity is 0');
        assert(pool.fee_growth_global_token0 == u256 { low: 0, high: 0 }, 'fgg0 == 0');
        assert(pool.fee_growth_global_token1 == u256 { low: 0, high: 0 }, 'fgg1 == 0');
    }

    #[test]
    #[available_gas(30000000)]
    fn test_swap_token0_exact_input_no_liquidity() {
        let setup = setup_pool(
            contract_address_const::<1>(), FEE_ONE_PERCENT, 1, Default::default()
        );

        let delta = swap(
            setup,
            amount: i129 { mag: 1, sign: false },
            is_token1: false,
            sqrt_ratio_limit: min_sqrt_ratio(),
            recipient: contract_address_const::<42>(),
        );

        assert(delta.amount0_delta == Default::default(), 'amount0_delta');
        assert(delta.amount1_delta == Default::default(), 'amount1_delta');

        let pool = setup.core.get_pool(setup.pool_key);
        assert(pool.sqrt_ratio == min_sqrt_ratio(), 'price is min');
        assert(pool.liquidity == 0, 'liquidity is 0');
        assert(pool.fee_growth_global_token0 == u256 { low: 0, high: 0 }, 'fgg0 == 0');
        assert(pool.fee_growth_global_token1 == u256 { low: 0, high: 0 }, 'fgg1 == 0');
    }

    #[test]
    #[available_gas(30000000)]
    fn test_swap_token1_exact_input_no_liquidity() {
        let setup = setup_pool(
            contract_address_const::<1>(), FEE_ONE_PERCENT, 1, Default::default()
        );

        let delta = swap(
            setup,
            amount: i129 { mag: 1, sign: false },
            is_token1: true,
            sqrt_ratio_limit: max_sqrt_ratio(),
            recipient: contract_address_const::<42>(),
        );

        assert(delta.amount0_delta == Default::default(), 'amount0_delta');
        assert(delta.amount1_delta == Default::default(), 'amount1_delta');

        let pool = setup.core.get_pool(setup.pool_key);
        assert(pool.sqrt_ratio == max_sqrt_ratio(), 'price is max');
        assert(pool.liquidity == 0, 'liquidity is 0');
        assert(pool.fee_growth_global_token0 == u256 { low: 0, high: 0 }, 'fgg0 == 0');
        assert(pool.fee_growth_global_token1 == u256 { low: 0, high: 0 }, 'fgg1 == 0');
    }

    #[test]
    #[available_gas(30000000)]
    fn test_swap_token0_exact_output_no_liquidity() {
        let setup = setup_pool(
            contract_address_const::<1>(), FEE_ONE_PERCENT, 1, Default::default()
        );

        let delta = swap(
            setup,
            amount: i129 { mag: 1, sign: true },
            is_token1: false,
            sqrt_ratio_limit: max_sqrt_ratio(),
            recipient: contract_address_const::<42>(),
        );

        assert(delta.amount0_delta == Default::default(), 'amount0_delta');
        assert(delta.amount1_delta == Default::default(), 'amount1_delta');

        let pool = setup.core.get_pool(setup.pool_key);
        assert(pool.sqrt_ratio == max_sqrt_ratio(), 'price is max');
        assert(pool.liquidity == 0, 'liquidity is 0');
        assert(pool.fee_growth_global_token0 == u256 { low: 0, high: 0 }, 'fgg0 == 0');
        assert(pool.fee_growth_global_token1 == u256 { low: 0, high: 0 }, 'fgg1 == 0');
    }

    #[test]
    #[available_gas(30000000)]
    fn test_swap_token1_exact_output_no_liquidity() {
        let setup = setup_pool(
            contract_address_const::<1>(), FEE_ONE_PERCENT, 1, Default::default()
        );

        let delta = swap(
            setup,
            amount: i129 { mag: 1, sign: true },
            is_token1: true,
            sqrt_ratio_limit: min_sqrt_ratio(),
            recipient: contract_address_const::<42>(),
        );

        assert(delta.amount0_delta == Default::default(), 'amount0_delta');
        assert(delta.amount1_delta == Default::default(), 'amount1_delta');

        let pool = setup.core.get_pool(setup.pool_key);
        assert(pool.sqrt_ratio == min_sqrt_ratio(), 'price is min');
        assert(pool.liquidity == 0, 'liquidity is 0');
        assert(pool.fee_growth_global_token0 == u256 { low: 0, high: 0 }, 'fgg0 == 0');
        assert(pool.fee_growth_global_token1 == u256 { low: 0, high: 0 }, 'fgg1 == 0');
    }

    #[test]
    #[available_gas(30000000)]
    fn test_swap_token0_exact_input_against_small_liquidity_no_tick_cross() {
        let setup = setup_pool(
            contract_address_const::<1>(), FEE_ONE_PERCENT, 1, Default::default()
        );

        setup.token0.increase_balance(setup.locker.contract_address, 10000000);
        setup.token1.increase_balance(setup.locker.contract_address, 10000000);

        update_position(
            setup,
            tick_lower: i129 { mag: 10, sign: true },
            tick_upper: i129 { mag: 10, sign: false },
            liquidity_delta: i129 { mag: 1000000000, sign: false },
            recipient: contract_address_const::<42>()
        );

        let delta = swap(
            setup,
            amount: i129 { mag: 1000, sign: false },
            is_token1: false,
            sqrt_ratio_limit: min_sqrt_ratio(),
            recipient: contract_address_const::<42>()
        );

        assert(delta.amount0_delta == i129 { mag: 1000, sign: false }, 'amount0_delta==1000');
        assert(delta.amount1_delta == i129 { mag: 989, sign: true }, 'amount1_delta==989');

        let pool = setup.core.get_pool(setup.pool_key);
        assert(
            pool.sqrt_ratio == u256 { low: 340282030041728722151939677011487970083, high: 0 },
            'price lower'
        );
        assert(pool.liquidity == 1000000000, 'liquidity is original');
        assert(
            pool.fee_growth_global_token0 == u256 { low: 3402823669209384634633746074317, high: 0 },
            'fgg0 == 0'
        );
        assert(pool.fee_growth_global_token1 == u256 { low: 0, high: 0 }, 'fgg1 == 0');
    }

    #[test]
    #[available_gas(30000000)]
    fn test_swap_token0_exact_output_against_small_liquidity_no_tick_cross() {
        let setup = setup_pool(
            contract_address_const::<1>(), FEE_ONE_PERCENT, 1, Default::default()
        );

        setup.token0.increase_balance(setup.locker.contract_address, 10000000);
        setup.token1.increase_balance(setup.locker.contract_address, 10000000);

        update_position(
            setup,
            tick_lower: i129 { mag: 10, sign: true },
            tick_upper: i129 { mag: 10, sign: false },
            liquidity_delta: i129 { mag: 1000000000, sign: false },
            recipient: contract_address_const::<42>()
        );

        let delta = swap(
            setup,
            amount: i129 { mag: 1000, sign: true },
            is_token1: false,
            sqrt_ratio_limit: max_sqrt_ratio(),
            recipient: contract_address_const::<42>()
        );

        assert(delta.amount0_delta == i129 { mag: 1000, sign: true }, 'amount0_delta==1000');
        assert(delta.amount1_delta == i129 { mag: 1010, sign: false }, 'amount1_delta==989');

        let pool = setup.core.get_pool(setup.pool_key);
        assert(
            pool.sqrt_ratio == u256 { low: 343685537712540937764355495505137, high: 1 },
            'price lower'
        );
        assert(pool.liquidity == 1000000000, 'liquidity is original');
        assert(
            pool.fee_growth_global_token0 == u256 { low: 3402823669209384634633746074317, high: 0 },
            'fgg0 == 0'
        );
        assert(pool.fee_growth_global_token1 == u256 { low: 0, high: 0 }, 'fgg1 == 0');
    }

    #[test]
    #[available_gas(30000000)]
    fn test_swap_token0_exact_input_against_small_liquidity_with_tick_cross() {
        let setup = setup_pool(
            contract_address_const::<1>(), FEE_ONE_PERCENT, 1, Default::default()
        );

        setup.token0.increase_balance(setup.locker.contract_address, 10000000);
        setup.token1.increase_balance(setup.locker.contract_address, 10000000);

        update_position(
            setup,
            tick_lower: i129 { mag: 10, sign: true },
            tick_upper: i129 { mag: 10, sign: false },
            liquidity_delta: i129 { mag: 10000000, sign: false },
            recipient: contract_address_const::<42>()
        );

        let delta = swap(
            setup,
            amount: i129 { mag: 1000, sign: false },
            is_token1: false,
            sqrt_ratio_limit: min_sqrt_ratio(),
            recipient: contract_address_const::<42>()
        );

        assert(delta.amount0_delta == i129 { mag: 51, sign: false }, 'amount0_delta==1000');
        assert(delta.amount1_delta == i129 { mag: 49, sign: true }, 'amount1_delta==987');

        let pool = setup.core.get_pool(setup.pool_key);
        assert(pool.sqrt_ratio == min_sqrt_ratio(), 'price min');
        assert(pool.liquidity == 0, 'liquidity is 0');
        assert(
            pool.fee_growth_global_token0 == u256 {
                low: 34028236692093846346337460743176, high: 0
            },
            'fgg0 != 0'
        );
        assert(pool.fee_growth_global_token1 == u256 { low: 0, high: 0 }, 'fgg1 == 0');
    }

    #[test]
    #[available_gas(30000000)]
    fn test_swap_token0_exact_output_against_small_liquidity_with_tick_cross() {
        let setup = setup_pool(
            contract_address_const::<1>(), FEE_ONE_PERCENT, 1, Default::default()
        );

        setup.token0.increase_balance(setup.locker.contract_address, 10000000);
        setup.token1.increase_balance(setup.locker.contract_address, 10000000);

        update_position(
            setup,
            tick_lower: i129 { mag: 10, sign: true },
            tick_upper: i129 { mag: 10, sign: false },
            liquidity_delta: i129 { mag: 10000000, sign: false },
            recipient: contract_address_const::<42>()
        );

        let delta = swap(
            setup,
            amount: i129 { mag: 1000, sign: true },
            is_token1: false,
            sqrt_ratio_limit: max_sqrt_ratio(),
            recipient: contract_address_const::<42>()
        );

        assert(delta.amount0_delta == i129 { mag: 50, sign: true }, 'amount0_delta');
        assert(delta.amount1_delta == i129 { mag: 50, sign: false }, 'amount1_delta');

        let pool = setup.core.get_pool(setup.pool_key);
        assert(pool.sqrt_ratio == max_sqrt_ratio(), 'price min');
        assert(pool.liquidity == 0, 'liquidity is 0');
        assert(
            pool.fee_growth_global_token0 == u256 {
                low: 34028236692093846346337460743176, high: 0
            },
            'fgg0 != 0'
        );
        assert(pool.fee_growth_global_token1 == u256 { low: 0, high: 0 }, 'fgg1 == 0');
    }

    #[test]
    #[available_gas(30000000)]
    fn test_swap_token1_exact_input_against_small_liquidity_no_tick_cross() {
        let setup = setup_pool(
            contract_address_const::<1>(), FEE_ONE_PERCENT, 1, Default::default()
        );

        setup.token0.increase_balance(setup.locker.contract_address, 10000000);
        setup.token1.increase_balance(setup.locker.contract_address, 10000000);

        update_position(
            setup,
            tick_lower: i129 { mag: 10, sign: true },
            tick_upper: i129 { mag: 10, sign: false },
            liquidity_delta: i129 { mag: 1000000000, sign: false },
            recipient: contract_address_const::<42>()
        );

        let delta = swap(
            setup,
            amount: i129 { mag: 1000, sign: false },
            is_token1: true,
            sqrt_ratio_limit: max_sqrt_ratio(),
            recipient: contract_address_const::<42>()
        );

        assert(delta.amount1_delta == i129 { mag: 1000, sign: false }, 'amount0_delta==1000');
        assert(delta.amount0_delta == i129 { mag: 989, sign: true }, 'amount1_delta==989');

        let pool = setup.core.get_pool(setup.pool_key);
        assert(
            pool.sqrt_ratio == u256 { low: 336879543251729078828740861357450, high: 1 },
            'price lower'
        );
        assert(pool.liquidity == 1000000000, 'liquidity is original');
        assert(pool.fee_growth_global_token0 == u256 { low: 0, high: 0 }, 'fgg0 == 0');
        assert(
            pool.fee_growth_global_token1 == u256 { low: 3402823669209384634633746074317, high: 0 },
            'fgg1 != 0'
        );
    }

    #[test]
    #[available_gas(30000000)]
    fn test_swap_token1_exact_output_against_small_liquidity_no_tick_cross() {
        let setup = setup_pool(
            contract_address_const::<1>(), FEE_ONE_PERCENT, 1, Default::default()
        );

        setup.token0.increase_balance(setup.locker.contract_address, 10000000);
        setup.token1.increase_balance(setup.locker.contract_address, 10000000);

        update_position(
            setup,
            tick_lower: i129 { mag: 10, sign: true },
            tick_upper: i129 { mag: 10, sign: false },
            liquidity_delta: i129 { mag: 1000000000, sign: false },
            recipient: contract_address_const::<42>()
        );

        let delta = swap(
            setup,
            amount: i129 { mag: 1000, sign: true },
            is_token1: true,
            sqrt_ratio_limit: min_sqrt_ratio(),
            recipient: contract_address_const::<42>()
        );

        assert(delta.amount1_delta == i129 { mag: 1000, sign: true }, 'amount0_delta');
        assert(delta.amount0_delta == i129 { mag: 1010, sign: false }, 'amount1_delta');

        let pool = setup.core.get_pool(setup.pool_key);
        assert(
            pool.sqrt_ratio == u256 { low: 340282023235747873315526509423414705371, high: 0 },
            'price'
        );
        assert(pool.liquidity == 1000000000, 'liquidity is original');
        assert(pool.fee_growth_global_token0 == u256 { low: 0, high: 0 }, 'fgg0 == 0');
        assert(
            pool.fee_growth_global_token1 == u256 { low: 3402823669209384634633746074317, high: 0 },
            'fgg1 != 0'
        );
    }

    #[test]
    #[available_gas(30000000)]
    fn test_swap_token1_exact_input_against_small_liquidity_with_tick_cross() {
        let setup = setup_pool(
            contract_address_const::<1>(), FEE_ONE_PERCENT, 1, Default::default()
        );

        setup.token0.increase_balance(setup.locker.contract_address, 10000000);
        setup.token1.increase_balance(setup.locker.contract_address, 10000000);

        update_position(
            setup,
            tick_lower: i129 { mag: 10, sign: true },
            tick_upper: i129 { mag: 10, sign: false },
            liquidity_delta: i129 { mag: 10000000, sign: false },
            recipient: contract_address_const::<42>()
        );

        let delta = swap(
            setup,
            amount: i129 { mag: 1000, sign: false },
            is_token1: true,
            sqrt_ratio_limit: max_sqrt_ratio(),
            recipient: contract_address_const::<42>()
        );

        assert(delta.amount0_delta == i129 { mag: 49, sign: true }, 'amount0_delta');
        assert(delta.amount1_delta == i129 { mag: 51, sign: false }, 'amount1_delta');

        let pool = setup.core.get_pool(setup.pool_key);
        assert(pool.sqrt_ratio == max_sqrt_ratio(), 'ratio after');
        assert(pool.liquidity == 0, 'liquidity is 0');
        assert(pool.fee_growth_global_token0 == u256 { low: 0, high: 0 }, 'fgg0 == 0');
        assert(
            pool.fee_growth_global_token1 == u256 {
                low: 34028236692093846346337460743176, high: 0
            },
            'fgg1 != 0'
        );
    }

    #[test]
    #[available_gas(30000000)]
    fn test_swap_token1_exact_output_against_small_liquidity_with_tick_cross() {
        let setup = setup_pool(
            contract_address_const::<1>(), FEE_ONE_PERCENT, 1, Default::default()
        );

        setup.token0.increase_balance(setup.locker.contract_address, 10000000);
        setup.token1.increase_balance(setup.locker.contract_address, 10000000);

        update_position(
            setup,
            tick_lower: i129 { mag: 10, sign: true },
            tick_upper: i129 { mag: 10, sign: false },
            liquidity_delta: i129 { mag: 10000000, sign: false },
            recipient: contract_address_const::<42>()
        );

        let delta = swap(
            setup,
            amount: i129 { mag: 1000, sign: true },
            is_token1: true,
            sqrt_ratio_limit: min_sqrt_ratio(),
            recipient: contract_address_const::<42>()
        );

        assert(delta.amount0_delta == i129 { mag: 50, sign: false }, 'amount0_delta');
        assert(delta.amount1_delta == i129 { mag: 50, sign: true }, 'amount1_delta');

        let pool = setup.core.get_pool(setup.pool_key);
        assert(pool.sqrt_ratio == min_sqrt_ratio(), 'ratio after');
        assert(pool.liquidity == 0, 'liquidity is 0');
        assert(pool.fee_growth_global_token0 == u256 { low: 0, high: 0 }, 'fgg0 == 0');
        assert(
            pool.fee_growth_global_token1 == u256 {
                low: 34028236692093846346337460743176, high: 0
            },
            'fgg1 != 0'
        );
    }
}
