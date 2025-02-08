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

test isCursor {
    const empty: Selection = .{ .anchor = Pos.fromInt(1), .cursor = Pos.fromInt(1) };
    const not_empty: Selection = .{ .anchor = Pos.fromInt(1), .cursor = Pos.fromInt(2) };

    try std.testing.expectEqual(true, empty.isCursor());
    try std.testing.expectEqual(false, not_empty.isCursor());
}

test "refAllDecls" {
    std.testing.refAllDecls(@This());
}
