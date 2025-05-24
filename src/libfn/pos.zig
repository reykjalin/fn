const std = @import("std");

/// A `Pos` represents a position in the text editor. `Pos` is a wrapper around `usize`. You can use
/// `fromInt` and `toInt` to convert between `Pos` and `usize`.
pub const Pos = enum(usize) {
    _,

    /// Converts the provided `usize` to a `Pos`.
    pub fn fromInt(pos: usize) Pos {
        return @enumFromInt(pos);
    }

    /// Converts this `Pos` to a `usize`.
    pub fn toInt(self: Pos) usize {
        return @intFromEnum(self);
    }

    /// Returns true if both positions are the same.
    pub fn eql(a: Pos, b: Pos) bool {
        return a.toInt() == b.toInt();
    }

    /// Returns `true` if this `Pos` comes before the `other` `Pos`.
    pub fn comesBefore(self: Pos, other: Pos) bool {
        return self.toInt() < other.toInt();
    }

    /// Returns `true` if this `Pos` comes after the `other` `Pos`.
    pub fn comesAfter(self: Pos, other: Pos) bool {
        return self.toInt() > other.toInt();
    }

    /// Comparison function used for sorting.
    pub fn lessThan(_: void, lhs: Pos, rhs: Pos) bool {
        return lhs.comesBefore(rhs);
    }

    test fromInt {
        const a = Pos.fromInt(0);
        const b = Pos.fromInt(12345);

        try std.testing.expect(@intFromEnum(a) == 0);
        try std.testing.expect(@intFromEnum(b) == 12345);
    }

    test toInt {
        const a = Pos.fromInt(0);
        const b = Pos.fromInt(12345);

        try std.testing.expect(a.toInt() == 0);
        try std.testing.expect(b.toInt() == 12345);
    }

    test eql {
        const a = Pos.fromInt(0);
        const b = Pos.fromInt(0);

        try std.testing.expectEqual(true, Pos.eql(a, b));
        try std.testing.expectEqual(true, Pos.eql(a, a));
        try std.testing.expectEqual(true, Pos.eql(b, b));

        const c = Pos.fromInt(4);

        try std.testing.expectEqual(false, Pos.eql(c, a));
        try std.testing.expectEqual(false, Pos.eql(c, b));
        try std.testing.expectEqual(true, Pos.eql(c, c));

        const d = Pos.fromInt(3);

        try std.testing.expectEqual(false, Pos.eql(d, a));
        try std.testing.expectEqual(false, Pos.eql(d, b));
        try std.testing.expectEqual(false, Pos.eql(d, c));
        try std.testing.expectEqual(true, Pos.eql(d, d));
    }

    test comesBefore {
        const a = Pos.fromInt(0);
        const b = Pos.fromInt(0);

        try std.testing.expectEqual(false, a.comesBefore(b));
        try std.testing.expectEqual(false, b.comesBefore(a));

        const c = Pos.fromInt(4);

        try std.testing.expectEqual(false, c.comesBefore(a));
        try std.testing.expectEqual(true, a.comesBefore(c));

        const d = Pos.fromInt(3);

        try std.testing.expectEqual(true, d.comesBefore(c));
        try std.testing.expectEqual(false, c.comesBefore(d));
    }

    test comesAfter {
        const a = Pos.fromInt(0);
        const b = Pos.fromInt(0);

        try std.testing.expectEqual(false, a.comesAfter(b));
        try std.testing.expectEqual(false, b.comesAfter(a));

        const c = Pos.fromInt(4);

        try std.testing.expectEqual(true, c.comesAfter(a));
        try std.testing.expectEqual(false, a.comesAfter(c));

        const d = Pos.fromInt(3);

        try std.testing.expectEqual(false, d.comesAfter(c));
        try std.testing.expectEqual(true, c.comesAfter(d));
    }
};

test "refAllDecls" {
    std.testing.refAllDecls(@This());
}
