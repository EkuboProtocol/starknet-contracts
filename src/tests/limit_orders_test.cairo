use crate::components::util::serialize;
use crate::interfaces::core::{IForwardeeDispatcher, IForwardeeDispatcherTrait};
use crate::interfaces::extensions::limit_orders::{
    ForwardCallbackData, OrderKey, PlaceOrderForwardCallbackData,
};
use crate::tests::helper::{Deployer, DeployerTrait, set_caller_address_once};
use crate::types::i129::i129;

#[test]
#[should_panic(expected: ("Limit orders deprecated", 'ENTRYPOINT_FAILED'))]
fn test_place_order_reverts_as_deprecated() {
    let mut deployer: Deployer = Default::default();
    let core = deployer.deploy_core();
    let limit_orders = deployer.deploy_limit_orders(core);
    let forwardee = IForwardeeDispatcher { contract_address: limit_orders.contract_address };

    set_caller_address_once(limit_orders.contract_address, core.contract_address);
    forwardee
        .forwarded(
            original_locker: 3.try_into().unwrap(),
            id: 0,
            data: serialize(
                @ForwardCallbackData::PlaceOrder(
                    PlaceOrderForwardCallbackData {
                        salt: 1,
                        order_key: OrderKey {
                            token0: 1.try_into().unwrap(),
                            token1: 2.try_into().unwrap(),
                            tick: i129 { mag: 0, sign: false },
                        },
                        liquidity: 1,
                    },
                ),
            )
                .span(),
        );
}
