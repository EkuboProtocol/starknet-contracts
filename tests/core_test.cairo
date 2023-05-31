use parlay::core::{Parlay, IParlayDispatcher, IParlayDispatcherTrait};
use starknet::contract_address_const;
use starknet::ContractAddress;
use starknet::testing::{set_caller_address, set_contract_address};
use integer::u256;
use integer::u256_from_felt252;
use integer::BoundedInt;
use traits::Into;
use parlay::types::keys::PoolKey;
use parlay::types::i129::i129;
use parlay::math::ticks::{max_sqrt_ratio, min_sqrt_ratio};
use array::{ArrayTrait};
use option::OptionTrait;
use option::Option;
use tests::mocks::mock_erc20::{MockERC20, IMockERC20Dispatcher, IMockERC20DispatcherTrait};
use tests::mocks::locker::{
    CoreLocker, Action, ActionResult, ICoreLockerDispatcher, ICoreLockerDispatcherTrait,
    UpdatePositionParameters, SwapParameters
};

mod helper {
    use super::{
        contract_address_const, ContractAddress, PoolKey, Parlay, IParlayDispatcher,
        IParlayDispatcherTrait, i129, CoreLocker, ICoreLockerDispatcher, MockERC20,
        IMockERC20Dispatcher
    };
    use starknet::{deploy_syscall, ClassHash};
    use array::{Array, ArrayTrait};
    use traits::{Into, TryInto};
    use option::{Option, OptionTrait};
    use starknet::class_hash::Felt252TryIntoClassHash;
    use result::{Result, ResultTrait};
    use parlay::math::utils::ContractAddressOrder;

    fn deploy_mock_token() -> IMockERC20Dispatcher {
        let constructor_calldata: Array<felt252> = Default::default();
        let (token_address, _) = deploy_syscall(
            MockERC20::TEST_CLASS_HASH.try_into().unwrap(), 0, constructor_calldata.span(), true
        )
            .expect('token deploy failed');
        return IMockERC20Dispatcher { contract_address: token_address };
    }

    fn fake_pool_key(fee: u128) -> PoolKey {
        PoolKey {
            token0: contract_address_const::<1>(), token1: contract_address_const::<2>(), fee
        }
    }

    #[derive(Copy, Drop)]
    struct SetupPoolResult {
        token0: IMockERC20Dispatcher,
        token1: IMockERC20Dispatcher,
        pool_key: PoolKey,
        core: IParlayDispatcher,
        locker: ICoreLockerDispatcher
    }

    fn setup_pool(owner: ContractAddress, fee: u128, initial_tick: i129) -> SetupPoolResult {
        let mut token0 = deploy_mock_token();
        let mut token1 = deploy_mock_token();
        if (token0.contract_address > token1.contract_address) {
            let temp = token1;
            token1 = token0;
            token0 = temp;
        }

        let pool_key: PoolKey = PoolKey {
            token0: token0.contract_address, token1: token1.contract_address, fee
        };

        let mut core_constructor_args: Array<felt252> = Default::default();
        core_constructor_args.append(owner.into());

        let (core_address, _) = deploy_syscall(
            Parlay::TEST_CLASS_HASH.try_into().unwrap(), 1, core_constructor_args.span(), true
        )
            .expect('core deploy failed');

        let core = IParlayDispatcher { contract_address: core_address };

        core.initialize_pool(pool_key, initial_tick);

        let mut locker_constructor_args: Array<felt252> = Default::default();
        locker_constructor_args.append(core_address.into());
        let (locker_address, _) = deploy_syscall(
            CoreLocker::TEST_CLASS_HASH.try_into().unwrap(), 1, locker_constructor_args.span(), true
        )
            .expect('locker deploy failed');

        let locker = ICoreLockerDispatcher { contract_address: locker_address };

        SetupPoolResult { token0, token1, pool_key, core, locker }
    }
}

mod owner_tests {
    use super::{PoolKey, Parlay, i129, contract_address_const, set_caller_address};
    #[test]
    #[available_gas(2000000)]
    fn test_constructor_sets_owner() {
        assert(Parlay::get_owner() == contract_address_const::<0>(), 'not set');
        Parlay::constructor(contract_address_const::<1>());
        let owner_read = Parlay::get_owner();
        assert(owner_read == contract_address_const::<1>(), 'owner');
    }

    #[test]
    #[available_gas(2000000)]
    fn test_owner_can_be_changed_by_owner() {
        Parlay::constructor(contract_address_const::<1>());
        set_caller_address(contract_address_const::<1>());
        Parlay::set_owner(contract_address_const::<42>());
        assert(Parlay::get_owner() == contract_address_const::<42>(), 'owner');
    }

    #[test]
    #[available_gas(2000000)]
    #[should_panic(expected: ('OWNER_ONLY', ))]
    fn test_owner_cannot_be_changed_by_caller() {
        set_caller_address(contract_address_const::<1>());
        Parlay::set_owner(contract_address_const::<42>());
    }
}

mod initialize_pool_tests {
    use super::helper::{fake_pool_key};
    use super::{PoolKey, Parlay, i129, contract_address_const};
    #[test]
    #[available_gas(2000000)]
    fn test_initialize_pool_works_uninitialized() {
        Parlay::initialize_pool(fake_pool_key(0), i129 { mag: 1000, sign: true });
        let pool = Parlay::get_pool(fake_pool_key(0));
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
    fn test_initialize_pool_fails_token_order() {
        let pool_key = PoolKey {
            token0: contract_address_const::<1>(), token1: contract_address_const::<1>(), fee: 0, 
        };
        Parlay::initialize_pool(pool_key, i129 { mag: 0, sign: false });
    }

    #[test]
    #[available_gas(3000000)]
    #[should_panic(expected: ('ALREADY_INITIALIZED', ))]
    fn test_initialize_pool_fails_already_initialized() {
        let pool_key = fake_pool_key(0);
        Parlay::initialize_pool(pool_key, i129 { mag: 1000, sign: true });
        Parlay::initialize_pool(pool_key, i129 { mag: 1000, sign: true });
    }
}

mod initialized_ticks_tests {
    use super::helper::{fake_pool_key};
    use super::{Option, OptionTrait, PoolKey, Parlay, i129};

    #[test]
    #[available_gas(500000000)]
    fn test_insert_many_ticks_prev_next() {
        let pool_key = fake_pool_key(0);
        Parlay::insert_initialized_tick(pool_key, i129 { mag: 100, sign: true });
        Parlay::insert_initialized_tick(pool_key, i129 { mag: 50, sign: true });
        Parlay::insert_initialized_tick(pool_key, i129 { mag: 10, sign: true });
        Parlay::insert_initialized_tick(pool_key, i129 { mag: 5, sign: true });
        Parlay::insert_initialized_tick(pool_key, i129 { mag: 1, sign: true });
        Parlay::insert_initialized_tick(pool_key, i129 { mag: 1, sign: false });
        Parlay::insert_initialized_tick(pool_key, i129 { mag: 5, sign: false });
        Parlay::insert_initialized_tick(pool_key, i129 { mag: 10, sign: false });
        Parlay::insert_initialized_tick(pool_key, i129 { mag: 50, sign: false });
        Parlay::insert_initialized_tick(pool_key, i129 { mag: 100, sign: false });

        let mut node = Parlay::initialized_ticks::read((pool_key, i129 { mag: 0, sign: false }));
        assert(node.left.is_some(), '0.left');
        assert(node.right.is_some(), '0.right');

        assert(
            Parlay::next_initialized_tick(pool_key, i129 { mag: 42, sign: true })
                .expect('>-42') == i129 {
                mag: 10, sign: true
            },
            'next tick of -42'
        );
        assert(
            Parlay::prev_initialized_tick(pool_key, i129 { mag: 42, sign: true })
                .expect('<=-42') == i129 {
                mag: 50, sign: true
            },
            'prev tick of -42'
        );
        assert(
            Parlay::next_initialized_tick(pool_key, i129 { mag: 42, sign: false })
                .expect('>42') == i129 {
                mag: 50, sign: false
            },
            'next tick of 42'
        );
        assert(
            Parlay::prev_initialized_tick(pool_key, i129 { mag: 42, sign: false })
                .expect('<=42') == i129 {
                mag: 10, sign: false
            },
            'prev tick of 42'
        );
    }

    #[test]
    #[available_gas(5000000)]
    #[should_panic(expected: ('ALREADY_EXISTS', ))]
    fn test_insert_fails_if_already_exists() {
        let pool_key = fake_pool_key(0);

        Parlay::insert_initialized_tick(pool_key, i129 { mag: 1000, sign: true });
        Parlay::insert_initialized_tick(pool_key, i129 { mag: 1000, sign: true });
    }

    // test that removing a tick that does not exist in the tree fails
    #[test]
    #[available_gas(5000000)]
    #[should_panic(expected: ('TICK_NOT_FOUND', ))]
    fn test_remove_fails_if_does_not_exist() {
        Parlay::remove_initialized_tick(fake_pool_key(0), i129 { mag: 1000, sign: true });
    }

    #[test]
    #[available_gas(5000000)]
    fn test_insert_initialized_tick_next_initialized_tick() {
        let pool_key = fake_pool_key(0);
        Parlay::insert_initialized_tick(pool_key, i129 { mag: 1000, sign: true });
        Parlay::insert_initialized_tick(pool_key, i129 { mag: 1000, sign: false });

        assert(
            Parlay::next_initialized_tick(pool_key, i129 { mag: 1001, sign: true })
                .expect('-1001') == i129 {
                mag: 1000, sign: true
            },
            'next tick of -1001'
        );
        assert(
            Parlay::next_initialized_tick(pool_key, i129 { mag: 1000, sign: true })
                .expect('-1000') == i129 {
                mag: 0, sign: false
            },
            'next tick of -1000'
        );
        assert(
            Parlay::next_initialized_tick(pool_key, i129 { mag: 999, sign: true })
                .expect('-999') == i129 {
                mag: 0, sign: false
            },
            'next tick of -999'
        );
        assert(
            Parlay::next_initialized_tick(pool_key, i129 { mag: 1, sign: true })
                .expect('-1') == i129 {
                mag: 0, sign: false
            },
            'next tick of -1'
        );
        assert(
            Parlay::next_initialized_tick(pool_key, i129 { mag: 0, sign: false })
                .expect('0') == i129 {
                mag: 1000, sign: false
            },
            'next tick of 0'
        );
        assert(
            Parlay::next_initialized_tick(pool_key, i129 { mag: 1, sign: false })
                .expect('1') == i129 {
                mag: 1000, sign: false
            },
            'next tick of 1'
        );
        assert(
            Parlay::next_initialized_tick(pool_key, i129 { mag: 999, sign: false })
                .expect('999') == i129 {
                mag: 1000, sign: false
            },
            'next tick of 999'
        );
        assert(
            Parlay::next_initialized_tick(pool_key, i129 { mag: 1000, sign: false }).is_none(),
            'next tick of 1000'
        );
        assert(
            Parlay::next_initialized_tick(pool_key, i129 { mag: 1001, sign: false }).is_none(),
            'next tick of 1001'
        );
    }

    #[test]
    #[available_gas(5000000)]
    fn test_insert_initialized_tick_prev_initialized_tick() {
        let pool_key = fake_pool_key(0);

        Parlay::insert_initialized_tick(pool_key, i129 { mag: 1000, sign: true });
        Parlay::insert_initialized_tick(pool_key, i129 { mag: 1000, sign: false });

        assert(
            Parlay::prev_initialized_tick(pool_key, i129 { mag: 1001, sign: true }).is_none(),
            'prev tick of -1001'
        );
        assert(
            Parlay::prev_initialized_tick(pool_key, i129 { mag: 1000, sign: true })
                .expect('-1000') == i129 {
                mag: 1000, sign: true
            },
            'prev tick of -1000'
        );
        assert(
            Parlay::prev_initialized_tick(pool_key, i129 { mag: 999, sign: true })
                .expect('-999') == i129 {
                mag: 1000, sign: true
            },
            'prev tick of -999'
        );
        assert(
            Parlay::prev_initialized_tick(pool_key, i129 { mag: 1, sign: true })
                .expect('-1') == i129 {
                mag: 1000, sign: true
            },
            'prev tick of -1'
        );
        assert(
            Parlay::prev_initialized_tick(pool_key, i129 { mag: 0, sign: false })
                .expect('0') == i129 {
                mag: 0, sign: false
            },
            'prev tick of 0'
        );
        assert(
            Parlay::prev_initialized_tick(pool_key, i129 { mag: 1, sign: false })
                .expect('1') == i129 {
                mag: 0, sign: false
            },
            'prev tick of 1'
        );
        assert(
            Parlay::prev_initialized_tick(pool_key, i129 { mag: 999, sign: false })
                .expect('999') == i129 {
                mag: 0, sign: false
            },
            'prev tick of 999'
        );
        assert(
            Parlay::prev_initialized_tick(pool_key, i129 { mag: 1000, sign: false })
                .expect('1000') == i129 {
                mag: 1000, sign: false
            },
            'prev tick of 1000'
        );
        assert(
            Parlay::prev_initialized_tick(pool_key, i129 { mag: 1001, sign: false })
                .expect('1000') == i129 {
                mag: 1000, sign: false
            },
            'prev tick of 1001'
        );
    }
}


mod locks {
    use debug::PrintTrait;

    use super::helper::setup_pool;
    use super::{
        contract_address_const, Action, ActionResult, ICoreLockerDispatcher,
        ICoreLockerDispatcherTrait, i129, UpdatePositionParameters, SwapParameters,
        IMockERC20Dispatcher, IMockERC20DispatcherTrait, min_sqrt_ratio, max_sqrt_ratio
    };


    const FEE_ONE_PERCENT: u128 = 0x28f5c28f5c28f5c28f5c28f5c28f5c2;

    #[test]
    #[available_gas(50000000)]
    fn test_assert_locker_id_call() {
        let setup = setup_pool(contract_address_const::<1>(), FEE_ONE_PERCENT, Default::default());
        setup.locker.call(Action::AssertLockerId(0));
    }
    #[test]
    #[available_gas(50000000)]
    #[should_panic(
        expected: (
            'INVALID_LOCKER_ID', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED'
        )
    )]
    fn test_assert_locker_id_call_wrong() {
        let setup = setup_pool(contract_address_const::<1>(), FEE_ONE_PERCENT, Default::default());
        setup.locker.call(Action::AssertLockerId(1));
    }

    #[test]
    #[available_gas(50000000)]
    fn test_zero_liquidity_add() {
        let setup = setup_pool(contract_address_const::<1>(), FEE_ONE_PERCENT, Default::default());
        setup
            .locker
            .call(
                Action::UpdatePosition(
                    (
                        setup.pool_key, UpdatePositionParameters {
                            tick_lower: i129 {
                                mag: 10, sign: true
                                }, tick_upper: i129 {
                                mag: 10, sign: false
                            }, liquidity_delta: Default::default()
                        }, contract_address_const::<42>()
                    )
                )
            );
    }

    #[test]
    #[available_gas(50000000)]
    #[should_panic(
        expected: (
            'u256_sub Overflow',
            'ENTRYPOINT_FAILED',
            'ENTRYPOINT_FAILED',
            'ENTRYPOINT_FAILED',
            'ENTRYPOINT_FAILED'
        )
    )]
    fn test_small_amount_liquidity_add_no_tokens() {
        let setup = setup_pool(contract_address_const::<1>(), FEE_ONE_PERCENT, Default::default());

        setup
            .locker
            .call(
                Action::UpdatePosition(
                    (
                        setup.pool_key, UpdatePositionParameters {
                            tick_lower: i129 {
                                mag: 10, sign: true
                                }, tick_upper: i129 {
                                mag: 10, sign: false
                                }, liquidity_delta: i129 {
                                mag: 100, sign: false
                            }
                        }, contract_address_const::<42>()
                    )
                )
            );
    }


    #[test]
    #[available_gas(50000000)]
    fn test_small_amount_liquidity_add() {
        let setup = setup_pool(contract_address_const::<1>(), FEE_ONE_PERCENT, Default::default());

        setup
            .token0
            .increase_balance(setup.locker.contract_address, u256 { low: 10000000, high: 0 });
        setup
            .token1
            .increase_balance(setup.locker.contract_address, u256 { low: 10000000, high: 0 });

        let result = setup
            .locker
            .call(
                Action::UpdatePosition(
                    (
                        setup.pool_key, UpdatePositionParameters {
                            tick_lower: i129 {
                                mag: 10, sign: true
                                }, tick_upper: i129 {
                                mag: 10, sign: false
                                }, liquidity_delta: i129 {
                                mag: 10000000, sign: false
                            }
                        }, contract_address_const::<42>()
                    )
                )
            );

        match result {
            ActionResult::AssertLockerId(_) => {
                assert(false, 'unexpected result')
            },
            ActionResult::UpdatePosition(delta) => {
                assert(delta.amount0_delta == i129 { mag: 51, sign: false }, 'amount0_delta');
                assert(delta.amount1_delta == i129 { mag: 51, sign: false }, 'amount1_delta');
            },
            ActionResult::Swap(_) => {
                assert(false, 'unexpected result')
            }
        }
    }

    #[test]
    #[available_gas(50000000)]
    fn test_swap_0_amount() {
        let setup = setup_pool(contract_address_const::<1>(), FEE_ONE_PERCENT, Default::default());

        let result = setup
            .locker
            .call(
                Action::Swap(
                    (
                        setup.pool_key, SwapParameters {
                            amount: Default::default(), // input 0 token0, price decreasing
                            is_token1: false,
                            sqrt_ratio_limit: min_sqrt_ratio(),
                        }, contract_address_const::<42>()
                    )
                )
            );

        match result {
            ActionResult::AssertLockerId(_) => {
                assert(false, 'unexpected result')
            },
            ActionResult::UpdatePosition(_) => {
                assert(false, 'unexpected result')
            },
            ActionResult::Swap(delta) => {
                assert(delta.amount0_delta == Default::default(), 'amount0_delta');
                assert(delta.amount1_delta == Default::default(), 'amount1_delta');
            }
        }
    }
}
