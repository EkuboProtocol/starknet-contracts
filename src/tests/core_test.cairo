use ekubo::core::{Core};
use ekubo::interfaces::core::{ICoreDispatcherTrait, ICoreDispatcher, Delta};
use starknet::contract_address_const;
use starknet::ContractAddress;
use starknet::testing::{set_contract_address};
use integer::u256;
use integer::u256_from_felt252;
use integer::BoundedInt;
use traits::{Into, TryInto};
use ekubo::types::keys::PoolKey;
use ekubo::types::storage::{Pool};
use ekubo::types::i129::{i129, i129OptionPartialEq};
use ekubo::types::bounds::{Bounds};
use ekubo::math::ticks::{
    max_sqrt_ratio, min_sqrt_ratio, min_tick, max_tick, constants as tick_constants
};
use array::{ArrayTrait};
use option::{Option, OptionTrait};
use ekubo::tests::mocks::mock_erc20::{MockERC20, IMockERC20Dispatcher, IMockERC20DispatcherTrait};
use zeroable::Zeroable;

use ekubo::tests::helper::{
    FEE_ONE_PERCENT, deploy_core, setup_pool, swap, update_position, SetupPoolResult
};

use ekubo::tests::mocks::locker::{
    CoreLocker, Action, ActionResult, ICoreLockerDispatcher, ICoreLockerDispatcherTrait,
    UpdatePositionParameters, SwapParameters
};

impl EqualTickBool of traits::PartialEq<(i129, bool)> {
    fn eq(lhs: @(i129, bool), rhs: @(i129, bool)) -> bool {
        let (a, b) = *lhs;
        let (c, d) = *rhs;
        (a == c) & (b == d)
    }
    fn ne(lhs: @(i129, bool), rhs: @(i129, bool)) -> bool {
        !EqualTickBool::eq(lhs, rhs)
    }
}

mod owner_tests {
    use super::{
        deploy_core, PoolKey, ICoreDispatcherTrait, i129, contract_address_const,
        set_contract_address, MockERC20, TryInto, OptionTrait, Zeroable, IMockERC20Dispatcher,
        IMockERC20DispatcherTrait
    };

    use starknet::class_hash::Felt252TryIntoClassHash;

    #[test]
    #[available_gas(2000000)]
    fn test_constructor_sets_owner() {
        let core = deploy_core();
        assert(core.get_owner().is_non_zero(), 'owner');
    }

    #[test]
    #[available_gas(2000000)]
    fn test_owner_can_be_changed_by_owner() {
        let core = deploy_core();
        set_contract_address(core.get_owner());
        core.set_owner(contract_address_const::<102>());
        assert(core.get_owner() == contract_address_const::<102>(), 'owner');
    }

    #[test]
    #[available_gas(2000000)]
    #[should_panic(expected: ('OWNER_ONLY', 'ENTRYPOINT_FAILED', ))]
    fn test_owner_cannot_be_changed_by_other() {
        let core = deploy_core();
        set_contract_address(contract_address_const::<1>());
        core.set_owner(contract_address_const::<42>());
    }

    #[test]
    #[available_gas(2000000)]
    #[should_panic(expected: ('OWNER_ONLY', 'ENTRYPOINT_FAILED', ))]
    fn test_replace_class_hash_cannot_be_called_by_non_owner() {
        let core = deploy_core();
        set_contract_address(contract_address_const::<1>());
        core.replace_class_hash(Zeroable::zero());
    }

    #[test]
    #[available_gas(2000000)]
    fn test_replace_class_hash_can_be_called_by_owner() {
        let core = deploy_core();
        set_contract_address(core.get_owner());
        core.replace_class_hash(MockERC20::TEST_CLASS_HASH.try_into().unwrap());
    }

    #[test]
    #[available_gas(2000000)]
    #[should_panic(expected: ('ENTRYPOINT_NOT_FOUND', ))]
    fn test_after_replacing_class_hash_calls_fail() {
        let core = deploy_core();
        set_contract_address(core.get_owner());
        core.replace_class_hash(MockERC20::TEST_CLASS_HASH.try_into().unwrap());
        core.replace_class_hash(MockERC20::TEST_CLASS_HASH.try_into().unwrap());
    }

    #[test]
    #[available_gas(2000000)]
    fn test_after_replacing_class_hash_calls_as_new_contract_succeed() {
        let core = deploy_core();
        set_contract_address(core.get_owner());
        core.replace_class_hash(MockERC20::TEST_CLASS_HASH.try_into().unwrap());
        // these won't fail because it has a new implementation
        IMockERC20Dispatcher {
            contract_address: core.contract_address
        }.increase_balance(contract_address_const::<1>(), 100);
        assert(
            IMockERC20Dispatcher {
                contract_address: core.contract_address
            }.balance_of(contract_address_const::<1>()) == 100,
            'balance'
        );
    }
}

mod initialize_pool_tests {
    use super::{
        PoolKey, deploy_core, ICoreDispatcherTrait, i129, contract_address_const,
        i129OptionPartialEq, Zeroable
    };

    #[test]
    #[available_gas(2000000)]
    fn test_initialize_pool_works_uninitialized() {
        let core = deploy_core();
        let pool_key = PoolKey {
            token0: contract_address_const::<1>(),
            token1: contract_address_const::<2>(),
            fee: 0,
            tick_spacing: 1,
            extension: Zeroable::zero(),
        };
        core.initialize_pool(pool_key, i129 { mag: 1000, sign: true });
        let pool = core.get_pool(pool_key);
        assert(
            pool.sqrt_ratio == u256 { low: 340112268350713539826535022315348447443, high: 0 },
            'sqrt_ratio'
        );
        assert(pool.tick == i129 { mag: 1000, sign: true }, 'tick');
        assert(pool.liquidity == 0, 'tick');
        assert(pool.fee_growth_global_token0.is_zero(), 'fggt0');
        assert(pool.fee_growth_global_token1.is_zero(), 'fggt1');
    }

    #[test]
    #[available_gas(3000000)]
    #[should_panic(expected: ('TOKEN_ORDER', 'ENTRYPOINT_FAILED', ))]
    fn test_initialize_pool_fails_token_order_same_token() {
        let core = deploy_core();
        let pool_key = PoolKey {
            token0: contract_address_const::<1>(),
            token1: contract_address_const::<1>(),
            fee: 0,
            tick_spacing: 1,
            extension: Zeroable::zero(),
        };
        core.initialize_pool(pool_key, Zeroable::zero());
    }

    #[test]
    #[available_gas(3000000)]
    #[should_panic(expected: ('TOKEN_ORDER', 'ENTRYPOINT_FAILED', ))]
    fn test_initialize_pool_fails_token_order_wrong_order() {
        let core = deploy_core();
        let pool_key = PoolKey {
            token0: contract_address_const::<2>(),
            token1: contract_address_const::<1>(),
            fee: 0,
            tick_spacing: 1,
            extension: Zeroable::zero(),
        };

        core.initialize_pool(pool_key, Zeroable::zero());
    }

    #[test]
    #[available_gas(3000000)]
    #[should_panic(expected: ('TOKEN_ZERO', 'ENTRYPOINT_FAILED', ))]
    fn test_initialize_pool_fails_token_order_zero_token() {
        let core = deploy_core();
        let pool_key = PoolKey {
            token0: Zeroable::zero(),
            token1: contract_address_const::<1>(),
            fee: 0,
            tick_spacing: 1,
            extension: Zeroable::zero(),
        };
        core.initialize_pool(pool_key, Zeroable::zero());
    }

    #[test]
    #[available_gas(3000000)]
    #[should_panic(expected: ('TICK_SPACING', 'ENTRYPOINT_FAILED', ))]
    fn test_initialize_pool_fails_zero_tick_spacing() {
        let core = deploy_core();
        let pool_key = PoolKey {
            token0: contract_address_const::<1>(),
            token1: contract_address_const::<2>(),
            fee: 0,
            tick_spacing: 0,
            extension: Zeroable::zero(),
        };
        core.initialize_pool(pool_key, Zeroable::zero());
    }

    #[test]
    #[available_gas(3000000)]
    fn test_initialize_pool_succeeds_max_tick_spacing_minus_one() {
        let core = deploy_core();
        let pool_key = PoolKey {
            token0: contract_address_const::<1>(),
            token1: contract_address_const::<2>(),
            fee: 0,
            tick_spacing: 1386294,
            extension: Zeroable::zero(),
        };
        core.initialize_pool(pool_key, Zeroable::zero());
    }

    #[test]
    #[available_gas(3000000)]
    #[should_panic(expected: ('TICK_SPACING', 'ENTRYPOINT_FAILED', ))]
    fn test_initialize_pool_fails_max_tick_spacing() {
        let core = deploy_core();
        let pool_key = PoolKey {
            token0: contract_address_const::<1>(),
            token1: contract_address_const::<2>(),
            fee: 0,
            tick_spacing: 1386295,
            extension: Zeroable::zero(),
        };
        core.initialize_pool(pool_key, Zeroable::zero());
    }

    #[test]
    #[available_gas(4000000)]
    #[should_panic(expected: ('ALREADY_INITIALIZED', 'ENTRYPOINT_FAILED', ))]
    fn test_initialize_pool_fails_already_initialized() {
        let core = deploy_core();
        let pool_key = PoolKey {
            token0: contract_address_const::<1>(),
            token1: contract_address_const::<2>(),
            fee: 0,
            tick_spacing: 1,
            extension: Zeroable::zero(),
        };
        core.initialize_pool(pool_key, i129 { mag: 1000, sign: true });
        core.initialize_pool(pool_key, i129 { mag: 1000, sign: true });
    }
}


mod initialized_ticks {
    use super::{
        setup_pool, update_position, contract_address_const, FEE_ONE_PERCENT, tick_constants,
        ICoreDispatcherTrait, i129, IMockERC20DispatcherTrait, EqualTickBool, min_tick, max_tick,
        Bounds
    };

    #[test]
    #[available_gas(30000000)]
    #[should_panic(expected: ('PREV_FROM_MIN', 'ENTRYPOINT_FAILED', ))]
    fn test_prev_initialized_tick_min_tick_minus_one() {
        let setup = setup_pool(
            fee: FEE_ONE_PERCENT,
            tick_spacing: tick_constants::TICKS_IN_ONE_PERCENT,
            initial_tick: Zeroable::zero(),
            extension: Zeroable::zero(),
        );

        setup
            .core
            .prev_initialized_tick(
                pool_key: setup.pool_key,
                from: min_tick() - i129 { mag: 1, sign: false },
                skip_ahead: 0
            );
    }

    #[test]
    #[available_gas(30000000)]
    fn test_prev_initialized_tick_min_tick() {
        let setup = setup_pool(
            fee: FEE_ONE_PERCENT,
            tick_spacing: tick_constants::TICKS_IN_ONE_PERCENT,
            initial_tick: Zeroable::zero(),
            extension: Zeroable::zero(),
        );

        assert(
            setup
                .core
                .prev_initialized_tick(
                    pool_key: setup.pool_key, from: min_tick(), skip_ahead: 5
                ) == (min_tick(), false),
            'min tick always limited'
        );
    }

    #[test]
    #[available_gas(30000000)]
    #[should_panic(expected: ('NEXT_FROM_MAX', 'ENTRYPOINT_FAILED', ))]
    fn test_next_initialized_tick_max_tick() {
        let setup = setup_pool(
            fee: FEE_ONE_PERCENT,
            tick_spacing: tick_constants::TICKS_IN_ONE_PERCENT,
            initial_tick: Zeroable::zero(),
            extension: Zeroable::zero(),
        );

        setup.core.next_initialized_tick(pool_key: setup.pool_key, from: max_tick(), skip_ahead: 0);
    }

    #[test]
    #[available_gas(30000000)]
    fn test_next_initialized_tick_max_tick_minus_one() {
        let setup = setup_pool(
            fee: FEE_ONE_PERCENT,
            tick_spacing: tick_constants::TICKS_IN_ONE_PERCENT,
            initial_tick: Zeroable::zero(),
            extension: Zeroable::zero(),
        );

        assert(
            setup
                .core
                .next_initialized_tick(
                    pool_key: setup.pool_key,
                    from: max_tick() - i129 { mag: 1, sign: false },
                    skip_ahead: 5
                ) == (max_tick(), false),
            'max tick always limited'
        );
    }

    #[test]
    #[available_gas(30000000)]
    fn test_next_prev_initialized_tick_none_initialized() {
        let setup = setup_pool(
            fee: FEE_ONE_PERCENT,
            tick_spacing: tick_constants::TICKS_IN_ONE_PERCENT,
            initial_tick: Zeroable::zero(),
            extension: Zeroable::zero(),
        );

        assert(
            setup
                .core
                .prev_initialized_tick(
                    pool_key: setup.pool_key, from: Zeroable::zero(), skip_ahead: 0
                ) == (Zeroable::zero(), false),
            'prev from 0'
        );

        assert(
            setup
                .core
                .prev_initialized_tick(
                    pool_key: setup.pool_key, from: Zeroable::zero(), skip_ahead: 2
                ) == (i129 { mag: 2547200, sign: true }, false),
            'prev from 0, skip 1'
        );

        assert(
            setup
                .core
                .prev_initialized_tick(
                    pool_key: setup.pool_key, from: Zeroable::zero(), skip_ahead: 5
                ) == (i129 { mag: 6368000, sign: true }, false),
            'prev from 0, skip 5'
        );

        assert(
            setup
                .core
                .next_initialized_tick(
                    pool_key: setup.pool_key, from: Zeroable::zero(), skip_ahead: 0
                ) == (i129 { mag: 1263650, sign: false }, false),
            'next from 0'
        );

        assert(
            setup
                .core
                .next_initialized_tick(
                    pool_key: setup.pool_key, from: Zeroable::zero(), skip_ahead: 1
                ) == (i129 { mag: 2537250, sign: false }, false),
            'next from 0, skip 1'
        );

        assert(
            setup
                .core
                .next_initialized_tick(
                    pool_key: setup.pool_key, from: Zeroable::zero(), skip_ahead: 5
                ) == (i129 { mag: 7631650, sign: false }, false),
            'next from 0, skip 5'
        );
    }

    #[test]
    #[available_gas(300000000)]
    fn test_next_prev_initialized_tick_several_initialized() {
        let setup = setup_pool(
            fee: FEE_ONE_PERCENT,
            tick_spacing: tick_constants::TICKS_IN_ONE_PERCENT,
            initial_tick: Zeroable::zero(),
            extension: Zeroable::zero(),
        );

        setup.token0.increase_balance(setup.locker.contract_address, 100000000);
        setup.token1.increase_balance(setup.locker.contract_address, 100000000);

        update_position(
            setup: setup,
            bounds: Bounds {
                tick_lower: i129 {
                    mag: tick_constants::TICKS_IN_ONE_PERCENT * 12, sign: true
                    }, tick_upper: i129 {
                    mag: tick_constants::TICKS_IN_ONE_PERCENT * 9, sign: false
                },
            },
            liquidity_delta: i129 { mag: 1, sign: false },
            recipient: contract_address_const::<42>()
        );
        update_position(
            setup: setup,
            bounds: Bounds {
                tick_lower: i129 {
                    mag: tick_constants::TICKS_IN_ONE_PERCENT * 128, sign: true
                    }, tick_upper: i129 {
                    mag: tick_constants::TICKS_IN_ONE_PERCENT * 128, sign: false
                },
            },
            liquidity_delta: i129 { mag: 1, sign: false },
            recipient: contract_address_const::<42>()
        );
        update_position(
            setup: setup,
            bounds: Bounds {
                tick_lower: i129 {
                    mag: tick_constants::TICKS_IN_ONE_PERCENT * 154, sign: true
                    }, tick_upper: i129 {
                    mag: tick_constants::TICKS_IN_ONE_PERCENT * 200, sign: false
                },
            },
            liquidity_delta: i129 { mag: 1, sign: false },
            recipient: contract_address_const::<42>()
        );
        // -154, -128, -12, 9, 128, 200

        assert(
            setup
                .core
                .next_initialized_tick(
                    pool_key: setup.pool_key,
                    from: i129 { mag: tick_constants::TICKS_IN_ONE_PERCENT * 500, sign: true },
                    skip_ahead: 5
                ) == (i129 { mag: tick_constants::TICKS_IN_ONE_PERCENT * 154, sign: true }, true),
            'next from -500, skip 5'
        );
        assert(
            setup
                .core
                .next_initialized_tick(
                    pool_key: setup.pool_key,
                    from: i129 { mag: tick_constants::TICKS_IN_ONE_PERCENT * 154, sign: true },
                    skip_ahead: 5
                ) == (i129 { mag: tick_constants::TICKS_IN_ONE_PERCENT * 128, sign: true }, true),
            'next from -154, skip 5'
        );
        assert(
            setup
                .core
                .next_initialized_tick(
                    pool_key: setup.pool_key,
                    from: i129 { mag: tick_constants::TICKS_IN_ONE_PERCENT * 128, sign: true },
                    skip_ahead: 5
                ) == (i129 { mag: tick_constants::TICKS_IN_ONE_PERCENT * 12, sign: true }, true),
            'next from -128, skip 5'
        );
        assert(
            setup
                .core
                .next_initialized_tick(
                    pool_key: setup.pool_key,
                    from: i129 { mag: tick_constants::TICKS_IN_ONE_PERCENT * 12, sign: true },
                    skip_ahead: 5
                ) == (i129 { mag: tick_constants::TICKS_IN_ONE_PERCENT * 9, sign: false }, true),
            'next from -12, skip 5'
        );
        assert(
            setup
                .core
                .next_initialized_tick(
                    pool_key: setup.pool_key,
                    from: i129 { mag: tick_constants::TICKS_IN_ONE_PERCENT * 9, sign: false },
                    skip_ahead: 5
                ) == (i129 { mag: tick_constants::TICKS_IN_ONE_PERCENT * 128, sign: false }, true),
            'next from 9, skip 5'
        );
        assert(
            setup
                .core
                .next_initialized_tick(
                    pool_key: setup.pool_key,
                    from: i129 { mag: tick_constants::TICKS_IN_ONE_PERCENT * 128, sign: false },
                    skip_ahead: 5
                ) == (i129 { mag: tick_constants::TICKS_IN_ONE_PERCENT * 200, sign: false }, true),
            'next from 128, skip 5'
        );

        // prev

        assert(
            setup
                .core
                .prev_initialized_tick(
                    pool_key: setup.pool_key,
                    from: i129 { mag: tick_constants::TICKS_IN_ONE_PERCENT * 500, sign: false },
                    skip_ahead: 5
                ) == (i129 { mag: tick_constants::TICKS_IN_ONE_PERCENT * 200, sign: false }, true),
            'prev from 500, skip 5'
        );
        assert(
            setup
                .core
                .prev_initialized_tick(
                    pool_key: setup.pool_key,
                    from: i129 { mag: tick_constants::TICKS_IN_ONE_PERCENT * 199, sign: false },
                    skip_ahead: 5
                ) == (i129 { mag: tick_constants::TICKS_IN_ONE_PERCENT * 128, sign: false }, true),
            'prev from 199, skip 5'
        );
        assert(
            setup
                .core
                .prev_initialized_tick(
                    pool_key: setup.pool_key,
                    from: i129 { mag: tick_constants::TICKS_IN_ONE_PERCENT * 127, sign: false },
                    skip_ahead: 5
                ) == (i129 { mag: tick_constants::TICKS_IN_ONE_PERCENT * 9, sign: false }, true),
            'prev from 127, skip 5'
        );
        assert(
            setup
                .core
                .prev_initialized_tick(
                    pool_key: setup.pool_key,
                    from: i129 { mag: tick_constants::TICKS_IN_ONE_PERCENT * 8, sign: false },
                    skip_ahead: 5
                ) == (i129 { mag: tick_constants::TICKS_IN_ONE_PERCENT * 12, sign: true }, true),
            'prev from 8, skip 5'
        );
        assert(
            setup
                .core
                .prev_initialized_tick(
                    pool_key: setup.pool_key,
                    from: i129 { mag: tick_constants::TICKS_IN_ONE_PERCENT * 13, sign: true },
                    skip_ahead: 5
                ) == (i129 { mag: tick_constants::TICKS_IN_ONE_PERCENT * 128, sign: true }, true),
            'prev from -13, skip 5'
        );
        assert(
            setup
                .core
                .prev_initialized_tick(
                    pool_key: setup.pool_key,
                    from: i129 { mag: tick_constants::TICKS_IN_ONE_PERCENT * 129, sign: true },
                    skip_ahead: 5
                ) == (i129 { mag: tick_constants::TICKS_IN_ONE_PERCENT * 154, sign: true }, true),
            'prev from -129, skip 5'
        );
    }
}

mod locks {
    use debug::PrintTrait;

    use ekubo::types::i129::{i129OptionPartialEq};
    use ekubo::math::ticks::{tick_to_sqrt_ratio};
    use super::{
        setup_pool, FEE_ONE_PERCENT, swap, update_position, SetupPoolResult, tick_constants,
        contract_address_const, Action, ActionResult, ICoreLockerDispatcher,
        ICoreLockerDispatcherTrait, i129, UpdatePositionParameters, SwapParameters,
        IMockERC20Dispatcher, IMockERC20DispatcherTrait, min_sqrt_ratio, max_sqrt_ratio, min_tick,
        max_tick, ICoreDispatcherTrait, ContractAddress, Delta, EqualTickBool, Bounds, Zeroable
    };

    #[test]
    #[available_gas(500000000)]
    fn test_assert_locker_id_call() {
        let setup = setup_pool(
            fee: FEE_ONE_PERCENT,
            tick_spacing: tick_constants::TICKS_IN_ONE_PERCENT,
            initial_tick: Zeroable::zero(),
            extension: Zeroable::zero(),
        );
        setup.locker.call(Action::AssertLockerId(0));
    }

    #[test]
    #[available_gas(500000000)]
    fn test_relock_call() {
        let setup = setup_pool(
            fee: FEE_ONE_PERCENT,
            tick_spacing: tick_constants::TICKS_IN_ONE_PERCENT,
            initial_tick: Zeroable::zero(),
            extension: Zeroable::zero(),
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
            fee: FEE_ONE_PERCENT,
            tick_spacing: tick_constants::TICKS_IN_ONE_PERCENT,
            initial_tick: Zeroable::zero(),
            extension: Zeroable::zero(),
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
            fee: FEE_ONE_PERCENT,
            tick_spacing: tick_constants::TICKS_IN_ONE_PERCENT,
            initial_tick: Zeroable::zero(),
            extension: Zeroable::zero(),
        );
        setup.locker.call(Action::Relock((1, 5)));
    }

    #[test]
    #[available_gas(500000000)]
    fn test_zero_liquidity_add() {
        let setup = setup_pool(
            fee: FEE_ONE_PERCENT,
            tick_spacing: tick_constants::TICKS_IN_ONE_PERCENT,
            initial_tick: Zeroable::zero(),
            extension: Zeroable::zero(),
        );
        update_position(
            setup: setup,
            bounds: Bounds {
                tick_lower: i129 {
                    mag: tick_constants::TICKS_IN_ONE_PERCENT, sign: true
                    }, tick_upper: i129 {
                    mag: tick_constants::TICKS_IN_ONE_PERCENT, sign: false
                }
            },
            liquidity_delta: Zeroable::zero(),
            recipient: contract_address_const::<42>()
        );
        assert(
            setup
                .core
                .prev_initialized_tick(
                    pool_key: setup.pool_key,
                    from: i129 { mag: tick_constants::TICKS_IN_ONE_PERCENT, sign: true },
                    skip_ahead: 1
                ) != (i129 { mag: tick_constants::TICKS_IN_ONE_PERCENT, sign: true }, true),
            'ticks not initialized'
        );
        assert(
            setup
                .core
                .prev_initialized_tick(
                    pool_key: setup.pool_key,
                    from: i129 { mag: tick_constants::TICKS_IN_ONE_PERCENT, sign: false },
                    skip_ahead: 1
                ) != (i129 { mag: tick_constants::TICKS_IN_ONE_PERCENT, sign: false }, false),
            'ticks not initialized'
        );
    }

    #[test]
    #[available_gas(500000000)]
    #[should_panic(
        expected: (
            'BOUNDS_TICK_SPACING',
            'ENTRYPOINT_FAILED',
            'ENTRYPOINT_FAILED',
            'ENTRYPOINT_FAILED',
            'ENTRYPOINT_FAILED'
        )
    )]
    fn test_small_amount_liquidity_add_tick_spacing_not_divisible_lower() {
        let setup = setup_pool(
            fee: FEE_ONE_PERCENT,
            tick_spacing: tick_constants::TICKS_IN_ONE_PERCENT,
            initial_tick: Zeroable::zero(),
            extension: Zeroable::zero(),
        );

        update_position(
            setup: setup,
            bounds: Bounds {
                tick_lower: i129 {
                    mag: tick_constants::TICKS_IN_ONE_PERCENT, sign: true
                    }, tick_upper: i129 {
                    mag: 12, sign: false
                },
            },
            liquidity_delta: i129 { mag: 100, sign: false },
            recipient: contract_address_const::<42>()
        );
    }

    #[test]
    #[available_gas(500000000)]
    #[should_panic(
        expected: (
            'BOUNDS_TICK_SPACING',
            'ENTRYPOINT_FAILED',
            'ENTRYPOINT_FAILED',
            'ENTRYPOINT_FAILED',
            'ENTRYPOINT_FAILED'
        )
    )]
    fn test_small_amount_liquidity_add_tick_spacing_not_divisible_upper() {
        let setup = setup_pool(
            fee: FEE_ONE_PERCENT,
            tick_spacing: tick_constants::TICKS_IN_ONE_PERCENT,
            initial_tick: Zeroable::zero(),
            extension: Zeroable::zero(),
        );

        update_position(
            setup: setup,
            bounds: Bounds {
                tick_lower: i129 {
                    mag: tick_constants::TICKS_IN_ONE_PERCENT, sign: true
                    }, tick_upper: i129 {
                    mag: 10, sign: false
                },
            },
            liquidity_delta: i129 { mag: 100, sign: false },
            recipient: contract_address_const::<42>()
        );
    }


    #[test]
    #[available_gas(500000000)]
    #[should_panic(
        expected: (
            'BOUNDS_TICK_SPACING',
            'ENTRYPOINT_FAILED',
            'ENTRYPOINT_FAILED',
            'ENTRYPOINT_FAILED',
            'ENTRYPOINT_FAILED'
        )
    )]
    fn test_small_amount_liquidity_add_no_tokens() {
        let setup = setup_pool(
            fee: FEE_ONE_PERCENT,
            tick_spacing: tick_constants::TICKS_IN_ONE_PERCENT,
            initial_tick: Zeroable::zero(),
            extension: Zeroable::zero(),
        );

        let delta = update_position(
            setup: setup,
            bounds: Bounds {
                tick_lower: i129 { mag: 10, sign: true }, tick_upper: i129 { mag: 10, sign: false }, 
            },
            liquidity_delta: Zeroable::zero(),
            recipient: contract_address_const::<42>()
        );
        assert(delta.amount0 == Zeroable::zero(), 'amount0');
        assert(delta.amount1 == Zeroable::zero(), 'amount1');
    }


    #[test]
    #[available_gas(500000000)]
    fn test_small_amount_liquidity_add() {
        let setup = setup_pool(
            fee: FEE_ONE_PERCENT,
            tick_spacing: 1,
            initial_tick: Zeroable::zero(),
            extension: Zeroable::zero(),
        );

        setup.token0.increase_balance(setup.locker.contract_address, 10000000);
        setup.token1.increase_balance(setup.locker.contract_address, 10000000);

        let delta = update_position(
            setup: setup,
            bounds: Bounds {
                tick_lower: i129 { mag: 10, sign: true }, tick_upper: i129 { mag: 10, sign: false }, 
            },
            liquidity_delta: i129 { mag: 10000000, sign: false },
            recipient: contract_address_const::<42>()
        );

        assert(delta.amount0 == i129 { mag: 50, sign: false }, 'amount0');
        assert(delta.amount1 == i129 { mag: 50, sign: false }, 'amount1_delta');
    }

    #[test]
    #[available_gas(500000000)]
    fn test_larger_amount_liquidity_add() {
        let setup = setup_pool(
            fee: FEE_ONE_PERCENT,
            tick_spacing: tick_constants::TICKS_IN_ONE_PERCENT,
            initial_tick: Zeroable::zero(),
            extension: Zeroable::zero(),
        );

        setup.token0.increase_balance(setup.locker.contract_address, 10000000000);
        setup.token1.increase_balance(setup.locker.contract_address, 10000000000);

        let delta = update_position(
            setup,
            bounds: Bounds {
                tick_lower: i129 {
                    mag: tick_constants::TICKS_IN_ONE_PERCENT, sign: true
                    }, tick_upper: i129 {
                    mag: tick_constants::TICKS_IN_ONE_PERCENT, sign: false
                },
            },
            liquidity_delta: i129 { mag: 1000000000, sign: false },
            recipient: contract_address_const::<42>()
        );

        assert(delta.amount0 == i129 { mag: 4962643, sign: false }, 'amount0');
        assert(delta.amount1 == i129 { mag: 4962643, sign: false }, 'amount1_delta');
    }

    #[test]
    #[available_gas(500000000)]
    fn test_full_range_liquidity_add() {
        let setup = setup_pool(
            fee: FEE_ONE_PERCENT,
            tick_spacing: 1,
            initial_tick: Zeroable::zero(),
            extension: Zeroable::zero(),
        );

        setup
            .token0
            .increase_balance(setup.locker.contract_address, 0xffffffffffffffffffffffffffffffff);
        setup
            .token1
            .increase_balance(setup.locker.contract_address, 0xffffffffffffffffffffffffffffffff);

        let delta = update_position(
            setup,
            bounds: Default::default(),
            liquidity_delta: i129 { mag: 1000000000, sign: false },
            recipient: contract_address_const::<42>()
        );

        assert(delta.amount0 == i129 { mag: 1000000000, sign: false }, 'amount0');
        assert(delta.amount1 == i129 { mag: 1000000000, sign: false }, 'amount1_delta');
    }

    #[test]
    #[available_gas(500000000)]
    fn test_full_range_liquidity_add_and_half_burn() {
        let setup = setup_pool(
            fee: FEE_ONE_PERCENT,
            tick_spacing: 1,
            initial_tick: Zeroable::zero(),
            extension: Zeroable::zero(),
        );

        setup
            .token0
            .increase_balance(setup.locker.contract_address, 0xffffffffffffffffffffffffffffffff);
        setup
            .token1
            .increase_balance(setup.locker.contract_address, 0xffffffffffffffffffffffffffffffff);

        update_position(
            setup: setup,
            bounds: Default::default(),
            liquidity_delta: i129 { mag: 1000000000, sign: false },
            recipient: contract_address_const::<42>()
        );

        let delta = update_position(
            setup: setup,
            bounds: Default::default(),
            liquidity_delta: i129 { mag: 500000000, sign: true },
            recipient: contract_address_const::<42>()
        );

        assert(
            setup
                .core
                .prev_initialized_tick(
                    pool_key: setup.pool_key, from: min_tick(), skip_ahead: 1
                ) == (min_tick(), true),
            'ticks initialized'
        );
        assert(
            setup
                .core
                .prev_initialized_tick(
                    pool_key: setup.pool_key, from: max_tick(), skip_ahead: 1
                ) == (max_tick(), true),
            'ticks initialized'
        );

        assert(delta.amount0 == i129 { mag: 494999999, sign: true }, 'amount0');
        assert(delta.amount1 == i129 { mag: 494999999, sign: true }, 'amount1_delta');
    }

    #[test]
    #[available_gas(500000000)]
    fn test_full_range_liquidity_add_and_full_burn() {
        let setup = setup_pool(
            fee: FEE_ONE_PERCENT,
            tick_spacing: 1,
            initial_tick: Zeroable::zero(),
            extension: Zeroable::zero(),
        );

        setup
            .token0
            .increase_balance(setup.locker.contract_address, 0xffffffffffffffffffffffffffffffff);
        setup
            .token1
            .increase_balance(setup.locker.contract_address, 0xffffffffffffffffffffffffffffffff);

        update_position(
            setup,
            bounds: Default::default(),
            liquidity_delta: i129 { mag: 1000000000, sign: false },
            recipient: contract_address_const::<42>()
        );

        let delta = update_position(
            setup,
            bounds: Default::default(),
            liquidity_delta: i129 { mag: 1000000000, sign: true },
            recipient: contract_address_const::<42>()
        );

        assert(
            setup
                .core
                .prev_initialized_tick(
                    pool_key: setup.pool_key, from: min_tick(), skip_ahead: 1
                ) != (min_tick(), true),
            'ticks initialized'
        );
        assert(
            setup
                .core
                .prev_initialized_tick(
                    pool_key: setup.pool_key, from: max_tick(), skip_ahead: 1
                ) != (max_tick(), true),
            'ticks initialized'
        );

        assert(delta.amount0 == i129 { mag: 989999999, sign: true }, 'amount0');
        assert(delta.amount1 == i129 { mag: 989999999, sign: true }, 'amount1_delta');
    }

    #[test]
    #[available_gas(8000000)]
    fn test_swap_token0_zero_amount_zero_liquidity() {
        let setup = setup_pool(
            fee: FEE_ONE_PERCENT,
            tick_spacing: tick_constants::TICKS_IN_ONE_PERCENT,
            initial_tick: Zeroable::zero(),
            extension: Zeroable::zero(),
        );

        let delta = swap(
            setup,
            amount: Zeroable::zero(), // input 0 token0, price decreasing
            is_token1: false,
            sqrt_ratio_limit: min_sqrt_ratio(),
            recipient: contract_address_const::<42>(),
            skip_ahead: 0,
        );

        assert(delta.amount0 == Zeroable::zero(), 'amount0');
        assert(delta.amount1 == Zeroable::zero(), 'amount1_delta');

        let pool = setup.core.get_pool(setup.pool_key);
        assert(pool.sqrt_ratio == u256 { low: 0, high: 1 }, 'price did not move');
        assert(pool.liquidity == 0, 'liquidity is 0');
        assert(pool.fee_growth_global_token0.is_zero(), 'fgg0 == 0');
        assert(pool.fee_growth_global_token1.is_zero(), 'fgg1 == 0');
    }

    #[test]
    #[available_gas(30000000)]
    fn test_swap_token0_exact_input_no_liquidity() {
        let setup = setup_pool(
            fee: FEE_ONE_PERCENT,
            tick_spacing: tick_constants::TICKS_IN_ONE_PERCENT,
            initial_tick: Zeroable::zero(),
            extension: Zeroable::zero(),
        );

        let sqrt_ratio_limit = tick_to_sqrt_ratio(
            i129 { mag: tick_constants::TICKS_IN_ONE_PERCENT * 3, sign: true }
        );

        let delta = swap(
            setup,
            amount: i129 { mag: 1, sign: false },
            is_token1: false,
            sqrt_ratio_limit: sqrt_ratio_limit,
            recipient: contract_address_const::<42>(),
            skip_ahead: 0,
        );

        assert(delta.amount0 == Zeroable::zero(), 'amount0');
        assert(delta.amount1 == Zeroable::zero(), 'amount1_delta');

        let pool = setup.core.get_pool(setup.pool_key);
        assert(pool.sqrt_ratio == sqrt_ratio_limit, 'price is min');
        assert(pool.liquidity == 0, 'liquidity is 0');
        assert(pool.fee_growth_global_token0.is_zero(), 'fgg0 == 0');
        assert(pool.fee_growth_global_token1.is_zero(), 'fgg1 == 0');
    }

    #[test]
    #[available_gas(30000000)]
    fn test_swap_token1_exact_input_no_liquidity() {
        let setup = setup_pool(
            fee: FEE_ONE_PERCENT,
            tick_spacing: tick_constants::TICKS_IN_ONE_PERCENT,
            initial_tick: Zeroable::zero(),
            extension: Zeroable::zero(),
        );

        let sqrt_ratio_limit = u256 { low: 0, high: 2 };

        let delta = swap(
            setup,
            amount: i129 { mag: 1, sign: false },
            is_token1: true,
            sqrt_ratio_limit: sqrt_ratio_limit,
            recipient: contract_address_const::<42>(),
            skip_ahead: 0,
        );

        assert(delta.amount0 == Zeroable::zero(), 'amount0');
        assert(delta.amount1 == Zeroable::zero(), 'amount1_delta');

        let pool = setup.core.get_pool(setup.pool_key);
        assert(pool.sqrt_ratio == sqrt_ratio_limit, 'price is max');
        assert(pool.liquidity == 0, 'liquidity is 0');
        assert(pool.fee_growth_global_token0.is_zero(), 'fgg0 == 0');
        assert(pool.fee_growth_global_token1.is_zero(), 'fgg1 == 0');
    }

    #[test]
    #[available_gas(30000000)]
    fn test_swap_token0_exact_output_no_liquidity() {
        let setup = setup_pool(
            fee: FEE_ONE_PERCENT,
            tick_spacing: tick_constants::TICKS_IN_ONE_PERCENT,
            initial_tick: Zeroable::zero(),
            extension: Zeroable::zero(),
        );

        let sqrt_ratio_limit = u256 { low: 0, high: 2 };

        let delta = swap(
            setup,
            amount: i129 { mag: 1, sign: true },
            is_token1: false,
            sqrt_ratio_limit: sqrt_ratio_limit,
            recipient: contract_address_const::<42>(),
            skip_ahead: 0,
        );

        assert(delta.amount0 == Zeroable::zero(), 'amount0');
        assert(delta.amount1 == Zeroable::zero(), 'amount1_delta');

        let pool = setup.core.get_pool(setup.pool_key);
        assert(pool.sqrt_ratio == sqrt_ratio_limit, 'price is capped');
        assert(pool.liquidity == 0, 'liquidity is 0');
        assert(pool.fee_growth_global_token0.is_zero(), 'fgg0 == 0');
        assert(pool.fee_growth_global_token1.is_zero(), 'fgg1 == 0');
    }

    #[test]
    #[available_gas(30000000)]
    fn test_swap_token1_exact_output_no_liquidity() {
        let setup = setup_pool(
            fee: FEE_ONE_PERCENT,
            tick_spacing: tick_constants::TICKS_IN_ONE_PERCENT,
            initial_tick: Zeroable::zero(),
            extension: Zeroable::zero(),
        );

        let sqrt_ratio_limit = u256 { low: 0, high: 1 } / u256 { low: 2, high: 0 };

        let delta = swap(
            setup,
            amount: i129 { mag: 1, sign: true },
            is_token1: true,
            sqrt_ratio_limit: sqrt_ratio_limit,
            recipient: contract_address_const::<42>(),
            skip_ahead: 0,
        );

        assert(delta.amount0 == Zeroable::zero(), 'amount0');
        assert(delta.amount1 == Zeroable::zero(), 'amount1_delta');

        let pool = setup.core.get_pool(setup.pool_key);
        assert(pool.sqrt_ratio == sqrt_ratio_limit, 'price is min');
        assert(pool.liquidity == 0, 'liquidity is 0');
        assert(pool.fee_growth_global_token0.is_zero(), 'fgg0 == 0');
        assert(pool.fee_growth_global_token1.is_zero(), 'fgg1 == 0');
    }

    #[test]
    #[available_gas(30000000)]
    fn test_swap_token0_exact_input_against_small_liquidity_no_tick_cross() {
        let setup = setup_pool(
            fee: FEE_ONE_PERCENT,
            tick_spacing: tick_constants::TICKS_IN_ONE_PERCENT,
            initial_tick: Zeroable::zero(),
            extension: Zeroable::zero(),
        );

        setup.token0.increase_balance(setup.locker.contract_address, 10000000);
        setup.token1.increase_balance(setup.locker.contract_address, 10000000);

        update_position(
            setup,
            bounds: Bounds {
                tick_lower: i129 {
                    mag: tick_constants::TICKS_IN_ONE_PERCENT, sign: true
                    }, tick_upper: i129 {
                    mag: tick_constants::TICKS_IN_ONE_PERCENT, sign: false
                },
            },
            liquidity_delta: i129 { mag: 1000000000, sign: false },
            recipient: contract_address_const::<42>()
        );

        let delta = swap(
            setup,
            amount: i129 { mag: 1000, sign: false },
            is_token1: false,
            sqrt_ratio_limit: min_sqrt_ratio(),
            recipient: contract_address_const::<42>(),
            skip_ahead: 0
        );

        assert(delta.amount0 == i129 { mag: 1000, sign: false }, 'amount0==1000');
        assert(delta.amount1 == i129 { mag: 989, sign: true }, 'amount1_delta==989');

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
        assert(pool.fee_growth_global_token1.is_zero(), 'fgg1 == 0');
    }

    #[test]
    #[available_gas(30000000)]
    fn test_swap_token0_exact_output_against_small_liquidity_no_tick_cross() {
        let setup = setup_pool(
            fee: FEE_ONE_PERCENT,
            tick_spacing: tick_constants::TICKS_IN_ONE_PERCENT,
            initial_tick: Zeroable::zero(),
            extension: Zeroable::zero(),
        );

        setup.token0.increase_balance(setup.locker.contract_address, 1000000000);
        setup.token1.increase_balance(setup.locker.contract_address, 1000000000);

        update_position(
            setup,
            bounds: Bounds {
                tick_lower: i129 {
                    mag: tick_constants::TICKS_IN_ONE_PERCENT, sign: true
                    }, tick_upper: i129 {
                    mag: tick_constants::TICKS_IN_ONE_PERCENT, sign: false
                },
            },
            liquidity_delta: i129 { mag: 1000000000, sign: false },
            recipient: contract_address_const::<42>()
        );

        let delta = swap(
            setup,
            amount: i129 { mag: 1000, sign: true },
            is_token1: false,
            sqrt_ratio_limit: max_sqrt_ratio(),
            recipient: contract_address_const::<42>(),
            skip_ahead: 0
        );

        assert(delta.amount0 == i129 { mag: 1000, sign: true }, 'amount0==1000');
        assert(delta.amount1 == i129 { mag: 1010, sign: false }, 'amount1_delta==989');

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
        assert(pool.fee_growth_global_token1.is_zero(), 'fgg1 == 0');
    }


    #[test]
    #[available_gas(30000000)]
    fn test_swap_token0_exact_input_against_small_liquidity_with_tick_cross() {
        let setup = setup_pool(
            fee: FEE_ONE_PERCENT,
            tick_spacing: tick_constants::TICKS_IN_ONE_PERCENT,
            initial_tick: Zeroable::zero(),
            extension: Zeroable::zero(),
        );

        setup.token0.increase_balance(setup.locker.contract_address, 10000000);
        setup.token1.increase_balance(setup.locker.contract_address, 10000000);

        update_position(
            setup,
            bounds: Bounds {
                tick_lower: i129 {
                    mag: tick_constants::TICKS_IN_ONE_PERCENT, sign: true
                    }, tick_upper: i129 {
                    mag: tick_constants::TICKS_IN_ONE_PERCENT, sign: false
                },
            },
            liquidity_delta: i129 { mag: 100000, sign: false },
            recipient: contract_address_const::<42>()
        );

        let sqrt_ratio_limit = tick_to_sqrt_ratio(
            i129 { mag: tick_constants::TICKS_IN_ONE_PERCENT * 2, sign: true }
        );

        let delta = swap(
            setup,
            amount: i129 { mag: 1000, sign: false },
            is_token1: false,
            sqrt_ratio_limit: sqrt_ratio_limit,
            recipient: contract_address_const::<42>(),
            skip_ahead: 0
        );

        assert(delta.amount0 == i129 { mag: 499, sign: false }, 'amount0==1000');
        assert(delta.amount1 == i129 { mag: 496, sign: true }, 'amount1_delta==987');

        let pool = setup.core.get_pool(setup.pool_key);
        assert(pool.sqrt_ratio == sqrt_ratio_limit, 'price min');
        assert(pool.liquidity == 0, 'liquidity is 0');
        assert(
            pool.fee_growth_global_token0 == u256 {
                low: 17014118346046923173168730371588410, high: 0
            },
            'fgg0 != 0'
        );
        assert(pool.fee_growth_global_token1.is_zero(), 'fgg1 == 0');
    }

    #[test]
    #[available_gas(30000000)]
    fn test_swap_token0_exact_output_against_small_liquidity_with_tick_cross() {
        let setup = setup_pool(
            fee: FEE_ONE_PERCENT,
            tick_spacing: tick_constants::TICKS_IN_ONE_PERCENT,
            initial_tick: Zeroable::zero(),
            extension: Zeroable::zero(),
        );

        setup.token0.increase_balance(setup.locker.contract_address, 10000000);
        setup.token1.increase_balance(setup.locker.contract_address, 10000000);

        update_position(
            setup,
            bounds: Bounds {
                tick_lower: i129 {
                    mag: tick_constants::TICKS_IN_ONE_PERCENT, sign: true
                    }, tick_upper: i129 {
                    mag: tick_constants::TICKS_IN_ONE_PERCENT, sign: false
                },
            },
            liquidity_delta: i129 { mag: 100000, sign: false },
            recipient: contract_address_const::<42>()
        );

        let sqrt_ratio_limit = tick_to_sqrt_ratio(
            i129 { mag: tick_constants::TICKS_IN_ONE_PERCENT * 2, sign: false }
        );

        let delta = swap(
            setup,
            amount: i129 { mag: 1000, sign: true },
            is_token1: false,
            sqrt_ratio_limit: sqrt_ratio_limit,
            recipient: contract_address_const::<42>(),
            skip_ahead: 0
        );

        assert(delta.amount0 == i129 { mag: 497, sign: true }, 'amount0');
        assert(delta.amount1 == i129 { mag: 498, sign: false }, 'amount1_delta');

        let pool = setup.core.get_pool(setup.pool_key);
        assert(pool.sqrt_ratio == sqrt_ratio_limit, 'price min');
        assert(pool.liquidity == 0, 'liquidity is 0');
        assert(
            pool.fee_growth_global_token0 == u256 {
                low: 17014118346046923173168730371588410, high: 0
            },
            'fgg0 != 0'
        );
        assert(pool.fee_growth_global_token1.is_zero(), 'fgg1 == 0');
    }

    #[test]
    #[available_gas(30000000)]
    fn test_swap_token1_exact_input_against_small_liquidity_no_tick_cross() {
        let setup = setup_pool(
            fee: FEE_ONE_PERCENT,
            tick_spacing: tick_constants::TICKS_IN_ONE_PERCENT,
            initial_tick: Zeroable::zero(),
            extension: Zeroable::zero(),
        );

        setup.token0.increase_balance(setup.locker.contract_address, 10000000);
        setup.token1.increase_balance(setup.locker.contract_address, 10000000);

        update_position(
            setup,
            bounds: Bounds {
                tick_lower: i129 {
                    mag: tick_constants::TICKS_IN_ONE_PERCENT, sign: true
                    }, tick_upper: i129 {
                    mag: tick_constants::TICKS_IN_ONE_PERCENT, sign: false
                },
            },
            liquidity_delta: i129 { mag: 1000000000, sign: false },
            recipient: contract_address_const::<42>()
        );

        let delta = swap(
            setup,
            amount: i129 { mag: 1000, sign: false },
            is_token1: true,
            sqrt_ratio_limit: max_sqrt_ratio(),
            recipient: contract_address_const::<42>(),
            skip_ahead: 0
        );

        assert(delta.amount1 == i129 { mag: 1000, sign: false }, 'amount0==1000');
        assert(delta.amount0 == i129 { mag: 989, sign: true }, 'amount1_delta==989');

        let pool = setup.core.get_pool(setup.pool_key);
        assert(
            pool.sqrt_ratio == u256 { low: 336879543251729078828740861357450, high: 1 },
            'price lower'
        );
        assert(pool.liquidity == 1000000000, 'liquidity is original');
        assert(pool.fee_growth_global_token0.is_zero(), 'fgg0 == 0');
        assert(
            pool.fee_growth_global_token1 == u256 { low: 3402823669209384634633746074317, high: 0 },
            'fgg1 != 0'
        );
    }

    #[test]
    #[available_gas(30000000)]
    fn test_swap_token1_exact_output_against_small_liquidity_no_tick_cross() {
        let setup = setup_pool(
            fee: FEE_ONE_PERCENT,
            tick_spacing: tick_constants::TICKS_IN_ONE_PERCENT,
            initial_tick: Zeroable::zero(),
            extension: Zeroable::zero(),
        );

        setup.token0.increase_balance(setup.locker.contract_address, 10000000);
        setup.token1.increase_balance(setup.locker.contract_address, 10000000);

        update_position(
            setup,
            bounds: Bounds {
                tick_lower: i129 {
                    mag: tick_constants::TICKS_IN_ONE_PERCENT, sign: true
                    }, tick_upper: i129 {
                    mag: tick_constants::TICKS_IN_ONE_PERCENT, sign: false
                },
            },
            liquidity_delta: i129 { mag: 1000000000, sign: false },
            recipient: contract_address_const::<42>()
        );

        let delta = swap(
            setup,
            amount: i129 { mag: 1000, sign: true },
            is_token1: true,
            sqrt_ratio_limit: min_sqrt_ratio(),
            recipient: contract_address_const::<42>(),
            skip_ahead: 0
        );

        assert(delta.amount1 == i129 { mag: 1000, sign: true }, 'amount0');
        assert(delta.amount0 == i129 { mag: 1010, sign: false }, 'amount1_delta');

        let pool = setup.core.get_pool(setup.pool_key);
        assert(
            pool.sqrt_ratio == u256 { low: 340282023235747873315526509423414705370, high: 0 },
            'price'
        );
        assert(pool.liquidity == 1000000000, 'liquidity is original');
        assert(pool.fee_growth_global_token0.is_zero(), 'fgg0 == 0');
        assert(
            pool.fee_growth_global_token1 == u256 { low: 3402823669209384634633746074317, high: 0 },
            'fgg1 != 0'
        );
    }

    #[test]
    #[available_gas(30000000)]
    fn test_swap_token1_exact_input_against_small_liquidity_with_tick_cross() {
        let setup = setup_pool(
            fee: FEE_ONE_PERCENT,
            tick_spacing: tick_constants::TICKS_IN_ONE_PERCENT,
            initial_tick: Zeroable::zero(),
            extension: Zeroable::zero(),
        );

        setup.token0.increase_balance(setup.locker.contract_address, 10000000);
        setup.token1.increase_balance(setup.locker.contract_address, 10000000);

        update_position(
            setup,
            bounds: Bounds {
                tick_lower: i129 {
                    mag: tick_constants::TICKS_IN_ONE_PERCENT, sign: true
                    }, tick_upper: i129 {
                    mag: tick_constants::TICKS_IN_ONE_PERCENT, sign: false
                },
            },
            liquidity_delta: i129 { mag: 10000000, sign: false },
            recipient: contract_address_const::<42>()
        );

        let sqrt_ratio_limit = tick_to_sqrt_ratio(
            i129 { mag: tick_constants::TICKS_IN_ONE_PERCENT * 5, sign: false }
        );

        let delta = swap(
            setup,
            amount: i129 { mag: 1000000, sign: false },
            is_token1: true,
            sqrt_ratio_limit: sqrt_ratio_limit,
            recipient: contract_address_const::<42>(),
            skip_ahead: 0
        );

        assert(delta.amount0 == i129 { mag: 49626, sign: true }, 'amount0');
        assert(delta.amount1 == i129 { mag: 49874, sign: false }, 'amount1_delta');

        let pool = setup.core.get_pool(setup.pool_key);
        assert(pool.sqrt_ratio == sqrt_ratio_limit, 'ratio after');
        assert(pool.liquidity == 0, 'liquidity is 0');
        assert(pool.fee_growth_global_token0.is_zero(), 'fgg0 == 0');
        assert(
            pool.fee_growth_global_token1 == u256 {
                low: 16980090109354829326822392910845233, high: 0
            },
            'fgg1 != 0'
        );
    }

    #[test]
    #[available_gas(30000000)]
    fn test_swap_token1_exact_output_against_small_liquidity_with_tick_cross() {
        let setup = setup_pool(
            fee: FEE_ONE_PERCENT,
            tick_spacing: tick_constants::TICKS_IN_ONE_PERCENT,
            initial_tick: Zeroable::zero(),
            extension: Zeroable::zero(),
        );

        setup.token0.increase_balance(setup.locker.contract_address, 10000000000000000);
        setup.token1.increase_balance(setup.locker.contract_address, 10000000000000000);

        update_position(
            setup,
            bounds: Bounds {
                tick_lower: i129 {
                    mag: tick_constants::TICKS_IN_ONE_PERCENT, sign: true
                    }, tick_upper: i129 {
                    mag: tick_constants::TICKS_IN_ONE_PERCENT, sign: false
                },
            },
            liquidity_delta: i129 { mag: 10000000, sign: false },
            recipient: contract_address_const::<42>()
        );

        let sqrt_ratio_limit = tick_to_sqrt_ratio(
            i129 { mag: tick_constants::TICKS_IN_ONE_PERCENT * 5, sign: true }
        );

        let delta = swap(
            setup,
            amount: i129 { mag: 10000000, sign: true },
            is_token1: true,
            sqrt_ratio_limit: sqrt_ratio_limit,
            recipient: contract_address_const::<42>(),
            skip_ahead: 0
        );

        assert(delta.amount0 == i129 { mag: 49873, sign: false }, 'amount0');
        assert(delta.amount1 == i129 { mag: 49627, sign: true }, 'amount1_delta');

        let pool = setup.core.get_pool(setup.pool_key);
        assert(pool.sqrt_ratio == sqrt_ratio_limit, 'ratio after');
        assert(pool.liquidity == 0, 'liquidity is 0');
        assert(pool.fee_growth_global_token0.is_zero(), 'fgg0 == 0');
        assert(
            pool.fee_growth_global_token1 == u256 {
                low: 16912033635970641634129717989358880, high: 0
            },
            'fgg1 != 0'
        );
    }
}
