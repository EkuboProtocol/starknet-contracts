use starknet::{
    ContractAddress, contract_address_const, get_caller_address, get_contract_address,
    StorageAccess, StorageBaseAddress, SyscallResult, storage_read_syscall, storage_write_syscall,
    storage_address_from_base_and_offset
};
use ekubo::types::i129::{i129, i129IntoFelt252};
use ekubo::math::ticks::{tick_to_sqrt_ratio};
use array::{ArrayTrait};
use ekubo::interfaces::core::{IEkuboDispatcher, UpdatePositionParameters, IEkuboDispatcherTrait};
use ekubo::types::keys::{PoolKey};
use core::hash::LegacyHash;
use traits::{Into, TryInto};
use option::{Option, OptionTrait};
use ekubo::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
use ekubo::math::liquidity::{max_liquidity};
use ekubo::interfaces::positions::{Bounds, TokenInfo};
use serde::Serde;


// Compute the hash for a given position key
fn hash_key(pool_key: PoolKey, bounds: Bounds) -> felt252 {
    LegacyHash::hash(pedersen(bounds.tick_lower.into(), bounds.tick_upper.into()), pool_key)
}

impl TokenInfoStorageAccess of StorageAccess<TokenInfo> {
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<TokenInfo> {
        let key_hash: felt252 = storage_read_syscall(
            address_domain, storage_address_from_base_and_offset(base, 0_u8)
        )?;
        let liquidity: u128 = storage_read_syscall(
            address_domain, storage_address_from_base_and_offset(base, 1_u8)
        )?
            .try_into()
            .expect('LIQUIDITY');
        let fee_growth_inside_last_token0: u256 = u256 {
            low: storage_read_syscall(
                address_domain, storage_address_from_base_and_offset(base, 2_u8)
            )?
                .try_into()
                .expect('FGILT0L'),
            high: storage_read_syscall(
                address_domain, storage_address_from_base_and_offset(base, 3_u8)
            )?
                .try_into()
                .expect('FGILT0H')
        };
        let fee_growth_inside_last_token1: u256 = u256 {
            low: storage_read_syscall(
                address_domain, storage_address_from_base_and_offset(base, 4_u8)
            )?
                .try_into()
                .expect('FGILT1L'),
            high: storage_read_syscall(
                address_domain, storage_address_from_base_and_offset(base, 5_u8)
            )?
                .try_into()
                .expect('FGILT1H')
        };

        let fees_token0: u128 = storage_read_syscall(
            address_domain, storage_address_from_base_and_offset(base, 6_u8)
        )?
            .try_into()
            .expect('FT0');
        let fees_token1: u128 = storage_read_syscall(
            address_domain, storage_address_from_base_and_offset(base, 7_u8)
        )?
            .try_into()
            .expect('FT1');

        SyscallResult::Ok(
            TokenInfo {
                key_hash,
                liquidity,
                fee_growth_inside_last_token0,
                fee_growth_inside_last_token1,
                fees_token0,
                fees_token1
            }
        )
    }
    fn write(address_domain: u32, base: StorageBaseAddress, value: TokenInfo) -> SyscallResult<()> {
        storage_write_syscall(
            address_domain, storage_address_from_base_and_offset(base, 0_u8), value.key_hash
        )?;
        storage_write_syscall(
            address_domain, storage_address_from_base_and_offset(base, 1_u8), value.liquidity.into()
        )?;
        storage_write_syscall(
            address_domain,
            storage_address_from_base_and_offset(base, 2_u8),
            value.fee_growth_inside_last_token0.low.into()
        )?;
        storage_write_syscall(
            address_domain,
            storage_address_from_base_and_offset(base, 3_u8),
            value.fee_growth_inside_last_token0.high.into()
        )?;
        storage_write_syscall(
            address_domain,
            storage_address_from_base_and_offset(base, 4_u8),
            value.fee_growth_inside_last_token1.low.into()
        )?;
        storage_write_syscall(
            address_domain,
            storage_address_from_base_and_offset(base, 5_u8),
            value.fee_growth_inside_last_token1.high.into()
        )?;
        storage_write_syscall(
            address_domain,
            storage_address_from_base_and_offset(base, 6_u8),
            value.fees_token0.into()
        )?;
        storage_write_syscall(
            address_domain,
            storage_address_from_base_and_offset(base, 7_u8),
            value.fees_token0.into()
        )?;
        SyscallResult::Ok(())
    }
}


#[contract]
mod Positions {
    use super::{
        ContractAddress, get_caller_address, i129, contract_address_const, ArrayTrait,
        IEkuboDispatcher, IEkuboDispatcherTrait, PoolKey, Bounds, TokenInfo, hash_key,
        IERC20Dispatcher, IERC20DispatcherTrait, get_contract_address, Serde, Option, OptionTrait,
        TokenInfoStorageAccess, max_liquidity, tick_to_sqrt_ratio, UpdatePositionParameters
    };

    struct Storage {
        core: ContractAddress,
        next_token_id: u128,
        approvals: LegacyMap<u128, ContractAddress>,
        owners: LegacyMap<u128, ContractAddress>,
        balances: LegacyMap<ContractAddress, u128>,
        operators: LegacyMap<(ContractAddress, ContractAddress), bool>,
        token_info: LegacyMap<u128, TokenInfo>,
    }

    #[event]
    fn Transfer(from: ContractAddress, to: ContractAddress, token_id: u256) {}

    #[event]
    fn Approval(owner: ContractAddress, approved: ContractAddress, token_id: u256) {}

    #[event]
    fn ApprovalForAll(owner: ContractAddress, operator: ContractAddress, approved: bool) {}

    #[constructor]
    fn constructor(_core: ContractAddress) {
        core::write(_core);
        next_token_id::write(1);
    }

    #[view]
    fn name() -> felt252 {
        'Ekubo Position NFT'
    }

    #[view]
    fn symbol() -> felt252 {
        'EpNFT'
    }

    #[external]
    fn approve(to: ContractAddress, token_id: u256) {
        let caller = get_caller_address();
        assert(caller == owner_of(token_id), 'OWNER');
        approvals::write(token_id.low, to);
        Approval(caller, to, token_id);
    }

    #[view]
    fn balance_of(account: ContractAddress) -> u256 {
        u256 { low: balances::read(account), high: 0 }
    }

    #[view]
    fn owner_of(token_id: u256) -> ContractAddress {
        assert(token_id.high == 0, 'INVALID_ID');
        owners::read(token_id.low)
    }

    #[internal]
    fn validate_token_id(token_id: u256) {
        assert(token_id.high == 0, 'INVALID_ID');
    }

    #[internal]
    fn check_is_caller_authorized(owner: ContractAddress, token_id: u128) {
        let caller = get_caller_address();
        if (caller != owner) {
            let approved = approvals::read(token_id);
            if (caller != approved) {
                let operator = operators::read((owner, caller));
                assert(operator, 'UNAUTHORIZED');
            }
        }
    }

    #[internal]
    fn transfer(from: ContractAddress, to: ContractAddress, token_id: u256) {
        validate_token_id(token_id);

        let owner = owners::read(token_id.low);
        assert(owner == from, 'OWNER');

        check_is_caller_authorized(owner, token_id.low);

        owners::write(token_id.low, to);
        approvals::write(token_id.low, contract_address_const::<0>());
        balances::write(from, balances::read(from) - 1);
        balances::write(to, balances::read(to) + 1);
        Transfer(from, to, token_id);
    }

    #[external]
    fn transfer_from(from: ContractAddress, to: ContractAddress, token_id: u256) {
        transfer(from, to, token_id);
    }

    // #[external]
    // fn safe_transfer_from(
    //     from: ContractAddress, to: ContractAddress, token_id: u256, data: Span<felt252>
    // ) {
    //     transfer(from, to, token_id);
    //     assert(false, 'todo');
    // }

    #[external]
    fn set_approval_for_all(operator: ContractAddress, approved: bool) {
        let owner = get_caller_address();
        operators::write((owner, operator), approved);
        ApprovalForAll(owner, operator, approved);
    }

    #[view]
    fn get_approved(token_id: u256) -> ContractAddress {
        approvals::read(token_id.low)
    }

    #[view]
    fn is_approved_for_all(owner: ContractAddress, operator: ContractAddress) -> bool {
        operators::read((owner, operator))
    }

    #[view]
    fn token_uri(token_id: u256) -> felt252 {
        'https://nft.ekubo.org/'
    }

    // Creates the NFT and returns the token ID. Does not add any liquidity.
    #[external]
    fn mint(recipient: ContractAddress, pool_key: PoolKey, bounds: Bounds) -> u128 {
        let id = next_token_id::read();
        next_token_id::write(id + 1);

        // effect the mint by updating storage
        owners::write(id, recipient);
        balances::write(recipient, balances::read(recipient) + 1);
        token_info::write(
            id,
            TokenInfo {
                key_hash: hash_key(pool_key, bounds),
                liquidity: Default::default(),
                fee_growth_inside_last_token0: Default::default(),
                fee_growth_inside_last_token1: Default::default(),
                fees_token0: Default::default(),
                fees_token1: Default::default(),
            }
        );

        Transfer(contract_address_const::<0>(), recipient, u256 { low: id, high: 0 });

        id
    }

    #[internal]
    fn get_token_info(token_id: u128, pool_key: PoolKey, bounds: Bounds) -> TokenInfo {
        let info = token_info::read(token_id);
        assert(info.key_hash == hash_key(pool_key, bounds), 'POSITION_KEY');
        info
    }

    #[derive(Serde, Copy, Drop)]
    struct DepositCallbackData {
        pool_key: PoolKey,
        bounds: Bounds,
        liquidity: u128
    }
    #[derive(Serde, Copy, Drop)]
    struct WithdrawCallbackData {
        bounds: Bounds,
        min_token0: u128,
        min_token1: u128
    }
    #[derive(Serde, Copy, Drop)]
    enum LockCallbackData {
        Deposit: DepositCallbackData,
        Withdraw: WithdrawCallbackData
    }

    #[derive(Serde, Copy, Drop)]
    struct WithdrawCallbackResult {
        token0_amount: u128,
        token1_amount: u128
    }
    #[derive(Serde, Copy, Drop)]
    enum LockCallbackResult {
        Deposit: (),
        Withdraw: WithdrawCallbackResult
    }

    // Initializes a pool only if it's not already initialized
    // This is useful as part of a batch of operations, to avoid failing the entire batch because the pool was already initialized
    #[external]
    fn maybe_initialize_pool(pool_key: PoolKey, initial_tick: i129) {
        let core_dispatcher = IEkuboDispatcher { contract_address: core::read() };
        let pool = core_dispatcher.get_pool(pool_key);
        if (pool.sqrt_ratio == Default::default()) {
            core_dispatcher.initialize_pool(pool_key, initial_tick);
        }
    }

    #[external]
    fn deposit_last(pool_key: PoolKey, bounds: Bounds, min_liquidity: u128) -> u128 {
        deposit(u256 { low: next_token_id::read() - 1, high: 0 }, pool_key, bounds, min_liquidity)
    }

    #[internal]
    fn balance_of_token(token: ContractAddress) -> u128 {
        let balance = IERC20Dispatcher {
            contract_address: token
        }.balance_of(get_contract_address());
        assert(balance.high == 0, 'BALANCE_OVERFLOW');
        balance.low
    }

    // Deposits the tokens held by this contract for the given token ID, using the balances transiently held by this contract
    #[external]
    fn deposit(token_id: u256, pool_key: PoolKey, bounds: Bounds, min_liquidity: u128) -> u128 {
        validate_token_id(token_id);
        check_is_caller_authorized(owners::read(token_id.low), token_id.low);

        let info = get_token_info(token_id.low, pool_key, bounds);

        let pool = IEkuboDispatcher { contract_address: core::read() }.get_pool(pool_key);

        // todo: compute the fees owed to this position before touching the pool, add it to the position

        let liquidity = max_liquidity(
            pool.sqrt_ratio,
            tick_to_sqrt_ratio(bounds.tick_lower),
            tick_to_sqrt_ratio(bounds.tick_upper),
            balance_of_token(pool_key.token0),
            balance_of_token(pool_key.token1)
        );

        assert(liquidity >= min_liquidity, 'MIN_LIQUIDITY');

        let mut data: Array<felt252> = ArrayTrait::new();
        // make the deposit to the pool
        Serde::<LockCallbackData>::serialize(
            @LockCallbackData::Deposit(DepositCallbackData { pool_key, bounds, liquidity }),
            ref data
        );

        let mut result = IEkuboDispatcher { contract_address: core::read() }.lock(data).span();

        match Serde::<LockCallbackResult>::deserialize(ref result)
            .expect('CALLBACK_RESULT_DESERIALIZE') {
            LockCallbackResult::Deposit(_) => {},
            LockCallbackResult::Withdraw(_) => {
                assert(false, 'INVALID_DEPOSIT_RESULT');
            }
        };

        liquidity
    }

    #[external]
    fn withdraw(
        token_id: u256,
        pool_key: PoolKey,
        bounds: Bounds,
        liquidity: u128,
        min_token0: u128,
        min_token1: u128
    ) -> (u128, u128) {
        validate_token_id(token_id);
        check_is_caller_authorized(owners::read(token_id.low), token_id.low);

        let info = get_token_info(token_id.low, pool_key, bounds);

        let mut data: Array<felt252> = ArrayTrait::new();
        // make the deposit to the pool
        Serde::<LockCallbackData>::serialize(
            @LockCallbackData::Withdraw(WithdrawCallbackData { bounds, min_token0, min_token1 }),
            ref data
        );

        let mut result = IEkuboDispatcher { contract_address: core::read() }.lock(data).span();

        let (token0_amount, token1_amount) =
            match Serde::<LockCallbackResult>::deserialize(ref result)
                .expect('CALLBACK_RESULT_DESERIALIZE') {
            LockCallbackResult::Deposit(_) => {
                assert(false, 'INVALID_WITHDRAW_RESULT');
                (Default::<u128>::default(), Default::<u128>::default())
            },
            LockCallbackResult::Withdraw(result) => {
                assert(false, 'TODO');
                (Default::<u128>::default(), Default::<u128>::default())
            }
        };
        // todo: update the position info here

        (token0_amount, token1_amount)
    }

    // This contract only holds tokens for the duration of a transaction.
    #[external]
    fn clear(token: ContractAddress, recipient: ContractAddress) {
        let dispatcher = IERC20Dispatcher { contract_address: token };
        let balance = dispatcher.balance_of(get_contract_address());
        if (balance != u256 { low: 0, high: 0 }) {
            dispatcher.transfer(recipient, balance);
        }
    }

    use debug::PrintTrait;

    #[external]
    fn locked(id: felt252, data: Array<felt252>) -> Array<felt252> {
        let caller = get_caller_address();
        assert(caller == core::read(), 'CORE');

        let mut data_span = data.span();
        let result: LockCallbackResult =
            match Serde::<LockCallbackData>::deserialize(ref data_span)
                .expect('DESERIALIZE_CALLBACK_FAILED') {
            LockCallbackData::Deposit(deposit) => {
                let delta = IEkuboDispatcher {
                    contract_address: caller
                }
                    .update_position(
                        deposit.pool_key,
                        UpdatePositionParameters {
                            tick_lower: deposit.bounds.tick_lower,
                            tick_upper: deposit.bounds.tick_upper,
                            liquidity_delta: i129 {
                                mag: deposit.liquidity, sign: false
                            }
                        }
                    );

                if delta.amount0_delta.mag != 0 {
                    IERC20Dispatcher {
                        contract_address: deposit.pool_key.token0
                    }.transfer(caller, u256 { low: delta.amount0_delta.mag, high: 0 });
                    IEkuboDispatcher { contract_address: caller }.deposit(deposit.pool_key.token0);
                }
                if (delta.amount1_delta.mag != 0) {
                    IERC20Dispatcher {
                        contract_address: deposit.pool_key.token1
                    }.transfer(caller, u256 { low: delta.amount1_delta.mag, high: 0 });
                    IEkuboDispatcher { contract_address: caller }.deposit(deposit.pool_key.token1);
                }

                LockCallbackResult::Deposit(())
            },
            LockCallbackData::Withdraw(withdraw) => {
                LockCallbackResult::Withdraw(
                    WithdrawCallbackResult {
                        token0_amount: Default::default(), token1_amount: Default::default()
                    }
                )
            }
        };

        let mut result_data: Array<felt252> = ArrayTrait::new();
        Serde::<LockCallbackResult>::serialize(@result, ref result_data);
        result_data
    }
}
