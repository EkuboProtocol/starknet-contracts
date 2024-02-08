pub mod core;
pub mod mock_erc20;
pub mod owned_nft;
pub mod positions;
pub mod router;
pub mod token_registry;

pub mod components {
    pub mod clear;
    pub mod owned;
    pub mod shared_locker;
    pub mod upgradeable;
    pub mod util;
}

pub mod extensions {
    pub mod twamm;
}

pub mod interfaces {
    pub mod core;
    pub mod erc20;
    pub mod erc721;
    pub mod positions;
    pub mod src5;
    pub mod upgradeable;
}

pub mod math {
    pub mod bitmap;
    #[cfg(test)]
    mod bitmap_test;
    pub mod bits;
    #[cfg(test)]
    mod bits_test;
    pub mod delta;
    #[cfg(test)]
    mod delta_test;
    pub mod exp2;
    #[cfg(test)]
    mod exp2_test;
    pub mod fee;
    #[cfg(test)]
    mod fee_test;
    pub mod liquidity;
    #[cfg(test)]
    mod liquidity_test;
    pub mod mask;
    #[cfg(test)]
    mod mask_test;
    pub mod max_liquidity;
    #[cfg(test)]
    mod max_liquidity_test;
    pub mod muldiv;
    #[cfg(test)]
    mod muldiv_test;
    pub mod sqrt_ratio;
    #[cfg(test)]
    mod sqrt_ratio_test;
    pub mod string;
    #[cfg(test)]
    mod string_test;
    pub mod swap;
    #[cfg(test)]
    mod swap_test;
    pub mod ticks;
    #[cfg(test)]
    mod ticks_test;
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
}

pub mod types {
    pub mod bounds;
    #[cfg(test)]
    pub(crate) mod bounds_test;
    pub mod call_points;
    #[cfg(test)]
    pub(crate) mod call_points_test;
    pub mod delta;
    #[cfg(test)]
    pub(crate) mod delta_test;
    pub mod fees_per_liquidity;
    #[cfg(test)]
    pub(crate) mod fees_per_liquidity_test;
    pub mod i129;
    #[cfg(test)]
    pub(crate) mod i129_test;
    pub mod keys;
    #[cfg(test)]
    pub(crate) mod keys_test;
    pub mod pool_price;
    #[cfg(test)]
    pub(crate) mod pool_price_test;
    pub mod position;
    #[cfg(test)]
    pub(crate) mod position_test;
}

