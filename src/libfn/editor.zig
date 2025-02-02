// AUTHOR: Kristófer R. <kristofer@thorlaksson.com>
// LICENSE: MIT

const std = @import("std");

/// Managed editor object for a single file. **All properties are considered private after
/// initialization. Modifying them will result in undefined behavior.** Use the helper methods
/// instead of modifying properties directly.
const Editor = @This();

// Byte-level cursor position in the content buffer. This is not unicode aware.
pub const BytePos = usize;

/// Unicode-aware row/col cursor position in the current content-buffer.
pub const Pos = struct {
    row: usize,
    col: usize,

    /// Returns true if both positions are the same.
    pub fn eql(a: Pos, b: Pos) bool {
        return a.row == b.row and a.col == b.col;
    }

    /// Returns `true` if this `Pos` comes before the `other` `Pos`.
    pub fn comesBefore(self: Pos, other: Pos) bool {
        if (self.row < other.row) return true;
        if (self.row == other.row and self.col < other.col) return true;

        return false;
    }
};

/// A span from one cursor to another counts as a selection.
pub const Selection = struct {
    cursor: Pos,
    anchor: Pos,
};

pub const Range = struct {
    from: Pos,
    to: Pos,

    pub fn before(self: *Range) Pos {
        if (self.from.comesBefore(self.to)) return self.from;

        return self.to;
    }

    pub fn after(self: *Range) Pos {
        if (self.from.comesBefore(self.to)) return self.to;

        return self.from;
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
lines: std.ArrayList(BytePos),
/// An array of tokens in the text. The text will be tokenized every time it changes. **Modifying
/// this will cause undefined behavior**. The default tokenization has the whole text set to a
/// simple `Text` type.
tokens: std.ArrayList(Token),
/// An array tracking all of the selections in the editor. **Modifying this will cause undefined
/// behavior**. Use the methods on the editor to manipulate the selections instead.
selections: std.ArrayList(Selection),

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
    try selections.append(.{
        .cursor = .{ .row = 0, .col = 0 },
        .anchor = .{ .row = 0, .col = 0 },
    });

    var lines = std.ArrayList(usize).init(allocator);
    try lines.append(0);

    var tokens = std.ArrayList(Token).init(allocator);
    try tokens.append(.{ .pos = .{ .row = 0, .col = 0 }, .text = "", .type = .Text });

    return .{
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

/// Inserts the provided text before all selections. Selections will not be cleared, and will
/// instead move with the content such that they will still select the same text.
pub fn insertTextBeforeSelection(self: *Editor, text: []const u8) !void {
    _ = self;
    _ = text;
}

/// Inserts the provided text after all selections. Selections will not be cleared. The inserted
/// text will instead be appended to the end of each selection.
pub fn insertTextAfterSelection(self: *Editor, text: []const u8) !void {
    _ = self;
    _ = text;
}

/// Delete text in the specified range.
pub fn deleteRange(self: *Editor, range: Range) !void {
    // 1. Nothing to do if the range is empty.

    if (Pos.eql(range.from, range.to)) return;

    // 2. Assert that the range is valid.

    const before = range.before();
    const after = range.after();

    std.debug.assert(before.row < self.lines.items.len);
    std.debug.assert(after.row < self.lines.items.len);

    // It's impossible to represent a position before line 0 so we don't have to check for that. So
    // it's enough to just ensure that the end of the range doesn't go beyond the last character on
    // the last line.

    const last_line = self.text.items[self.lines.items[self.lines.items.len - 1]..];
    std.debug.assert(after.row != self.lines.items.len - 1 or after.col < last_line.len);

    // 3. Remove the range.

    const beforeBytePos = self.toBytePos(before);
    const afterBytePos = self.toBytePos(after);

    self.text.replaceRangeAssumeCapacity(beforeBytePos, afterBytePos - beforeBytePos, "");

    // 4. Update line start indices.

    try self.updateLines();

    // 5. TODO: Update selections.
}

/// Tokenizes the text.
/// TODO: Have language extensions implement this and call those functions when relevant.
fn tokenize(self: *Editor) !void {
    self.tokens.clearRetainingCapacity();
    try self.tokens.append(.{
        .pos = .{ .row = 0, .col = 0 },
        .text = self.text.items,
        .type = .Text,
    });
}

/// Updates the indeces for the start of each line in the text.
fn updateLines(self: *Editor) !void {
    self.lines.clearRetainingCapacity();
    try self.lines.append(0);

    var it = std.mem.tokenizeScalar(u8, self.text.items, '\n');
    while (it.next()) |_| {
        // The current index of the iterator is always on the newline. To make the index point to
        // the first character of each line we have to add one.
        // NOTE: This will result in the last index being equal to the length of the text array if
        //       the file ends with a newline.
        try self.lines.append(it.index +| 1);
    }

    // The iterator will reach the end and add an index even if the last character isn't a new line
    // character. So we make sure to remove the last index if the file doesn't end with a new line.
    // NOTE: We only do this if we've added more than just the start of the first line to the list
    //       of lines.
    if (self.lines.items.len > 1 and !std.mem.endsWith(u8, self.text.items, "\n"))
        _ = self.lines.pop();
}

/// Converts the provided `Pos` object to a `BytePos`.
pub fn toBytePos(self: *Editor, pos: Pos) BytePos {
    // 1. Assert that the provided row position is valid.

    std.debug.assert(pos.row < self.lines.items.len);

    // 2. Get the correct line.

    const lineStartIndex: BytePos = self.lines.items[pos.row];
    const lineEndIndex: BytePos = if (pos.row + 1 < self.lines.items.len)
        self.lines.items[pos.row + 1]
    else
        self.text.items.len;

    // 3. Assert that the provided column position is valid.

    // An empty line is possible which is why we have to use an equality check here.
    std.debug.assert(lineStartIndex <= lineEndIndex);
    std.debug.assert(pos.col <= lineEndIndex - lineStartIndex);

    // 4. Return the right byte position.

    return lineStartIndex + pos.col;
}

/// Converts the provided `BytePos` object to a `Pos`.
pub fn fromBytepos(self: *Editor, pos: BytePos) Pos {
    // 1. Assert that the provided position is valid.

    // NOTE: The position after the last character in a file is a valid position which is why we
    //       must check for equality against the text length.
    std.debug.assert(pos <= self.text.items.len);

    // 2. Find the row indicated by the byte-level position.

    var row: usize = 0;
    for (self.lines.items, 0..) |lineStartIndex, i| {
        // If we're past the provided byte-level position then we know the previous position was the
        // correct row.
        if (lineStartIndex > pos) break;
        row = i;
    }

    // 3. Use the byte-level position of the start of the row to calculate the column of the
    //    provided position.

    const startOfRowIndex: BytePos = self.lines.items[row];

    return .{ .row = row, .col = pos - startOfRowIndex };
}

test "Pos.eql" {
    const a: Pos = .{ .row = 0, .col = 0 };
    const b: Pos = .{ .row = 0, .col = 0 };

    try std.testing.expectEqual(true, Pos.eql(a, b));
    try std.testing.expectEqual(true, Pos.eql(a, a));
    try std.testing.expectEqual(true, Pos.eql(b, b));

    const c: Pos = .{ .row = 10, .col = 15 };

    try std.testing.expectEqual(false, Pos.eql(c, a));
    try std.testing.expectEqual(false, Pos.eql(c, b));
    try std.testing.expectEqual(true, Pos.eql(c, c));

    const d: Pos = .{ .row = 10, .col = 14 };

    try std.testing.expectEqual(false, Pos.eql(d, a));
    try std.testing.expectEqual(false, Pos.eql(d, b));
    try std.testing.expectEqual(false, Pos.eql(d, c));
    try std.testing.expectEqual(true, Pos.eql(d, d));
}

test "Pos.comesBefore" {
    const a: Pos = .{ .row = 0, .col = 0 };
    const b: Pos = .{ .row = 0, .col = 0 };

    try std.testing.expectEqual(false, a.comesBefore(b));
    try std.testing.expectEqual(false, b.comesBefore(a));

    const c: Pos = .{ .row = 10, .col = 15 };

    try std.testing.expectEqual(false, c.comesBefore(a));
    try std.testing.expectEqual(true, a.comesBefore(c));

    const d: Pos = .{ .row = 10, .col = 14 };

    try std.testing.expectEqual(true, d.comesBefore(c));
    try std.testing.expectEqual(false, c.comesBefore(d));
}

test "toBytePos" {
    var editor = try Editor.init(std.testing.allocator);
    defer editor.deinit();

    try editor.text.appendSlice("012\n456\n890\n");
    // Updating the lines is required to properly calculate the byte-level cursor positions.
    try editor.updateLines();

    try std.testing.expectEqual(0, editor.toBytePos(.{ .row = 0, .col = 0 }));
    try std.testing.expectEqual(2, editor.toBytePos(.{ .row = 0, .col = 2 }));
    try std.testing.expectEqual(3, editor.toBytePos(.{ .row = 0, .col = 3 }));

    try std.testing.expectEqual(4, editor.toBytePos(.{ .row = 1, .col = 0 }));
    try std.testing.expectEqual(5, editor.toBytePos(.{ .row = 1, .col = 1 }));
    try std.testing.expectEqual(7, editor.toBytePos(.{ .row = 1, .col = 3 }));

    try std.testing.expectEqual(8, editor.toBytePos(.{ .row = 2, .col = 0 }));
    try std.testing.expectEqual(10, editor.toBytePos(.{ .row = 2, .col = 2 }));
    try std.testing.expectEqual(11, editor.toBytePos(.{ .row = 2, .col = 3 }));

    try std.testing.expectEqual(12, editor.toBytePos(.{ .row = 3, .col = 0 }));
}

test "fromBytePos" {
    var editor = try Editor.init(std.testing.allocator);
    defer editor.deinit();

    try editor.text.appendSlice("012\n456\n890\n");
    // Updating the lines is required to properly calculate the byte-level cursor positions.
    try editor.updateLines();

    try std.testing.expectEqual(Pos{ .row = 0, .col = 0 }, editor.fromBytepos(0));
    try std.testing.expectEqual(Pos{ .row = 0, .col = 2 }, editor.fromBytepos(2));
    try std.testing.expectEqual(Pos{ .row = 0, .col = 3 }, editor.fromBytepos(3));

    try std.testing.expectEqual(Pos{ .row = 1, .col = 0 }, editor.fromBytepos(4));
    try std.testing.expectEqual(Pos{ .row = 1, .col = 1 }, editor.fromBytepos(5));
    try std.testing.expectEqual(Pos{ .row = 1, .col = 3 }, editor.fromBytepos(7));

    try std.testing.expectEqual(Pos{ .row = 2, .col = 0 }, editor.fromBytepos(8));
    try std.testing.expectEqual(Pos{ .row = 2, .col = 2 }, editor.fromBytepos(10));
    try std.testing.expectEqual(Pos{ .row = 2, .col = 3 }, editor.fromBytepos(11));

    try std.testing.expectEqual(Pos{ .row = 3, .col = 0 }, editor.fromBytepos(12));
}

test "Insert before selections" {
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

test "Insert after selections" {
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

test "Delete text" {
    var editor = try Editor.init(std.testing.allocator);
    defer editor.deinit();

    try editor.text.appendSlice("012\n456\n890\n");
    // Updating the lines is required to properly calculate the byte-level cursor positions, which
    // is used in the delete function.
    try editor.updateLines();

    // 1. Ensure all state is unchanged after deleting an empty range.

    // 2. Delete within a line.

    // 3. Delete at the start of a line.

    // 4. Delete at the end of a line.

    // 5. Delete at the start of a file.

    // 6. Delete at the end of a file.

    // 7. Delete from start of line to end of line.

    // 8. Delete from start of line to start of next line.

    // 9. Delete from end of line to start of next line (merge the lines).

    // 10. Delete from end of line to end of next line.

    // 11. Delete from within a line to the end of line.

    // 12. Delete from within a line to the start of next line.

    // 13. Delete from within a line to within next line.

    // 14. Delete from multiple lines.

}

test "Tokenizing text" {
    var editor = try Editor.init(std.testing.allocator);
    defer editor.deinit();

    // 1. Empty text.

    try editor.tokenize();

    try std.testing.expectEqualSlices(
        Token,
        &.{
            .{ .pos = .{ .row = 0, .col = 0 }, .text = &.{}, .type = .Text },
        },
        editor.tokens.items,
    );

    // 2. Some text.

    try editor.text.appendSlice("lorem ipsum\n");
    try editor.tokenize();

    try std.testing.expectEqual(1, editor.tokens.items.len);

    const token = editor.tokens.items[0];

    try std.testing.expectEqual(Editor.TokenType.Text, token.type);
    try std.testing.expectEqual(Editor.Pos{ .row = 0, .col = 0 }, token.pos);
    try std.testing.expectEqualStrings("lorem ipsum\n", token.text);
}

test "Updating line numbers" {
    var editor = try Editor.init(std.testing.allocator);
    defer editor.deinit();

    // 1. Empty text.

    try editor.updateLines();

    // We should always have at least one line.
    try std.testing.expectEqual(1, editor.lines.items.len);
    try std.testing.expectEqualSlices(
        usize,
        &.{0},
        editor.lines.items,
    );

    // 2. One line.

    try editor.text.appendSlice("012");
    try editor.updateLines();

    try std.testing.expectEqualSlices(
        usize,
        &.{0},
        editor.lines.items,
    );

    editor.text.clearRetainingCapacity();

    // 3. One line, ends with a new line.

    try editor.text.appendSlice("012\n");
    try editor.updateLines();

    try std.testing.expectEqualSlices(
        usize,
        &.{ 0, 4 },
        editor.lines.items,
    );

    editor.text.clearRetainingCapacity();

    // 4. Multiple lines.

    try editor.text.appendSlice("012\n456\n890");
    try editor.updateLines();

    try std.testing.expectEqualSlices(
        usize,
        &.{ 0, 4, 8 },
        editor.lines.items,
    );

    editor.text.clearRetainingCapacity();

    // 5. Multiple lines, ends with a new line.

    try editor.text.appendSlice("012\n456\n890\n");
    try editor.updateLines();

    try std.testing.expectEqualSlices(
        usize,
        &.{ 0, 4, 8, 12 },
        editor.lines.items,
    );
}
