use core::array::{ArrayTrait};
use core::num::traits::{Zero};
use core::option::{Option, OptionTrait};
use core::traits::{Into, TryInto};
use ekubo::core::{Core};
use ekubo::interfaces::core::{
    ICoreDispatcherTrait, ICoreDispatcher, UpdatePositionParameters, SwapParameters
};
use ekubo::interfaces::upgradeable::{IUpgradeableDispatcher, IUpgradeableDispatcherTrait};
use ekubo::math::muldiv::{div};
use ekubo::math::ticks::{
    max_sqrt_ratio, min_sqrt_ratio, min_tick, max_tick, constants as tick_constants,
    tick_to_sqrt_ratio
};
use ekubo::mock_erc20::{MockERC20, IMockERC20Dispatcher, IMockERC20DispatcherTrait};

use ekubo::tests::helper::{
    FEE_ONE_PERCENT, Deployer, DeployerTrait, swap, update_position, accumulate_as_fees,
    SetupPoolResult, default_owner
};

use ekubo::tests::mocks::locker::{
    CoreLocker, Action, ActionResult, ICoreLockerDispatcher, ICoreLockerDispatcherTrait,
};
use ekubo::tests::mocks::mock_upgradeable::{MockUpgradeable};
use ekubo::types::bounds::{Bounds, max_bounds};
use ekubo::types::delta::{Delta};
use ekubo::types::fees_per_liquidity::{FeesPerLiquidity};
use ekubo::types::i129::{i129};
use ekubo::types::keys::{PoolKey, SavedBalanceKey};
use starknet::testing::{set_contract_address, pop_log};
use starknet::{ContractAddress, contract_address_const};


// floor(log base 1.000001 of 1.01)
const TICKS_IN_ONE_PERCENT: u128 = 9950;

mod owner_tests {
    use ekubo::components::owned::{IOwnedDispatcher, IOwnedDispatcherTrait};

    use ekubo::positions::{Positions};
    use starknet::class_hash::{ClassHash};
    use super::{
        Core, Deployer, DeployerTrait, PoolKey, ICoreDispatcherTrait, i129, contract_address_const,
        set_contract_address, MockERC20, MockUpgradeable, TryInto, OptionTrait, Zero,
        IMockERC20Dispatcher, IMockERC20DispatcherTrait, ContractAddress, Into,
        IUpgradeableDispatcher, IUpgradeableDispatcherTrait, pop_log, default_owner,
    };


    #[test]
    #[should_panic(expected: ('OWNER_ONLY', 'ENTRYPOINT_FAILED',))]
    fn test_replace_class_hash_cannot_be_called_by_non_owner() {
        let mut d: Deployer = Default::default();
        let core = d.deploy_core();
        set_contract_address(contract_address_const::<1>());
        let class_hash: ClassHash = Core::TEST_CLASS_HASH.try_into().unwrap();
        IUpgradeableDispatcher { contract_address: core.contract_address }
            .replace_class_hash(class_hash);
    }

    #[test]
    fn test_replace_class_hash_can_be_called_by_owner() {
        let mut d: Deployer = Default::default();
        let core = d.deploy_core();
        pop_log::<ekubo::components::owned::Owned::OwnershipTransferred>(core.contract_address)
            .unwrap();

        set_contract_address(default_owner());
        let class_hash: ClassHash = Core::TEST_CLASS_HASH.try_into().unwrap();
        IUpgradeableDispatcher { contract_address: core.contract_address }
            .replace_class_hash(class_hash);

        let event: ekubo::components::upgradeable::Upgradeable::ClassHashReplaced = pop_log(
            core.contract_address
        )
            .unwrap();
        assert(event.new_class_hash == class_hash, 'event.class_hash');
    }

    #[test]
    fn test_transfer_ownership() {
        let mut d: Deployer = Default::default();
        let core = d.deploy_core();
        let owned = IOwnedDispatcher { contract_address: core.contract_address };

        let event: ekubo::components::owned::Owned::OwnershipTransferred = pop_log(
            core.contract_address
        )
            .unwrap();
        assert(event.old_owner.is_zero(), 'zero');
        assert(event.new_owner == default_owner(), 'initial owner');
        assert(owned.get_owner() == default_owner(), 'is default');

        set_contract_address(default_owner());
        let new_owner = contract_address_const::<123456789>();
        owned.transfer_ownership(new_owner);

        let event: ekubo::components::owned::Owned::OwnershipTransferred = pop_log(
            core.contract_address
        )
            .unwrap();
        assert(event.old_owner == default_owner(), 'old owner');
        assert(event.new_owner == new_owner, 'new owner');
        assert(owned.get_owner() == new_owner, 'is new owner');
    }

    #[test]
    #[should_panic(expected: ('OWNER_ONLY', 'ENTRYPOINT_FAILED',))]
    fn test_transfer_ownership_then_replace_class_hash_fails() {
        let mut d: Deployer = Default::default();
        let core = d.deploy_core();
        let owned = IOwnedDispatcher { contract_address: core.contract_address };
        set_contract_address(default_owner());
        let new_owner = contract_address_const::<123456789>();
        owned.transfer_ownership(new_owner);
        let class_hash: ClassHash = Core::TEST_CLASS_HASH.try_into().unwrap();
        IUpgradeableDispatcher { contract_address: core.contract_address }
            .replace_class_hash(class_hash);
    }

    #[test]
    fn test_transfer_ownership_then_replace_class_hash_succeeds() {
        let mut d: Deployer = Default::default();
        let core = d.deploy_core();
        let owned = IOwnedDispatcher { contract_address: core.contract_address };
        set_contract_address(default_owner());
        let new_owner = contract_address_const::<123456789>();
        owned.transfer_ownership(new_owner);
        set_contract_address(new_owner);

        let class_hash: ClassHash = Core::TEST_CLASS_HASH.try_into().unwrap();
        IUpgradeableDispatcher { contract_address: core.contract_address }
            .replace_class_hash(class_hash);
    }

    #[test]
    #[should_panic(expected: ('MISSING_PRIMARY_INTERFACE_ID', 'ENTRYPOINT_FAILED'))]
    fn test_fails_upgrading_to_other_contract_without_interface_id() {
        let mut d: Deployer = Default::default();
        let core = d.deploy_core();
        set_contract_address(default_owner());
        // MockERC20 is not upgradeable, first call succeeds, second fails
        IUpgradeableDispatcher { contract_address: core.contract_address }
            .replace_class_hash(MockERC20::TEST_CLASS_HASH.try_into().unwrap());
        IUpgradeableDispatcher { contract_address: core.contract_address }
            .replace_class_hash(MockERC20::TEST_CLASS_HASH.try_into().unwrap());
    }

    #[test]
    #[should_panic(expected: ('UPGRADEABLE_ID_MISMATCH', 'ENTRYPOINT_FAILED'))]
    fn test_fails_upgrading_to_other_contract() {
        let mut d: Deployer = Default::default();
        let core = d.deploy_core();
        set_contract_address(default_owner());
        IUpgradeableDispatcher { contract_address: core.contract_address }
            .replace_class_hash(Positions::TEST_CLASS_HASH.try_into().unwrap());
    }
}

mod initialize_pool_tests {
    use ekubo::math::ticks::constants::{MAX_TICK_SPACING};
    use super::{
        PoolKey, Deployer, DeployerTrait, ICoreDispatcherTrait, i129, contract_address_const, Zero,
        OptionTrait, pop_log, tick_to_sqrt_ratio
    };

    #[test]
    fn test_initialize_pool_works_uninitialized() {
        let mut d: Deployer = Default::default();
        let core = d.deploy_core();
        let pool_key = PoolKey {
            token0: contract_address_const::<1>(),
            token1: contract_address_const::<2>(),
            fee: 0,
            tick_spacing: 1,
            extension: Zero::zero(),
        };
        core.initialize_pool(pool_key, i129 { mag: 1000, sign: true });
        let (price, liquidity, fees_per_liquidity) = (
            core.get_pool_price(pool_key),
            core.get_pool_liquidity(pool_key),
            core.get_pool_fees_per_liquidity(pool_key)
        );
        assert(
            price.sqrt_ratio == u256 { low: 340112268350713539826535022315348447443, high: 0 },
            'sqrt_ratio'
        );
        assert(price.tick == i129 { mag: 1000, sign: true }, 'tick');
        assert(liquidity.is_zero(), 'tick');
        assert(fees_per_liquidity.is_zero(), 'fpl');

        pop_log::<ekubo::components::owned::Owned::OwnershipTransferred>(core.contract_address)
            .unwrap();
        let event: ekubo::core::Core::PoolInitialized = pop_log(core.contract_address).unwrap();
        assert(event.pool_key == pool_key, 'event.pool_key');
        assert(event.initial_tick == i129 { mag: 1000, sign: true }, 'event.initial_tick');
        assert(event.sqrt_ratio == tick_to_sqrt_ratio(event.initial_tick), 'event.sqrt_ratio');
    }

    #[test]
    #[should_panic(expected: ('TOKEN_ORDER', 'ENTRYPOINT_FAILED',))]
    fn test_initialize_pool_fails_token_order_same_token() {
        let mut d: Deployer = Default::default();
        let core = d.deploy_core();
        let pool_key = PoolKey {
            token0: contract_address_const::<1>(),
            token1: contract_address_const::<1>(),
            fee: 0,
            tick_spacing: 1,
            extension: Zero::zero(),
        };
        core.initialize_pool(pool_key, Zero::zero());
    }

    #[test]
    #[should_panic(expected: ('TOKEN_ORDER', 'ENTRYPOINT_FAILED',))]
    fn test_initialize_pool_fails_token_order_wrong_order() {
        let mut d: Deployer = Default::default();
        let core = d.deploy_core();
        let pool_key = PoolKey {
            token0: contract_address_const::<2>(),
            token1: contract_address_const::<1>(),
            fee: 0,
            tick_spacing: 1,
            extension: Zero::zero(),
        };

        core.initialize_pool(pool_key, Zero::zero());
    }

    #[test]
    #[should_panic(expected: ('TOKEN_NON_ZERO', 'ENTRYPOINT_FAILED',))]
    fn test_initialize_pool_fails_token_order_zero_token() {
        let mut d: Deployer = Default::default();
        let core = d.deploy_core();
        let pool_key = PoolKey {
            token0: Zero::zero(),
            token1: contract_address_const::<1>(),
            fee: 0,
            tick_spacing: 1,
            extension: Zero::zero(),
        };
        core.initialize_pool(pool_key, Zero::zero());
    }

    #[test]
    #[should_panic(expected: ('TICK_SPACING', 'ENTRYPOINT_FAILED',))]
    fn test_initialize_pool_fails_zero_tick_spacing() {
        let mut d: Deployer = Default::default();
        let core = d.deploy_core();
        let pool_key = PoolKey {
            token0: contract_address_const::<1>(),
            token1: contract_address_const::<2>(),
            fee: 0,
            tick_spacing: 0,
            extension: Zero::zero(),
        };
        core.initialize_pool(pool_key, Zero::zero());
    }

    #[test]
    fn test_initialize_pool_succeeds_max_tick_spacing() {
        let mut d: Deployer = Default::default();
        let core = d.deploy_core();
        let pool_key = PoolKey {
            token0: contract_address_const::<1>(),
            token1: contract_address_const::<2>(),
            fee: 0,
            tick_spacing: MAX_TICK_SPACING,
            extension: Zero::zero(),
        };
        core.initialize_pool(pool_key, Zero::zero());
    }

    #[test]
    #[should_panic(expected: ('TICK_SPACING', 'ENTRYPOINT_FAILED',))]
    fn test_initialize_pool_fails_max_tick_spacing_plus_one() {
        let mut d: Deployer = Default::default();
        let core = d.deploy_core();
        let pool_key = PoolKey {
            token0: contract_address_const::<1>(),
            token1: contract_address_const::<2>(),
            fee: 0,
            tick_spacing: MAX_TICK_SPACING + 1,
            extension: Zero::zero(),
        };
        core.initialize_pool(pool_key, Zero::zero());
    }

    #[test]
    #[should_panic(expected: ('ALREADY_INITIALIZED', 'ENTRYPOINT_FAILED',))]
    fn test_initialize_pool_fails_already_initialized() {
        let mut d: Deployer = Default::default();
        let core = d.deploy_core();
        let pool_key = PoolKey {
            token0: contract_address_const::<1>(),
            token1: contract_address_const::<2>(),
            fee: 0,
            tick_spacing: 1,
            extension: Zero::zero(),
        };
        core.initialize_pool(pool_key, i129 { mag: 1000, sign: true });
        core.initialize_pool(pool_key, i129 { mag: 1000, sign: true });
    }

    #[test]
    fn test_maybe_initialize_pool_twice() {
        let mut d: Deployer = Default::default();
        let core = d.deploy_core();
        let pool_key = PoolKey {
            token0: contract_address_const::<1>(),
            token1: contract_address_const::<2>(),
            fee: Zero::zero(),
            tick_spacing: 1,
            extension: Zero::zero(),
        };
        assert(
            core
                .maybe_initialize_pool(pool_key, Zero::zero())
                .unwrap() == 0x100000000000000000000000000000000_u256,
            'price'
        );
        assert(
            core.maybe_initialize_pool(pool_key, i129 { mag: 1000, sign: false }).is_none(),
            'second'
        );
        assert(
            core.maybe_initialize_pool(pool_key, i129 { mag: 1000, sign: true }).is_none(), 'third'
        );

        assert(
            core.get_pool_price(pool_key).sqrt_ratio == 0x100000000000000000000000000000000_u256,
            'ratio'
        );
    }
}


mod initialized_ticks {
    use super::{
        Deployer, DeployerTrait, update_position, contract_address_const, FEE_ONE_PERCENT,
        tick_constants, ICoreDispatcherTrait, i129, IMockERC20DispatcherTrait, min_tick, max_tick,
        Bounds, Zero, TICKS_IN_ONE_PERCENT
    };

    #[test]
    #[should_panic(expected: ('PREV_FROM_MIN', 'ENTRYPOINT_FAILED',))]
    fn test_prev_initialized_tick_min_tick_minus_one() {
        let mut d: Deployer = Default::default();
        let setup = d
            .setup_pool(
                fee: FEE_ONE_PERCENT,
                tick_spacing: TICKS_IN_ONE_PERCENT,
                initial_tick: Zero::zero(),
                extension: Zero::zero(),
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
    fn test_prev_initialized_tick_min_tick() {
        let mut d: Deployer = Default::default();
        let setup = d
            .setup_pool(
                fee: FEE_ONE_PERCENT,
                tick_spacing: TICKS_IN_ONE_PERCENT,
                initial_tick: Zero::zero(),
                extension: Zero::zero(),
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
    #[should_panic(expected: ('NEXT_FROM_MAX', 'ENTRYPOINT_FAILED',))]
    fn test_next_initialized_tick_max_tick() {
        let mut d: Deployer = Default::default();
        let setup = d
            .setup_pool(
                fee: FEE_ONE_PERCENT,
                tick_spacing: TICKS_IN_ONE_PERCENT,
                initial_tick: Zero::zero(),
                extension: Zero::zero(),
            );

        setup.core.next_initialized_tick(pool_key: setup.pool_key, from: max_tick(), skip_ahead: 0);
    }

    #[test]
    fn test_next_initialized_tick_max_tick_minus_one() {
        let mut d: Deployer = Default::default();
        let setup = d
            .setup_pool(
                fee: FEE_ONE_PERCENT,
                tick_spacing: TICKS_IN_ONE_PERCENT,
                initial_tick: Zero::zero(),
                extension: Zero::zero(),
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
    fn test_next_initialized_tick_exceeds_max_tick_spacing() {
        let mut d: Deployer = Default::default();
        let setup = d
            .setup_pool(
                fee: FEE_ONE_PERCENT,
                tick_spacing: tick_constants::MAX_TICK_SPACING,
                initial_tick: Zero::zero(),
                extension: Zero::zero(),
            );

        assert(
            setup
                .core
                .next_initialized_tick(
                    pool_key: setup.pool_key, from: Zero::zero(), skip_ahead: 0
                ) == (max_tick(), false),
            'max tick limited'
        );
    }

    #[test]
    fn test_prev_initialized_tick_exceeds_min_tick_spacing() {
        let mut d: Deployer = Default::default();
        let setup = d
            .setup_pool(
                fee: FEE_ONE_PERCENT,
                tick_spacing: tick_constants::MAX_TICK_SPACING,
                initial_tick: Zero::zero(),
                extension: Zero::zero(),
            );

        assert(
            setup
                .core
                .prev_initialized_tick(
                    pool_key: setup.pool_key, from: Zero::zero(), skip_ahead: 0
                ) == (i129 { mag: Zero::zero(), sign: false }, false),
            'min tick 0'
        );

        assert(
            setup
                .core
                .prev_initialized_tick(
                    pool_key: setup.pool_key, from: i129 { mag: 1, sign: true }, skip_ahead: 0
                ) == (min_tick(), false),
            'min tick'
        );
    }

    #[test]
    fn test_next_prev_initialized_tick_none_initialized() {
        let mut d: Deployer = Default::default();
        let setup = d
            .setup_pool(
                fee: FEE_ONE_PERCENT,
                tick_spacing: TICKS_IN_ONE_PERCENT,
                initial_tick: Zero::zero(),
                extension: Zero::zero(),
            );

        assert(
            setup
                .core
                .prev_initialized_tick(
                    pool_key: setup.pool_key, from: Zero::zero(), skip_ahead: 0
                ) == (Zero::zero(), false),
            'prev from 0'
        );

        assert(
            setup
                .core
                .prev_initialized_tick(
                    pool_key: setup.pool_key, from: Zero::zero(), skip_ahead: 2
                ) == (i129 { mag: 4994900, sign: true }, false), // 5014800 == 251*9950*2
            'prev from 0, skip 2'
        );

        assert(
            setup
                .core
                .prev_initialized_tick(
                    pool_key: setup.pool_key, from: Zero::zero(), skip_ahead: 5
                ) == (i129 { mag: 12487250, sign: true }, false), // 2547200 == 251*9950*5
            'prev from 0, skip 5'
        );

        assert(
            setup
                .core
                .next_initialized_tick(
                    pool_key: setup.pool_key, from: Zero::zero(), skip_ahead: 0
                ) == (i129 { mag: 2487500, sign: false }, false),
            'next from 0'
        );

        assert(
            setup
                .core
                .next_initialized_tick(
                    pool_key: setup.pool_key, from: Zero::zero(), skip_ahead: 1
                ) == (i129 { mag: 4984950, sign: false }, false),
            'next from 0, skip 1'
        );

        assert(
            setup
                .core
                .next_initialized_tick(
                    pool_key: setup.pool_key, from: Zero::zero(), skip_ahead: 5
                ) == (i129 { mag: 14974750, sign: false }, false),
            'next from 0, skip 5'
        );
    }

    #[test]
    fn test_next_prev_initialized_tick_several_initialized() {
        let mut d: Deployer = Default::default();
        let setup = d
            .setup_pool(
                fee: FEE_ONE_PERCENT,
                tick_spacing: TICKS_IN_ONE_PERCENT,
                initial_tick: Zero::zero(),
                extension: Zero::zero(),
            );

        setup.token0.increase_balance(setup.locker.contract_address, 100000000);
        setup.token1.increase_balance(setup.locker.contract_address, 100000000);

        update_position(
            setup: setup,
            bounds: Bounds {
                lower: i129 { mag: TICKS_IN_ONE_PERCENT * 12, sign: true },
                upper: i129 { mag: TICKS_IN_ONE_PERCENT * 9, sign: false },
            },
            liquidity_delta: i129 { mag: 1, sign: false },
            recipient: contract_address_const::<42>()
        );
        update_position(
            setup: setup,
            bounds: Bounds {
                lower: i129 { mag: TICKS_IN_ONE_PERCENT * 128, sign: true },
                upper: i129 { mag: TICKS_IN_ONE_PERCENT * 128, sign: false },
            },
            liquidity_delta: i129 { mag: 1, sign: false },
            recipient: contract_address_const::<42>()
        );
        update_position(
            setup: setup,
            bounds: Bounds {
                lower: i129 { mag: TICKS_IN_ONE_PERCENT * 154, sign: true },
                upper: i129 { mag: TICKS_IN_ONE_PERCENT * 200, sign: false },
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
                    from: i129 { mag: TICKS_IN_ONE_PERCENT * 500, sign: true },
                    skip_ahead: 5
                ) == (i129 { mag: TICKS_IN_ONE_PERCENT * 154, sign: true }, true),
            'next from -500, skip 5'
        );
        assert(
            setup
                .core
                .next_initialized_tick(
                    pool_key: setup.pool_key,
                    from: i129 { mag: TICKS_IN_ONE_PERCENT * 154, sign: true },
                    skip_ahead: 5
                ) == (i129 { mag: TICKS_IN_ONE_PERCENT * 128, sign: true }, true),
            'next from -154, skip 5'
        );
        assert(
            setup
                .core
                .next_initialized_tick(
                    pool_key: setup.pool_key,
                    from: i129 { mag: TICKS_IN_ONE_PERCENT * 128, sign: true },
                    skip_ahead: 5
                ) == (i129 { mag: TICKS_IN_ONE_PERCENT * 12, sign: true }, true),
            'next from -128, skip 5'
        );
        assert(
            setup
                .core
                .next_initialized_tick(
                    pool_key: setup.pool_key,
                    from: i129 { mag: TICKS_IN_ONE_PERCENT * 12, sign: true },
                    skip_ahead: 5
                ) == (i129 { mag: TICKS_IN_ONE_PERCENT * 9, sign: false }, true),
            'next from -12, skip 5'
        );
        assert(
            setup
                .core
                .next_initialized_tick(
                    pool_key: setup.pool_key,
                    from: i129 { mag: TICKS_IN_ONE_PERCENT * 9, sign: false },
                    skip_ahead: 5
                ) == (i129 { mag: TICKS_IN_ONE_PERCENT * 128, sign: false }, true),
            'next from 9, skip 5'
        );
        assert(
            setup
                .core
                .next_initialized_tick(
                    pool_key: setup.pool_key,
                    from: i129 { mag: TICKS_IN_ONE_PERCENT * 128, sign: false },
                    skip_ahead: 5
                ) == (i129 { mag: TICKS_IN_ONE_PERCENT * 200, sign: false }, true),
            'next from 128, skip 5'
        );

        // prev

        assert(
            setup
                .core
                .prev_initialized_tick(
                    pool_key: setup.pool_key,
                    from: i129 { mag: TICKS_IN_ONE_PERCENT * 500, sign: false },
                    skip_ahead: 5
                ) == (i129 { mag: TICKS_IN_ONE_PERCENT * 200, sign: false }, true),
            'prev from 500, skip 5'
        );
        assert(
            setup
                .core
                .prev_initialized_tick(
                    pool_key: setup.pool_key,
                    from: i129 { mag: TICKS_IN_ONE_PERCENT * 199, sign: false },
                    skip_ahead: 5
                ) == (i129 { mag: TICKS_IN_ONE_PERCENT * 128, sign: false }, true),
            'prev from 199, skip 5'
        );
        assert(
            setup
                .core
                .prev_initialized_tick(
                    pool_key: setup.pool_key,
                    from: i129 { mag: TICKS_IN_ONE_PERCENT * 127, sign: false },
                    skip_ahead: 5
                ) == (i129 { mag: TICKS_IN_ONE_PERCENT * 9, sign: false }, true),
            'prev from 127, skip 5'
        );
        assert(
            setup
                .core
                .prev_initialized_tick(
                    pool_key: setup.pool_key,
                    from: i129 { mag: TICKS_IN_ONE_PERCENT * 8, sign: false },
                    skip_ahead: 5
                ) == (i129 { mag: TICKS_IN_ONE_PERCENT * 12, sign: true }, true),
            'prev from 8, skip 5'
        );
        assert(
            setup
                .core
                .prev_initialized_tick(
                    pool_key: setup.pool_key,
                    from: i129 { mag: TICKS_IN_ONE_PERCENT * 13, sign: true },
                    skip_ahead: 5
                ) == (i129 { mag: TICKS_IN_ONE_PERCENT * 128, sign: true }, true),
            'prev from -13, skip 5'
        );
        assert(
            setup
                .core
                .prev_initialized_tick(
                    pool_key: setup.pool_key,
                    from: i129 { mag: TICKS_IN_ONE_PERCENT * 129, sign: true },
                    skip_ahead: 5
                ) == (i129 { mag: TICKS_IN_ONE_PERCENT * 154, sign: true }, true),
            'prev from -129, skip 5'
        );
    }
}

mod locks {
    use ekubo::math::ticks::{tick_to_sqrt_ratio};
    use ekubo::tests::helper::{
        Deployer, DeployerTrait, update_position_inner, accumulate_as_fees_inner, flash_borrow_inner
    };
    use super::{
        FeesPerLiquidity, FEE_ONE_PERCENT, swap, update_position, SetupPoolResult, tick_constants,
        div, contract_address_const, Action, ActionResult, ICoreLockerDispatcher,
        ICoreLockerDispatcherTrait, i129, UpdatePositionParameters, SwapParameters,
        IMockERC20Dispatcher, IMockERC20DispatcherTrait, min_sqrt_ratio, max_sqrt_ratio, min_tick,
        max_tick, ICoreDispatcherTrait, ContractAddress, Delta, Bounds, Zero, PoolKey,
        accumulate_as_fees, max_bounds, SavedBalanceKey, TICKS_IN_ONE_PERCENT
    };

    #[test]
    #[should_panic(expected: ('NOT_LOCKED', 'ENTRYPOINT_FAILED'))]
    fn test_error_from_action_not_locked() {
        let mut d: Deployer = Default::default();
        let setup = d
            .setup_pool(
                fee: FEE_ONE_PERCENT,
                tick_spacing: TICKS_IN_ONE_PERCENT,
                initial_tick: Zero::zero(),
                extension: Zero::zero(),
            );
        // should fail because not locked at all
        setup.core.pay(contract_address_const::<1>());
    }

    fn save_to_core(locker: ICoreLockerDispatcher, token: ContractAddress, amount: u128) {
        match locker
            .call(
                Action::SaveBalance(
                    (
                        SavedBalanceKey {
                            owner: contract_address_const::<0>(), token: token, salt: 0
                        },
                        amount
                    )
                )
            ) {
            ActionResult::SaveBalance => {},
            _ => { assert(false, 'expected save'); },
        };
    }

    #[test]
    fn test_flash_borrow_balanced() {
        let mut d: Deployer = Default::default();
        let core = d.deploy_core();
        let locker = d.deploy_locker(core);
        let token = d.deploy_mock_token();

        token.increase_balance(locker.contract_address, 100000000);
        save_to_core(locker, token.contract_address, 100000000);

        flash_borrow_inner(
            core: core,
            locker: locker,
            token: token.contract_address,
            amount_borrow: 0,
            amount_repay: 0
        );
        flash_borrow_inner(
            core: core,
            locker: locker,
            token: token.contract_address,
            amount_borrow: 10,
            amount_repay: 10
        );
        flash_borrow_inner(
            core: core,
            locker: locker,
            token: token.contract_address,
            amount_borrow: 100000000,
            amount_repay: 100000000
        );
    }

    #[test]
    #[should_panic(expected: ('NOT_ZEROED', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED'))]
    fn test_flash_borrow_underpay() {
        let mut d: Deployer = Default::default();
        let core = d.deploy_core();
        let locker = d.deploy_locker(core);
        let token = d.deploy_mock_token();

        token.increase_balance(locker.contract_address, 100000000);
        save_to_core(locker, token.contract_address, 100000000);

        flash_borrow_inner(
            core: core,
            locker: locker,
            token: token.contract_address,
            amount_borrow: 100,
            amount_repay: 0
        );
    }

    #[test]
    #[should_panic(expected: ('NOT_ZEROED', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED'))]
    fn test_flash_borrow_overpay() {
        let mut d: Deployer = Default::default();
        let core = d.deploy_core();
        let locker = d.deploy_locker(core);
        let token = d.deploy_mock_token();

        token.increase_balance(locker.contract_address, 100000000 + 100);
        save_to_core(locker, token.contract_address, 100000000);

        flash_borrow_inner(
            core: core,
            locker: locker,
            token: token.contract_address,
            amount_borrow: 0,
            amount_repay: 100
        );
    }

    #[test]
    #[should_panic(
        expected: (
            'INSUFFICIENT_BALANCE',
            'ENTRYPOINT_FAILED',
            'ENTRYPOINT_FAILED',
            'ENTRYPOINT_FAILED',
            'ENTRYPOINT_FAILED',
            'ENTRYPOINT_FAILED'
        )
    )]
    fn test_flash_borrow_more_than_core_balance() {
        let mut d: Deployer = Default::default();
        let core = d.deploy_core();
        let locker = d.deploy_locker(core);
        let token = d.deploy_mock_token();

        token.increase_balance(locker.contract_address, 100000000);
        save_to_core(locker, token.contract_address, 100000000);

        flash_borrow_inner(
            core: core,
            locker: locker,
            token: token.contract_address,
            amount_borrow: 100000000 + 10,
            amount_repay: 100000000 + 10
        );
    }


    #[test]
    fn test_assert_locker_id_call() {
        let mut d: Deployer = Default::default();
        let setup = d
            .setup_pool(
                fee: FEE_ONE_PERCENT,
                tick_spacing: TICKS_IN_ONE_PERCENT,
                initial_tick: Zero::zero(),
                extension: Zero::zero(),
            );
        setup.locker.call(Action::AssertLockerId(0));
    }

    #[test]
    fn test_relock_call() {
        let mut d: Deployer = Default::default();
        let setup = d
            .setup_pool(
                fee: FEE_ONE_PERCENT,
                tick_spacing: TICKS_IN_ONE_PERCENT,
                initial_tick: Zero::zero(),
                extension: Zero::zero(),
            );
        setup.locker.call(Action::Relock((0, 5)));
    }

    #[test]
    #[should_panic(
        expected: (
            'INVALID_LOCKER_ID', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED'
        )
    )]
    fn test_assert_locker_id_call_wrong() {
        let mut d: Deployer = Default::default();
        let setup = d
            .setup_pool(
                fee: FEE_ONE_PERCENT,
                tick_spacing: TICKS_IN_ONE_PERCENT,
                initial_tick: Zero::zero(),
                extension: Zero::zero(),
            );
        setup.locker.call(Action::AssertLockerId(1));
    }

    #[test]
    #[should_panic(
        expected: (
            'RL_INVALID_LOCKER_ID', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED'
        )
    )]
    fn test_relock_call_fails_invalid_id() {
        let mut d: Deployer = Default::default();
        let setup = d
            .setup_pool(
                fee: FEE_ONE_PERCENT,
                tick_spacing: TICKS_IN_ONE_PERCENT,
                initial_tick: Zero::zero(),
                extension: Zero::zero(),
            );
        setup.locker.call(Action::Relock((1, 5)));
    }

    #[test]
    fn test_zero_liquidity_add() {
        let mut d: Deployer = Default::default();
        let setup = d
            .setup_pool(
                fee: FEE_ONE_PERCENT,
                tick_spacing: TICKS_IN_ONE_PERCENT,
                initial_tick: Zero::zero(),
                extension: Zero::zero(),
            );
        update_position(
            setup: setup,
            bounds: Bounds {
                lower: i129 { mag: TICKS_IN_ONE_PERCENT, sign: true },
                upper: i129 { mag: TICKS_IN_ONE_PERCENT, sign: false }
            },
            liquidity_delta: Zero::zero(),
            recipient: contract_address_const::<42>()
        );
        assert(
            setup
                .core
                .prev_initialized_tick(
                    pool_key: setup.pool_key,
                    from: i129 { mag: TICKS_IN_ONE_PERCENT, sign: true },
                    skip_ahead: 1
                ) != (i129 { mag: TICKS_IN_ONE_PERCENT, sign: true }, true),
            'ticks not initialized'
        );
        assert(
            setup
                .core
                .prev_initialized_tick(
                    pool_key: setup.pool_key,
                    from: i129 { mag: TICKS_IN_ONE_PERCENT, sign: false },
                    skip_ahead: 1
                ) != (i129 { mag: TICKS_IN_ONE_PERCENT, sign: false }, false),
            'ticks not initialized'
        );
    }

    #[test]
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
        let mut d: Deployer = Default::default();
        let setup = d
            .setup_pool(
                fee: FEE_ONE_PERCENT,
                tick_spacing: TICKS_IN_ONE_PERCENT,
                initial_tick: Zero::zero(),
                extension: Zero::zero(),
            );

        update_position(
            setup: setup,
            bounds: Bounds {
                lower: i129 { mag: TICKS_IN_ONE_PERCENT, sign: true },
                upper: i129 { mag: 12, sign: false },
            },
            liquidity_delta: i129 { mag: 100, sign: false },
            recipient: contract_address_const::<42>()
        );
    }

    #[test]
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
        let mut d: Deployer = Default::default();
        let setup = d
            .setup_pool(
                fee: FEE_ONE_PERCENT,
                tick_spacing: TICKS_IN_ONE_PERCENT,
                initial_tick: Zero::zero(),
                extension: Zero::zero(),
            );

        update_position(
            setup: setup,
            bounds: Bounds {
                lower: i129 { mag: TICKS_IN_ONE_PERCENT, sign: true },
                upper: i129 { mag: 10, sign: false },
            },
            liquidity_delta: i129 { mag: 100, sign: false },
            recipient: contract_address_const::<42>()
        );
    }


    #[test]
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
        let mut d: Deployer = Default::default();
        let setup = d
            .setup_pool(
                fee: FEE_ONE_PERCENT,
                tick_spacing: TICKS_IN_ONE_PERCENT,
                initial_tick: Zero::zero(),
                extension: Zero::zero(),
            );

        let delta = update_position(
            setup: setup,
            bounds: Bounds {
                lower: i129 { mag: 10, sign: true }, upper: i129 { mag: 10, sign: false },
            },
            liquidity_delta: Zero::zero(),
            recipient: contract_address_const::<42>()
        );
        assert(delta.amount0 == Zero::zero(), 'amount0');
        assert(delta.amount1 == Zero::zero(), 'amount1');
    }


    #[test]
    fn test_small_amount_liquidity_add() {
        let mut d: Deployer = Default::default();
        let setup = d
            .setup_pool(
                fee: FEE_ONE_PERCENT,
                tick_spacing: 1,
                initial_tick: Zero::zero(),
                extension: Zero::zero(),
            );

        setup.token0.increase_balance(setup.locker.contract_address, 10000000);
        setup.token1.increase_balance(setup.locker.contract_address, 10000000);

        let delta = update_position(
            setup: setup,
            bounds: Bounds {
                lower: i129 { mag: 10, sign: true }, upper: i129 { mag: 10, sign: false },
            },
            liquidity_delta: i129 { mag: 10000000, sign: false },
            recipient: contract_address_const::<42>()
        );

        assert(delta.amount0 == i129 { mag: 50, sign: false }, 'amount0');
        assert(delta.amount1 == i129 { mag: 50, sign: false }, 'amount1');
    }

    #[test]
    #[should_panic(
        expected: (
            'NOT_EXTENSION',
            'ENTRYPOINT_FAILED',
            'ENTRYPOINT_FAILED',
            'ENTRYPOINT_FAILED',
            'ENTRYPOINT_FAILED'
        )
    )]
    fn test_accumulate_fees_per_liquidity_not_extension() {
        let mut d: Deployer = Default::default();
        let setup = d
            .setup_pool(
                fee: FEE_ONE_PERCENT,
                tick_spacing: 1,
                initial_tick: Zero::zero(),
                extension: Zero::zero(),
            );

        setup.token0.increase_balance(setup.locker.contract_address, 10000000);
        setup.token1.increase_balance(setup.locker.contract_address, 10000000);

        // add 1 liquidity
        update_position(
            setup: setup,
            bounds: Bounds {
                lower: i129 { mag: 0, sign: false }, upper: i129 { mag: 1, sign: false },
            },
            liquidity_delta: i129 { mag: 1, sign: false },
            recipient: contract_address_const::<42>()
        );
        assert(setup.core.get_pool_liquidity(setup.pool_key) == 1, 'liquidity');
        assert(
            setup.core.get_pool_fees_per_liquidity(setup.pool_key).is_zero(), 'fees_per_liquidity'
        );

        accumulate_as_fees(setup: setup, amount0: 2, amount1: 3);
    }

    #[test]
    fn test_accumulate_fees_per_liquidity_success() {
        let mut d: Deployer = Default::default();
        let core = d.deploy_core();
        let (token0, token1) = d.deploy_two_mock_tokens();
        let locker = d.deploy_locker(core);
        locker.set_call_points();

        let pool_key = PoolKey {
            token0: token0.contract_address,
            token1: token1.contract_address,
            fee: FEE_ONE_PERCENT,
            tick_spacing: 1,
            extension: locker.contract_address,
        };

        core.initialize_pool(pool_key, Zero::zero());

        token0.increase_balance(locker.contract_address, 10000000);
        token1.increase_balance(locker.contract_address, 10000000);

        // add 1 liquidity
        update_position_inner(
            core,
            pool_key,
            locker,
            bounds: Bounds {
                lower: i129 { mag: 0, sign: false }, upper: i129 { mag: 1, sign: false },
            },
            liquidity_delta: i129 { mag: 1, sign: false },
            recipient: contract_address_const::<42>()
        );
        assert(core.get_pool_liquidity(pool_key) == 1, 'liquidity');
        assert(core.get_pool_fees_per_liquidity(pool_key).is_zero(), 'fees_per_liquidity');

        accumulate_as_fees_inner(core, pool_key, locker, amount0: 2, amount1: 3);

        assert(
            core
                .get_pool_fees_per_liquidity(
                    pool_key
                ) == FeesPerLiquidity {
                    value0: 680564733841876926926749214863536422912,
                    value1: 1020847100762815390390123822295304634368
                },
            'fees_per_liquidity'
        );
    }

    #[test]
    fn test_larger_amount_liquidity_add() {
        let mut d: Deployer = Default::default();
        let setup = d
            .setup_pool(
                fee: FEE_ONE_PERCENT,
                tick_spacing: TICKS_IN_ONE_PERCENT,
                initial_tick: Zero::zero(),
                extension: Zero::zero(),
            );

        setup.token0.increase_balance(setup.locker.contract_address, 10000000000);
        setup.token1.increase_balance(setup.locker.contract_address, 10000000000);

        let delta = update_position(
            setup,
            bounds: Bounds {
                lower: i129 { mag: TICKS_IN_ONE_PERCENT, sign: true },
                upper: i129 { mag: TICKS_IN_ONE_PERCENT, sign: false },
            },
            liquidity_delta: i129 { mag: 1000000000, sign: false },
            recipient: contract_address_const::<42>()
        );

        assert(delta.amount0 == i129 { mag: 4962643, sign: false }, 'amount0');
        assert(delta.amount1 == i129 { mag: 4962643, sign: false }, 'amount1_delta');
    }

    #[test]
    fn test_full_range_liquidity_add() {
        let mut d: Deployer = Default::default();
        let setup = d
            .setup_pool(
                fee: FEE_ONE_PERCENT,
                tick_spacing: 1,
                initial_tick: Zero::zero(),
                extension: Zero::zero(),
            );

        setup
            .token0
            .increase_balance(setup.locker.contract_address, 0xffffffffffffffffffffffffffffffff);
        setup
            .token1
            .increase_balance(setup.locker.contract_address, 0xffffffffffffffffffffffffffffffff);

        let delta = update_position(
            setup,
            bounds: max_bounds(1),
            liquidity_delta: i129 { mag: 1000000000, sign: false },
            recipient: contract_address_const::<42>()
        );

        assert(delta.amount0 == i129 { mag: 1000000000, sign: false }, 'amount0');
        assert(delta.amount1 == i129 { mag: 1000000000, sign: false }, 'amount1_delta');
    }

    #[test]
    fn test_full_range_liquidity_add_and_half_burn() {
        let mut d: Deployer = Default::default();
        let setup = d
            .setup_pool(
                fee: FEE_ONE_PERCENT,
                tick_spacing: 1,
                initial_tick: Zero::zero(),
                extension: Zero::zero(),
            );

        setup
            .token0
            .increase_balance(setup.locker.contract_address, 0xffffffffffffffffffffffffffffffff);
        setup
            .token1
            .increase_balance(setup.locker.contract_address, 0xffffffffffffffffffffffffffffffff);

        update_position(
            setup: setup,
            bounds: max_bounds(1),
            liquidity_delta: i129 { mag: 1000000000, sign: false },
            recipient: contract_address_const::<42>()
        );

        let delta = update_position(
            setup: setup,
            bounds: max_bounds(1),
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
    fn test_full_range_liquidity_add_and_full_burn() {
        let mut d: Deployer = Default::default();
        let setup = d
            .setup_pool(
                fee: FEE_ONE_PERCENT,
                tick_spacing: 1,
                initial_tick: Zero::zero(),
                extension: Zero::zero(),
            );

        setup
            .token0
            .increase_balance(setup.locker.contract_address, 0xffffffffffffffffffffffffffffffff);
        setup
            .token1
            .increase_balance(setup.locker.contract_address, 0xffffffffffffffffffffffffffffffff);

        update_position(
            setup,
            bounds: max_bounds(1),
            liquidity_delta: i129 { mag: 1000000000, sign: false },
            recipient: contract_address_const::<42>()
        );

        let delta = update_position(
            setup,
            bounds: max_bounds(1),
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
    fn test_swap_token0_zero_amount_zero_liquidity() {
        let mut d: Deployer = Default::default();
        let setup = d
            .setup_pool(
                fee: FEE_ONE_PERCENT,
                tick_spacing: TICKS_IN_ONE_PERCENT,
                initial_tick: Zero::zero(),
                extension: Zero::zero(),
            );

        let delta = swap(
            setup,
            amount: Zero::zero(), // input 0 token0, price decreasing
            is_token1: false,
            sqrt_ratio_limit: min_sqrt_ratio(),
            recipient: contract_address_const::<42>(),
            skip_ahead: 0,
        );

        assert(delta.amount0 == Zero::zero(), 'amount0');
        assert(delta.amount1 == Zero::zero(), 'amount1_delta');

        let (price, liquidity, fees_per_liquidity) = (
            setup.core.get_pool_price(setup.pool_key),
            setup.core.get_pool_liquidity(setup.pool_key),
            setup.core.get_pool_fees_per_liquidity(setup.pool_key)
        );
        assert(price.sqrt_ratio == 0x100000000000000000000000000000000_u256, 'price did not move');
        assert(liquidity == 0, 'liquidity is 0');
        assert(fees_per_liquidity.is_zero(), 'fees is 0');
    }

    #[test]
    fn test_swap_token0_exact_input_no_liquidity() {
        let mut d: Deployer = Default::default();
        let setup = d
            .setup_pool(
                fee: FEE_ONE_PERCENT,
                tick_spacing: TICKS_IN_ONE_PERCENT,
                initial_tick: Zero::zero(),
                extension: Zero::zero(),
            );

        let sqrt_ratio_limit = tick_to_sqrt_ratio(
            i129 { mag: TICKS_IN_ONE_PERCENT * 3, sign: true }
        );

        let delta = swap(
            setup,
            amount: i129 { mag: 1, sign: false },
            is_token1: false,
            sqrt_ratio_limit: sqrt_ratio_limit,
            recipient: contract_address_const::<42>(),
            skip_ahead: 0,
        );

        assert(delta.amount0 == Zero::zero(), 'amount0');
        assert(delta.amount1 == Zero::zero(), 'amount1_delta');

        let (price, liquidity, fees_per_liquidity) = (
            setup.core.get_pool_price(setup.pool_key),
            setup.core.get_pool_liquidity(setup.pool_key),
            setup.core.get_pool_fees_per_liquidity(setup.pool_key)
        );
        assert(price.sqrt_ratio == sqrt_ratio_limit, 'price is min');
        assert(liquidity == 0, 'liquidity is 0');
        assert(fees_per_liquidity.is_zero(), 'fees is 0');
    }

    #[test]
    fn test_swap_token1_exact_input_no_liquidity() {
        let mut d: Deployer = Default::default();
        let setup = d
            .setup_pool(
                fee: FEE_ONE_PERCENT,
                tick_spacing: TICKS_IN_ONE_PERCENT,
                initial_tick: Zero::zero(),
                extension: Zero::zero(),
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

        assert(delta.amount0 == Zero::zero(), 'amount0');
        assert(delta.amount1 == Zero::zero(), 'amount1_delta');

        let (price, liquidity, fees_per_liquidity) = (
            setup.core.get_pool_price(setup.pool_key),
            setup.core.get_pool_liquidity(setup.pool_key),
            setup.core.get_pool_fees_per_liquidity(setup.pool_key)
        );
        assert(price.sqrt_ratio == sqrt_ratio_limit, 'price is max');
        assert(liquidity == 0, 'liquidity is 0');
        assert(fees_per_liquidity.is_zero(), 'fees is 0');
    }

    #[test]
    fn test_swap_token0_exact_output_no_liquidity() {
        let mut d: Deployer = Default::default();
        let setup = d
            .setup_pool(
                fee: FEE_ONE_PERCENT,
                tick_spacing: TICKS_IN_ONE_PERCENT,
                initial_tick: Zero::zero(),
                extension: Zero::zero(),
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

        assert(delta.amount0 == Zero::zero(), 'amount0');
        assert(delta.amount1 == Zero::zero(), 'amount1_delta');

        let (price, liquidity, fees_per_liquidity) = (
            setup.core.get_pool_price(setup.pool_key),
            setup.core.get_pool_liquidity(setup.pool_key),
            setup.core.get_pool_fees_per_liquidity(setup.pool_key)
        );
        assert(price.sqrt_ratio == sqrt_ratio_limit, 'price is capped');
        assert(liquidity == 0, 'liquidity is 0');
        assert(fees_per_liquidity.is_zero(), 'fees is 0');
    }

    #[test]
    fn test_swap_token1_exact_output_no_liquidity() {
        let mut d: Deployer = Default::default();
        let setup = d
            .setup_pool(
                fee: FEE_ONE_PERCENT,
                tick_spacing: TICKS_IN_ONE_PERCENT,
                initial_tick: Zero::zero(),
                extension: Zero::zero(),
            );

        let sqrt_ratio_limit = 0x100000000000000000000000000000000_u256 / u256 { low: 2, high: 0 };

        let delta = swap(
            setup,
            amount: i129 { mag: 1, sign: true },
            is_token1: true,
            sqrt_ratio_limit: sqrt_ratio_limit,
            recipient: contract_address_const::<42>(),
            skip_ahead: 0,
        );

        assert(delta.amount0 == Zero::zero(), 'amount0');
        assert(delta.amount1 == Zero::zero(), 'amount1_delta');

        let (price, liquidity, fees_per_liquidity) = (
            setup.core.get_pool_price(setup.pool_key),
            setup.core.get_pool_liquidity(setup.pool_key),
            setup.core.get_pool_fees_per_liquidity(setup.pool_key)
        );
        assert(price.sqrt_ratio == sqrt_ratio_limit, 'price is min');
        assert(liquidity == 0, 'liquidity is 0');
        assert(fees_per_liquidity.is_zero(), 'fees is 0');
    }

    #[test]
    fn test_swap_token0_exact_input_against_small_liquidity_no_tick_cross() {
        let mut d: Deployer = Default::default();
        let setup = d
            .setup_pool(
                fee: FEE_ONE_PERCENT,
                tick_spacing: TICKS_IN_ONE_PERCENT,
                initial_tick: Zero::zero(),
                extension: Zero::zero(),
            );

        setup.token0.increase_balance(setup.locker.contract_address, 10000000);
        setup.token1.increase_balance(setup.locker.contract_address, 10000000);

        update_position(
            setup,
            bounds: Bounds {
                lower: i129 { mag: TICKS_IN_ONE_PERCENT, sign: true },
                upper: i129 { mag: TICKS_IN_ONE_PERCENT, sign: false },
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

        assert(delta.amount0 == i129 { mag: 1000, sign: false }, 'amount0');
        assert(delta.amount1 == i129 { mag: 989, sign: true }, 'amount1');

        let (price, liquidity, fees_per_liquidity) = (
            setup.core.get_pool_price(setup.pool_key),
            setup.core.get_pool_liquidity(setup.pool_key),
            setup.core.get_pool_fees_per_liquidity(setup.pool_key)
        );
        assert(
            price.sqrt_ratio == u256 { low: 340282030041728722151939677011487970083, high: 0 },
            'price lower'
        );
        assert(liquidity == 1000000000, 'liquidity is original');
        assert(
            fees_per_liquidity == FeesPerLiquidity {
                value0: 3402823669209384634633746074317, value1: 0,
            },
            'fees'
        );
    }

    #[test]
    fn test_swap_token0_exact_input_against_small_liquidity_no_tick_cross_example() {
        let FEE_THIRTY_BIPS = 1020847100762815411640772995208708096;
        let TICK_SPACING_60_BIPS = 5982;

        let nearby_starting_tick = i129 { mag: 5553823, sign: true };
        let upper_tick = i129 { mag: 5551296 - (5982 * 20), sign: true };
        let lower_tick = i129 { mag: 5551296 + (5982 * 20), sign: true };

        let mut d: Deployer = Default::default();
        let setup = d
            .setup_pool(
                fee: FEE_THIRTY_BIPS,
                tick_spacing: TICK_SPACING_60_BIPS,
                initial_tick: nearby_starting_tick,
                extension: Zero::zero(),
            );

        setup.token0.increase_balance(setup.locker.contract_address, 717193642384000);
        setup.token1.increase_balance(setup.locker.contract_address, 717193642384000);

        assert(
            swap(
                setup,
                amount: i129 { mag: 1, sign: false },
                is_token1: true,
                sqrt_ratio_limit: 21175949444679574865522613902772161611,
                recipient: contract_address_const::<42>(),
                skip_ahead: 0
            )
                .is_zero(),
            'swap to price zero'
        );

        update_position(
            setup,
            bounds: Bounds { lower: lower_tick, upper: upper_tick },
            liquidity_delta: i129 { mag: 717193642384, sign: false },
            recipient: contract_address_const::<42>()
        );

        let (price, liquidity) = (
            setup.core.get_pool_price(setup.pool_key),
            setup.core.get_pool_liquidity(setup.pool_key),
        );

        assert(price.sqrt_ratio == 21175949444679574865522613902772161611, 'starting_price');
        assert(price.tick == nearby_starting_tick, 'price tick');
        assert(liquidity == 717193642384, 'liquidity');
        let delta = swap(
            setup,
            amount: i129 { mag: 9995000000, sign: false },
            is_token1: false,
            sqrt_ratio_limit: min_sqrt_ratio(),
            recipient: contract_address_const::<42>(),
            skip_ahead: 0
        );
        assert(delta.amount0 == i129 { mag: 9995000000, sign: false }, 'amount0');
        assert(delta.amount1 == i129 { mag: 38557555, sign: true }, 'amount1');
    }

    #[test]
    fn test_swap_token0_exact_output_against_small_liquidity_no_tick_cross() {
        let mut d: Deployer = Default::default();
        let setup = d
            .setup_pool(
                fee: FEE_ONE_PERCENT,
                tick_spacing: TICKS_IN_ONE_PERCENT,
                initial_tick: Zero::zero(),
                extension: Zero::zero(),
            );

        setup.token0.increase_balance(setup.locker.contract_address, 1000000000);
        setup.token1.increase_balance(setup.locker.contract_address, 1000000000);

        update_position(
            setup,
            bounds: Bounds {
                lower: i129 { mag: TICKS_IN_ONE_PERCENT, sign: true },
                upper: i129 { mag: TICKS_IN_ONE_PERCENT, sign: false },
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

        assert(delta.amount0 == i129 { mag: 1000, sign: true }, 'amount0');
        assert(delta.amount1 == i129 { mag: 1012, sign: false }, 'amount1');

        let (price, liquidity, fees_per_liquidity) = (
            setup.core.get_pool_price(setup.pool_key),
            setup.core.get_pool_liquidity(setup.pool_key),
            setup.core.get_pool_fees_per_liquidity(setup.pool_key)
        );
        assert(
            price.sqrt_ratio == u256 { low: 0x10c6f8ba2f9812745d280cca2e8d, high: 1 }, 'price lower'
        );
        assert(liquidity == 1000000000, 'liquidity is original');
        assert(
            fees_per_liquidity == FeesPerLiquidity {
                value0: 0, value1: 0x2f3ea0be6ace18ebf8fbc39f15
            },
            'fees'
        );
    }


    #[test]
    fn test_swap_token0_exact_input_against_small_liquidity_with_tick_cross() {
        let mut d: Deployer = Default::default();
        let setup = d
            .setup_pool(
                fee: FEE_ONE_PERCENT,
                tick_spacing: TICKS_IN_ONE_PERCENT,
                initial_tick: Zero::zero(),
                extension: Zero::zero(),
            );

        setup.token0.increase_balance(setup.locker.contract_address, 10000000);
        setup.token1.increase_balance(setup.locker.contract_address, 10000000);

        update_position(
            setup,
            bounds: Bounds {
                lower: i129 { mag: TICKS_IN_ONE_PERCENT, sign: true },
                upper: i129 { mag: TICKS_IN_ONE_PERCENT, sign: false },
            },
            liquidity_delta: i129 { mag: 100000, sign: false },
            recipient: contract_address_const::<42>()
        );

        let sqrt_ratio_limit = tick_to_sqrt_ratio(
            i129 { mag: TICKS_IN_ONE_PERCENT * 2, sign: true }
        );

        let delta = swap(
            setup,
            amount: i129 { mag: 1000, sign: false },
            is_token1: false,
            sqrt_ratio_limit: sqrt_ratio_limit,
            recipient: contract_address_const::<42>(),
            skip_ahead: 0
        );

        assert(delta.amount0 == i129 { mag: 505, sign: false }, 'amount0');
        assert(delta.amount1 == i129 { mag: 496, sign: true }, 'amount1');

        let (price, liquidity, fees_per_liquidity) = (
            setup.core.get_pool_price(setup.pool_key),
            setup.core.get_pool_liquidity(setup.pool_key),
            setup.core.get_pool_fees_per_liquidity(setup.pool_key)
        );
        assert(price.sqrt_ratio == sqrt_ratio_limit, 'price min');
        assert(liquidity == 0, 'liquidity is 0');

        assert(
            fees_per_liquidity == FeesPerLiquidity {
                value0: 0x3eea209aaa3ad18d25edd052934ac, value1: 0,
            },
            'fees'
        );
    }


    #[test]
    fn test_swap_token0_exact_output_against_small_liquidity_with_tick_cross() {
        let mut d: Deployer = Default::default();
        let setup = d
            .setup_pool(
                fee: FEE_ONE_PERCENT,
                tick_spacing: TICKS_IN_ONE_PERCENT,
                initial_tick: Zero::zero(),
                extension: Zero::zero(),
            );

        setup.token0.increase_balance(setup.locker.contract_address, 10000000);
        setup.token1.increase_balance(setup.locker.contract_address, 10000000);

        update_position(
            setup,
            bounds: Bounds {
                lower: i129 { mag: TICKS_IN_ONE_PERCENT, sign: true },
                upper: i129 { mag: TICKS_IN_ONE_PERCENT, sign: false },
            },
            liquidity_delta: i129 { mag: 100000, sign: false },
            recipient: contract_address_const::<42>()
        );

        let sqrt_ratio_limit = tick_to_sqrt_ratio(
            i129 { mag: TICKS_IN_ONE_PERCENT * 2, sign: false }
        );

        let delta = swap(
            setup,
            amount: i129 { mag: 1000, sign: true },
            is_token1: false,
            sqrt_ratio_limit: sqrt_ratio_limit,
            recipient: contract_address_const::<42>(),
            skip_ahead: 0
        );

        assert(delta.amount0 == i129 { mag: 496, sign: true }, 'amount0');
        assert(delta.amount1 == i129 { mag: 505, sign: false }, 'amount1');

        let (price, liquidity, fees_per_liquidity) = (
            setup.core.get_pool_price(setup.pool_key),
            setup.core.get_pool_liquidity(setup.pool_key),
            setup.core.get_pool_fees_per_liquidity(setup.pool_key)
        );
        assert(price.sqrt_ratio == sqrt_ratio_limit, 'price min');
        assert(liquidity == 0, 'liquidity is 0');
        assert(
            fees_per_liquidity == FeesPerLiquidity {
                value0: 0, value1: 0x3eea209aaa3ad18d25edd052934ac
            },
            'fees'
        );
    }

    #[test]
    fn test_swap_token1_exact_input_against_small_liquidity_no_tick_cross() {
        let mut d: Deployer = Default::default();
        let setup = d
            .setup_pool(
                fee: FEE_ONE_PERCENT,
                tick_spacing: TICKS_IN_ONE_PERCENT,
                initial_tick: Zero::zero(),
                extension: Zero::zero(),
            );

        setup.token0.increase_balance(setup.locker.contract_address, 10000000);
        setup.token1.increase_balance(setup.locker.contract_address, 10000000);

        update_position(
            setup,
            bounds: Bounds {
                lower: i129 { mag: TICKS_IN_ONE_PERCENT, sign: true },
                upper: i129 { mag: TICKS_IN_ONE_PERCENT, sign: false },
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

        assert(delta.amount1 == i129 { mag: 1000, sign: false }, 'amount0');
        assert(delta.amount0 == i129 { mag: 989, sign: true }, 'amount1');

        let (price, liquidity, fees_per_liquidity) = (
            setup.core.get_pool_price(setup.pool_key),
            setup.core.get_pool_liquidity(setup.pool_key),
            setup.core.get_pool_fees_per_liquidity(setup.pool_key)
        );
        assert(
            price.sqrt_ratio == u256 { low: 336879543251729078828740861357450, high: 1 },
            'price lower'
        );
        assert(liquidity == 1000000000, 'liquidity is original');
        assert(
            fees_per_liquidity == FeesPerLiquidity {
                value0: 0, value1: 3402823669209384634633746074317,
            },
            'fees'
        );
    }

    #[test]
    fn test_swap_token1_exact_output_against_small_liquidity_no_tick_cross() {
        let mut d: Deployer = Default::default();
        let setup = d
            .setup_pool(
                fee: FEE_ONE_PERCENT,
                tick_spacing: TICKS_IN_ONE_PERCENT,
                initial_tick: Zero::zero(),
                extension: Zero::zero(),
            );

        setup.token0.increase_balance(setup.locker.contract_address, 10000000);
        setup.token1.increase_balance(setup.locker.contract_address, 10000000);

        update_position(
            setup,
            bounds: Bounds {
                lower: i129 { mag: TICKS_IN_ONE_PERCENT, sign: true },
                upper: i129 { mag: TICKS_IN_ONE_PERCENT, sign: false },
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

        assert(delta.amount0 == i129 { mag: 1012, sign: false }, 'amount1');
        assert(delta.amount1 == i129 { mag: 1000, sign: true }, 'amount0');

        let (price, liquidity, fees_per_liquidity) = (
            setup.core.get_pool_price(setup.pool_key),
            setup.core.get_pool_liquidity(setup.pool_key),
            setup.core.get_pool_fees_per_liquidity(setup.pool_key)
        );
        assert(
            price.sqrt_ratio == u256 { low: 0xffffef39085f4a1272c94b380cb6c7a7, high: 0 }, 'price'
        );
        assert(liquidity == 1000000000, 'liquidity is original');
        assert(
            fees_per_liquidity == FeesPerLiquidity {
                value0: 0x2f3ea0be6ace18ebf8fbc39f15, value1: 0
            },
            'fees'
        );
    }

    #[test]
    fn test_swap_token1_exact_input_against_small_liquidity_with_tick_cross() {
        let mut d: Deployer = Default::default();
        let setup = d
            .setup_pool(
                fee: FEE_ONE_PERCENT,
                tick_spacing: TICKS_IN_ONE_PERCENT,
                initial_tick: Zero::zero(),
                extension: Zero::zero(),
            );

        setup.token0.increase_balance(setup.locker.contract_address, 10000000);
        setup.token1.increase_balance(setup.locker.contract_address, 10000000);

        update_position(
            setup,
            bounds: Bounds {
                lower: i129 { mag: TICKS_IN_ONE_PERCENT, sign: true },
                upper: i129 { mag: TICKS_IN_ONE_PERCENT, sign: false },
            },
            liquidity_delta: i129 { mag: 10000000, sign: false },
            recipient: contract_address_const::<42>()
        );

        let sqrt_ratio_limit = tick_to_sqrt_ratio(
            i129 { mag: TICKS_IN_ONE_PERCENT * 5, sign: false }
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
        assert(delta.amount1 == i129 { mag: 50378, sign: false }, 'amount1');

        let (price, liquidity, fees_per_liquidity) = (
            setup.core.get_pool_price(setup.pool_key),
            setup.core.get_pool_liquidity(setup.pool_key),
            setup.core.get_pool_fees_per_liquidity(setup.pool_key)
        );
        assert(
            price.sqrt_ratio == u256 { low: 0x672a6ec856fce6c85fbf4a4920eb890, high: 1 },
            'ratio after'
        );
        assert(liquidity == 0, 'liquidity is 0');
        assert(
            fees_per_liquidity == FeesPerLiquidity {
                value0: 0, value1: 0x34d925a0a379166c530f718d0b15d
            },
            'fees'
        );
    }

    #[test]
    fn test_swap_token1_exact_output_against_small_liquidity_with_tick_cross() {
        let mut d: Deployer = Default::default();
        let setup = d
            .setup_pool(
                fee: FEE_ONE_PERCENT,
                tick_spacing: TICKS_IN_ONE_PERCENT,
                initial_tick: Zero::zero(),
                extension: Zero::zero(),
            );

        setup.token0.increase_balance(setup.locker.contract_address, 10000000000000000);
        setup.token1.increase_balance(setup.locker.contract_address, 10000000000000000);

        update_position(
            setup,
            bounds: Bounds {
                lower: i129 { mag: TICKS_IN_ONE_PERCENT, sign: true },
                upper: i129 { mag: TICKS_IN_ONE_PERCENT, sign: false },
            },
            liquidity_delta: i129 { mag: 10000000, sign: false },
            recipient: contract_address_const::<42>()
        );

        let sqrt_ratio_limit = tick_to_sqrt_ratio(
            i129 { mag: TICKS_IN_ONE_PERCENT * 5, sign: true }
        );

        let delta = swap(
            setup,
            amount: i129 { mag: 10000000, sign: true },
            is_token1: true,
            sqrt_ratio_limit: sqrt_ratio_limit,
            recipient: contract_address_const::<42>(),
            skip_ahead: 0
        );

        assert(delta.amount0 == i129 { mag: 50378, sign: false }, 'amount0');
        assert(delta.amount1 == i129 { mag: 49626, sign: true }, 'amount1');

        let (price, liquidity, fees_per_liquidity) = (
            setup.core.get_pool_price(setup.pool_key),
            setup.core.get_pool_liquidity(setup.pool_key),
            setup.core.get_pool_fees_per_liquidity(setup.pool_key)
        );
        assert(price.sqrt_ratio == sqrt_ratio_limit, 'ratio after');
        assert(liquidity == 0, 'liquidity is 0');
        assert(
            fees_per_liquidity == FeesPerLiquidity {
                value0: 0x34d925a0a379166c530f718d0b15d, value1: 0
            },
            'fees'
        );
    }

    #[test]
    fn test_swap_exact_input_token0_multiple_ticks_crossed_hit_limit() {
        let mut d: Deployer = Default::default();
        let setup = d
            .setup_pool(
                fee: FEE_ONE_PERCENT,
                tick_spacing: TICKS_IN_ONE_PERCENT,
                initial_tick: Zero::zero(),
                extension: Zero::zero(),
            );

        setup.token0.increase_balance(setup.locker.contract_address, 10000000000000000);
        setup.token1.increase_balance(setup.locker.contract_address, 10000000000000000);

        // in range liquidity
        update_position(
            setup,
            bounds: Bounds {
                lower: i129 { mag: TICKS_IN_ONE_PERCENT, sign: true },
                upper: i129 { mag: TICKS_IN_ONE_PERCENT, sign: false },
            },
            liquidity_delta: i129 { mag: 10000000, sign: false },
            recipient: contract_address_const::<42>()
        );

        // out of range liquidity in the direction of the price movement
        update_position(
            setup,
            bounds: Bounds {
                lower: i129 { mag: 2 * TICKS_IN_ONE_PERCENT, sign: true },
                upper: i129 { mag: TICKS_IN_ONE_PERCENT, sign: true },
            },
            liquidity_delta: i129 { mag: 10000000, sign: false },
            recipient: contract_address_const::<42>()
        );

        // out of range liquidity in the OPPOSITE direction that cancels out the delta
        update_position(
            setup,
            bounds: Bounds {
                lower: i129 { mag: TICKS_IN_ONE_PERCENT, sign: false },
                upper: i129 { mag: 2 * TICKS_IN_ONE_PERCENT, sign: false },
            },
            liquidity_delta: i129 { mag: 10000000, sign: false },
            recipient: contract_address_const::<42>()
        );

        // right above the tick price
        let sqrt_ratio_limit = tick_to_sqrt_ratio(
            i129 { mag: TICKS_IN_ONE_PERCENT * 5, sign: true }
        )
            + 1;

        let delta = swap(
            setup,
            amount: i129 { mag: 100000000, sign: false },
            is_token1: false,
            sqrt_ratio_limit: sqrt_ratio_limit,
            recipient: contract_address_const::<42>(),
            skip_ahead: 0
        );

        assert(delta.amount0 == i129 { mag: 101008, sign: false }, 'amount0');
        assert(delta.amount1 == i129 { mag: 99006, sign: true }, 'amount1');

        let (price, liquidity, fees_per_liquidity) = (
            setup.core.get_pool_price(setup.pool_key),
            setup.core.get_pool_liquidity(setup.pool_key),
            setup.core.get_pool_fees_per_liquidity(setup.pool_key)
        );
        assert(price.tick == i129 { mag: TICKS_IN_ONE_PERCENT * 5, sign: true }, 'tick after');
        assert(price.sqrt_ratio == sqrt_ratio_limit, 'ratio after');
        assert(liquidity == 0, 'liquidity is 0');
        assert(
            fees_per_liquidity == FeesPerLiquidity {
                value0: 0x6a02d31917283ab1acb5d610426d5, value1: 0,
            },
            'fees'
        );
    }

    #[test]
    fn test_swap_exact_input_token1_multiple_ticks_crossed_hit_limit() {
        let mut d: Deployer = Default::default();
        let setup = d
            .setup_pool(
                fee: FEE_ONE_PERCENT,
                tick_spacing: TICKS_IN_ONE_PERCENT,
                initial_tick: Zero::zero(),
                extension: Zero::zero(),
            );

        setup.token0.increase_balance(setup.locker.contract_address, 10000000000000000);
        setup.token1.increase_balance(setup.locker.contract_address, 10000000000000000);

        // in range liquidity
        update_position(
            setup,
            bounds: Bounds {
                lower: i129 { mag: TICKS_IN_ONE_PERCENT, sign: true },
                upper: i129 { mag: TICKS_IN_ONE_PERCENT, sign: false },
            },
            liquidity_delta: i129 { mag: 10000000, sign: false },
            recipient: contract_address_const::<42>()
        );

        // out of range liquidity in the OPPOSITE direction
        update_position(
            setup,
            bounds: Bounds {
                lower: i129 { mag: 2 * TICKS_IN_ONE_PERCENT, sign: true },
                upper: i129 { mag: TICKS_IN_ONE_PERCENT, sign: true },
            },
            liquidity_delta: i129 { mag: 10000000, sign: false },
            recipient: contract_address_const::<42>()
        );

        // out of range liquidity in the direction
        update_position(
            setup,
            bounds: Bounds {
                lower: i129 { mag: TICKS_IN_ONE_PERCENT, sign: false },
                upper: i129 { mag: 2 * TICKS_IN_ONE_PERCENT, sign: false },
            },
            liquidity_delta: i129 { mag: 10000000, sign: false },
            recipient: contract_address_const::<42>()
        );

        // right above the tick price
        let sqrt_ratio_limit = tick_to_sqrt_ratio(
            i129 { mag: TICKS_IN_ONE_PERCENT * 5, sign: false }
        )
            - 1;

        let delta = swap(
            setup,
            amount: i129 { mag: 100000000, sign: false },
            is_token1: true,
            sqrt_ratio_limit: sqrt_ratio_limit,
            recipient: contract_address_const::<42>(),
            skip_ahead: 0
        );

        assert(delta.amount0 == i129 { mag: 0x182be, sign: true }, 'amount0');
        assert(delta.amount1 == i129 { mag: 0x18a90, sign: false }, 'amount1');

        let (price, liquidity, fees_per_liquidity) = (
            setup.core.get_pool_price(setup.pool_key),
            setup.core.get_pool_liquidity(setup.pool_key),
            setup.core.get_pool_fees_per_liquidity(setup.pool_key)
        );
        assert(
            price.tick == i129 { mag: (TICKS_IN_ONE_PERCENT * 5) - 1, sign: false }, 'tick after'
        );
        assert(price.sqrt_ratio == sqrt_ratio_limit, 'ratio after');
        assert(liquidity == 0, 'liquidity is 0');
        assert(
            fees_per_liquidity == FeesPerLiquidity {
                value0: 0, value1: 0x6a02d31917283ab1acb5d610426d5,
            },
            'fees'
        );
    }
}


mod save_load_tests {
    use ekubo::tests::mocks::locker::{Action, ActionResult};
    use super::{
        Deployer, DeployerTrait, IMockERC20DispatcherTrait, ICoreLockerDispatcherTrait,
        ICoreDispatcherTrait, contract_address_const, set_contract_address, SavedBalanceKey
    };

    #[test]
    fn test_save_load_1_token() {
        let mut d: Deployer = Default::default();
        let core = d.deploy_core();
        let token = d.deploy_mock_token();
        let locker = d.deploy_locker(core);

        token.increase_balance(locker.contract_address, 1);
        let cache_key: felt252 = 5678;

        set_contract_address(contract_address_const::<1234567>());

        // important because it allows us to load
        let recipient = locker.contract_address;

        match locker
            .call(
                Action::SaveBalance(
                    (
                        SavedBalanceKey {
                            owner: recipient, token: token.contract_address, salt: cache_key
                        },
                        1
                    )
                )
            ) {
            ActionResult::SaveBalance(balance_next) => {
                assert(balance_next == 1, 'balance_next');
            },
            _ => { assert(false, 'unexpected'); },
        };

        assert(
            core
                .get_saved_balance(
                    key: SavedBalanceKey {
                        owner: recipient, token: token.contract_address, salt: cache_key
                    }
                ) == 1,
            'saved 1'
        );
        assert(
            core
                .get_saved_balance(
                    key: SavedBalanceKey {
                        owner: recipient, token: token.contract_address, salt: 0
                    }
                ) == 0,
            'other cache key'
        );

        match locker.call(Action::LoadBalance((token.contract_address, cache_key, 1, recipient))) {
            ActionResult::LoadBalance(balance_next) => {
                assert(balance_next == 0, 'balance_next');
            },
            _ => { assert(false, 'unexpected') },
        };
    }
}
