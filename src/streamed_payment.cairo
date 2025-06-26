use starknet::ContractAddress;

#[derive(Drop, Copy, Serde, starknet::Store)]
pub struct PaymentStreamInfo {
    pub token_address: ContractAddress,
    pub owner: ContractAddress,
    pub recipient: ContractAddress,
    pub amount_remaining: u128,
    pub start_time: u64,
    pub end_time: u64,
    pub seconds_paid: u64,
}

#[starknet::interface]
pub trait IStreamedPayment<TContractState> {
    // Creates a payment stream and returns the ID of the payment stream
    fn create_stream(
        ref self: TContractState,
        token_address: ContractAddress,
        amount: u128,
        recipient: ContractAddress,
        start_time: u64,
        end_time: u64,
    ) -> u64;

    // Returns info on an existing payment stream
    fn get_stream_info(self: @TContractState, id: u64) -> PaymentStreamInfo;

    // Cancels a payment stream that has not ended yet
    fn cancel(ref self: TContractState, id: u64) -> u128;

    // Collects any pending amount for the given payment stream and returns the amount
    fn collect(ref self: TContractState, id: u64) -> u128;
}

#[starknet::contract]
pub mod StreamedPayment {
    use core::array::{Array, ArrayTrait};
    use core::num::traits::Zero;
    use starknet::storage::{
        Map, StorageMapWriteAccess, StoragePathEntry, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::{get_block_timestamp, get_caller_address, get_contract_address};
    use crate::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use super::{ContractAddress, IStreamedPayment, PaymentStreamInfo};


    #[derive(starknet::Event, Drop)]
    pub struct StreamCreated {
        pub id: u64,
        pub token_address: ContractAddress,
        pub owner: ContractAddress,
        pub recipient: ContractAddress,
        pub start_time: u64,
        pub end_time: u64,
        pub amount: u128,
    }

    #[derive(starknet::Event, Drop)]
    pub struct PaymentCollected {
        pub id: u64,
        pub amount: u128,
    }

    #[derive(starknet::Event, Drop)]
    pub struct StreamCanceled {
        pub id: u64,
        pub refund: u128,
    }

    #[derive(starknet::Event, Drop)]
    #[event]
    enum Event {
        StreamCreated: StreamCreated,
        PaymentCollected: PaymentCollected,
        StreamCanceled: StreamCanceled,
    }


    #[storage]
    struct Storage {
        pub next_id: u64,
        pub streams: Map<u64, PaymentStreamInfo>,
    }

    #[abi(embed_v0)]
    impl StreamedPaymentImpl of IStreamedPayment<ContractState> {
        fn create_stream(
            ref self: ContractState,
            token_address: ContractAddress,
            amount: u128,
            recipient: ContractAddress,
            start_time: u64,
            end_time: u64,
        ) -> u64 {
            assert(end_time > start_time, 'End time < start time');

            let owner = get_caller_address();

            let id = self.next_id.read();
            self.next_id.write(id + 1);

            self
                .streams
                .write(
                    id,
                    PaymentStreamInfo {
                        token_address: token_address,
                        owner: owner,
                        recipient: recipient,
                        amount_remaining: amount,
                        start_time: start_time,
                        end_time: end_time,
                        seconds_paid: 0,
                    },
                );

            assert(
                IERC20Dispatcher { contract_address: token_address }
                    .transferFrom(owner, get_contract_address(), amount.into()),
                'transferFrom failed',
            );

            self
                .emit(
                    StreamCreated {
                        id, token_address, owner, recipient, start_time, end_time, amount,
                    },
                );

            return id;
        }

        fn get_stream_info(self: @ContractState, id: u64) -> PaymentStreamInfo {
            self.streams.entry(id).read()
        }


        // Collects any pending amount for the given payment stream
        fn collect(ref self: ContractState, id: u64) -> u128 {
            let stream_entry = self.streams.entry(id);
            let mut stream = stream_entry.read();

            let now = get_block_timestamp();
            let (payment, seconds_paid): (u128, u64) = if (now < stream.start_time) {
                (0, 0)
            } else if now < stream.end_time {
                let seconds_paid_next = now - stream.start_time;
                let amount_remaining: u256 = stream.amount_remaining.into();
                let remaining_duration = stream.end_time - stream.start_time - stream.seconds_paid;

                (
                    ((amount_remaining * (seconds_paid_next - stream.seconds_paid).into())
                        / remaining_duration.into())
                        .try_into()
                        .unwrap(),
                    seconds_paid_next,
                )
            } else {
                (stream.amount_remaining, stream.end_time - stream.start_time)
            };

            if (payment.is_non_zero()) {
                stream.amount_remaining = stream.amount_remaining - payment;
                stream.seconds_paid = seconds_paid;

                stream_entry.write(stream);

                IERC20Dispatcher { contract_address: stream.token_address }
                    .transfer(stream.recipient, payment.into());

                self.emit(PaymentCollected { id, amount: payment });
            }

            payment
        }

        // Cancels a payment stream that has not ended yet
        fn cancel(ref self: ContractState, id: u64) -> u128 {
            // first we force a collect so you cannot refund unclaimed amounts
            self.collect(id);

            let stream_entry = self.streams.entry(id);
            let mut stream = stream_entry.read();

            assert(stream.owner == get_caller_address(), 'OWNER_ONLY');

            let refund = stream.amount_remaining;

            if (refund.is_non_zero()) {
                // zero out the amount remaining
                stream.amount_remaining = 0;
                stream_entry.write(stream);

                assert(
                    IERC20Dispatcher { contract_address: stream.token_address }
                        .transfer(stream.owner, refund.into()),
                    'transfer failed',
                );

                self.emit(StreamCanceled { id, refund });
            }

            refund
        }
    }
}
