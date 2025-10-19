use crate::math::string::to_decimal;

#[test]
fn test_to_decimal() {
    assert(to_decimal(0) == '0', '0');
    assert(to_decimal(12345) == '12345', '12345');
    assert(to_decimal(1000) == '1000', '1000');
    assert(to_decimal(2394828150) == '2394828150', '2394828150');
}


#[test]
fn test_large_numbers_to_decimal() {
    assert(to_decimal(12345678901234567890) == '12345678901234567890', '20 decimals');
    assert(to_decimal(9876543210) == '9876543210', '30 decimals');
}
