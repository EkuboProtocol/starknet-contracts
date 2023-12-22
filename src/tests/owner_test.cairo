use ekubo::owner::{hash_for_owner_check, check_owner_only, owner};
use starknet::testing::{set_caller_address};

#[test]
fn test_owner_hash() {
    assert(
        hash_for_owner_check(
            owner()
        ) == 2081329012068246261264209482314989835561593298919996586864094351098749398388,
        'owner_hash'
    );
}

#[test]
#[should_panic(expected: ('OWNER_ONLY',))]
fn test_check_owner_only_invalid() {
    check_owner_only();
}

#[test]
fn test_check_owner_only_passes_if_caller_is_owner() {
    set_caller_address(owner());
    check_owner_only();
}
