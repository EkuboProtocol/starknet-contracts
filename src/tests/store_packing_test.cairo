fn assert_round_trip<
    T,
    U,
    impl TStorePacking: starknet::StorePacking<T, U>,
    impl TPartialEq: PartialEq<T>,
    impl TDrop: Drop<T>,
    impl TCopy: Copy<T>
>(
    value: T
) {
    assert(
        starknet::StorePacking::<T, U>::unpack(TStorePacking::pack(value)) == value, 'roundtrip'
    );
}
