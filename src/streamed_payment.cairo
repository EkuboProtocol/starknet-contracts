use starknet::ContractAddress;

#[derive(Drop, Copy, Serde, starknet::Store)]
pub struct PaymentStreamInfo {
    pub token_address: ContractAddress,
    pub owner: ContractAddress,
    pub recipient: ContractAddress,
    pub amount_total: u128,
    pub amount_paid: u128,
    pub start_time: u64,
    pub end_time: u64,
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

    // Transfers ownership of a stream. Only callable by the current owner.
    fn transfer_stream_ownership(ref self: TContractState, id: u64, new_owner: ContractAddress);

    // Changes the recipient of the stream. Only callable by the stream owner or the recipient.
    fn change_stream_recipient(ref self: TContractState, id: u64, new_recipient: ContractAddress);

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
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePathEntry,
        StoragePointerReadAccess, StoragePointerWriteAccess,
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
                        amount_total: amount,
                        amount_paid: 0,
                        start_time: start_time,
                        end_time: end_time,
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


        fn transfer_stream_ownership(ref self: ContractState, id: u64, new_owner: ContractAddress) {
            let mut stream = self.streams.read(id);

            assert(stream.owner == get_caller_address(), 'Only owner can transfer');

            stream.owner = new_owner;

            self.streams.write(id, stream);
        }

        fn change_stream_recipient(
            ref self: ContractState, id: u64, new_recipient: ContractAddress,
        ) {
            let mut stream = self.streams.read(id);

            let caller = get_caller_address();
            assert(
                stream.owner == caller || stream.recipient == caller,
                'Only owner/recipient can change',
            );

            stream.recipient = new_recipient;

            self.streams.write(id, stream);
        }

        // Collects any pending amount for the given payment stream
        fn collect(ref self: ContractState, id: u64) -> u128 {
            let stream_entry = self.streams.entry(id);
            let mut stream = stream_entry.read();

            let now = get_block_timestamp();
            let payment: u128 = if now < stream.start_time {
                0
            } else if now < stream.end_time {
                let amount_owed: u256 = stream.amount_total.into()
                    * (now - stream.start_time).into()
                    / (stream.end_time - stream.start_time).into();

                (amount_owed - stream.amount_paid.into()).try_into().unwrap()
            } else {
                stream.amount_total - stream.amount_paid
            };

            if (payment.is_non_zero()) {
                stream.amount_paid += payment;

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

            assert(stream.owner == get_caller_address(), 'Only owner can cancel');

            let refund = stream.amount_total - stream.amount_paid;

            if (refund.is_non_zero()) {
                // the total amount is now just the amount paid
                stream.amount_total = stream.amount_paid;
                // refund is only non zero iff block timestamp < end_time
                stream.end_time = get_block_timestamp();
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
