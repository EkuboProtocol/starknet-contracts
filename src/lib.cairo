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

mod extensions {
    mod limit_orders;
    #[cfg(test)]
    mod limit_orders_test;
}

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
mod tests {
    mod core_test;
    mod extensions_test;
    mod helper;
    mod mock_erc20_test;
    mod owned_nft_test;
    mod positions_test;
    mod router_test;
    mod store_packing_test;
    mod token_registry_test;
    mod upgradeable_test;

    mod mocks {
        mod locker;
        mod mock_extension;
        mod mock_upgradeable;
    }
}

mod types {
    mod bounds;
    #[cfg(test)]
    mod bounds_test;
    mod call_points;
    #[cfg(test)]
    mod call_points_test;
    mod delta;
    #[cfg(test)]
    mod delta_test;
    mod fees_per_liquidity;
    #[cfg(test)]
    mod fees_per_liquidity_test;
    mod i129;
    #[cfg(test)]
    mod i129_test;
    mod keys;
    #[cfg(test)]
    mod keys_test;
    mod pool_price;
    #[cfg(test)]
    mod pool_price_test;
    mod position;
    #[cfg(test)]
    mod position_test;
}

