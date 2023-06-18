const IERC165_ID: u32 = 0x01ffc9a7;

#[starknet::interface]
trait IERC165<TStorage> {
    fn supports_interface(self: @TStorage, interface_id: u32) -> bool;
}
