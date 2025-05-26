const std = @import("std");

/// An `IndexPos` represents a position in the text editor. `IndexPos` is a wrapper around `usize`.
/// You can use `fromInt` and `toInt` to convert between `IndexPos` and `usize`.
pub const IndexPos = enum(usize) {
    _,

    /// Converts the provided `usize` to a `Pos`.
    pub fn fromInt(pos: usize) IndexPos {
        return @enumFromInt(pos);
    }

    /// Converts this `Pos` to a `usize`.
    pub fn toInt(self: IndexPos) usize {
        return @intFromEnum(self);
    }

    /// Returns true if both positions are the same.
    pub fn eql(a: IndexPos, b: IndexPos) bool {
        return a.toInt() == b.toInt();
    }

    /// Returns `true` if this `Pos` comes before the `other` `Pos`.
    pub fn comesBefore(self: IndexPos, other: IndexPos) bool {
        return self.toInt() < other.toInt();
    }

    /// Returns `true` if this `Pos` comes after the `other` `Pos`.
    pub fn comesAfter(self: IndexPos, other: IndexPos) bool {
        return self.toInt() > other.toInt();
    }

    /// Comparison function used for sorting.
    pub fn lessThan(_: void, lhs: IndexPos, rhs: IndexPos) bool {
        return lhs.comesBefore(rhs);
    }

    test fromInt {
        const a = IndexPos.fromInt(0);
        const b = IndexPos.fromInt(12345);

        try std.testing.expect(@intFromEnum(a) == 0);
        try std.testing.expect(@intFromEnum(b) == 12345);
    }

    test toInt {
        const a = IndexPos.fromInt(0);
        const b = IndexPos.fromInt(12345);

        try std.testing.expect(a.toInt() == 0);
        try std.testing.expect(b.toInt() == 12345);
    }

    test eql {
        const a = IndexPos.fromInt(0);
        const b = IndexPos.fromInt(0);

        try std.testing.expectEqual(true, IndexPos.eql(a, b));
        try std.testing.expectEqual(true, IndexPos.eql(a, a));
        try std.testing.expectEqual(true, IndexPos.eql(b, b));

        const c = IndexPos.fromInt(4);

        try std.testing.expectEqual(false, IndexPos.eql(c, a));
        try std.testing.expectEqual(false, IndexPos.eql(c, b));
        try std.testing.expectEqual(true, IndexPos.eql(c, c));

        const d = IndexPos.fromInt(3);

        try std.testing.expectEqual(false, IndexPos.eql(d, a));
        try std.testing.expectEqual(false, IndexPos.eql(d, b));
        try std.testing.expectEqual(false, IndexPos.eql(d, c));
        try std.testing.expectEqual(true, IndexPos.eql(d, d));
    }

    test comesBefore {
        const a = IndexPos.fromInt(0);
        const b = IndexPos.fromInt(0);

        try std.testing.expectEqual(false, a.comesBefore(b));
        try std.testing.expectEqual(false, b.comesBefore(a));

        const c = IndexPos.fromInt(4);

        try std.testing.expectEqual(false, c.comesBefore(a));
        try std.testing.expectEqual(true, a.comesBefore(c));

        const d = IndexPos.fromInt(3);

        try std.testing.expectEqual(true, d.comesBefore(c));
        try std.testing.expectEqual(false, c.comesBefore(d));
    }

    test comesAfter {
        const a = IndexPos.fromInt(0);
        const b = IndexPos.fromInt(0);

        try std.testing.expectEqual(false, a.comesAfter(b));
        try std.testing.expectEqual(false, b.comesAfter(a));

        const c = IndexPos.fromInt(4);

        try std.testing.expectEqual(true, c.comesAfter(a));
        try std.testing.expectEqual(false, a.comesAfter(c));

        const d = IndexPos.fromInt(3);

        try std.testing.expectEqual(false, d.comesAfter(c));
        try std.testing.expectEqual(true, c.comesAfter(d));
    }
};

test "refAllDecls" {
    std.testing.refAllDecls(@This());
}
