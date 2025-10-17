// NOTE: These tests require mainnet forking with snforge_std and are not compatible with the
// standard cairo-test runner. They have been commented out to allow the codebase to compile.
// To run these tests, use: snforge test --fork-url <mainnet_rpc_url>

// use core::serde::Serde;
// use crate::revenue_buybacks::{
//     Config, IRevenueBuybacksDispatcher, IRevenueBuybacksDispatcherTrait,
// };
// use snforge_std::{
//     CheatSpan, ContractClassTrait, DeclareResultTrait, cheat_caller_address, declare,
//     start_cheat_block_timestamp_global, stop_cheat_caller_address,
// };
// use starknet::{ContractAddress, contract_address_const, get_block_timestamp};
// use crate::components::owned::{IOwnedDispatcher, IOwnedDispatcherTrait};
// use crate::interfaces::core::{ICoreDispatcher, ICoreDispatcherTrait};
// use crate::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
// use crate::interfaces::erc721::{IERC721Dispatcher, IERC721DispatcherTrait};
// use crate::interfaces::extensions::twamm::OrderKey;
// use crate::interfaces::positions::{IPositionsDispatcher, IPositionsDispatcherTrait};
// use crate::interfaces::router::IRouterDispatcher;
// use crate::tests::helper::{Deployer, DeployerTrait};


// fn example_config() -> Config {
//     Config {
//         buy_token: ekubo_token().contract_address,
//         min_delay: 0,
//         max_delay: 43200,
//         // 30 seconds
//         min_duration: 30,
//         // 7 days
//         max_duration: 604800,
//         // 30 bips
//         fee: 1020847100762815411640772995208708096,
//     }
// }

// // Deploys the revenue buybacks with the specified config or a default config and makes it the owner
// // of ekubo core
// fn setup(default_config: Option<Config>) -> IRevenueBuybacksDispatcher {
//     let mut d: Deployer = Default::default();
//     let core = d.deploy_core();
//     let rb = deploy_revenue_buybacks(default_config);
//     cheat_caller_address(core.contract_address, governor_address(), CheatSpan::Indefinite);
//     IOwnedDispatcher { contract_address: core.contract_address }
//         .transfer_ownership(rb.contract_address);
//     stop_cheat_caller_address(core.contract_address);
//     rb
// }

// fn advance_time(by: u64) -> u64 {
//     let time = get_block_timestamp();
//     let next = time + by;
//     start_cheat_block_timestamp_global(next);
//     next
// }

// #[test]
// #[fork("mainnet")]
// fn test_setup() {
//     let rb = setup(default_config: Option::Some(example_config()));
//     assert_eq!(
//         IOwnedDispatcher { contract_address: rb.contract_address }.get_owner(), governor_address(),
//     );
//     assert_eq!(
//         IOwnedDispatcher { contract_address: ekubo_core().contract_address }.get_owner(),
//         rb.contract_address,
//     );
//     assert_eq!(rb.get_core(), ekubo_core().contract_address);
//     assert_eq!(rb.get_positions(), positions().contract_address);
//     // the owner of the minted positions token is the revenue buybacks contract
//     assert_eq!(
//         IERC721Dispatcher {
//             contract_address: IPositionsDispatcher { contract_address: rb.get_positions() }
//                 .get_nft_address(),
//         }
//             .owner_of(rb.get_token_id().into()),
//         rb.contract_address,
//     );
//     // default config, so any address will do
//     assert_eq!(rb.get_config(sell_token: contract_address_const::<0xdeadbeef>()), example_config());
// }

// #[test]
// #[fork("mainnet")]
// fn test_eth_buybacks() {
//     let rb = setup(default_config: Option::Some(example_config()));
//     let start_time = (get_block_timestamp() / 16) * 16;
//     let end_time = start_time + (16 * 8);

//     let protocol_revenue_eth = ekubo_core().get_protocol_fees_collected(eth_token());
//     rb.start_buybacks_all(sell_token: eth_token(), start_time: start_time, end_time: end_time);

//     let config = rb.get_config(eth_token());

//     let order_key = OrderKey {
//         sell_token: eth_token(),
//         buy_token: ekubo_token().contract_address,
//         fee: config.fee,
//         start_time,
//         end_time,
//     };

//     let order_info = positions().get_order_info(id: rb.get_token_id(), order_key: order_key);

//     // rounding error may not be sold
//     assert_lt!(protocol_revenue_eth - order_info.remaining_sell_amount, 2);
//     assert_eq!(order_info.purchased_amount, 0);

//     advance_time(end_time - get_block_timestamp());

//     let order_info_after = positions().get_order_info(id: rb.get_token_id(), order_key: order_key);

//     assert_eq!(order_info_after.remaining_sell_amount, 0);
//     assert_gt!(order_info_after.purchased_amount, 0);

//     let balance_before = ekubo_token().balanceOf(governor_address());
//     rb.collect_proceeds_to_owner(order_key);
//     let balance_after = ekubo_token().balanceOf(governor_address());
//     assert_eq!(balance_after - balance_before, order_info_after.purchased_amount.into());
// }

// #[test]
// #[fork("mainnet")]
// #[should_panic(expected: ('Invalid sell token',))]
// fn test_same_token_buyback_fails() {
//     let rb = setup(default_config: Option::Some(example_config()));
//     let start_time = (get_block_timestamp() / 16) * 16;
//     let end_time = start_time + (16 * 8);

//     rb
//         .start_buybacks_all(
//             sell_token: ekubo_token().contract_address, start_time: start_time, end_time: end_time,
//         );
// }


// #[test]
// #[fork("mainnet")]
// #[should_panic(expected: ('No config for token',))]
// fn test_buyback_with_no_config() {
//     let rb = setup(default_config: Option::None);
//     rb.get_config(sell_token: eth_token());
// }


// #[test]
// #[fork("mainnet")]
// fn test_buyback_with_config_override() {
//     let rb = setup(default_config: Option::None);
//     cheat_caller_address(rb.contract_address, governor_address(), CheatSpan::Indefinite);
//     rb
//         .set_config_override(
//             sell_token: eth_token(), config_override: Option::Some(example_config()),
//         );
//     stop_cheat_caller_address(rb.contract_address);

//     assert_eq!(rb.get_config(sell_token: eth_token()), example_config());

//     let start_time = (get_block_timestamp() / 16) * 16;
//     let end_time = start_time + (16 * 8);

//     rb.start_buybacks_all(sell_token: eth_token(), start_time: start_time, end_time: end_time);
// }


// #[test]
// #[fork("mainnet")]
// fn test_reclaim_core() {
//     let rb = setup(default_config: Option::Some(example_config()));

//     cheat_caller_address(rb.contract_address, governor_address(), CheatSpan::Indefinite);
//     rb.reclaim_core();
//     stop_cheat_caller_address(rb.contract_address);
//     assert_eq!(
//         IOwnedDispatcher { contract_address: ekubo_core().contract_address }.get_owner(),
//         governor_address(),
//     );
//     assert_eq!(
//         IERC721Dispatcher { contract_address: positions().get_nft_address() }
//             .ownerOf(rb.get_token_id().into()),
//         rb.contract_address,
//     );
// }

