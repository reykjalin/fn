const std = @import("std");

const Pos = @import("pos.zig").Pos;

/// A pair of positions count as a range.
const Range = @This();

from: Pos,
to: Pos,

/// Returns `true` if and only if a.from == b.from and a.to == b.to. In other words; the order
/// of `.to` and `.from` positions within the range matters.
pub fn strictEql(a: Range, b: Range) bool {
    return a.from.eql(b.from) and a.to.eql(b.to);
}

/// Returns `true` if a and b cover the same areas of the text editor. The order of the `.to`
/// and `.from` positions within each range does not matter.
pub fn eql(a: Range, b: Range) bool {
    return a.before().eql(b.before()) and a.after().eql(b.after());
}

/// Returns whichever position in the range that comes earlier in the text.
pub fn before(self: Range) Pos {
    if (self.from.comesBefore(self.to)) return self.from;

    return self.to;
}

/// Returns whichever position in the range that comes later in the text.
pub fn after(self: Range) Pos {
    if (self.from.comesBefore(self.to)) return self.to;

    return self.from;
}

/// Returns `true` if the range has 0 width, i.e. the `from` and `to` positions are the same.
pub fn isEmpty(self: Range) bool {
    return self.from.eql(self.to);
}

/// Returns `true` if the provided positions sits within the range. A position on the edges of
/// the range counts as being inside the range. For example: a position {0,0} is considered to
/// be contained by a range from {0,0} to {0,1}.
pub fn containsPos(self: Range, pos: Pos) bool {
    // 1. Check if the provided position is inside the range.

    if (self.before().comesBefore(pos) and self.after().comesAfter(pos)) return true;

    // 2. Check if the provided position is on the edge of the range, which we also think of as
    //    containing the position.
    return self.from.eql(pos) or self.to.eql(pos);
}

/// Returns `true` if the provided range sits within this range. This uses the same logic as
/// `containsPos` and the same rules apply. Equal ranges are considered to contain each other.
pub fn containsRange(self: Range, other: Range) bool {
    return self.containsPos(other.from) and self.containsPos(other.to);
}

/// Returns `true` if there's an overlap between the provided ranges. In other words; at least
/// one edge from either range is inside the other.
pub fn hasOverlap(a: Range, b: Range) bool {
    // If a contains one of the positions in b the revers is also true, so it's enough to check
    // for just one of these conditions.
    return a.containsPos(b.from) or a.containsPos(b.to);
}

test eql {
    const a: Range = .{ .from = Pos.fromInt(0), .to = Pos.fromInt(3) };
    const b: Range = .{ .from = Pos.fromInt(3), .to = Pos.fromInt(0) };
    const c: Range = .{ .from = Pos.fromInt(1), .to = Pos.fromInt(5) };

    try std.testing.expectEqual(true, Range.eql(a, a));
    try std.testing.expectEqual(true, Range.eql(b, b));
    try std.testing.expectEqual(true, Range.eql(c, c));

    try std.testing.expectEqual(true, Range.eql(a, b));
    try std.testing.expectEqual(true, Range.eql(b, a));

    try std.testing.expectEqual(false, Range.eql(c, a));
    try std.testing.expectEqual(false, Range.eql(a, c));
    try std.testing.expectEqual(false, Range.eql(c, b));
    try std.testing.expectEqual(false, Range.eql(b, c));
}

test strictEql {
    const a: Range = .{ .from = Pos.fromInt(0), .to = Pos.fromInt(3) };
    const b: Range = .{ .from = Pos.fromInt(3), .to = Pos.fromInt(0) };
    const c: Range = .{ .from = Pos.fromInt(1), .to = Pos.fromInt(5) };

    try std.testing.expectEqual(true, Range.strictEql(a, a));
    try std.testing.expectEqual(true, Range.strictEql(b, b));
    try std.testing.expectEqual(true, Range.strictEql(c, c));

    try std.testing.expectEqual(false, Range.strictEql(a, b));
    try std.testing.expectEqual(false, Range.strictEql(b, a));

    try std.testing.expectEqual(false, Range.strictEql(c, a));
    try std.testing.expectEqual(false, Range.strictEql(a, c));
    try std.testing.expectEqual(false, Range.strictEql(c, b));
    try std.testing.expectEqual(false, Range.strictEql(b, c));
}

test isEmpty {
    const empty: Range = .{ .from = Pos.fromInt(1), .to = Pos.fromInt(1) };
    const not_empty: Range = .{ .from = Pos.fromInt(1), .to = Pos.fromInt(2) };

    try std.testing.expectEqual(true, empty.isEmpty());
    try std.testing.expectEqual(false, not_empty.isEmpty());
}

test containsPos {
    const range: Range = .{
        .from = Pos.fromInt(1),
        .to = Pos.fromInt(5),
    };

    try std.testing.expectEqual(true, range.containsPos(Pos.fromInt(1)));
    try std.testing.expectEqual(true, range.containsPos(Pos.fromInt(3)));
    try std.testing.expectEqual(true, range.containsPos(Pos.fromInt(5)));

    try std.testing.expectEqual(false, range.containsPos(Pos.fromInt(0)));
    try std.testing.expectEqual(false, range.containsPos(Pos.fromInt(6)));
    try std.testing.expectEqual(false, range.containsPos(Pos.fromInt(10)));
}

test containsRange {
    const a: Range = .{ .from = Pos.fromInt(2), .to = Pos.fromInt(10) };

    // 1. Ranges contain themselves and equal ranges.

    try std.testing.expectEqual(true, a.containsRange(a));

    // 2. Ranges contain other ranges that fall within themselves.

    // From start edge to inside.
    const in_a_1: Range = .{ .from = a.from, .to = Pos.fromInt(7) };
    // From inside to end edge.
    const in_a_2: Range = .{ .from = Pos.fromInt(6), .to = a.to };
    // Completely inside.
    const in_a_3: Range = .{ .from = Pos.fromInt(4), .to = Pos.fromInt(8) };

    try std.testing.expectEqual(true, a.containsRange(in_a_1));
    try std.testing.expectEqual(true, a.containsRange(in_a_2));
    try std.testing.expectEqual(true, a.containsRange(in_a_3));

    // 3. Ranges do not contain other ranges where one edge is outside.

    // Start edge is outside.
    const outside_a_1: Range = .{ .from = Pos.fromInt(a.from.toInt() -| 2), .to = Pos.fromInt(4) };
    // End edge is outside.
    const outside_a_2: Range = .{ .from = Pos.fromInt(6), .to = Pos.fromInt(a.to.toInt() +| 4) };

    try std.testing.expectEqual(false, a.containsRange(outside_a_1));
    try std.testing.expectEqual(false, a.containsRange(outside_a_2));

    // 4. Ranges do not contain other ranges that are entirely outside.

    // Outside start, edges are touching.
    const outside_a_3: Range = .{ .from = Pos.fromInt(0), .to = a.from };
    // Outside start, edges not touching.
    const outside_a_4: Range = .{ .from = Pos.fromInt(0), .to = Pos.fromInt(a.from.toInt() -| 1) };
    // Outside end, edges are touching.
    const outside_a_5: Range = .{ .from = a.to, .to = Pos.fromInt(a.to.toInt() +| 4) };
    // Outside end, edges not touching.
    const outside_a_6: Range = .{ .from = Pos.fromInt(a.to.toInt() +| 1), .to = Pos.fromInt(a.to.toInt() +| 4) };

    try std.testing.expectEqual(false, a.containsRange(outside_a_3));
    try std.testing.expectEqual(false, a.containsRange(outside_a_4));
    try std.testing.expectEqual(false, a.containsRange(outside_a_5));
    try std.testing.expectEqual(false, a.containsRange(outside_a_6));
}

test hasOverlap {
    const a: Range = .{ .from = Pos.fromInt(2), .to = Pos.fromInt(10) };

    // 1. Ranges overlap themselves and equal ranges.

    try std.testing.expectEqual(true, Range.hasOverlap(a, a));

    // 2. Ranges overlap containing ranges.

    // From start edge to inside.
    const in_a_1: Range = .{ .from = a.from, .to = Pos.fromInt(7) };
    // From inside to end edge.
    const in_a_2: Range = .{ .from = Pos.fromInt(6), .to = a.to };
    // Completely inside.
    const in_a_3: Range = .{ .from = Pos.fromInt(4), .to = Pos.fromInt(8) };

    try std.testing.expectEqual(true, Range.hasOverlap(a, in_a_1));
    try std.testing.expectEqual(true, Range.hasOverlap(a, in_a_2));
    try std.testing.expectEqual(true, Range.hasOverlap(a, in_a_3));

    // 3. Ranges overlap when only one edge is inside the other.

    // Start edge is outside.
    const outside_a_1: Range = .{ .from = Pos.fromInt(a.from.toInt() -| 2), .to = Pos.fromInt(4) };
    // End edge is outside.
    const outside_a_2: Range = .{ .from = Pos.fromInt(6), .to = Pos.fromInt(a.to.toInt() +| 4) };

    try std.testing.expectEqual(true, Range.hasOverlap(a, outside_a_1));
    try std.testing.expectEqual(true, Range.hasOverlap(a, outside_a_2));

    // 4. Ranges overlap when edges are touching.
    //    TODO: Maybe they shouldn't be considered to be overlapping here? It's just easier to
    //          implement this if they do, so leaving this as is for now.

    // Outside start, edges are touching.
    const outside_a_3: Range = .{ .from = Pos.fromInt(0), .to = a.from };
    // Outside end, edges are touching.
    const outside_a_4: Range = .{ .from = a.to, .to = Pos.fromInt(a.to.toInt() +| 4) };

    try std.testing.expectEqual(true, Range.hasOverlap(a, outside_a_3));
    try std.testing.expectEqual(true, Range.hasOverlap(a, outside_a_4));

    // 5. Ranges do not overlap when one does not contain an edge from the other.

    // Outside start, edges not touching.
    const outside_a_5: Range = .{ .from = Pos.fromInt(0), .to = Pos.fromInt(a.from.toInt() -| 1) };
    // Outside end, edges not touching.
    const outside_a_6: Range = .{ .from = Pos.fromInt(a.to.toInt() +| 1), .to = Pos.fromInt(a.to.toInt() +| 4) };

    try std.testing.expectEqual(false, Range.hasOverlap(a, outside_a_5));
    try std.testing.expectEqual(false, Range.hasOverlap(a, outside_a_6));
}

test "refAllDecls" {
    std.testing.refAllDecls(@This());
}
