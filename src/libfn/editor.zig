// AUTHOR: Kristófer R. <kristofer@thorlaksson.com>
// LICENSE: MIT

const std = @import("std");

/// Managed editor object for a single file. **All properties are considered private after
/// initialization. Modifying them will result in undefined behavior.** Use the helper methods
/// instead of modifying properties directly.
const Editor = @This();

/// Unicode-aware row/col cursor position in the current content-buffer.
pub const Pos = enum(usize) {
    _,

    pub fn fromInt(pos: usize) Pos {
        return @enumFromInt(pos);
    }

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
};

pub const CoordinatePos = struct {
    row: usize,
    col: usize,
};

pub const Range = struct {
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
};

/// A span from one cursor to another counts as a selection.
pub const Selection = struct {
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
};

pub const TokenType = enum {
    Text,
    Whitespace,
};

pub const Token = struct {
    pos: Pos,
    type: TokenType,
    text: []const u8,
};

/// The currently loaded file. **Modifying this will cause undefined behavior**. Use the helper
/// methods to manipulate the currently open file.
filename: std.ArrayList(u8),
/// The text of the currently loaded file. **Modifying this will cause undefined behavior**.
/// Use the helper methods to manipulate file text.
text: std.ArrayList(u8),
/// The start position of each line in the content buffer using a byte-position. **Modifying this
/// will cause undefined behavior**. This will automatically be kept up to date by helper methods.
lines: std.ArrayList(Pos),
/// An array of tokens in the text. The text will be tokenized every time it changes. **Modifying
/// this will cause undefined behavior**. The default tokenization has the whole text set to a
/// simple `Text` type.
tokens: std.ArrayList(Token),
/// An array tracking all of the selections in the editor. **Modifying this will cause undefined
/// behavior**. Use the methods on the editor to manipulate the selections instead.
selections: std.ArrayList(Selection),
/// Allocator that the editor can use when necessary.
allocator: std.mem.Allocator,

pub const Command = union(enum) {
    /// Adds a new cursor at the given position.
    AddCursor: Pos,
    /// Adds a new selection at the given position.
    AddSelection: Range,
    /// Deletes text inside all selections. Nothing will be deleted from empty selections.
    DeleteInsideSelections,
    /// Deletes the letter after the cursor. Unicode-aware.
    DeleteLetterAfterCursors,
    /// Deletes the letter before the cursor. Unicode-aware.
    DeleteLetterBeforeCursors,
};

/// Initializes an Editor struct with an empty filename and empty content buffer.
pub fn init(allocator: std.mem.Allocator) !Editor {
    var selections = std.ArrayList(Selection).init(allocator);
    try selections.append(.{ .anchor = Pos.fromInt(0), .cursor = Pos.fromInt(0) });

    var lines = std.ArrayList(Pos).init(allocator);
    try lines.append(Pos.fromInt(0));

    var tokens = std.ArrayList(Token).init(allocator);
    try tokens.append(.{ .pos = Pos.fromInt(0), .text = "", .type = .Text });

    return .{
        .allocator = allocator,
        .filename = std.ArrayList(u8).init(allocator),
        .lines = lines,
        .selections = selections,
        .text = std.ArrayList(u8).init(allocator),
        .tokens = tokens,
    };
}

pub fn deinit(self: *Editor) void {
    self.filename.deinit();
    self.lines.deinit();
    self.selections.deinit();
    self.text.deinit();
    self.tokens.deinit();
}

/// Opens the file provided and loads the contents of the file into the content buffer. `filename`
/// must be a file pathk relative to the current working directory or an absolute path.
/// TODO: handle errors in a way that this can return `void` or maybe some `result` type.
pub fn openFile(self: *Editor, filename: []const u8) !void {
    // 1. Open the file for reading.

    const file = try std.fs.cwd().openFile(filename, .{ .mode = .read_only });
    defer file.close();

    // 2. Get a reader to read the file.

    var buf_reader = std.io.bufferedReader(file.reader());
    const reader = buf_reader.reader();

    // 3. Read the file and store in state.

    const content = try reader.readAll();
    self.text.clearRetainingCapacity();
    try self.text.appendSlice(content);

    // 4. Only after the file has been successfully read do we update file name and other state.

    self.filename.clearRetainingCapacity();
    try self.filename.appendSlice(filename);

    // 5. Update line start array.

    try self.updateLines();

    // 6. Tokenize the new text.

    try self.tokenize();
}

/// Deletes the character immediately before the cursor.
/// FIXME: Make this unicode aware.
pub fn deleteCharacterBeforeCursors(self: *Editor) !void {
    // 1. Find all the cursor positions.

    var cursors = std.ArrayList(Pos).init(self.allocator);
    defer cursors.deinit();

    for (self.selections.items) |selection| {
        try cursors.append(selection.cursor);
    }

    // 2. The selections aren't guaranteed to be in order, so we sort them and make sure we delete
    //    from the back of the text first. That way we don't have to update all the cursors after
    //    each deletion.

    std.mem.sort(Pos, cursors.items, {}, Pos.lessThan);
    std.mem.reverse(Pos, cursors.items);

    // 3. Delete the cursors.

    for (cursors.items) |cursor| {
        // We can't delete before the first character in the file, so that's a noop.
        if (cursor.toInt() == 0) continue;

        _ = self.text.orderedRemove(cursor.toInt() -| 1);
    }

    // 4. Update state.

    // Need to update the line positions since they will have moved in most cases.
    try self.updateLines();

    // Need to re-tokenize.
    try self.tokenize();

    // Need to move the cursors.
    for (self.selections.items) |*selection| {
        // Move the cursor back 1 character.
        // FIXME: Make this unicode-aware.
        selection.cursor = Pos.fromInt(selection.cursor.toInt() -| 1);

        // If the cursor moved to a position before the anchor, change the selection to a cursor.
        if (selection.cursor.comesBefore(selection.anchor)) {
            selection.anchor = selection.cursor;
        }
    }
}

/// Inserts the provided text before all selections. Selections will not be cleared, and will
/// instead move with the content such that they will still select the same text.
pub fn insertTextBeforeSelection(self: *Editor, text: []const u8) !void {
    _ = self;
    _ = text;

    // TODO: implement.
}

/// Inserts the provided text after all selections. Selections will not be cleared. The inserted
/// text will instead be appended to the end of each selection.
pub fn insertTextAfterSelection(self: *Editor, text: []const u8) !void {
    _ = self;
    _ = text;

    // TODO: implement.
}

/// Tokenizes the text.
/// TODO: Have language extensions implement this and call those functions when relevant.
fn tokenize(self: *Editor) !void {
    self.tokens.clearRetainingCapacity();
    try self.tokens.append(.{
        .pos = Pos.fromInt(0),
        .text = self.text.items,
        .type = .Text,
    });
}

/// Updates the indeces for the start of each line in the text.
fn updateLines(self: *Editor) !void {
    self.lines.clearRetainingCapacity();
    try self.lines.append(Pos.fromInt(0));

    // NOTE: We start counting from 1 because we consider the start of a line to be **after** a
    //       newline character, not before.
    for (self.text.items, 1..) |char, i| {
        if (char == '\n') try self.lines.append(Pos.fromInt(i));
    }
}

/// Converts the provided `BytePos` object to a `Pos`.
pub fn toCoordinatePos(self: *Editor, pos: Pos) CoordinatePos {
    // 1. Assert that the provided position is valid.

    // NOTE: The position after the last character in a file is a valid position which is why we
    //       must check for equality against the text length.
    std.debug.assert(pos.toInt() <= self.text.items.len);

    // 2. Find the row indicated by the byte-level position.

    const row: usize = row: {
        var row: usize = 0;
        for (self.lines.items, 0..) |lineStartIndex, i| {
            // If we're past the provided byte-level position then we know the previous position was the
            // correct row_index.
            if (lineStartIndex.comesAfter(pos)) break :row row;
            row = i;
        }

        // If haven't found the position in the loop, we can safely use the last line.
        break :row self.lines.items.len -| 1;
    };

    // 3. Use the byte-level position of the start of the row to calculate the column of the
    //    provided position.

    const startOfRowIndex: Pos = self.lines.items[row];

    return .{ .row = row, .col = pos.toInt() -| startOfRowIndex.toInt() };
}

test "Pos.eql" {
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

test "Pos.comesBefore" {
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

test "Pos.comesAfter" {
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

test "Range.eql" {
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

test "Range.strictEql" {
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

test "Range.isEmpty" {
    const empty: Range = .{ .from = Pos.fromInt(1), .to = Pos.fromInt(1) };
    const not_empty: Range = .{ .from = Pos.fromInt(1), .to = Pos.fromInt(2) };

    try std.testing.expectEqual(true, empty.isEmpty());
    try std.testing.expectEqual(false, not_empty.isEmpty());
}

test "Range.containsPos" {
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

test "Range.containsRange" {
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

test "Range.hasOverlap" {
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

test "Selection.isCursor" {
    const empty: Selection = .{ .anchor = Pos.fromInt(1), .cursor = Pos.fromInt(1) };
    const not_empty: Selection = .{ .anchor = Pos.fromInt(1), .cursor = Pos.fromInt(2) };

    try std.testing.expectEqual(true, empty.isCursor());
    try std.testing.expectEqual(false, not_empty.isCursor());
}

test toCoordinatePos {
    var editor = try Editor.init(std.testing.allocator);
    defer editor.deinit();

    try editor.text.appendSlice("012\n456\n890\n");
    // Updating the lines is required to properly calculate the byte-level cursor positions.
    try editor.updateLines();

    try std.testing.expectEqual(CoordinatePos{ .row = 0, .col = 0 }, editor.toCoordinatePos(Pos.fromInt(0)));
    try std.testing.expectEqual(CoordinatePos{ .row = 0, .col = 2 }, editor.toCoordinatePos(Pos.fromInt(2)));
    try std.testing.expectEqual(CoordinatePos{ .row = 0, .col = 3 }, editor.toCoordinatePos(Pos.fromInt(3)));

    try std.testing.expectEqual(CoordinatePos{ .row = 1, .col = 0 }, editor.toCoordinatePos(Pos.fromInt(4)));
    try std.testing.expectEqual(CoordinatePos{ .row = 1, .col = 1 }, editor.toCoordinatePos(Pos.fromInt(5)));
    try std.testing.expectEqual(CoordinatePos{ .row = 1, .col = 3 }, editor.toCoordinatePos(Pos.fromInt(7)));

    try std.testing.expectEqual(CoordinatePos{ .row = 2, .col = 0 }, editor.toCoordinatePos(Pos.fromInt(8)));
    try std.testing.expectEqual(CoordinatePos{ .row = 2, .col = 2 }, editor.toCoordinatePos(Pos.fromInt(10)));
    try std.testing.expectEqual(CoordinatePos{ .row = 2, .col = 3 }, editor.toCoordinatePos(Pos.fromInt(11)));

    try std.testing.expectEqual(CoordinatePos{ .row = 3, .col = 0 }, editor.toCoordinatePos(Pos.fromInt(12)));
}

test insertTextBeforeSelection {
    var editor = try Editor.init(std.testing.allocator);
    defer editor.deinit();

    // 1. Insertion without new line.

    try editor.insertTextBeforeSelection("lorem ipsum");

    // try std.testing.expectEqualStrings("lorem ipsum", editor.text.items);
    // try std.testing.expectEqualSlices(
    //     Selection,
    //     &.{.{ .row = 0, .col = 11 }},
    //     editor.selections.items,
    // );

    // 2. Insertion that starts with a new line.

    // 3. Insertion that ends with a new line.

    // 4. Insertion that contains a new line in the middle.
}

test insertTextAfterSelection {
    var editor = try Editor.init(std.testing.allocator);
    defer editor.deinit();

    // 1. Insertion without new line.

    try editor.insertTextAfterSelection("lorem ipsum");

    // try std.testing.expectEqualStrings("lorem ipsum", editor.text.items);
    // try std.testing.expectEqualSlices(
    //     Selection,
    //     &.{.{ .row = 0, .col = 11 }},
    //     editor.selections.items,
    // );

    // 2. Insertion that starts with a new line.

    // 3. Insertion that ends with a new line.

    // 4. Insertion that contains a new line in the middle.
}

test deleteCharacterBeforeCursors {
    var editor = try Editor.init(std.testing.allocator);
    defer editor.deinit();

    try editor.text.appendSlice("012\n456\n890\n");

    // NOTE: Editor is always initialized with one selection at the start.

    // == Cursors == //

    // 1. Deleting from the first position is a noop.

    try editor.deleteCharacterBeforeCursors();

    try std.testing.expectEqualStrings("012\n456\n890\n", editor.text.items);
    try std.testing.expectEqualSlices(
        Selection,
        &.{.{ .anchor = Pos.fromInt(0), .cursor = Pos.fromInt(0) }},
        editor.selections.items,
    );

    // 2. Deleting from the back deletes the last character.

    // 3. Deleting the first character only deletes the first character.

    // 4. Deleting in multiple places.

    // 5. Deleting when 2 cursors are in the same location (may happen with overlapping selections).

    // 6. Cursors should merge when they reach the start of the file.

    // == Selections == //

    // 7. Deleting in a selection should shrink the selection.

    // 8. Shrinking a selection to a cursor should make that selection a cursor.

    // 9. Deleting from side-by-side selections where the anchor from one touches the cursor from
    //    the other.

    // 10. Deleting from side-by-side selections where the anchors are touching.

    // 11. Deleting from side-by-side selections where the cursors are touching.

    // 12. Deleting from overlapping selections. Test cursor inside the other with other cursor both
    //     before and after. Test anchor inside the other with other cursor both before and after.

    // == Mix between cursors and selections == //

    // TBD
}

test tokenize {
    var editor = try Editor.init(std.testing.allocator);
    defer editor.deinit();

    // 1. Empty text.

    try editor.tokenize();

    try std.testing.expectEqualSlices(
        Token,
        &.{
            .{ .pos = Pos.fromInt(0), .text = &.{}, .type = .Text },
        },
        editor.tokens.items,
    );

    // 2. Some text.

    try editor.text.appendSlice("lorem ipsum\n");
    try editor.tokenize();

    try std.testing.expectEqual(1, editor.tokens.items.len);

    const token = editor.tokens.items[0];

    try std.testing.expectEqual(Editor.TokenType.Text, token.type);
    try std.testing.expectEqual(Pos.fromInt(0), token.pos);
    try std.testing.expectEqualStrings("lorem ipsum\n", token.text);
}

test updateLines {
    var editor = try Editor.init(std.testing.allocator);
    defer editor.deinit();

    // 1. Empty text.

    try editor.updateLines();

    // We should always have at least one line.
    try std.testing.expectEqual(1, editor.lines.items.len);
    try std.testing.expectEqualSlices(
        Pos,
        &.{Pos.fromInt(0)},
        editor.lines.items,
    );

    // 2. One line.

    try editor.text.appendSlice("012");
    try editor.updateLines();

    try std.testing.expectEqualSlices(
        Pos,
        &.{Pos.fromInt(0)},
        editor.lines.items,
    );

    editor.text.clearRetainingCapacity();

    // 3. One line, ends with a new line.

    try editor.text.appendSlice("012\n");
    try editor.updateLines();

    try std.testing.expectEqualSlices(
        Pos,
        &.{ Pos.fromInt(0), Pos.fromInt(4) },
        editor.lines.items,
    );

    editor.text.clearRetainingCapacity();

    // 4. Multiple lines.

    try editor.text.appendSlice("012\n456\n890");
    try editor.updateLines();

    try std.testing.expectEqualSlices(
        Pos,
        &.{ Pos.fromInt(0), Pos.fromInt(4), Pos.fromInt(8) },
        editor.lines.items,
    );

    editor.text.clearRetainingCapacity();

    // 5. Multiple lines, ends with a new line.

    try editor.text.appendSlice("012\n456\n890\n");
    try editor.updateLines();

    try std.testing.expectEqualSlices(
        Pos,
        &.{ Pos.fromInt(0), Pos.fromInt(4), Pos.fromInt(8), Pos.fromInt(12) },
        editor.lines.items,
    );

    editor.text.clearRetainingCapacity();

    // 6. Multiple new lines in a row.

    try editor.text.appendSlice("012\n\n\n67\n\n0");
    try editor.updateLines();

    try std.testing.expectEqualSlices(
        Pos,
        &.{ Pos.fromInt(0), Pos.fromInt(4), Pos.fromInt(5), Pos.fromInt(6), Pos.fromInt(9), Pos.fromInt(10) },
        editor.lines.items,
    );
}
