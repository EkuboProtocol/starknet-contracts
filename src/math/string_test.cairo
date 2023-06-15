use ekubo::math::string::to_decimal;

use debug::PrintTrait;

#[test]
#[available_gas(50000000)]
fn test_to_decimal() {
    assert(to_decimal(0) == '0', '0');
    assert(to_decimal(12345) == '12345', '12345');
    assert(to_decimal(1000) == '1000', '1000');
    assert(to_decimal(2394828150) == '2394828150', '2394828150');
}
