const std = @import("std");

/// A `Pos` represents a position in the text editor. `Pos` is a 2-dimensional position based on
/// `row` and `col`.
pub const Pos = @This();

row: usize,
col: usize,

pub const init: Pos = .{ .row = 0, .col = 0 };

/// Returns true if both positions are the same.
pub fn eql(self: Pos, other: Pos) bool {
    return self.row == other.row and self.col == other.col;
}

/// Returns `true` if this `Pos` comes before the `other` `Pos`.
pub fn comesBefore(self: Pos, other: Pos) bool {
    if (self.row < other.row) return true;
    if (self.row > other.row) return false;
    return self.col < other.col;
}

/// Returns `true` if this `Pos` comes after the `other` `Pos`.
pub fn comesAfter(self: Pos, other: Pos) bool {
    if (self.row > other.row) return true;
    if (self.row < other.row) return false;
    return self.col > other.col;
}

/// Comparison function used for sorting.
pub fn lessThan(_: void, lhs: Pos, rhs: Pos) bool {
    return lhs.comesBefore(rhs);
}

test eql {
    const a: Pos = .{ .row = 0, .col = 3 };
    const b: Pos = .{ .row = 0, .col = 3 };

    try std.testing.expect(a.eql(b));
    try std.testing.expect(a.eql(a));
    try std.testing.expect(b.eql(b));

    const c: Pos = .{ .row = 4, .col = 0 };

    try std.testing.expect(!c.eql(a));
    try std.testing.expect(!c.eql(b));
    try std.testing.expect(c.eql(c));

    const d: Pos = .{ .row = 1, .col = 5 };

    try std.testing.expect(!d.eql(a));
    try std.testing.expect(!d.eql(b));
    try std.testing.expect(!d.eql(c));
    try std.testing.expect(d.eql(d));
}

test comesBefore {
    const a: Pos = .{ .row = 0, .col = 3 };
    const b: Pos = .{ .row = 0, .col = 3 };

    try std.testing.expect(!a.comesBefore(b));
    try std.testing.expect(!b.comesBefore(a));

    const c: Pos = .{ .row = 4, .col = 0 };

    try std.testing.expect(!c.comesBefore(a));
    try std.testing.expect(a.comesBefore(c));

    const d: Pos = .{ .row = 1, .col = 5 };

    try std.testing.expect(d.comesBefore(c));
    try std.testing.expect(!c.comesBefore(d));
}

test comesAfter {
    const a: Pos = .{ .row = 0, .col = 3 };
    const b: Pos = .{ .row = 0, .col = 3 };

    try std.testing.expect(!a.comesAfter(b));
    try std.testing.expect(!b.comesAfter(a));

    const c: Pos = .{ .row = 4, .col = 0 };

    try std.testing.expect(c.comesAfter(a));
    try std.testing.expect(!a.comesAfter(c));

    const d: Pos = .{ .row = 1, .col = 5 };

    try std.testing.expect(!d.comesAfter(c));
    try std.testing.expect(c.comesAfter(d));
}

test "refAllDecls" {
    std.testing.refAllDecls(@This());
}
