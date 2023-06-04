use ekubo::core::{Ekubo, IEkuboDispatcher, IEkuboDispatcherTrait, Delta};
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
use tests::mocks::mock_erc20::{MockERC20, IMockERC20Dispatcher, IMockERC20DispatcherTrait};
use tests::mocks::locker::{
    CoreLocker, Action, ActionResult, ICoreLockerDispatcher, ICoreLockerDispatcherTrait,
    UpdatePositionParameters, SwapParameters
};

mod helper {
    use super::{
        contract_address_const, ContractAddress, PoolKey, Ekubo, IEkuboDispatcher,
        IEkuboDispatcherTrait, i129, CoreLocker, ICoreLockerDispatcher, ICoreLockerDispatcherTrait,
        MockERC20, IMockERC20Dispatcher, Action, ActionResult, UpdatePositionParameters,
        SwapParameters, IMockERC20DispatcherTrait, Delta
    };
    use starknet::{deploy_syscall, ClassHash};
    use array::{Array, ArrayTrait};
    use traits::{Into, TryInto};
    use option::{Option, OptionTrait};
    use starknet::class_hash::Felt252TryIntoClassHash;
    use result::{Result, ResultTrait};
    use ekubo::math::utils::ContractAddressOrder;

    fn deploy_mock_token() -> IMockERC20Dispatcher {
        let constructor_calldata: Array<felt252> = Default::default();
        let (token_address, _) = deploy_syscall(
            MockERC20::TEST_CLASS_HASH.try_into().unwrap(), 0, constructor_calldata.span(), true
        )
            .expect('token deploy failed');
        return IMockERC20Dispatcher { contract_address: token_address };
    }

    fn fake_pool_key() -> PoolKey {
        PoolKey {
            token0: contract_address_const::<1>(),
            token1: contract_address_const::<2>(),
            fee: 0,
            tick_spacing: 1
        }
    }

    #[derive(Copy, Drop)]
    struct SetupPoolResult {
        token0: IMockERC20Dispatcher,
        token1: IMockERC20Dispatcher,
        pool_key: PoolKey,
        core: IEkuboDispatcher,
        locker: ICoreLockerDispatcher
    }

    fn setup_pool(
        owner: ContractAddress, fee: u128, tick_spacing: u128, initial_tick: i129
    ) -> SetupPoolResult {
        let mut token0 = deploy_mock_token();
        let mut token1 = deploy_mock_token();
        if (token0.contract_address > token1.contract_address) {
            let temp = token1;
            token1 = token0;
            token0 = temp;
        }

        let pool_key: PoolKey = PoolKey {
            token0: token0.contract_address, token1: token1.contract_address, fee, tick_spacing
        };

        let mut core_constructor_args: Array<felt252> = Default::default();
        core_constructor_args.append(owner.into());

        let (core_address, _) = deploy_syscall(
            Ekubo::TEST_CLASS_HASH.try_into().unwrap(), 1, core_constructor_args.span(), true
        )
            .expect('core deploy failed');

        let core = IEkuboDispatcher { contract_address: core_address };

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


    #[derive(Drop, Copy)]
    struct Balances {
        token0_balance_core: u256,
        token1_balance_core: u256,
        token0_balance_recipient: u256,
        token1_balance_recipient: u256,
        token0_balance_locker: u256,
        token1_balance_locker: u256,
    }
    fn get_balances(_setup: SetupPoolResult, recipient: ContractAddress) -> Balances {
        let token0_balance_core = _setup.token0.balance_of(_setup.core.contract_address);
        let token1_balance_core = _setup.token1.balance_of(_setup.core.contract_address);
        let token0_balance_recipient = _setup.token0.balance_of(recipient);
        let token1_balance_recipient = _setup.token1.balance_of(recipient);
        let token0_balance_locker = _setup.token0.balance_of(_setup.locker.contract_address);
        let token1_balance_locker = _setup.token1.balance_of(_setup.locker.contract_address);
        Balances {
            token0_balance_core,
            token1_balance_core,
            token0_balance_recipient,
            token1_balance_recipient,
            token0_balance_locker,
            token1_balance_locker,
        }
    }

    fn diff(x: u256, y: u256) -> i129 {
        let (lower, upper) = if x < y {
            (x, y)
        } else {
            (y, x)
        };
        let diff = upper - lower;
        assert(diff.high == 0, 'diff_overflow');
        i129 { mag: diff.low, sign: (x < y) & (diff != 0) }
    }

    fn assert_balances_delta(before: Balances, after: Balances, delta: Delta) {
        assert(
            diff(after.token0_balance_core, before.token0_balance_core) == delta.amount0_delta,
            'token0_balance_core'
        );
        assert(
            diff(after.token1_balance_core, before.token1_balance_core) == delta.amount1_delta,
            'token1_balance_core'
        );

        if (delta.amount0_delta.sign) {
            assert(
                diff(after.token0_balance_recipient, before.token0_balance_recipient) == -delta
                    .amount0_delta,
                'token0_balance_recipient'
            );
        } else {
            assert(
                diff(after.token0_balance_locker, before.token0_balance_locker) == -delta
                    .amount0_delta,
                'token0_balance_locker'
            );
        }
        if (delta.amount1_delta.sign) {
            assert(
                diff(after.token1_balance_recipient, before.token1_balance_recipient) == -delta
                    .amount1_delta,
                'token1_balance_recipient'
            );
        } else {
            assert(
                diff(after.token1_balance_locker, before.token1_balance_locker) == -delta
                    .amount1_delta,
                'token1_balance_locker'
            );
        }
    }

    fn update_position(
        setup: SetupPoolResult,
        tick_lower: i129,
        tick_upper: i129,
        liquidity_delta: i129,
        recipient: ContractAddress
    ) -> Delta {
        let before: Balances = get_balances(setup, recipient);
        match setup
            .locker
            .call(
                Action::UpdatePosition(
                    (
                        setup.pool_key, UpdatePositionParameters {
                            tick_lower, tick_upper, liquidity_delta
                        }, recipient
                    )
                )
            ) {
            ActionResult::AssertLockerId(_) => {
                assert(false, 'unexpected');
                Default::default()
            },
            ActionResult::UpdatePosition(delta) => {
                let after: Balances = get_balances(setup, recipient);
                assert_balances_delta(before, after, delta);
                delta
            },
            ActionResult::Swap(_) => {
                assert(false, 'unexpected');
                Default::default()
            },
        }
    }

    fn swap(
        setup: SetupPoolResult,
        amount: i129,
        is_token1: bool,
        sqrt_ratio_limit: u256,
        recipient: ContractAddress
    ) -> Delta {
        let before: Balances = get_balances(setup, recipient);

        match setup
            .locker
            .call(
                Action::Swap(
                    (
                        setup.pool_key, SwapParameters {
                            amount, is_token1, sqrt_ratio_limit, 
                        }, recipient
                    )
                )
            ) {
            ActionResult::AssertLockerId(_) => {
                assert(false, 'unexpected');
                Default::default()
            },
            ActionResult::UpdatePosition(_) => {
                assert(false, 'unexpected');
                Default::default()
            },
            ActionResult::Swap(delta) => {
                let after: Balances = get_balances(setup, recipient);
                assert_balances_delta(before, after, delta);
                delta
            },
        }
    }
}

mod owner_tests {
    use super::{PoolKey, Ekubo, i129, contract_address_const, set_caller_address};
    #[test]
    #[available_gas(2000000)]
    fn test_constructor_sets_owner() {
        assert(Ekubo::get_owner() == contract_address_const::<0>(), 'not set');
        Ekubo::constructor(contract_address_const::<1>());
        let owner_read = Ekubo::get_owner();
        assert(owner_read == contract_address_const::<1>(), 'owner');
    }

    #[test]
    #[available_gas(2000000)]
    fn test_owner_can_be_changed_by_owner() {
        Ekubo::constructor(contract_address_const::<1>());
        set_caller_address(contract_address_const::<1>());
        Ekubo::set_owner(contract_address_const::<42>());
        assert(Ekubo::get_owner() == contract_address_const::<42>(), 'owner');
    }

    #[test]
    #[available_gas(2000000)]
    #[should_panic(expected: ('OWNER_ONLY', ))]
    fn test_owner_cannot_be_changed_by_caller() {
        set_caller_address(contract_address_const::<1>());
        Ekubo::set_owner(contract_address_const::<42>());
    }
}

mod initialize_pool_tests {
    use super::helper::{fake_pool_key};
    use super::{PoolKey, Ekubo, i129, contract_address_const};
    #[test]
    #[available_gas(2000000)]
    fn test_initialize_pool_works_uninitialized() {
        Ekubo::initialize_pool(fake_pool_key(), i129 { mag: 1000, sign: true });
        let pool = Ekubo::get_pool(fake_pool_key());
        assert(
            pool.sqrt_ratio == u256 { low: 340112268350713539826535022315348447443, high: 0 },
            'sqrt_ratio'
        );
        assert(pool.root_tick == Option::None(()), 'root_tick');
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
        Ekubo::initialize_pool(pool_key, i129 { mag: 0, sign: false });
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
        Ekubo::initialize_pool(pool_key, i129 { mag: 0, sign: false });
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
        Ekubo::initialize_pool(pool_key, i129 { mag: 0, sign: false });
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
        Ekubo::initialize_pool(pool_key, i129 { mag: 0, sign: false });
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
        Ekubo::initialize_pool(pool_key, i129 { mag: 0, sign: false });
    }

    #[test]
    #[available_gas(4000000)]
    #[should_panic(expected: ('ALREADY_INITIALIZED', ))]
    fn test_initialize_pool_fails_already_initialized() {
        let pool_key = fake_pool_key();
        Ekubo::initialize_pool(pool_key, i129 { mag: 1000, sign: true });
        Ekubo::initialize_pool(pool_key, i129 { mag: 1000, sign: true });
    }
}

mod initialized_ticks_tests {
    use super::helper::{fake_pool_key};
    use super::{Option, OptionTrait, PoolKey, Pool, Ekubo, i129};
    use ekubo::math::utils::{u128_max};

    fn max_height(pool_key: PoolKey, from_tick: Option<i129>) -> u128 {
        match (from_tick) {
            Option::Some(value) => {
                let node = Ekubo::initialized_ticks::read((pool_key, value));
                u128_max(max_height(pool_key, node.left), max_height(pool_key, node.right)) + 1
            },
            Option::None(_) => 0
        }
    }

    fn check_tree_correctness(pool_key: PoolKey, tick: Option<i129>, parent: Option<i129>) {
        match tick {
            Option::Some(value) => {
                let node = Ekubo::initialized_ticks::read((pool_key, value));
                assert(parent == node.parent, 'parent');
                match node.left {
                    Option::Some(left) => {
                        assert(left < value, 'left < current');
                    },
                    Option::None(_) => {}
                }
                match node.right {
                    Option::Some(right) => {
                        assert(right > value, 'right > current');
                    },
                    Option::None(_) => {}
                }
                check_tree_correctness(pool_key, node.left, tick);
                check_tree_correctness(pool_key, node.right, tick);
            },
            Option::None(_) => {}
        }
        if (tick.is_none()) {
            return ();
        }
    }

    fn rebalance_tree(pool_key: PoolKey, root: i129) -> Option<i129> {
        let pool = Ekubo::pools::read(pool_key);
        Ekubo::pools::write(
            pool_key,
            Pool {
                sqrt_ratio: pool.sqrt_ratio,
                root_tick: Option::Some(root),
                tick: pool.tick,
                liquidity: pool.liquidity,
                fee_growth_global_token0: pool.fee_growth_global_token0,
                fee_growth_global_token1: pool.fee_growth_global_token1,
            }
        );
        Option::Some(Ekubo::rebalance_tree(pool_key, root))
    }

    fn is_tree_balanced(pool_key: PoolKey, at_tick: Option<i129>) -> bool {
        match at_tick {
            Option::Some(value) => {
                let node = Ekubo::initialized_ticks::read((pool_key, value));
                let left_height = max_height(pool_key, node.left);
                let right_height = max_height(pool_key, node.right);
                let diff = if (left_height < right_height) {
                    right_height - left_height
                } else {
                    left_height - right_height
                };
                diff <= 1
                    & is_tree_balanced(pool_key, node.left)
                    & is_tree_balanced(pool_key, node.right)
            },
            Option::None(_) => true,
        }
    }

    #[test]
    #[available_gas(500000000)]
    fn test_insert_balanced() {
        let pool_key = fake_pool_key();
        let mut root_tick = Ekubo::insert_initialized_tick(
            pool_key, Option::None(()), i129 { mag: 0, sign: false }
        );
        root_tick =
            Ekubo::insert_initialized_tick(pool_key, root_tick, i129 { mag: 1, sign: true });
        root_tick =
            Ekubo::insert_initialized_tick(pool_key, root_tick, i129 { mag: 1, sign: false });

        assert(is_tree_balanced(pool_key, root_tick), 'tree is balanced');
        check_tree_correctness(pool_key, root_tick, Option::None(()));

        assert(root_tick == Option::Some(i129 { mag: 0, sign: false }), 'root tick is 0');
        let root_node = Ekubo::initialized_ticks::read((pool_key, root_tick.unwrap()));
        assert(root_node.left == Option::Some(i129 { mag: 1, sign: true }), 'left is -1');
        assert(root_node.right == Option::Some(i129 { mag: 1, sign: false }), 'right is 1');

        assert(
            Ekubo::initialized_ticks::read(
                (pool_key, i129 { mag: 1, sign: true })
            ) == Default::default(),
            'left is default'
        );
        assert(
            Ekubo::initialized_ticks::read(
                (pool_key, i129 { mag: 1, sign: false })
            ) == Default::default(),
            'right is default'
        );
    }

    #[test]
    #[available_gas(500000000)]
    fn test_insert_balanced_bigger_tree() {
        let pool_key = fake_pool_key();
        let mut root_tick = Ekubo::insert_initialized_tick(
            pool_key, Option::None(()), i129 { mag: 0, sign: false }
        );
        root_tick =
            Ekubo::insert_initialized_tick(pool_key, root_tick, i129 { mag: 2, sign: true });
        root_tick =
            Ekubo::insert_initialized_tick(pool_key, root_tick, i129 { mag: 2, sign: false });
        root_tick =
            Ekubo::insert_initialized_tick(pool_key, root_tick, i129 { mag: 3, sign: true });
        root_tick =
            Ekubo::insert_initialized_tick(pool_key, root_tick, i129 { mag: 1, sign: true });
        root_tick =
            Ekubo::insert_initialized_tick(pool_key, root_tick, i129 { mag: 3, sign: false });
        root_tick =
            Ekubo::insert_initialized_tick(pool_key, root_tick, i129 { mag: 1, sign: false });

        assert(is_tree_balanced(pool_key, root_tick), 'tree is balanced');
        check_tree_correctness(pool_key, root_tick, Option::None(()));
        assert(root_tick == Option::Some(i129 { mag: 0, sign: false }), 'root tick is 0');

        let root_node = Ekubo::initialized_ticks::read((pool_key, root_tick.unwrap()));
        assert(root_node.left == Option::Some(i129 { mag: 2, sign: true }), 'root.left is -2');
        assert(root_node.right == Option::Some(i129 { mag: 2, sign: false }), 'root.right is 2');

        let left_node = Ekubo::initialized_ticks::read((pool_key, root_node.left.unwrap()));
        assert(left_node.left == Option::Some(i129 { mag: 3, sign: true }), 'left.left is -3');
        assert(left_node.right == Option::Some(i129 { mag: 1, sign: true }), 'left.right is -1');

        let right_node = Ekubo::initialized_ticks::read((pool_key, root_node.right.unwrap()));
        assert(right_node.left == Option::Some(i129 { mag: 1, sign: false }), 'left.left is 1');
        assert(right_node.right == Option::Some(i129 { mag: 3, sign: false }), 'left.right is 3');

        assert(
            Ekubo::initialized_ticks::read(
                (pool_key, i129 { mag: 3, sign: true })
            ) == Default::default(),
            'leaf -3 is default'
        );
        assert(
            Ekubo::initialized_ticks::read(
                (pool_key, i129 { mag: 1, sign: true })
            ) == Default::default(),
            'leaf -1 is default'
        );
        assert(
            Ekubo::initialized_ticks::read(
                (pool_key, i129 { mag: 1, sign: false })
            ) == Default::default(),
            'leaf 1 is default'
        );
        assert(
            Ekubo::initialized_ticks::read(
                (pool_key, i129 { mag: 3, sign: false })
            ) == Default::default(),
            'leaf 3 is default'
        );
    }


    // this test should be updated when the rebalancing is implemented
    #[test]
    #[available_gas(5000000000)]
    fn test_insert_sorted_ticks_and_removes() {
        let pool_key = fake_pool_key();
        let mut root: Option<i129> = Option::None(());
        let mut next: i129 = i129 { mag: 0, sign: false };
        loop {
            if (next > i129 { mag: 30, sign: false }) {
                break ();
            }
            root = Ekubo::insert_initialized_tick(pool_key, root, next);
            next = next + i129 { mag: 1, sign: false };
        };

        assert(!is_tree_balanced(pool_key, root), 'tree is not balanced');
        check_tree_correctness(pool_key, root, Option::None(()));

        // remove some from the middle
        next = i129 { mag: 10, sign: false };
        loop {
            if (next < i129 { mag: 6, sign: false }) {
                break ();
            }
            root = Ekubo::remove_initialized_tick(pool_key, root, next);
            next = next - i129 { mag: 1, sign: false };
        };
        assert(!is_tree_balanced(pool_key, root), 'tree is not balanced');
        check_tree_correctness(pool_key, root, Option::None(()));

        // remove the root node 5 times
        next = i129 { mag: 0, sign: false };
        loop {
            if (next > i129 { mag: 4, sign: false }) {
                break ();
            }
            root = Ekubo::remove_initialized_tick(pool_key, root, root.unwrap());
            next = next + i129 { mag: 1, sign: false };
        };
        assert(!is_tree_balanced(pool_key, root), 'tree is not balanced');
        check_tree_correctness(pool_key, root, Option::None(()));

        root = rebalance_tree(pool_key, root.unwrap());
        assert(is_tree_balanced(pool_key, root), 'tree is balanced');
        check_tree_correctness(pool_key, root, Option::None(()));
    }

    #[test]
    #[available_gas(500000000)]
    fn test_insert_balanced_remove_left() {
        let pool_key = fake_pool_key();
        let mut root_tick = Ekubo::insert_initialized_tick(
            pool_key, Option::None(()), i129 { mag: 0, sign: false }
        );
        root_tick =
            Ekubo::insert_initialized_tick(pool_key, root_tick, i129 { mag: 1, sign: true });
        root_tick =
            Ekubo::insert_initialized_tick(pool_key, root_tick, i129 { mag: 1, sign: false });

        assert(root_tick == Option::Some(i129 { mag: 0, sign: false }), 'root tick is 0');

        root_tick =
            Ekubo::remove_initialized_tick(pool_key, root_tick, i129 { mag: 1, sign: true });
        assert(is_tree_balanced(pool_key, root_tick), 'tree is balanced');
        check_tree_correctness(pool_key, root_tick, Option::None(()));

        assert(root_tick == Option::Some(i129 { mag: 0, sign: false }), 'root tick is 0');
        let root_node = Ekubo::initialized_ticks::read((pool_key, root_tick.unwrap()));
        assert(root_node.left == Option::None(()), 'left is gone');
        assert(root_node.right == Option::Some(i129 { mag: 1, sign: false }), 'right is 1');
    }


    #[test]
    #[available_gas(500000000)]
    fn test_insert_balanced_remove_right() {
        let pool_key = fake_pool_key();
        let mut root_tick = Ekubo::insert_initialized_tick(
            pool_key, Option::None(()), i129 { mag: 0, sign: false }
        );
        root_tick =
            Ekubo::insert_initialized_tick(pool_key, root_tick, i129 { mag: 1, sign: true });
        root_tick =
            Ekubo::insert_initialized_tick(pool_key, root_tick, i129 { mag: 1, sign: false });

        root_tick =
            Ekubo::remove_initialized_tick(pool_key, root_tick, i129 { mag: 1, sign: false });
        assert(is_tree_balanced(pool_key, root_tick), 'tree is balanced');
        check_tree_correctness(pool_key, root_tick, Option::None(()));

        assert(root_tick == Option::Some(i129 { mag: 0, sign: false }), 'root tick is 0');
        let root_node = Ekubo::initialized_ticks::read((pool_key, root_tick.unwrap()));
        assert(root_node.left == Option::Some(i129 { mag: 1, sign: true }), 'left is -1');
        assert(root_node.right == Option::None(()), 'right is gone');
    }


    #[test]
    #[available_gas(500000000)]
    fn test_insert_balanced_remove_root() {
        let pool_key = fake_pool_key();
        let mut root_tick = Ekubo::insert_initialized_tick(
            pool_key, Option::None(()), i129 { mag: 0, sign: false }
        );
        root_tick =
            Ekubo::insert_initialized_tick(pool_key, root_tick, i129 { mag: 1, sign: true });
        root_tick =
            Ekubo::insert_initialized_tick(pool_key, root_tick, i129 { mag: 1, sign: false });

        root_tick =
            Ekubo::remove_initialized_tick(pool_key, root_tick, i129 { mag: 0, sign: false });
        assert(is_tree_balanced(pool_key, root_tick), 'tree is balanced');
        check_tree_correctness(pool_key, root_tick, Option::None(()));

        assert(root_tick == Option::Some(i129 { mag: 1, sign: false }), 'root tick is 1');
        let root_node = Ekubo::initialized_ticks::read((pool_key, root_tick.unwrap()));
        assert(root_node.parent == Option::None(()), 'parent is none');
        assert(root_node.left == Option::Some(i129 { mag: 1, sign: true }), 'left is -1');
        assert(root_node.right == Option::None(()), 'right is empty');
    }


    #[test]
    #[available_gas(500000000)]
    fn test_insert_many_ticks_prev_next() {
        let pool_key = fake_pool_key();
        let mut root_tick = Ekubo::insert_initialized_tick(
            pool_key, Option::None(()), i129 { mag: 100, sign: true }
        );
        root_tick =
            Ekubo::insert_initialized_tick(pool_key, root_tick, i129 { mag: 50, sign: true });
        root_tick =
            Ekubo::insert_initialized_tick(pool_key, root_tick, i129 { mag: 10, sign: true });
        root_tick =
            Ekubo::insert_initialized_tick(pool_key, root_tick, i129 { mag: 5, sign: true });
        root_tick =
            Ekubo::insert_initialized_tick(pool_key, root_tick, i129 { mag: 1, sign: true });
        root_tick =
            Ekubo::insert_initialized_tick(pool_key, root_tick, i129 { mag: 1, sign: false });
        root_tick =
            Ekubo::insert_initialized_tick(pool_key, root_tick, i129 { mag: 5, sign: false });
        root_tick =
            Ekubo::insert_initialized_tick(pool_key, root_tick, i129 { mag: 10, sign: false });
        root_tick =
            Ekubo::insert_initialized_tick(pool_key, root_tick, i129 { mag: 50, sign: false });
        root_tick =
            Ekubo::insert_initialized_tick(pool_key, root_tick, i129 { mag: 100, sign: false });

        assert(!is_tree_balanced(pool_key, root_tick), 'tree not balanced');
        check_tree_correctness(pool_key, root_tick, Option::None(()));

        assert(
            Ekubo::next_initialized_tick(pool_key, root_tick, i129 { mag: 42, sign: true })
                .expect('>-42') == i129 {
                mag: 10, sign: true
            },
            'next tick of -42'
        );
        assert(
            Ekubo::prev_initialized_tick(pool_key, root_tick, i129 { mag: 42, sign: true })
                .expect('<=-42') == i129 {
                mag: 50, sign: true
            },
            'prev tick of -42'
        );
        assert(
            Ekubo::next_initialized_tick(pool_key, root_tick, i129 { mag: 42, sign: false })
                .expect('>42') == i129 {
                mag: 50, sign: false
            },
            'next tick of 42'
        );
        assert(
            Ekubo::prev_initialized_tick(pool_key, root_tick, i129 { mag: 42, sign: false })
                .expect('<=42') == i129 {
                mag: 10, sign: false
            },
            'prev tick of 42'
        );

        root_tick = rebalance_tree(pool_key, root_tick.unwrap());
        assert(is_tree_balanced(pool_key, root_tick), 'tree is balanced');
        check_tree_correctness(pool_key, root_tick, Option::None(()));
    }

    #[test]
    #[available_gas(500000000)]
    fn test_insert_many_ticks_prev_next_reverse_order_insert() {
        let pool_key = fake_pool_key();
        let mut root_tick = Ekubo::insert_initialized_tick(
            pool_key, Option::None(()), i129 { mag: 100, sign: false }
        );
        root_tick =
            Ekubo::insert_initialized_tick(pool_key, root_tick, i129 { mag: 50, sign: false });
        root_tick =
            Ekubo::insert_initialized_tick(pool_key, root_tick, i129 { mag: 10, sign: false });
        root_tick =
            Ekubo::insert_initialized_tick(pool_key, root_tick, i129 { mag: 5, sign: false });
        root_tick =
            Ekubo::insert_initialized_tick(pool_key, root_tick, i129 { mag: 1, sign: false });
        root_tick =
            Ekubo::insert_initialized_tick(pool_key, root_tick, i129 { mag: 1, sign: true });
        root_tick =
            Ekubo::insert_initialized_tick(pool_key, root_tick, i129 { mag: 5, sign: true });
        root_tick =
            Ekubo::insert_initialized_tick(pool_key, root_tick, i129 { mag: 10, sign: true });
        root_tick =
            Ekubo::insert_initialized_tick(pool_key, root_tick, i129 { mag: 50, sign: true });
        root_tick =
            Ekubo::insert_initialized_tick(pool_key, root_tick, i129 { mag: 100, sign: true });

        assert(!is_tree_balanced(pool_key, root_tick), 'tree not balanced');
        check_tree_correctness(pool_key, root_tick, Option::None(()));

        assert(
            Ekubo::next_initialized_tick(pool_key, root_tick, i129 { mag: 42, sign: true })
                .expect('>-42') == i129 {
                mag: 10, sign: true
            },
            'next tick of -42'
        );
        assert(
            Ekubo::prev_initialized_tick(pool_key, root_tick, i129 { mag: 42, sign: true })
                .expect('<=-42') == i129 {
                mag: 50, sign: true
            },
            'prev tick of -42'
        );
        assert(
            Ekubo::next_initialized_tick(pool_key, root_tick, i129 { mag: 42, sign: false })
                .expect('>42') == i129 {
                mag: 50, sign: false
            },
            'next tick of 42'
        );
        assert(
            Ekubo::prev_initialized_tick(pool_key, root_tick, i129 { mag: 42, sign: false })
                .expect('<=42') == i129 {
                mag: 10, sign: false
            },
            'prev tick of 42'
        );

        root_tick = rebalance_tree(pool_key, root_tick.unwrap());
        assert(is_tree_balanced(pool_key, root_tick), 'tree not balanced');
        check_tree_correctness(pool_key, root_tick, Option::None(()));
    }

    #[test]
    #[available_gas(50000000)]
    #[should_panic(expected: ('ALREADY_EXISTS', ))]
    fn test_insert_fails_if_already_exists() {
        let pool_key = fake_pool_key();

        let root_tick = Ekubo::insert_initialized_tick(
            pool_key, Option::None(()), i129 { mag: 1000, sign: true }
        );
        Ekubo::insert_initialized_tick(pool_key, root_tick, i129 { mag: 1000, sign: true });
    }

    // test that removing a tick that does not exist in the tree fails
    #[test]
    #[available_gas(50000000)]
    #[should_panic(expected: ('TICK_NOT_FOUND', ))]
    fn test_remove_fails_if_does_not_exist() {
        Ekubo::remove_initialized_tick(
            fake_pool_key(), Option::None(()), i129 { mag: 1000, sign: true }
        );
    }

    #[test]
    #[available_gas(50000000)]
    fn test_insert_initialized_tick_next_initialized_tick() {
        let pool_key = fake_pool_key();

        let mut root_tick = Ekubo::insert_initialized_tick(
            pool_key, Option::None(()), i129 { mag: 1000, sign: true }
        );
        root_tick =
            Ekubo::insert_initialized_tick(pool_key, root_tick, i129 { mag: 1000, sign: false });

        assert(
            Ekubo::next_initialized_tick(pool_key, root_tick, i129 { mag: 1001, sign: true })
                .expect('-1001') == i129 {
                mag: 1000, sign: true
            },
            'next tick of -1001'
        );
        assert(
            Ekubo::next_initialized_tick(pool_key, root_tick, i129 { mag: 1000, sign: true })
                .expect('-1000') == i129 {
                mag: 1000, sign: false
            },
            'next tick of -1000'
        );
        assert(
            Ekubo::next_initialized_tick(pool_key, root_tick, i129 { mag: 999, sign: true })
                .expect('-999') == i129 {
                mag: 1000, sign: false
            },
            'next tick of -999'
        );
        assert(
            Ekubo::next_initialized_tick(pool_key, root_tick, i129 { mag: 1, sign: true })
                .expect('-1') == i129 {
                mag: 1000, sign: false
            },
            'next tick of -1'
        );
        assert(
            Ekubo::next_initialized_tick(pool_key, root_tick, i129 { mag: 0, sign: false })
                .expect('0') == i129 {
                mag: 1000, sign: false
            },
            'next tick of 0'
        );
        assert(
            Ekubo::next_initialized_tick(pool_key, root_tick, i129 { mag: 1, sign: false })
                .expect('1') == i129 {
                mag: 1000, sign: false
            },
            'next tick of 1'
        );
        assert(
            Ekubo::next_initialized_tick(pool_key, root_tick, i129 { mag: 999, sign: false })
                .expect('999') == i129 {
                mag: 1000, sign: false
            },
            'next tick of 999'
        );
        assert(
            Ekubo::next_initialized_tick(pool_key, root_tick, i129 { mag: 1000, sign: false })
                .is_none(),
            'next tick of 1000'
        );
        assert(
            Ekubo::next_initialized_tick(pool_key, root_tick, i129 { mag: 1001, sign: false })
                .is_none(),
            'next tick of 1001'
        );
    }

    #[test]
    #[available_gas(50000000)]
    fn test_insert_initialized_tick_prev_initialized_tick() {
        let pool_key = fake_pool_key();

        let mut root_tick = Ekubo::insert_initialized_tick(
            pool_key, Option::None(()), i129 { mag: 1000, sign: true }
        );
        Ekubo::insert_initialized_tick(pool_key, root_tick, i129 { mag: 1000, sign: false });

        assert(
            Ekubo::prev_initialized_tick(pool_key, root_tick, i129 { mag: 1001, sign: true })
                .is_none(),
            'prev tick of -1001'
        );
        assert(
            Ekubo::prev_initialized_tick(pool_key, root_tick, i129 { mag: 1000, sign: true })
                .expect('-1000') == i129 {
                mag: 1000, sign: true
            },
            'prev tick of -1000'
        );
        assert(
            Ekubo::prev_initialized_tick(pool_key, root_tick, i129 { mag: 999, sign: true })
                .expect('-999') == i129 {
                mag: 1000, sign: true
            },
            'prev tick of -999'
        );
        assert(
            Ekubo::prev_initialized_tick(pool_key, root_tick, i129 { mag: 1, sign: true })
                .expect('-1') == i129 {
                mag: 1000, sign: true
            },
            'prev tick of -1'
        );
        assert(
            Ekubo::prev_initialized_tick(pool_key, root_tick, i129 { mag: 0, sign: false })
                .expect('0') == i129 {
                mag: 1000, sign: true
            },
            'prev tick of 0'
        );
        assert(
            Ekubo::prev_initialized_tick(pool_key, root_tick, i129 { mag: 1, sign: false })
                .expect('1') == i129 {
                mag: 1000, sign: true
            },
            'prev tick of 1'
        );
        assert(
            Ekubo::prev_initialized_tick(pool_key, root_tick, i129 { mag: 999, sign: false })
                .expect('999') == i129 {
                mag: 1000, sign: true
            },
            'prev tick of 999'
        );
        assert(
            Ekubo::prev_initialized_tick(pool_key, root_tick, i129 { mag: 1000, sign: false })
                .expect('1000') == i129 {
                mag: 1000, sign: false
            },
            'prev tick of 1000'
        );
        assert(
            Ekubo::prev_initialized_tick(pool_key, root_tick, i129 { mag: 1001, sign: false })
                .expect('1000') == i129 {
                mag: 1000, sign: false
            },
            'prev tick of 1001'
        );
    }
}


mod locks {
    use debug::PrintTrait;

    use super::helper::{setup_pool, swap, update_position, SetupPoolResult};
    use ekubo::types::i129::{i129OptionPartialEq};
    use super::{
        contract_address_const, Action, ActionResult, ICoreLockerDispatcher,
        ICoreLockerDispatcherTrait, i129, UpdatePositionParameters, SwapParameters,
        IMockERC20Dispatcher, IMockERC20DispatcherTrait, min_sqrt_ratio, max_sqrt_ratio, min_tick,
        max_tick, IEkuboDispatcherTrait, ContractAddress, Delta
    };


    const FEE_ONE_PERCENT: u128 = 0x28f5c28f5c28f5c28f5c28f5c28f5c2;

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

        setup
            .token0
            .increase_balance(setup.locker.contract_address, u256 { low: 10000000, high: 0 });
        setup
            .token1
            .increase_balance(setup.locker.contract_address, u256 { low: 10000000, high: 0 });

        let delta = update_position(
            setup: setup,
            tick_lower: i129 { mag: 10, sign: true },
            tick_upper: i129 { mag: 10, sign: false },
            liquidity_delta: i129 { mag: 10000000, sign: false },
            recipient: contract_address_const::<42>()
        );

        assert(delta.amount0_delta == i129 { mag: 51, sign: false }, 'amount0_delta');
        assert(delta.amount1_delta == i129 { mag: 51, sign: false }, 'amount1_delta');
    }

    #[test]
    #[available_gas(500000000)]
    fn test_larger_amount_liquidity_add() {
        let setup = setup_pool(
            contract_address_const::<1>(), FEE_ONE_PERCENT, 1, Default::default()
        );

        setup
            .token0
            .increase_balance(setup.locker.contract_address, u256 { low: 10000000, high: 0 });
        setup
            .token1
            .increase_balance(setup.locker.contract_address, u256 { low: 10000000, high: 0 });

        let delta = update_position(
            setup,
            tick_lower: i129 { mag: 10, sign: true },
            tick_upper: i129 { mag: 10, sign: false },
            liquidity_delta: i129 { mag: 1000000000, sign: false },
            recipient: contract_address_const::<42>()
        );

        assert(delta.amount0_delta == i129 { mag: 5001, sign: false }, 'amount0_delta');
        assert(delta.amount1_delta == i129 { mag: 5001, sign: false }, 'amount1_delta');
    }

    #[test]
    #[available_gas(500000000)]
    fn test_full_range_liquidity_add() {
        let setup = setup_pool(
            contract_address_const::<1>(), FEE_ONE_PERCENT, 1, Default::default()
        );

        setup.token0.increase_balance(setup.locker.contract_address, u256 { low: 0, high: 1 });
        setup.token1.increase_balance(setup.locker.contract_address, u256 { low: 0, high: 1 });

        let delta = update_position(
            setup,
            tick_lower: min_tick(),
            tick_upper: max_tick(),
            liquidity_delta: i129 { mag: 1000000000, sign: false },
            recipient: contract_address_const::<42>()
        );

        assert(
            delta.amount0_delta == i129 { mag: 18446739710271796308434404910, sign: false },
            'amount0_delta'
        );
        assert(
            delta.amount1_delta == i129 { mag: 18446739710271796308434404910, sign: false },
            'amount1_delta'
        );
    }

    #[test]
    #[available_gas(500000000)]
    fn test_full_range_liquidity_add_and_half_burn() {
        let setup = setup_pool(
            contract_address_const::<1>(), FEE_ONE_PERCENT, 1, Default::default()
        );

        setup.token0.increase_balance(setup.locker.contract_address, u256 { low: 0, high: 1 });
        setup.token1.increase_balance(setup.locker.contract_address, u256 { low: 0, high: 1 });

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

        assert(
            delta.amount0_delta == i129 { mag: 9131136156584539172675030429, sign: true },
            'amount0_delta'
        );
        assert(
            delta.amount1_delta == i129 { mag: 9131136156584539172675030429, sign: true },
            'amount1_delta'
        );
    }

    #[test]
    #[available_gas(500000000)]
    fn test_full_range_liquidity_add_and_full_burn() {
        let setup = setup_pool(
            contract_address_const::<1>(), FEE_ONE_PERCENT, 1, Default::default()
        );

        setup.token0.increase_balance(setup.locker.contract_address, u256 { low: 0, high: 1 });
        setup.token1.increase_balance(setup.locker.contract_address, u256 { low: 0, high: 1 });

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

        assert(
            delta.amount0_delta == i129 { mag: 18262272313169078345350060859, sign: true },
            'amount0_delta'
        );
        assert(
            delta.amount1_delta == i129 { mag: 18262272313169078345350060859, sign: true },
            'amount1_delta'
        );
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
        assert(pool.root_tick == Option::None(()), 'root tick is none');
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
        assert(pool.root_tick == Option::None(()), 'root tick is none');
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
        assert(pool.root_tick == Option::None(()), 'root tick is none');
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

        setup
            .token0
            .increase_balance(setup.locker.contract_address, u256 { low: 10000000, high: 0 });
        setup
            .token1
            .increase_balance(setup.locker.contract_address, u256 { low: 10000000, high: 0 });

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
        assert(pool.root_tick == Option::Some(i129 { mag: 10, sign: true }), 'root tick is 10');
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

        setup
            .token0
            .increase_balance(setup.locker.contract_address, u256 { low: 10000000, high: 0 });
        setup
            .token1
            .increase_balance(setup.locker.contract_address, u256 { low: 10000000, high: 0 });

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
        assert(pool.root_tick == Option::Some(i129 { mag: 10, sign: true }), 'root tick is 10');
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

        setup
            .token0
            .increase_balance(setup.locker.contract_address, u256 { low: 10000000, high: 0 });
        setup
            .token1
            .increase_balance(setup.locker.contract_address, u256 { low: 10000000, high: 0 });

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
        assert(pool.root_tick == Option::Some(i129 { mag: 10, sign: true }), 'root tick is 10');
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

        setup
            .token0
            .increase_balance(setup.locker.contract_address, u256 { low: 10000000, high: 0 });
        setup
            .token1
            .increase_balance(setup.locker.contract_address, u256 { low: 10000000, high: 0 });

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

        assert(delta.amount0_delta == i129 { mag: 49, sign: true }, 'amount1_delta');
        assert(delta.amount1_delta == i129 { mag: 51, sign: false }, 'amount0_delta');

        let pool = setup.core.get_pool(setup.pool_key);
        assert(pool.sqrt_ratio == max_sqrt_ratio(), 'ratio after');
        assert(pool.root_tick == Option::Some(i129 { mag: 10, sign: true }), 'root tick is 10');
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
