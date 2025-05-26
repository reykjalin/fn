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

pub const init: Selection = .{ .cursor = .init, .anchor = .init };

pub fn createCursor(pos: Pos) Selection {
    return .{ .cursor = pos, .anchor = pos };
}

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
    return a.cursor.eql(b.cursor) and a.anchor.eql(b.anchor);
}

/// Returns `true` if there's an overlap between the provided selections. In other words; at least
/// one edge from either selection is inside the other.
pub fn hasOverlap(a: Selection, b: Selection) bool {
    return a.toRange().hasOverlap(b.toRange());
}

/// Returns `true` if `a` comes before `b`. Asserts that `a` and `b` don't overlap.
pub fn comesBefore(a: Selection, b: Selection) bool {
    std.debug.assert(!a.hasOverlap(b));
    return a.toRange().after().comesBefore(b.toRange().before());
}

/// Merges the provided Selections into a new selection. Asserts that the selections overlap.
pub fn merge(a: Selection, b: Selection) Selection {
    std.debug.assert(a.hasOverlap(b));

    // 1. If either range contains the other, return the container range.

    if (a.toRange().containsRange(b.toRange())) return a;
    if (b.toRange().containsRange(a.toRange())) return b;

    // 2. If `a` is a cursor we know it's not in `b`, so we know we only have to merge the correct
    //    edge.

    if (a.isCursor()) {
        if (a.anchor.comesBefore(b.toRange().before()))
            return .{ .anchor = a.anchor, .cursor = b.toRange().after() };

        return .{ .anchor = b.toRange().before(), .cursor = a.cursor };
    }

    // 3. Now we know we have overlapping ranges. `b` might still be a cursor, but it does not
    //    matter at this point since it doesn't change how we handle `b`. Now we just make sure we
    //    merge the ranges such that the anchor and cursor are in the right positions.

    // 4. Handle what happens when anchor comes before the cursor.

    if (a.anchor.comesBefore(a.cursor)) {
        // If the anchor comes after the first position in `b` we use the first position in `b` as
        // the new anchor.
        if (a.anchor.comesAfter(b.toRange().before()))
            return .{ .anchor = b.toRange().before(), .cursor = a.cursor };

        // Otherwise, we use the anchor from a, and set the cursor to the latter position in `b`.
        return .{ .anchor = a.anchor, .cursor = b.toRange().after() };
    }

    // 5. Otherwise the cursor comes before the anchor.

    // If the cursor comes after the first position in `b` we know we need to extend the cursor to
    // `b`s first position.
    if (a.cursor.comesAfter(b.toRange().before()))
        return .{ .anchor = a.anchor, .cursor = b.toRange().before() };

    // Otherwise, we extend the anchor to `b`s latter position.
    return .{ .anchor = b.toRange().after(), .cursor = a.cursor };
}

test merge {
    // 1. If one selection contains the other, just return the containing selection.

    try std.testing.expectEqual(
        Selection{ .anchor = .init, .cursor = .{ .row = 0, .col = 5 } },
        Selection.merge(
            .{ .anchor = .{ .row = 0, .col = 1 }, .cursor = .{ .row = 0, .col = 1 } },
            .{ .anchor = .init, .cursor = .{ .row = 0, .col = 5 } },
        ),
    );
    try std.testing.expectEqual(
        Selection{ .anchor = .init, .cursor = .{ .row = 0, .col = 5 } },
        Selection.merge(
            .{ .anchor = .init, .cursor = .{ .row = 0, .col = 5 } },
            .{ .anchor = .{ .row = 0, .col = 1 }, .cursor = .{ .row = 0, .col = 1 } },
        ),
    );

    // 2. Merging a cursor and a selection.

    try std.testing.expectEqual(
        Selection{ .anchor = .{ .row = 0, .col = 1 }, .cursor = .{ .row = 0, .col = 5 } },
        Selection.merge(
            .{ .anchor = .{ .row = 0, .col = 1 }, .cursor = .{ .row = 0, .col = 1 } },
            .{ .anchor = .{ .row = 0, .col = 1 }, .cursor = .{ .row = 0, .col = 5 } },
        ),
    );
    try std.testing.expectEqual(
        Selection{ .anchor = .init, .cursor = .{ .row = 0, .col = 1 } },
        Selection.merge(
            .{ .anchor = .init, .cursor = .{ .row = 0, .col = 1 } },
            .{ .anchor = .{ .row = 0, .col = 1 }, .cursor = .{ .row = 0, .col = 1 } },
        ),
    );

    // 3. Merging overlapping selections.

    try std.testing.expectEqual(
        Selection{ .anchor = .init, .cursor = .{ .row = 1, .col = 4 } },
        Selection.merge(
            .{ .anchor = .init, .cursor = .{ .row = 0, .col = 5 } },
            .{ .anchor = .{ .row = 0, .col = 4 }, .cursor = .{ .row = 1, .col = 4 } },
        ),
    );
    try std.testing.expectEqual(
        Selection{ .anchor = .init, .cursor = .{ .row = 1, .col = 4 } },
        Selection.merge(
            .{ .anchor = .{ .row = 0, .col = 4 }, .cursor = .{ .row = 1, .col = 4 } },
            .{ .anchor = .init, .cursor = .{ .row = 0, .col = 5 } },
        ),
    );
    try std.testing.expectEqual(
        Selection{ .cursor = .init, .anchor = .{ .row = 1, .col = 4 } },
        Selection.merge(
            .{ .cursor = .{ .row = 0, .col = 4 }, .anchor = .{ .row = 1, .col = 4 } },
            .{ .cursor = .init, .anchor = .{ .row = 0, .col = 5 } },
        ),
    );
    try std.testing.expectEqual(
        Selection{ .cursor = .init, .anchor = .{ .row = 1, .col = 4 } },
        Selection.merge(
            .{ .cursor = .init, .anchor = .{ .row = 0, .col = 5 } },
            .{ .cursor = .{ .row = 0, .col = 4 }, .anchor = .{ .row = 1, .col = 4 } },
        ),
    );
    try std.testing.expectEqual(
        Selection{ .cursor = .init, .anchor = .{ .row = 1, .col = 4 } },
        Selection.merge(
            .{ .cursor = .init, .anchor = .{ .row = 0, .col = 5 } },
            .{ .anchor = .{ .row = 0, .col = 4 }, .cursor = .{ .row = 1, .col = 4 } },
        ),
    );
}

test isCursor {
    const empty: Selection = .{
        .anchor = .{ .row = 0, .col = 1 },
        .cursor = .{ .row = 0, .col = 1 },
    };
    const not_empty: Selection = .{
        .anchor = .{ .row = 0, .col = 1 },
        .cursor = .{ .row = 0, .col = 2 },
    };

    try std.testing.expect(empty.isCursor());
    try std.testing.expect(!not_empty.isCursor());
}

test eql {
    const a: Selection = .{ .anchor = .init, .cursor = .{ .row = 0, .col = 3 } };
    const b: Selection = .{ .anchor = .{ .row = 0, .col = 3 }, .cursor = .init };
    const c: Selection = .{ .anchor = .{ .row = 1, .col = 2 }, .cursor = .{ .row = 1, .col = 5 } };

    try std.testing.expect(Selection.eql(a, a));
    try std.testing.expect(Selection.eql(b, b));
    try std.testing.expect(Selection.eql(c, c));

    try std.testing.expect(Selection.eql(a, b));
    try std.testing.expect(Selection.eql(b, a));

    try std.testing.expect(!Selection.eql(c, a));
    try std.testing.expect(!Selection.eql(a, c));
    try std.testing.expect(!Selection.eql(c, b));
    try std.testing.expect(!Selection.eql(b, c));
}

test comesBefore {
    const a: Selection = .{ .anchor = .init, .cursor = .{ .row = 0, .col = 3 } };
    const b: Selection = .{ .anchor = .{ .row = 0, .col = 4 }, .cursor = .{ .row = 1, .col = 2 } };
    const c: Selection = .{ .anchor = .{ .row = 2, .col = 3 }, .cursor = .{ .row = 1, .col = 5 } };

    try std.testing.expect(a.comesBefore(b));
    try std.testing.expect(b.comesBefore(c));
}

test strictEql {
    const a: Selection = .{ .anchor = .init, .cursor = .{ .row = 0, .col = 3 } };
    const b: Selection = .{ .anchor = .{ .row = 0, .col = 3 }, .cursor = .init };
    const c: Selection = .{ .anchor = .{ .row = 1, .col = 2 }, .cursor = .{ .row = 1, .col = 5 } };

    try std.testing.expect(Selection.strictEql(a, a));
    try std.testing.expect(Selection.strictEql(b, b));
    try std.testing.expect(Selection.strictEql(c, c));

    try std.testing.expect(!Selection.strictEql(a, b));
    try std.testing.expect(!Selection.strictEql(b, a));

    try std.testing.expect(!Selection.strictEql(c, a));
    try std.testing.expect(!Selection.strictEql(a, c));
    try std.testing.expect(!Selection.strictEql(c, b));
    try std.testing.expect(!Selection.strictEql(b, c));
}

test "refAllDecls" {
    std.testing.refAllDecls(@This());
}
