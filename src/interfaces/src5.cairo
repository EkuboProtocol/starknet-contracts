const ERC165_ID: felt252 = 0x01ffc9a7;
const SRC5_ID: felt252 = 0x3f918d17e5ee77373b56385708f855659a07f75997f365cf87748628532a055;

#[starknet::interface]
trait ISRC5<TStorage> {
    // Returns true if the contract supports the interface
    // Note this is backwards compatible with the old spec that took a u32, since they
    // share a selector
    fn supports_interface(self: @TStorage, interface_id: felt252) -> bool;
}
