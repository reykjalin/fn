const std = @import("std");

const Pos = @import("pos.zig").Pos;
const Range = @import("range.zig");

/// A span from one cursor to another counts as a selection.
const Selection = @This();

/// The edge of the selection that's considered to be a cursor. This is typically the "end"
/// of the selection, or where the cursor (bar, beam, block, underline, etc.) is located. The
/// cursor is not guaranteed to come after the anchor since selections are bi-directional.
cursor: Pos,
/// The edge of the selection that's considered to be an anchor. This is typically the "start"
/// of the selection, or where the cursor (bar, beam, block, underline, etc.) is not located.
/// The anchor is not guaranteed to come before the cursor since selections are bi-directional.
anchor: Pos,

/// Returns `true` if this selection is a cursor. A selection is considered a cursor if it's
/// empty.
pub fn isCursor(self: Selection) bool {
    return self.cursor.eql(self.anchor);
}

/// Returns a Range based on this Selection. The Range will go from the anchor to the cursor.
pub fn toRange(self: Selection) Range {
    return .{ .from = self.anchor, .to = self.cursor };
}

/// Returns a Selection based on the provided Range. The Selection will anchor to the Range's
/// `.from` value and the cursor will be at the Range's `.to` value.
pub fn fromRange(range: Range) Selection {
    return .{ .cursor = range.to, .anchor = range.from };
}

/// Returns `true` if a and b cover the same areas of the text editor. The order of the `.cursor`
/// and `.anchor` positions within each selection does not matter.
pub fn eql(a: Selection, b: Selection) bool {
    return a.toRange().eql(b.toRange());
}

/// Returns `true` if and only if a.cursor == b.cursor and a.anchor == b.anchor. In other words; the
/// order of `.anchor` and `.cursor` positions within the selection matters.
pub fn strictEql(a: Selection, b: Selection) bool {
    return a.cursor == b.cursor and a.anchor == b.anchor;
}

test isCursor {
    const empty: Selection = .{ .anchor = Pos.fromInt(1), .cursor = Pos.fromInt(1) };
    const not_empty: Selection = .{ .anchor = Pos.fromInt(1), .cursor = Pos.fromInt(2) };

    try std.testing.expectEqual(true, empty.isCursor());
    try std.testing.expectEqual(false, not_empty.isCursor());
}

test eql {
    const a: Selection = .{ .anchor = Pos.fromInt(0), .cursor = Pos.fromInt(3) };
    const b: Selection = .{ .anchor = Pos.fromInt(3), .cursor = Pos.fromInt(0) };
    const c: Selection = .{ .anchor = Pos.fromInt(1), .cursor = Pos.fromInt(5) };

    try std.testing.expectEqual(true, Selection.eql(a, a));
    try std.testing.expectEqual(true, Selection.eql(b, b));
    try std.testing.expectEqual(true, Selection.eql(c, c));

    try std.testing.expectEqual(true, Selection.eql(a, b));
    try std.testing.expectEqual(true, Selection.eql(b, a));

    try std.testing.expectEqual(false, Selection.eql(c, a));
    try std.testing.expectEqual(false, Selection.eql(a, c));
    try std.testing.expectEqual(false, Selection.eql(c, b));
    try std.testing.expectEqual(false, Selection.eql(b, c));
}

test strictEql {
    const a: Selection = .{ .anchor = Pos.fromInt(0), .cursor = Pos.fromInt(3) };
    const b: Selection = .{ .anchor = Pos.fromInt(3), .cursor = Pos.fromInt(0) };
    const c: Selection = .{ .anchor = Pos.fromInt(1), .cursor = Pos.fromInt(5) };

    try std.testing.expectEqual(true, Selection.strictEql(a, a));
    try std.testing.expectEqual(true, Selection.strictEql(b, b));
    try std.testing.expectEqual(true, Selection.strictEql(c, c));

    try std.testing.expectEqual(false, Selection.strictEql(a, b));
    try std.testing.expectEqual(false, Selection.strictEql(b, a));

    try std.testing.expectEqual(false, Selection.strictEql(c, a));
    try std.testing.expectEqual(false, Selection.strictEql(a, c));
    try std.testing.expectEqual(false, Selection.strictEql(c, b));
    try std.testing.expectEqual(false, Selection.strictEql(b, c));
}

test "refAllDecls" {
    std.testing.refAllDecls(@This());
}
