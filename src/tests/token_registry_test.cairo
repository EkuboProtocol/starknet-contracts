use ekubo::token_registry::TokenRegistry::{ten_pow};

#[test]
#[available_gas(3000000)]
fn test_ten_pow() {
    assert(ten_pow(0) == 1, '10^0');
    assert(ten_pow(1) == 10, '10^1');
    assert(ten_pow(2) == 100, '10^2');
    assert(ten_pow(3) == 1000, '10^3');
    assert(ten_pow(4) == 10000, '10^4');
    assert(ten_pow(5) == 100000, '10^5');
    assert(ten_pow(6) == 1000000, '10^6');
    assert(ten_pow(18) == 1000000000000000000, '10^18');
}
