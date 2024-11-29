pub mod core;
pub mod limit_orders;
pub mod mock_erc20;
pub mod oracle;
pub mod owned_nft;
pub mod positions;
pub mod price_fetcher;
pub mod router;
pub mod token_registry;
pub mod twamm;

pub mod components {
    pub mod clear;
    pub mod expires;
    pub mod owned;
    pub mod shared_locker;
    pub mod upgradeable;
    pub mod util;
}

pub mod interfaces {
    pub mod core;
    pub mod erc20;
    pub mod erc721;
    pub mod positions;
    pub mod src5;
    pub mod upgradeable;
    pub mod extensions {
        pub mod limit_orders;
        pub mod twamm;
    }
}

pub mod math {
    pub mod bitmap;
    pub mod bits;
    pub mod delta;
    pub mod exp;
    pub mod exp2;
    pub mod fee;
    pub mod liquidity;
    pub mod mask;
    pub mod max_liquidity;
    pub mod muldiv;
    pub mod sqrt_ratio;
    pub mod string;
    pub mod swap;
    pub mod ticks;
    pub mod time;
    pub mod twamm;
}

#[cfg(test)]
pub(crate) mod tests {
    pub(crate) mod clear_test;
    pub(crate) mod core_test;
    pub(crate) mod extensions_test;
    pub(crate) mod helper;
    pub(crate) mod mock_erc20_test;
    pub(crate) mod owned_nft_test;
    pub(crate) mod positions_test;
    pub(crate) mod router_test;
    pub(crate) mod store_packing_test;
    pub(crate) mod token_registry_test;
    pub(crate) mod upgradeable_test;

    pub(crate) mod mocks {
        pub(crate) mod locker;
        pub(crate) mod mock_extension;
        pub(crate) mod mock_upgradeable;
    }

    pub(crate) mod math {
        pub(crate) mod bitmap_test;
        pub(crate) mod bits_test;
        pub(crate) mod delta_test;
        pub(crate) mod exp2_test;
        pub(crate) mod exp_test;
        pub(crate) mod fee_test;
        pub(crate) mod liquidity_test;
        pub(crate) mod mask_test;
        pub(crate) mod max_liquidity_test;
        pub(crate) mod muldiv_test;
        pub(crate) mod sqrt_ratio_test;
        pub(crate) mod string_test;
        pub(crate) mod swap_test;
        pub(crate) mod ticks_test;
        pub(crate) mod time_test;
    }

    pub(crate) mod types {
        pub(crate) mod bounds_test;
        pub(crate) mod call_points_test;
        pub(crate) mod delta_test;
        pub(crate) mod fees_per_liquidity_test;
        pub(crate) mod i129_test;
        pub(crate) mod keys_test;
        pub(crate) mod pool_price_test;
        pub(crate) mod position_test;
        pub(crate) mod snapshot_test;
    }
}

pub mod types {
    pub mod bounds;
    pub mod call_points;
    pub mod delta;
    pub mod fees_per_liquidity;
    pub mod i129;
    pub mod keys;
    pub mod pool_price;
    pub mod position;
    pub mod snapshot;
}

