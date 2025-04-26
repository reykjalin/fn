//! A `Selection` contains 2 `Pos` structs, one represents the position of the cursor and the other
//! is an anchor. `Selection`s are semantically different from `Range`s. A `Range`s `Pos`itions are
//! arbitrary points, where neither has semantic meaning, unlike the `cursor` and `anchor` in a
//! `Selection`.

const std = @import("std");

const Pos = @import("pos.zig").Pos;
const Range = @import("Range.zig");

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

/// Returns `true` if there's an overlap between the provided selections. In other words; at least
/// one edge from either selection is inside the other.
pub fn hasOverlap(a: Selection, b: Selection) bool {
    return a.toRange().hasOverlap(b.toRange());
}

/// Merges the provided Selections into a new selection. Asserts that the selections overlap.
pub fn merge(a: Selection, b: Selection) Selection {
    std.debug.assert(a.hasOverlap(b));

    if (a.toRange().containsRange(b.toRange())) return a;
    if (b.toRange().containsRange(a.toRange())) return b;

    if (a.isCursor()) {
        if (a.anchor.comesBefore(b.toRange().before()))
            return .{ .anchor = a.anchor, .cursor = b.toRange().after() };

        return .{ .anchor = b.toRange().before(), .cursor = a.cursor };
    }

    if (a.anchor.comesBefore(a.cursor)) {
        if (a.anchor.comesAfter(b.toRange().before()))
            return .{ .anchor = b.toRange().before(), .cursor = a.cursor };

        return .{ .anchor = a.anchor, .cursor = b.toRange().after() };
    }

    if (a.cursor.comesAfter(b.toRange().before()))
        return .{ .anchor = a.anchor, .cursor = b.toRange().before() };

    return .{ .anchor = b.toRange().after(), .cursor = a.cursor };
}

test merge {
    // 1. If one selection contains the other, just return the containing selection.

    try std.testing.expectEqual(
        Selection{ .anchor = .fromInt(0), .cursor = .fromInt(5) },
        Selection.merge(
            .{ .anchor = .fromInt(1), .cursor = .fromInt(1) },
            .{ .anchor = .fromInt(0), .cursor = .fromInt(5) },
        ),
    );
    try std.testing.expectEqual(
        Selection{ .anchor = .fromInt(0), .cursor = .fromInt(5) },
        Selection.merge(
            .{ .anchor = .fromInt(0), .cursor = .fromInt(5) },
            .{ .anchor = .fromInt(1), .cursor = .fromInt(1) },
        ),
    );

    // 2. Merging a cursor and a selection.

    try std.testing.expectEqual(
        Selection{ .anchor = .fromInt(1), .cursor = .fromInt(5) },
        Selection.merge(
            .{ .anchor = .fromInt(1), .cursor = .fromInt(1) },
            .{ .anchor = .fromInt(1), .cursor = .fromInt(5) },
        ),
    );
    try std.testing.expectEqual(
        Selection{ .anchor = .fromInt(0), .cursor = .fromInt(1) },
        Selection.merge(
            .{ .anchor = .fromInt(0), .cursor = .fromInt(1) },
            .{ .anchor = .fromInt(1), .cursor = .fromInt(1) },
        ),
    );

    // 3. Merging overlapping selections.

    try std.testing.expectEqual(
        Selection{ .anchor = .fromInt(0), .cursor = .fromInt(9) },
        Selection.merge(
            .{ .anchor = .fromInt(0), .cursor = .fromInt(5) },
            .{ .anchor = .fromInt(1), .cursor = .fromInt(9) },
        ),
    );
    try std.testing.expectEqual(
        Selection{ .anchor = .fromInt(0), .cursor = .fromInt(9) },
        Selection.merge(
            .{ .anchor = .fromInt(1), .cursor = .fromInt(9) },
            .{ .anchor = .fromInt(0), .cursor = .fromInt(5) },
        ),
    );
    try std.testing.expectEqual(
        Selection{ .cursor = .fromInt(0), .anchor = .fromInt(9) },
        Selection.merge(
            .{ .cursor = .fromInt(1), .anchor = .fromInt(9) },
            .{ .cursor = .fromInt(0), .anchor = .fromInt(5) },
        ),
    );
    try std.testing.expectEqual(
        Selection{ .cursor = .fromInt(0), .anchor = .fromInt(9) },
        Selection.merge(
            .{ .cursor = .fromInt(0), .anchor = .fromInt(5) },
            .{ .cursor = .fromInt(1), .anchor = .fromInt(9) },
        ),
    );
    try std.testing.expectEqual(
        Selection{ .cursor = .fromInt(0), .anchor = .fromInt(9) },
        Selection.merge(
            .{ .cursor = .fromInt(0), .anchor = .fromInt(5) },
            .{ .anchor = .fromInt(1), .cursor = .fromInt(9) },
        ),
    );
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
