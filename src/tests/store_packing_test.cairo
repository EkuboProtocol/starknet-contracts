pub fn assert_round_trip<
    T, U, +starknet::storage_access::StorePacking<T, U>, +PartialEq<T>, +Drop<T>, +Copy<T>,
>(
    value: T,
) {
    assert(
        starknet::storage_access::StorePacking::<
            T, U,
        >::unpack(starknet::storage_access::StorePacking::<T, U>::pack(value)) == value,
        'roundtrip',
    );
}
