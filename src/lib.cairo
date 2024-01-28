mod core;
mod mock_erc20;
mod owned_nft;
mod positions;
mod router;
mod token_registry;

mod components {
    mod clear;
    mod owned;
    mod shared_locker;
    mod upgradeable;
    mod util;
}

mod extensions {}

mod interfaces {
    mod core;
    mod erc20;
    mod erc721;
    mod positions;
    mod src5;
    mod upgradeable;
}

mod math {
    mod bitmap;
    #[cfg(test)]
    mod bitmap_test;
    mod bits;
    #[cfg(test)]
    mod bits_test;
    mod delta;
    #[cfg(test)]
    mod delta_test;
    mod exp2;
    #[cfg(test)]
    mod exp2_test;
    mod fee;
    #[cfg(test)]
    mod fee_test;
    mod liquidity;
    #[cfg(test)]
    mod liquidity_test;
    mod mask;
    #[cfg(test)]
    mod mask_test;
    mod max_liquidity;
    #[cfg(test)]
    mod max_liquidity_test;
    mod muldiv;
    #[cfg(test)]
    mod muldiv_test;
    mod sqrt_ratio;
    #[cfg(test)]
    mod sqrt_ratio_test;
    mod string;
    #[cfg(test)]
    mod string_test;
    mod swap;
    #[cfg(test)]
    mod swap_test;
    mod ticks;
    #[cfg(test)]
    mod ticks_test;
}

#[cfg(test)]
pub(crate) mod tests {
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

mod types {
    mod bounds;
    #[cfg(test)]
    pub(crate) mod bounds_test;
    mod call_points;
    #[cfg(test)]
    pub(crate) mod call_points_test;
    mod delta;
    #[cfg(test)]
    pub(crate) mod delta_test;
    mod fees_per_liquidity;
    #[cfg(test)]
    pub(crate) mod fees_per_liquidity_test;
    mod i129;
    #[cfg(test)]
    pub(crate) mod i129_test;
    mod keys;
    #[cfg(test)]
    pub(crate) mod keys_test;
    mod pool_price;
    #[cfg(test)]
    pub(crate) mod pool_price_test;
    mod position;
    #[cfg(test)]
    pub(crate) mod position_test;
}

