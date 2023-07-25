use core::array::ArrayTrait;
use serde::Serde;
use starknet::storage_access::{StorePacking};
use traits::{Into};

// The points at which an extension should be called
#[derive(Copy, Drop, Serde)]
struct CallPoints {
    after_initialize_pool: bool,
    before_swap: bool,
    after_swap: bool,
    before_update_position: bool,
    after_update_position: bool,
}

impl CallPointsStorePacking of StorePacking<CallPoints, u8> {
    fn pack(value: CallPoints) -> u8 {
        value.into()
    }
    fn unpack(value: u8) -> CallPoints {
        value.into()
    }
}

impl CallPointsPartialEq of PartialEq<CallPoints> {
    fn eq(lhs: @CallPoints, rhs: @CallPoints) -> bool {
        (lhs.after_initialize_pool == rhs.after_initialize_pool)
            & (lhs.before_swap == rhs.before_swap)
            & (lhs.after_swap == rhs.after_swap)
            & (lhs.before_update_position == rhs.before_update_position)
            & (lhs.after_update_position == rhs.after_update_position)
    }
    fn ne(lhs: @CallPoints, rhs: @CallPoints) -> bool {
        !PartialEq::<CallPoints>::eq(lhs, rhs)
    }
}

impl CallPointsDefault of Default<CallPoints> {
    #[inline(always)]
    fn default() -> CallPoints {
        CallPoints {
            after_initialize_pool: false,
            before_swap: false,
            after_swap: false,
            before_update_position: false,
            after_update_position: false,
        }
    }
}

#[inline(always)]
fn all_call_points() -> CallPoints {
    CallPoints {
        after_initialize_pool: true,
        before_swap: true,
        after_swap: true,
        before_update_position: true,
        after_update_position: true,
    }
}

impl CallPointsIntoU8 of Into<CallPoints, u8> {
    fn into(self: CallPoints) -> u8 {
        let mut res: u8 = 0;
        if (self.after_initialize_pool) {
            res += 128;
        }
        if (self.before_swap) {
            res += 64;
        }
        if (self.after_swap) {
            res += 32;
        }
        if (self.before_update_position) {
            res += 16;
        }
        if (self.after_update_position) {
            res += 8;
        }
        res
    }
}

impl U8IntoCallPoints of Into<u8, CallPoints> {
    fn into(mut self: u8) -> CallPoints {
        // these are unused, but we need to remove them from the u8 and this is cheaper than masking
        let after_initialize_pool = if (self >= 128) {
            self -= 128;
            true
        } else {
            false
        };

        let before_swap = if (self >= 64) {
            self -= 64;
            true
        } else {
            false
        };

        let after_swap = if (self >= 32) {
            self -= 32;
            true
        } else {
            false
        };

        let before_update_position = if (self >= 16) {
            self -= 16;
            true
        } else {
            false
        };

        let after_update_position = if (self >= 8) {
            self -= 8;
            true
        } else {
            false
        };

        CallPoints {
            after_initialize_pool,
            before_swap,
            after_swap,
            before_update_position,
            after_update_position,
        }
    }
}

