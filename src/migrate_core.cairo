#[starknet::interface]
pub trait IMigrate<TContractState> {
    fn migrate(ref self: TContractState);
}

// A migration contract for fixing core's state irregularity on mainnet
#[starknet::contract]
mod Migrate {
    use core::array::{ArrayTrait};
    use core::num::traits::{Zero};
    use core::option::{Option};
    use ekubo::components::owned::{Owned as owned_component};
    use ekubo::components::upgradeable::{Upgradeable as upgradeable_component, IHasInterface};
    use ekubo::interfaces::core::{SwapParameters};
    use ekubo::math::ticks::{min_sqrt_ratio};
    use ekubo::types::fees_per_liquidity::{FeesPerLiquidity};
    use ekubo::types::i129::{i129};
    use ekubo::types::keys::{PoolKey};
    use ekubo::types::pool_price::{PoolPrice};
    use starknet::storage::{StorageMapWriteAccess, StoragePathEntry, StorageMapReadAccess, Map};
    use starknet::{contract_address_const};

    component!(path: owned_component, storage: owned, event: OwnedEvent);
    #[abi(embed_v0)]
    impl Owned = owned_component::OwnedImpl<ContractState>;
    impl Ownable = owned_component::OwnableImpl<ContractState>;

    component!(path: upgradeable_component, storage: upgradeable, event: UpgradeableEvent);
    #[abi(embed_v0)]
    impl Upgradeable = upgradeable_component::UpgradeableImpl<ContractState>;

    #[storage]
    pub struct Storage {
        pub pool_fees: Map<PoolKey, FeesPerLiquidity>,
        pub pool_price: Map<PoolKey, PoolPrice>,
        pub pool_liquidity: Map<PoolKey, u128>,
        pub tick_fees_outside: Map<PoolKey, Map<i129, FeesPerLiquidity>>,
        #[substorage(v0)]
        upgradeable: upgradeable_component::Storage,
        #[substorage(v0)]
        owned: owned_component::Storage,
    }

    #[derive(starknet::Event, Drop)]
    #[event]
    enum Event {
        #[flat]
        UpgradeableEvent: upgradeable_component::Event,
        OwnedEvent: owned_component::Event,
        Swapped: ekubo::core::Core::Swapped,
    }

    #[abi(embed_v0)]
    impl CoreHasInterface of IHasInterface<ContractState> {
        fn get_primary_interface_id(self: @ContractState) -> felt252 {
            return selector!("ekubo::core::Core");
        }
    }

    #[generate_trait]
    impl FixPools of FixPool1Trait {
        fn fix_wbtc_usdt_pool(ref self: ContractState) {
            let pool_key = PoolKey {
                token0: contract_address_const::<
                    0x3fe2b97c1fd336e750087d68b9b867997fd64a2661ff3ca5a7c771641e8e7ac
                >(),
                token1: contract_address_const::<
                    0x68f5c6a61780768455de69077e07e89787839bf8166decfbf92b645209c0fb8
                >(),
                fee: 1020847100762815411640772995208708096,
                tick_spacing: 5982,
                extension: contract_address_const::<0>(),
            };
            // subtract the liquidity_delta that was on the errant tick when it was crossed in
            // direction of decreasing price (thus became active)
            let liquidity_next = self.pool_liquidity.read(pool_key) - 11780001;
            self.pool_liquidity.write(pool_key, liquidity_next);

            // un-cross the tick
            self
                .tick_fees_outside
                .entry(pool_key)
                .write(
                    i129 { mag: 5730756, sign: false },
                    // starkli call --network mainnet --block 808014
                    // 0x00000005dd3D2F4429AF886cD1a3b08289DBcEa99A294197E9eB43b0e0325b4b
                    // get_pool_tick_fees_outside
                    // 0x3fe2b97c1fd336e750087d68b9b867997fd64a2661ff3ca5a7c771641e8e7ac
                    // 0x68f5c6a61780768455de69077e07e89787839bf8166decfbf92b645209c0fb8
                    // 1020847100762815411640772995208708096 5982 0 5730756 0
                    FeesPerLiquidity {
                        value0: 0x000000000000000000000000000000000003b70d4f1d70b2cf25499090e32987,
                        value1: 0x0000000000000000000000000000000004c744961f92ecd6e301fb440763da77
                    }
                );

            // emit an event containing a no-op swap so the indexer knows the liquidity of the pool
            // was changed
            let PoolPrice { sqrt_ratio, tick } = self.pool_price.read(pool_key);
            self
                .emit(
                    ekubo::core::Core::Swapped {
                        locker: Zero::zero(),
                        pool_key,
                        params: SwapParameters {
                            amount: Zero::zero(),
                            is_token1: false,
                            sqrt_ratio_limit: min_sqrt_ratio(),
                            skip_ahead: 0,
                        },
                        delta: Zero::zero(),
                        sqrt_ratio_after: sqrt_ratio,
                        tick_after: tick,
                        liquidity_after: liquidity_next
                    }
                );
        }

        fn fix_wbtc_strk_pool(ref self: ContractState) {
            let pool_key = PoolKey {
                token0: contract_address_const::<
                    0x3fe2b97c1fd336e750087d68b9b867997fd64a2661ff3ca5a7c771641e8e7ac
                >(),
                token1: contract_address_const::<
                    0x4718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d
                >(),
                fee: 3402823669209384634633746074317682114,
                tick_spacing: 19802,
                extension: contract_address_const::<0>(),
            };
            // subtract the liquidity_delta that was on the errant tick when it was crossed in
            // direction of decreasing price (thus became active)
            let liquidity_next = self.pool_liquidity.read(pool_key) - 20088269826;
            self.pool_liquidity.write(pool_key, liquidity_next);

            // un-cross the tick
            self
                .tick_fees_outside
                .entry(pool_key)
                .write(
                    i129 { mag: 33643598, sign: false },
                    // starkli call --network mainnet --block 794908
                    // 0x00000005dd3D2F4429AF886cD1a3b08289DBcEa99A294197E9eB43b0e0325b4b
                    // get_pool_tick_fees_outside
                    // 0x3fe2b97c1fd336e750087d68b9b867997fd64a2661ff3ca5a7c771641e8e7ac
                    // 0x4718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d
                    // 3402823669209384634633746074317682114 19802 0 33643598 0
                    FeesPerLiquidity {
                        value0: 0x00000000000000000000000000000000000000059a4782abf68bca93ec12d6e3,
                        value1: 0x0000000000000000000000000005ac4ab454ab16e8db8177aab2d24832859efa
                    }
                );

            // emit an event containing a no-op swap so the indexer knows the liquidity of the pool
            // was changed
            let PoolPrice { sqrt_ratio, tick } = self.pool_price.read(pool_key);
            self
                .emit(
                    ekubo::core::Core::Swapped {
                        locker: Zero::zero(),
                        pool_key,
                        params: SwapParameters {
                            amount: Zero::zero(),
                            is_token1: false,
                            sqrt_ratio_limit: min_sqrt_ratio(),
                            skip_ahead: 0,
                        },
                        delta: Zero::zero(),
                        sqrt_ratio_after: sqrt_ratio,
                        tick_after: tick,
                        liquidity_after: liquidity_next
                    }
                );
        }
    }

    #[abi(embed_v0)]
    impl MigrateImpl of super::IMigrate<ContractState> {
        fn migrate(ref self: ContractState) {
            self.require_owner();

            self.fix_wbtc_usdt_pool();
            self.fix_wbtc_strk_pool();
        }
    }
}
