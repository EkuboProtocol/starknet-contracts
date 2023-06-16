// The points at which an extension should be called
#[derive(Copy, Drop, Serde, storage_access::StorageAccess)]
struct CallPoints {
    after_initialize_pool: bool,
    before_swap: bool,
    after_swap: bool,
    before_update_position: bool,
    after_update_position: bool,
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
            res += 16;
        }
        if (self.before_swap) {
            res += 8;
        }
        if (self.after_swap) {
            res += 4;
        }
        if (self.before_update_position) {
            res += 2;
        }
        if (self.after_update_position) {
            res += 1;
        }
        res
    }
}

impl U8IntoCallPoints of Into<u8, CallPoints> {
    fn into(mut self: u8) -> CallPoints {
        let after_initialize_pool = if (self >= 16) {
            self -= 16;
            true
        } else {
            false
        };

        let before_swap = if (self >= 8) {
            self -= 8;
            true
        } else {
            false
        };
        let after_swap = if (self >= 4) {
            self -= 4;
            true
        } else {
            false
        };

        let before_update_position = if (self >= 2) {
            self -= 2;
            true
        } else {
            false
        };
        let after_update_position = if (self >= 1) {
            self -= 1;
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
