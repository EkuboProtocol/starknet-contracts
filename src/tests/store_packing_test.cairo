fn assert_round_trip<T, U, +starknet::StorePacking<T, U>, +PartialEq<T>, +Drop<T>, +Copy<T>>(
    value: T
) {
    assert(
        starknet::StorePacking::<
            T, U
        >::unpack(starknet::StorePacking::<T, U>::pack(value)) == value,
        'roundtrip'
    );
}
