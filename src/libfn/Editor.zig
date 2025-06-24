//! Managed editor object for a single file. **All properties are considered private after
//! initialization. Modifying them will result in undefined behavior.** Use the helper methods
//! instead of modifying properties directly.

const std = @import("std");

const Pos = @import("pos.zig");
const IndexPos = @import("indexpos.zig").IndexPos;
const Range = @import("Range.zig");
const Selection = @import("Selection.zig");

const Allocator = std.mem.Allocator;

const Editor = @This();

/// Represents a position in the currently open file in the `Editor`. Directly corresponds to a
/// `Pos`.
pub const CoordinatePos = struct {
    row: usize,
    col: usize,
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
filename: std.ArrayListUnmanaged(u8),
/// The text of the currently loaded file. **Modifying this will cause undefined behavior**.
/// Use the helper methods to manipulate file text.
text: std.ArrayListUnmanaged(u8),
/// The start position of each line in the content buffer using a byte-position. **Modifying this
/// will cause undefined behavior**. This will automatically be kept up to date by helper methods.
line_indexes: std.ArrayListUnmanaged(IndexPos),
/// An array of tokens in the text. The text will be tokenized every time it changes. **Modifying
/// this will cause undefined behavior**. The default tokenization has the whole text set to a
/// simple `Text` type.
tokens: std.ArrayListUnmanaged(Token),
/// An array tracking all of the selections in the editor. **Modifying this will cause undefined
/// behavior**. Use the methods on the editor to manipulate the selections instead.
selections: std.ArrayListUnmanaged(Selection),

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
pub fn init(allocator: Allocator) !Editor {
    var selections: std.ArrayListUnmanaged(Selection) = .empty;
    try selections.append(
        allocator,
        .init,
    );

    var lines: std.ArrayListUnmanaged(IndexPos) = .empty;
    try lines.append(allocator, .fromInt(0));

    var tokens: std.ArrayListUnmanaged(Token) = .empty;
    try tokens.append(allocator, .{ .pos = .{ .row = 0, .col = 0 }, .text = "", .type = .Text });

    return .{
        .filename = .empty,
        .line_indexes = lines,
        .selections = selections,
        .text = .empty,
        .tokens = tokens,
    };
}

pub fn deinit(self: *Editor, allocator: Allocator) void {
    self.filename.deinit(allocator);
    self.line_indexes.deinit(allocator);
    self.selections.deinit(allocator);
    self.text.deinit(allocator);
    self.tokens.deinit(allocator);
}

/// Opens the file provided and loads the contents of the file into the content buffer. `filename`
/// must be a file pathk relative to the current working directory or an absolute path.
/// TODO: handle errors in a way that this can return `void` or maybe some `result` type.
pub fn openFile(self: *Editor, allocator: Allocator, filename: []const u8) !void {
    // 1. Open a scratch buffer if no file name is provided.

    if (filename.len == 0) {
        self.filename.clearAndFree(allocator);
        self.text.clearAndFree(allocator);
        try self.updateLines(allocator);
        try self.tokenize(allocator);
        return;
    }

    // 2. Open the file for reading.

    const file = try std.fs.cwd().openFile(filename, .{ .mode = .read_only });
    defer file.close();

    // 3. Get a reader to read the file.

    var buf_reader = std.io.bufferedReader(file.reader());
    const reader = buf_reader.reader();

    // 4. Read the file and store in state.

    const contents = try reader.readAllAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(contents);

    self.text.clearRetainingCapacity();
    try self.text.appendSlice(allocator, contents);

    // 5. Only after the file has been successfully read do we update file name and other state.

    self.filename.clearRetainingCapacity();
    try self.filename.appendSlice(allocator, filename);

    // 6. Update line start array.

    try self.updateLines(allocator);

    // 7. Tokenize the new text.

    try self.tokenize(allocator);
}

/// Saves the text to the current location based on the `filename` field.
pub fn saveFile(self: *Editor) void {
    _ = self;
    // TODO: implement.
}

pub fn copySelectionsContent(self: *const Editor) void {
    _ = self;
    // TODO: implement.
}

/// Moves cursor before anchor for all selections.
pub fn moveCursorBeforeAnchorForAllSelections(self: *Editor) void {
    for (self.selections.items) |*s| {
        if (!s.cursor.comesBefore(s.anchor)) {
            const old_anchor = s.anchor;
            s.anchor = s.cursor;
            s.cursor = old_anchor;
        }
    }
}

/// Moves cursor after anchor for all selections.
pub fn moveCursorAfterAnchorForAllSelections(self: *Editor) void {
    for (self.selections.items) |*s| {
        if (!s.cursor.comesAfter(s.anchor)) {
            const old_anchor = s.anchor;
            s.anchor = s.cursor;
            s.cursor = old_anchor;
        }
    }
}

/// Moves each selection up one line. Selections will be collapsed to the cursor before they're
/// moved.
pub fn moveSelectionsUp(self: *Editor) void {
    for (self.selections.items) |*s| {
        if (s.cursor.row > 0) s.cursor.row -= 1;
        s.anchor = s.cursor;
    }

    // TODO: Merge selections.
}

/// Moves each selection down one line. Selections will be collapsed to the cursor before they're
/// moved.
pub fn moveSelectionsDown(self: *Editor) void {
    for (self.selections.items) |*s| {
        var cursor = s.cursor;
        cursor.row +|= 1;

        // Keep the cursor where it is when we try to move beyond the last line.
        if (cursor.row >= self.lineCount()) {
            continue;
        }

        s.cursor = cursor;
        s.anchor = s.cursor;
    }

    // TODO: Merge selections.
}

/// Moves each selection left one character. Selections will be collapsed to the cursor before
/// they're moved.
pub fn moveSelectionsLeft(self: *Editor) void {
    for (self.selections.items) |*s| {
        const line = self.getLine(s.cursor.row);

        // Reset virtual column location if it extends beyond the length of the line.
        if (s.cursor.col >= line.len) s.cursor.col = line.len;

        if (s.cursor.col == 0 and s.cursor.row > 0) {
            s.cursor.row -= 1;
            const new_line = self.getLine(s.cursor.row);
            s.cursor.col = new_line.len -| 1;
        } else {
            s.cursor.col -|= 1;
        }

        s.anchor = s.cursor;
    }

    // TODO: Merge selections.
}

/// Moves each selection right one character. Selections will be collapsed to the cursor before
/// they're moved.
pub fn moveSelectionsRight(self: *Editor) void {
    const num_lines = self.line_indexes.items.len -| 1;
    for (self.selections.items) |*s| {
        const line = self.getLine(s.cursor.row);

        s.cursor.col +|= 1;

        if (s.cursor.col > line.len -| 1 and s.cursor.row < num_lines) {
            s.cursor.row +|= 1;
            s.cursor.col = 0;
        } else if (s.cursor.row == num_lines) {
            // We want to allow the cursor to appear as if there's a new line at the end of a file
            // so it can be moved beyond the end, so to speak.
            const max_col = if (std.mem.endsWith(u8, line, "\n")) line.len else line.len +| 1;
            if (s.cursor.col > max_col)
                s.cursor.col = max_col;
        }

        s.anchor = s.cursor;
    }

    // TODO: Merge selections.
}

/// Collapses each selection to its cursor and moves it to the start of the line. If the cursor is
/// already at the start of the line it will be moved to the end of the previous line.
pub fn moveSelectionsToStartOfLine(self: *Editor) void {
    _ = self;
    // TODO: implement.
}

/// Collapses each selection to its cursor and moves it to the end of the line. If the cursor is
/// already at the end of the line it will be moved to the start of the next line.
pub fn moveSelectionsToEndOfLine(self: *Editor) void {
    _ = self;
    // TODO: implement.
}

/// Selects the word that comes after each selection's cursor. Behavior varies depending on cursor
/// location for each selection:
///
/// 1. If the cursor is at the start of a word, the selection will start from that position and go
///    to the end of the word.
/// 2. If the cursor is inside a word, the selection will start from that position and go to the end
///    of the word.
/// 3. If the cursor is at the end of a word, the selection will start at the beginning of the  next
///    word and go to the end of that word.
/// 4. If the cursor is in the whitespace immediately before a word, the selection will start at the
///    beginning of the next word and go to the end of that word.
/// 5. If the cursor is in long whitespace (> 1 space), and not at the position right before the
///    following word, the selection will start at the current cursor's position, and go to the
///    beginning of the following word.
pub fn selectNextWord(self: *Editor) void {
    _ = self;
    // TODO: implement.
}

/// Selects the word that comes before each selection's cursor. Behavior varies depending on cursor
/// location for each selection:
///
/// 1. If the cursor is at the start of a word, the selection starts at that position and goes to
///    the start of the preceding word.
/// 2. If the cursor is inside a word, the selection will start from that position and go to the
///    beginning of that word.
/// 3. If the cursor is in the whitespace following a word, the selection will start from that
///    position and go to the beginning of the preceding word.
pub fn selectPreviousWord(self: *Editor) void {
    _ = self;
    // TODO: implement.
}

/// Deletes everything in front of each cursor until the start of each cursor's line.
/// If cursor is already at the start of the line, it should delete the newline in front of it.
pub fn deleteToStartOfLine(self: *Editor) void {
    _ = self;

    // TODO: implement.
}

/// Returns the primary selection.
pub fn getPrimarySelection(self: *const Editor) Selection {
    std.debug.assert(self.selections.items.len > 0);
    return self.selections.items[0];
}

/// Returns the requested 0-indexed line. Asserts that the line is a valid line number. The editor
/// owns the memory returned, caller must not change or free the returned text.
/// Includes the new line character at the end of the line.
pub fn getLine(self: *const Editor, line: usize) []const u8 {
    std.debug.assert(line < self.line_indexes.items.len);

    const start_idx = self.line_indexes.items[line].toInt();
    const end_idx = if (line < self.line_indexes.items.len -| 1)
        self.line_indexes.items[line + 1].toInt()
    else
        self.text.items.len;

    std.debug.assert(start_idx <= end_idx);

    return self.text.items[start_idx..end_idx];
}

/// Returns all the text in the current file. Caller owns the memory and must free.
pub fn getAllTextOwned(self: *const Editor, allocator: Allocator) ![]const u8 {
    return try allocator.dupe(u8, self.text.items);
}

/// Deletes the character immediately before the cursor.
/// FIXME: Make this unicode aware.
pub fn deleteCharacterBeforeCursors(self: *Editor, allocator: Allocator) !void {
    // 1. Find all the cursor positions.

    var cursors: std.ArrayListUnmanaged(IndexPos) = .empty;
    defer cursors.deinit(allocator);

    for (self.selections.items) |selection| {
        var shouldAppend = true;
        const selection_cursor = toIndexPos(self.text.items, selection.cursor);

        // We make sure we only add one of each cursor position to make sure selections where the
        // cursors are touching don't cause 2 deletes.
        for (cursors.items) |cursor| {
            if (cursor.eql(selection_cursor)) {
                shouldAppend = false;
                break;
            }
        }

        if (shouldAppend) try cursors.append(allocator, selection_cursor);
    }

    // 2. The selections aren't guaranteed to be in order, so we sort them and make sure we delete
    //    from the back of the text first. That way we don't have to update all the cursors after
    //    each deletion.

    std.mem.sort(IndexPos, cursors.items, {}, IndexPos.lessThan);
    std.mem.reverse(IndexPos, cursors.items);

    // 3. Delete character before each cursor.

    const old_text = try allocator.dupe(u8, self.text.items);
    defer allocator.free(old_text);

    for (cursors.items) |cursor| {
        // We can't delete before the first character in the file, so that's a noop.
        if (cursor.toInt() == 0) continue;

        _ = self.text.orderedRemove(cursor.toInt() -| 1);
    }

    // 4. Update state.

    // Need to update the line positions since they will have moved in most cases.
    try self.updateLines(allocator);

    // Need to re-tokenize.
    try self.tokenize(allocator);

    // 5. Update selections.

    // Each selection moves a different amount. The first selection in the file moves back 1
    // character, the 2nd 2 characters, the 3rd 3 characters, and so on.
    // Since selections aren't guaranteed to be in order we need a way to update them in order. We
    // do this by constructing a map such that each selection receives an int describing how much it
    // should move.
    //
    // Example:
    //      Selections: {   10,   40,   30 }
    //  File order map: {    1,    3,    2 } These values represent the order within the file in
    //                                       which these selections appear.
    //     Calculation: { 10-1, 40-3, 30-2}
    //          Result: {    9,   37,   28 }

    var orderMap: std.ArrayListUnmanaged(usize) = .empty;
    defer orderMap.deinit(allocator);

    // FIXME: n^2 complexity on this is terrible, but it was the easy way to implement this. Use an
    //        actual sorting algorithm to do this faster, jeez. Although tbf, this is unlikely to
    //        be a real bottleneck, so maybe this is good enough. Integer math be fast like that.
    for (self.selections.items) |current| {
        var movement: usize = 1;
        for (self.selections.items) |other| {
            if (current.strictEql(other)) continue;

            // We move the cursor 1 additional character for every cursor that comes before it.
            if (other.cursor.comesBefore(current.cursor)) movement += 1;
        }

        try orderMap.append(allocator, movement);
    }

    // Need to move the cursors. Since each selection will have resulted in a deleted character we
    // need to move each cursor back equal to it's position in the file.
    for (self.selections.items, orderMap.items) |*selection, movement| {
        const cursor = toIndexPos(old_text, selection.cursor);
        const anchor = toIndexPos(old_text, selection.anchor);

        if (selection.isCursor()) {
            // FIXME: Make this unicode-aware.
            selection.cursor = self.toPos(.fromInt(cursor.toInt() -| movement));
            selection.anchor = selection.cursor;
            continue;
        }

        // Move both by `movement` if the cursor comes before the anchor in the selection.
        // Otherwise move just the cursor.
        if (selection.cursor.comesBefore(selection.anchor)) {
            // FIXME: Make this unicode-aware.
            selection.cursor = self.toPos(.fromInt(cursor.toInt() -| movement));
            selection.anchor = self.toPos(.fromInt(anchor.toInt() -| movement));
        } else {
            // FIXME: Make this unicode-aware.
            selection.cursor = self.toPos(.fromInt(cursor.toInt() -| movement));

            const is_first_selection_in_file = movement == 1;

            // Anything but the first selection has to move both the anchor and the cursor.
            if (!is_first_selection_in_file) {
                // Since the anchor comes before the cursor in this case we can't include the
                // shift generated by removing the character before the cursor in this selection,
                // so we subtract 1 from the movement.
                // FIXME: Make this unicode aware.
                const anchor_movement = movement -| 1;
                selection.anchor = self.toPos(.fromInt(anchor.toInt() -| anchor_movement));
            }

            // Collapse the selection into a cursor if the cursor moved beyond the anchor.
            if (selection.cursor.comesBefore(selection.anchor)) selection.anchor = selection.cursor;
        }
    }

    // 6. Remove duplicate selections.

    for (self.selections.items, 0..) |selection, i| {
        const is_last_selection = i == self.selections.items.len - 1;
        if (is_last_selection) break;

        var j = i + 1;
        while (j < self.selections.items.len) {
            const other_selection = self.selections.items[j];
            if (selection.eql(other_selection)) {
                _ = self.selections.swapRemove(j);

                // It's essential to `continue` here so we check `selection` against whichever
                // selection has now moved to be at index `j`.
                continue;
            }

            j += 1;
        }
    }
}

pub fn lineCount(self: *const Editor) usize {
    return self.line_indexes.items.len;
}

/// Inserts the provided text at the cursor location for each selection. Selectiosn will not be
/// cleared. If the anchor comes before the cursor the selection will expand to include the newly
/// inserted text. If the anchor comes after the cursor the text will be inserted before the
/// selection, and the selection moved with the new content such that it will still select the same
/// text.
pub fn insertTextAtCursors(self: *Editor, allocator: Allocator, text: []const u8) !void {
    for (self.selections.items) |*s| {
        const cursor = toIndexPos(self.text.items, s.cursor);

        // Insert text.
        try self.text.insertSlice(allocator, cursor.toInt(), text);

        // Check inserted text for new lines so we can handle them properly.
        const num_new_lines = std.mem.count(u8, text, "\n");
        const last_new_line = std.mem.lastIndexOfScalar(u8, text, '\n');

        // Update other selection positions.
        // NOTE: We've asserted that no selections overlap, so we stick to that assumption here.
        for (self.selections.items) |*other| {
            if (s.eql(other.*)) continue;

            if (s.comesBefore(other.*)) {
                other.cursor = .{
                    .row = other.cursor.row +| num_new_lines,
                    .col = if (last_new_line) |i| text[i +| 1..].len else other.cursor.col +| text.len,
                };
                other.anchor = .{
                    .row = other.anchor.row +| num_new_lines,
                    .col = if (last_new_line) |i| text[i +| 1..].len else other.anchor.col +| text.len,
                };
            }
        }

        // Update this selection's positions.
        if (s.isCursor()) {
            s.cursor = .{
                .row = s.cursor.row +| num_new_lines,
                .col = if (last_new_line) |i| text[i +| 1..].len else s.cursor.col +| text.len,
            };
            s.anchor = s.cursor;
        } else if (s.cursor.comesBefore(s.anchor)) {
            s.cursor = .{
                .row = s.cursor.row +| num_new_lines,
                .col = if (last_new_line) |i| text[i +| 1..].len else s.cursor.col +| text.len,
            };
            s.anchor = .{
                .row = s.anchor.row +| num_new_lines,
                .col = if (last_new_line) |i| text[i +| 1..].len else s.anchor.col +| text.len,
            };
        } else {
            s.cursor = .{
                .row = s.cursor.row +| num_new_lines,
                .col = if (last_new_line) |i| text[i +| 1..].len else s.cursor.col +| text.len,
            };
        }
    }

    std.debug.assert(!self.hasOverlappingSelections());

    try self.updateLines(allocator);
}

/// Appends the provided Selection to the current list of selections. If the new selection overlaps
/// an existing selection they will be merged.
pub fn appendSelection(self: *Editor, allocator: Allocator, new_selection: Selection) !void {
    // 1. Append the selection.

    try self.selections.append(allocator, new_selection);

    // 2. Merge any overlapping selections.

    var outer: usize = 0;
    outer_loop: while (outer < self.selections.items.len) {
        const before: Selection = self.selections.items[outer];

        // Go through the remaining selections and merge any that overlap with the current
        // selection.
        var inner = outer +| 1;
        while (inner < self.selections.items.len) : (inner += 1) {
            const after = self.selections.items[inner];
            if (before.hasOverlap(after)) {
                self.selections.items[outer] = .merge(before, after);
                _ = self.selections.swapRemove(inner);
                continue :outer_loop;
            }
        }

        outer += 1;
    }

    std.debug.assert(!self.hasOverlappingSelections());
}

/// Tokenizes the text.
/// TODO: Have language extensions implement this and call those functions when relevant.
fn tokenize(self: *Editor, allocator: Allocator) !void {
    self.tokens.clearRetainingCapacity();
    try self.tokens.append(allocator, .{
        .pos = .{ .row = 0, .col = 0 },
        .text = self.text.items,
        .type = .Text,
    });
}

/// Updates the indeces for the start of each line in the text.
fn updateLines(self: *Editor, allocator: Allocator) !void {
    self.line_indexes.clearRetainingCapacity();
    try self.line_indexes.append(allocator, .fromInt(0));

    // NOTE: We start counting from 1 because we consider the start of a line to be **after** a
    //       newline character, not before.
    for (self.text.items, 1..) |char, i| {
        if (char == '\n') try self.line_indexes.append(allocator, .fromInt(i));
    }
}

/// Converts the provided `Pos` object to a `CoordinatePos`.
pub fn toPos(self: *Editor, pos: IndexPos) Pos {
    // 1. Assert that the provided position is valid.

    // NOTE: The position after the last character in a file is a valid position which is why we
    //       must check for equality against the text length.
    std.debug.assert(pos.toInt() <= self.text.items.len);

    // 2. Find the row indicated by the byte-level position.

    const row: usize = row: {
        var row: usize = 0;
        for (self.line_indexes.items, 0..) |lineStartIndex, i| {
            // If we're past the provided byte-level position then we know the previous position was the
            // correct row_index.
            if (lineStartIndex.comesAfter(pos)) break :row row;
            row = i;
        }

        // If haven't found the position in the loop, we can safely use the last line.
        break :row self.line_indexes.items.len -| 1;
    };

    // 3. Use the byte-level position of the start of the row to calculate the column of the
    //    provided position.

    const startOfRowIndex: IndexPos = self.line_indexes.items[row];

    return .{ .row = row, .col = pos.toInt() -| startOfRowIndex.toInt() };
}

/// Converts the provided `CoordinatePos` object to a `Pos`.
pub fn toIndexPos(text: []const u8, pos: Pos) IndexPos {
    // 1. Assert that the provided position is valid.

    const lines = std.mem.count(u8, text, "\n") + 1;
    std.debug.assert(pos.row < lines);

    if (pos.row == 0) {
        std.debug.assert(pos.col <= text.len);
        return .fromInt(pos.col);
    }

    var line: usize = 0;
    var i: usize = 0;
    while (i < text.len) : (i += 1) {
        if (text[i] == '\n') {
            line += 1;

            if (line == pos.row) {
                std.debug.assert(i + pos.col + 1 <= text.len);
                return .fromInt(i + pos.col + 1);
            }
        }
    }

    return .fromInt(text.len);
}

/// Returns `true` if any of the current selections overlap, `false` otherwise.
fn hasOverlappingSelections(self: *const Editor) bool {
    for (0..self.selections.items.len -| 1) |i| {
        const s = self.selections.items[i];

        for (self.selections.items[i + 1 ..]) |other| {
            if (s.hasOverlap(other)) return true;
        }
    }

    return false;
}

const talloc = std.testing.allocator;

test init {
    var editor = try Editor.init(talloc);
    defer editor.deinit(talloc);
}

test toPos {
    var editor = try Editor.init(talloc);
    defer editor.deinit(talloc);

    try editor.text.appendSlice(talloc, "012\n456\n890\n");
    // Updating the lines is required to properly calculate the byte-level cursor positions.
    try editor.updateLines(talloc);

    try std.testing.expectEqual(Pos{ .row = 0, .col = 0 }, editor.toPos(.fromInt(0)));
    try std.testing.expectEqual(Pos{ .row = 0, .col = 2 }, editor.toPos(.fromInt(2)));
    try std.testing.expectEqual(Pos{ .row = 0, .col = 3 }, editor.toPos(.fromInt(3)));

    try std.testing.expectEqual(Pos{ .row = 1, .col = 0 }, editor.toPos(.fromInt(4)));
    try std.testing.expectEqual(Pos{ .row = 1, .col = 1 }, editor.toPos(.fromInt(5)));
    try std.testing.expectEqual(Pos{ .row = 1, .col = 3 }, editor.toPos(.fromInt(7)));

    try std.testing.expectEqual(Pos{ .row = 2, .col = 0 }, editor.toPos(.fromInt(8)));
    try std.testing.expectEqual(Pos{ .row = 2, .col = 2 }, editor.toPos(.fromInt(10)));
    try std.testing.expectEqual(Pos{ .row = 2, .col = 3 }, editor.toPos(.fromInt(11)));

    try std.testing.expectEqual(Pos{ .row = 3, .col = 0 }, editor.toPos(.fromInt(12)));
}

test toIndexPos {
    const text = "012\n456\n890\n";

    try std.testing.expectEqual(
        (IndexPos.fromInt(0)),
        Editor.toIndexPos(text, Pos{ .row = 0, .col = 0 }),
    );
    try std.testing.expectEqual(
        (IndexPos.fromInt(2)),
        Editor.toIndexPos(text, Pos{ .row = 0, .col = 2 }),
    );
    try std.testing.expectEqual(
        (IndexPos.fromInt(3)),
        Editor.toIndexPos(text, Pos{ .row = 0, .col = 3 }),
    );

    try std.testing.expectEqual(
        (IndexPos.fromInt(4)),
        Editor.toIndexPos(text, Pos{ .row = 1, .col = 0 }),
    );
    try std.testing.expectEqual(
        (IndexPos.fromInt(5)),
        Editor.toIndexPos(text, Pos{ .row = 1, .col = 1 }),
    );
    try std.testing.expectEqual(
        (IndexPos.fromInt(7)),
        Editor.toIndexPos(text, Pos{ .row = 1, .col = 3 }),
    );

    try std.testing.expectEqual(
        (IndexPos.fromInt(8)),
        Editor.toIndexPos(text, Pos{ .row = 2, .col = 0 }),
    );
    try std.testing.expectEqual(
        (IndexPos.fromInt(10)),
        Editor.toIndexPos(text, Pos{ .row = 2, .col = 2 }),
    );
    try std.testing.expectEqual(
        (IndexPos.fromInt(11)),
        Editor.toIndexPos(text, Pos{ .row = 2, .col = 3 }),
    );

    try std.testing.expectEqual(
        (IndexPos.fromInt(12)),
        Editor.toIndexPos(text, Pos{ .row = 3, .col = 0 }),
    );
}

test lineCount {
    var editor = try Editor.init(talloc);
    defer editor.deinit(talloc);

    try std.testing.expectEqual(1, editor.lineCount());

    try editor.text.appendSlice(talloc, "012");
    try editor.updateLines(talloc);

    try std.testing.expectEqual(1, editor.lineCount());

    try editor.text.appendSlice(talloc, "\n345\n");
    try editor.updateLines(talloc);

    try std.testing.expectEqual(3, editor.lineCount());

    try editor.text.appendSlice(talloc, "678");
    try editor.updateLines(talloc);

    try std.testing.expectEqual(3, editor.lineCount());

    try editor.text.appendSlice(talloc, "\n\n");
    try editor.updateLines(talloc);

    try std.testing.expectEqual(5, editor.lineCount());
}

test insertTextAtCursors {
    var editor: Editor = try .init(talloc);
    defer editor.deinit(talloc);

    // 1. Insertion happens at initial cursor to begin with.

    try editor.insertTextAtCursors(talloc, "hello");
    // Cursor is now at the end of the text.
    try std.testing.expectEqualStrings(
        "hello",
        editor.text.items,
    );
    try std.testing.expectEqualSlices(
        Selection,
        &.{.createCursor(.{ .row = 0, .col = 5 })},
        editor.selections.items,
    );

    // 2. Adding a cursor at the start makes insertion happen at both cursors.

    try editor.appendSelection(talloc, .init);
    try editor.insertTextAtCursors(talloc, ", world!");
    try std.testing.expectEqualStrings(
        ", world!hello, world!",
        editor.text.items,
    );
    try std.testing.expectEqualSlices(
        Selection,
        &.{
            .createCursor(.{ .row = 0, .col = 21 }),
            .createCursor(.{ .row = 0, .col = 8 }),
        },
        editor.selections.items,
    );

    // 3. Adding a selection in the middle causes text to appear in the right places.

    try editor.appendSelection(talloc, .{
        .anchor = .{ .row = 0, .col = 12 },
        .cursor = .{ .row = 0, .col = 15 },
    });
    try editor.appendSelection(talloc, .{
        .anchor = .{ .row = 0, .col = 19 },
        .cursor = .{ .row = 0, .col = 17 },
    });
    try editor.insertTextAtCursors(talloc, "abc");
    try std.testing.expectEqualStrings(
        ", world!abchello, abcwoabcrld!abc",
        editor.text.items,
    );
    try std.testing.expectEqualSlices(
        Selection,
        &.{
            .createCursor(.{ .row = 0, .col = 33 }),
            .createCursor(.{ .row = 0, .col = 11 }),
            .{ .anchor = .{ .row = 0, .col = 15 }, .cursor = .{ .row = 0, .col = 21 } },
            .{ .anchor = .{ .row = 0, .col = 28 }, .cursor = .{ .row = 0, .col = 26 } },
        },
        editor.selections.items,
    );

    // Reset.
    editor.deinit(talloc);
    editor = try .init(talloc);

    // 4. New lines handled correctly.

    try editor.insertTextAtCursors(talloc, "\n");
    try std.testing.expectEqualStrings(
        "\n",
        editor.text.items,
    );
    try std.testing.expectEqualSlices(
        Selection,
        &.{.createCursor(.{ .row = 1, .col = 0 })},
        editor.selections.items,
    );

    try editor.insertTextAtCursors(talloc, "\n");
    try std.testing.expectEqualStrings(
        "\n\n",
        editor.text.items,
    );
    try std.testing.expectEqualSlices(
        Selection,
        &.{.createCursor(.{ .row = 2, .col = 0 })},
        editor.selections.items,
    );

    try editor.insertTextAtCursors(talloc, "a\n");
    try std.testing.expectEqualStrings(
        "\n\na\n",
        editor.text.items,
    );
    try std.testing.expectEqualSlices(
        Selection,
        &.{.createCursor(.{ .row = 3, .col = 0 })},
        editor.selections.items,
    );

    try editor.insertTextAtCursors(talloc, "\n\n\n");
    try std.testing.expectEqualStrings(
        "\n\na\n\n\n\n",
        editor.text.items,
    );
    try std.testing.expectEqualSlices(
        Selection,
        &.{.createCursor(.{ .row = 6, .col = 0 })},
        editor.selections.items,
    );
}

test appendSelection {
    var editor = try Editor.init(talloc);
    defer editor.deinit(talloc);

    editor.selections.clearRetainingCapacity();

    // 1. Inserting a selection that would cause an existing selection to expand into a different,
    //    pre-existing selection should merge all selections.

    // 1 | 01^2|345^67|89
    //          ^       ^  insertion
    // Result:
    //
    // 1 | 01^2345678|9

    try editor.appendSelection(
        talloc,
        .{ .anchor = .{ .row = 0, .col = 2 }, .cursor = .{ .row = 0, .col = 3 } },
    );
    try editor.appendSelection(
        talloc,
        .{ .anchor = .{ .row = 0, .col = 6 }, .cursor = .{ .row = 0, .col = 8 } },
    );

    try std.testing.expect(!editor.hasOverlappingSelections());

    try editor.appendSelection(talloc, .{
        .anchor = .{ .row = 0, .col = 3 },
        .cursor = .{ .row = 0, .col = 9 },
    });

    try std.testing.expect(!editor.hasOverlappingSelections());
    try std.testing.expectEqualSlices(
        Selection,
        &.{.{ .anchor = .{ .row = 0, .col = 2 }, .cursor = .{ .row = 0, .col = 9 } }},
        editor.selections.items,
    );

    editor.selections.clearRetainingCapacity();

    // 1 | 01^2|345^67|89
    //               ^  ^  insertion
    // Result:
    //
    // 1 | 01^2|345^678|9

    try editor.appendSelection(talloc, .{
        .anchor = .{ .row = 0, .col = 2 },
        .cursor = .{ .row = 0, .col = 3 },
    });
    try editor.appendSelection(talloc, .{
        .anchor = .{ .row = 0, .col = 6 },
        .cursor = .{ .row = 0, .col = 8 },
    });

    try std.testing.expect(!editor.hasOverlappingSelections());

    try editor.appendSelection(talloc, .{
        .anchor = .{ .row = 0, .col = 7 },
        .cursor = .{ .row = 0, .col = 9 },
    });

    try std.testing.expect(!editor.hasOverlappingSelections());
    try std.testing.expectEqualSlices(
        Selection,
        &.{
            .{ .anchor = .{ .row = 0, .col = 2 }, .cursor = .{ .row = 0, .col = 3 } },
            .{ .anchor = .{ .row = 0, .col = 6 }, .cursor = .{ .row = 0, .col = 9 } },
        },
        editor.selections.items,
    );
}

fn testOnly_resetEditor(editor: *Editor, allocator: Allocator) !void {
    editor.text.clearRetainingCapacity();
    try editor.text.appendSlice(allocator, "012\n456\n890\n");
    try editor.updateLines(allocator);
    editor.selections.clearRetainingCapacity();
}

test deleteCharacterBeforeCursors {
    var editor = try Editor.init(talloc);
    defer editor.deinit(talloc);

    try testOnly_resetEditor(&editor, talloc);

    // Legend for selections:
    //  * A cursor (0-width selection): +
    //  * Anchor of a selection: ^
    //  * Cursor of a selection: |

    // == Cursors == //

    // 1. Deleting from the first position is a noop.

    // Before:
    //
    // 1 | +012
    // 2 | 456
    // 3 | 890
    // 4 |
    //
    // After:
    //
    // 1 | +012
    // 2 | 456
    // 3 | 890
    // 4 |

    try editor.selections.append(talloc, .init);

    try editor.deleteCharacterBeforeCursors(talloc);

    try std.testing.expectEqualStrings("012\n456\n890\n", editor.text.items);
    try std.testing.expectEqualSlices(
        Selection,
        &.{.init},
        editor.selections.items,
    );

    try testOnly_resetEditor(&editor, talloc);

    // 2. Deleting from the back deletes the last character.

    // Before:
    //
    // 1 | 012
    // 2 | 456
    // 3 | 890
    // 4 | +
    //
    // After:
    //
    // 1 | 012
    // 2 | 456
    // 3 | 890+

    try editor.selections.append(talloc, .createCursor(.{ .row = 3, .col = 0 }));

    try editor.deleteCharacterBeforeCursors(talloc);

    try std.testing.expectEqualStrings("012\n456\n890", editor.text.items);
    try std.testing.expect(3 == editor.lineCount());
    try std.testing.expectEqualSlices(
        Selection,
        &.{.createCursor(.{ .row = 2, .col = 3 })},
        editor.selections.items,
    );

    try testOnly_resetEditor(&editor, talloc);

    // 3. Deleting the first character only deletes the first character.

    // Before:
    //
    // 1 | 0+12
    // 2 | 456
    // 3 | 890
    // 4 |
    //
    // After:
    //
    // 1 | +12
    // 2 | 456
    // 3 | 890
    // 4 |

    try editor.selections.append(talloc, .createCursor(.{ .row = 0, .col = 1 }));

    try editor.deleteCharacterBeforeCursors(talloc);

    try std.testing.expectEqualStrings("12\n456\n890\n", editor.text.items);
    try std.testing.expectEqualSlices(
        Selection,
        &.{.init},
        editor.selections.items,
    );

    try testOnly_resetEditor(&editor, talloc);

    // 4. Deleting in multiple places.

    // Before:
    //
    // 1 | 012+
    // 2 | 456
    // 3 | +890
    // 4 |
    //
    // After:
    //
    // 1 | 01+
    // 2 | 456+890
    // 3 |

    try editor.selections.append(talloc, .createCursor(.{ .row = 0, .col = 3 }));
    try editor.selections.append(talloc, .createCursor(.{ .row = 2, .col = 0 }));

    try editor.deleteCharacterBeforeCursors(talloc);

    try std.testing.expectEqualStrings("01\n456890\n", editor.text.items);
    try std.testing.expectEqualSlices(
        Selection,
        &.{
            .createCursor(.{ .row = 0, .col = 2 }),
            .createCursor(.{ .row = 1, .col = 3 }),
        },
        editor.selections.items,
    );

    try testOnly_resetEditor(&editor, talloc);

    // 5. Cursors should merge when they reach the start of the file.

    // Before:
    //
    // 1 | 0+1+2
    // 2 | 456
    // 3 | 890
    // 4 |
    //
    // After:
    //
    // 1 | +2
    // 2 | 456
    // 3 | 890
    // 4 |

    try editor.selections.append(talloc, .createCursor(.{ .row = 0, .col = 1 }));
    try editor.selections.append(talloc, .createCursor(.{ .row = 0, .col = 2 }));

    try editor.deleteCharacterBeforeCursors(talloc);

    try std.testing.expectEqualStrings("2\n456\n890\n", editor.text.items);
    try std.testing.expectEqualSlices(
        Selection,
        &.{.init},
        editor.selections.items,
    );

    try testOnly_resetEditor(&editor, talloc);

    // Before:
    //
    // 1 | 0+12+
    // 2 | 456
    // 3 | 890
    // 4 |
    //
    // After:
    //
    // 1 | +1+
    // 2 | 456
    // 3 | 890
    // 4 |

    try editor.selections.append(talloc, .createCursor(.{ .row = 0, .col = 1 }));
    try editor.selections.append(talloc, .createCursor(.{ .row = 0, .col = 3 }));

    try editor.deleteCharacterBeforeCursors(talloc);

    try std.testing.expectEqualStrings("1\n456\n890\n", editor.text.items);
    try std.testing.expectEqualSlices(
        Selection,
        &.{
            .init,
            .createCursor(.{ .row = 0, .col = 1 }),
        },
        editor.selections.items,
    );

    // Before:
    //
    // 1 | +1+
    // 2 | 456
    // 3 | 890
    // 4 |
    //
    // After:
    //
    // 1 | +
    // 2 | 456
    // 3 | 890
    // 4 |

    try editor.deleteCharacterBeforeCursors(talloc);

    try std.testing.expectEqualStrings("\n456\n890\n", editor.text.items);
    try std.testing.expectEqualSlices(
        Selection,
        &.{.init},
        editor.selections.items,
    );

    try testOnly_resetEditor(&editor, talloc);

    // 6. Cursors should merge when they reach the same index after a deletion.

    // Before:
    //
    // 1 | 01+2+
    // 2 | 45+6
    // 3 | 890
    // 4 |
    //
    // After:
    //
    // 1 | 0+
    // 2 | 4+6
    // 3 | 890
    // 4 |

    try editor.selections.append(talloc, .createCursor(.{ .row = 0, .col = 2 }));
    try editor.selections.append(talloc, .createCursor(.{ .row = 0, .col = 3 }));
    try editor.selections.append(talloc, .createCursor(.{ .row = 1, .col = 2 }));

    try editor.deleteCharacterBeforeCursors(talloc);

    try std.testing.expectEqualStrings("0\n46\n890\n", editor.text.items);
    try std.testing.expectEqualSlices(
        Selection,
        &.{
            .createCursor(.{ .row = 0, .col = 1 }),
            .createCursor(.{ .row = 1, .col = 1 }),
        },
        editor.selections.items,
    );

    try testOnly_resetEditor(&editor, talloc);

    // Same test, but the selections appear in a different order.

    try editor.selections.append(talloc, .createCursor(.{ .row = 0, .col = 2 }));
    try editor.selections.append(talloc, .createCursor(.{ .row = 1, .col = 2 }));
    try editor.selections.append(talloc, .createCursor(.{ .row = 0, .col = 3 }));

    try editor.deleteCharacterBeforeCursors(talloc);

    try std.testing.expectEqualStrings("0\n46\n890\n", editor.text.items);
    try std.testing.expectEqualSlices(
        Selection,
        &.{
            .createCursor(.{ .row = 0, .col = 1 }),
            .createCursor(.{ .row = 1, .col = 1 }),
        },
        editor.selections.items,
    );

    try testOnly_resetEditor(&editor, talloc);

    // Same test, but the selections appear in a different order.

    try editor.selections.append(talloc, .createCursor(.{ .row = 1, .col = 2 }));
    try editor.selections.append(talloc, .createCursor(.{ .row = 0, .col = 3 }));
    try editor.selections.append(talloc, .createCursor(.{ .row = 0, .col = 2 }));

    try editor.deleteCharacterBeforeCursors(talloc);

    try std.testing.expectEqualStrings("0\n46\n890\n", editor.text.items);
    try std.testing.expectEqualSlices(
        Selection,
        &.{
            .createCursor(.{ .row = 1, .col = 1 }),
            .createCursor(.{ .row = 0, .col = 1 }),
        },
        editor.selections.items,
    );

    try testOnly_resetEditor(&editor, talloc);

    // Same test, but the selections appear in a different order.

    try editor.selections.append(talloc, .createCursor(.{ .row = 1, .col = 2 }));
    try editor.selections.append(talloc, .createCursor(.{ .row = 0, .col = 2 }));
    try editor.selections.append(talloc, .createCursor(.{ .row = 0, .col = 3 }));

    try editor.deleteCharacterBeforeCursors(talloc);

    try std.testing.expectEqualStrings("0\n46\n890\n", editor.text.items);
    try std.testing.expectEqualSlices(
        Selection,
        &.{
            .createCursor(.{ .row = 1, .col = 1 }),
            .createCursor(.{ .row = 0, .col = 1 }),
        },
        editor.selections.items,
    );

    try testOnly_resetEditor(&editor, talloc);

    // Same test, but the selections appear in a different order.

    try editor.selections.append(talloc, .createCursor(.{ .row = 0, .col = 2 }));
    try editor.selections.append(talloc, .createCursor(.{ .row = 0, .col = 3 }));
    try editor.selections.append(talloc, .createCursor(.{ .row = 1, .col = 2 }));

    try editor.deleteCharacterBeforeCursors(talloc);

    try std.testing.expectEqualStrings("0\n46\n890\n", editor.text.items);
    try std.testing.expectEqualSlices(
        Selection,
        &.{
            .createCursor(.{ .row = 0, .col = 1 }),
            .createCursor(.{ .row = 1, .col = 1 }),
        },
        editor.selections.items,
    );

    try testOnly_resetEditor(&editor, talloc);

    // == Selections == //

    // 6. Deleting when the cursor comes after the anchor should shrink the selection.

    // Before:
    //
    // 1 | 01^2
    // 2 | 456|
    // 3 | 890
    // 4 |
    //
    // After:
    //
    // 1 | 01^2
    // 2 | 45|
    // 3 | 890
    // 4 |

    try editor.selections.append(talloc, .{
        .anchor = .{ .row = 0, .col = 2 },
        .cursor = .{ .row = 1, .col = 3 },
    });

    try editor.deleteCharacterBeforeCursors(talloc);

    try std.testing.expectEqualStrings("012\n45\n890\n", editor.text.items);
    try std.testing.expectEqualSlices(
        Selection,
        &.{
            .{ .anchor = .{ .row = 0, .col = 2 }, .cursor = .{ .row = 1, .col = 2 } },
        },
        editor.selections.items,
    );

    try testOnly_resetEditor(&editor, talloc);

    // 7. Shrinking a selection to a cursor should make that selection a cursor.

    // Before:
    //
    // 1 | 01^2|
    // 2 | 456
    // 3 | 890
    // 4 |
    //
    // After:
    //
    // 1 | 01+
    // 2 | 456
    // 3 | 890
    // 4 |

    try editor.selections.append(talloc, .{
        .anchor = .{ .row = 0, .col = 2 },
        .cursor = .{ .row = 0, .col = 3 },
    });

    try editor.deleteCharacterBeforeCursors(talloc);

    try std.testing.expectEqualStrings("01\n456\n890\n", editor.text.items);
    try std.testing.expectEqual(1, editor.selections.items.len);
    try std.testing.expect(editor.selections.items[0].isCursor());
    try std.testing.expectEqualSlices(
        Selection,
        &.{
            .createCursor(.{ .row = 0, .col = 2 }),
        },
        editor.selections.items,
    );

    try testOnly_resetEditor(&editor, talloc);

    // 8. Selections are moved correctly after deletion even if they're out of order in the
    //    selections array.

    // Before:
    //
    // 1 | 01^2|
    // 2 | 4^56|
    // 3 | ^8|90
    // 4 |
    //
    // After:
    //
    // 1 | 01+
    // 2 | 4^5|
    // 3 | +90
    // 4 |

    try editor.selections.append(talloc, .{
        .anchor = .{ .row = 0, .col = 2 },
        .cursor = .{ .row = 0, .col = 3 },
    });
    try editor.selections.append(talloc, .{
        .anchor = .{ .row = 1, .col = 1 },
        .cursor = .{ .row = 1, .col = 3 },
    });
    try editor.selections.append(talloc, .{
        .anchor = .{ .row = 2, .col = 0 },
        .cursor = .{ .row = 2, .col = 1 },
    });

    try editor.deleteCharacterBeforeCursors(talloc);

    try std.testing.expectEqualStrings("01\n45\n90\n", editor.text.items);
    try std.testing.expectEqualSlices(
        Selection,
        &.{
            .createCursor(.{ .row = 0, .col = 2 }),
            .{ .anchor = .{ .row = 1, .col = 1 }, .cursor = .{ .row = 1, .col = 2 } },
            .createCursor(.{ .row = 2, .col = 0 }),
        },
        editor.selections.items,
    );

    try testOnly_resetEditor(&editor, talloc);

    // Same test, selections in a different order.

    try editor.selections.append(talloc, .{
        .anchor = .{ .row = 1, .col = 1 },
        .cursor = .{ .row = 1, .col = 3 },
    });
    try editor.selections.append(talloc, .{
        .anchor = .{ .row = 0, .col = 2 },
        .cursor = .{ .row = 0, .col = 3 },
    });
    try editor.selections.append(talloc, .{
        .anchor = .{ .row = 2, .col = 0 },
        .cursor = .{ .row = 2, .col = 1 },
    });

    try editor.deleteCharacterBeforeCursors(talloc);

    try std.testing.expectEqualStrings("01\n45\n90\n", editor.text.items);
    try std.testing.expectEqualSlices(
        Selection,
        &.{
            .{ .anchor = .{ .row = 1, .col = 1 }, .cursor = .{ .row = 1, .col = 2 } },
            .createCursor(.{ .row = 0, .col = 2 }),
            .createCursor(.{ .row = 2, .col = 0 }),
        },
        editor.selections.items,
    );

    try testOnly_resetEditor(&editor, talloc);

    // Same test, selections in a different order.

    try editor.selections.append(talloc, .{
        .anchor = .{ .row = 2, .col = 0 },
        .cursor = .{ .row = 2, .col = 1 },
    });
    try editor.selections.append(talloc, .{
        .anchor = .{ .row = 0, .col = 2 },
        .cursor = .{ .row = 0, .col = 3 },
    });
    try editor.selections.append(talloc, .{
        .anchor = .{ .row = 1, .col = 1 },
        .cursor = .{ .row = 1, .col = 3 },
    });

    try editor.deleteCharacterBeforeCursors(talloc);

    try std.testing.expectEqualStrings("01\n45\n90\n", editor.text.items);
    try std.testing.expectEqualSlices(
        Selection,
        &.{
            .createCursor(.{ .row = 2, .col = 0 }),
            .createCursor(.{ .row = 0, .col = 2 }),
            .{ .anchor = .{ .row = 1, .col = 1 }, .cursor = .{ .row = 1, .col = 2 } },
        },
        editor.selections.items,
    );

    try testOnly_resetEditor(&editor, talloc);

    // 9. Deleting from side-by-side selections where the anchor from one touches the cursor from
    //    the other.

    // Before:
    //
    // 1 | 0^1|^2|
    // 2 | 456
    // 3 | 890
    // 4 |
    //
    // After:
    //
    // 1 | 0+
    // 2 | 456
    // 3 | 890
    // 4 |

    try editor.selections.append(
        talloc,
        .{
            .anchor = .{ .row = 0, .col = 1 },
            .cursor = .{ .row = 0, .col = 2 },
        },
    );
    try editor.selections.append(
        talloc,
        .{
            .anchor = .{ .row = 0, .col = 2 },
            .cursor = .{ .row = 0, .col = 3 },
        },
    );

    try editor.deleteCharacterBeforeCursors(talloc);

    try std.testing.expectEqualStrings("0\n456\n890\n", editor.text.items);
    try std.testing.expectEqualSlices(
        Selection,
        &.{
            .createCursor(.{ .row = 0, .col = 1 }),
        },
        editor.selections.items,
    );

    try testOnly_resetEditor(&editor, talloc);

    // Before:
    //
    // 1 | ^01|^2
    // 2 | |456
    // 3 | 890
    // 4 |
    //
    // After:
    //
    // 1 | ^0|^2|456
    // 2 | 890
    // 3 |

    try editor.selections.append(talloc, .{
        .anchor = .init,
        .cursor = .{ .row = 0, .col = 2 },
    });
    try editor.selections.append(talloc, .{
        .anchor = .{ .row = 0, .col = 2 },
        .cursor = .{ .row = 1, .col = 0 },
    });

    try editor.deleteCharacterBeforeCursors(talloc);

    try std.testing.expectEqualStrings("02456\n890\n", editor.text.items);
    try std.testing.expectEqualSlices(
        Selection,
        &.{
            .{ .anchor = .init, .cursor = .{ .row = 0, .col = 1 } },
            .{ .anchor = .{ .row = 0, .col = 1 }, .cursor = .{ .row = 0, .col = 2 } },
        },
        editor.selections.items,
    );

    try testOnly_resetEditor(&editor, talloc);

    // 10. Deleting from side-by-side selections where the anchors are touching.

    // Before:
    //
    // 1 | 01|2^^
    // 2 | |456
    // 3 | 890
    // 4 |
    //
    // 1 | 0|2^+456
    // 2 | 890
    // 4 |

    try editor.selections.append(talloc, .{
        .anchor = .{ .row = 0, .col = 3 },
        .cursor = .{ .row = 0, .col = 2 },
    });
    try editor.selections.append(talloc, .{
        .anchor = .{ .row = 0, .col = 3 },
        .cursor = .{ .row = 1, .col = 0 },
    });

    try editor.deleteCharacterBeforeCursors(talloc);

    try std.testing.expectEqualStrings("02456\n890\n", editor.text.items);
    try std.testing.expectEqualSlices(
        Selection,
        &.{
            .{ .anchor = .{ .row = 0, .col = 2 }, .cursor = .{ .row = 0, .col = 1 } },
            .createCursor(.{ .row = 0, .col = 2 }),
        },
        editor.selections.items,
    );

    try testOnly_resetEditor(&editor, talloc);

    // Before:
    //
    // 1 | 01|2^^
    // 2 | 4|56
    // 3 | 890
    // 4 |
    //
    // After:
    //
    // 1 | 0|2^^
    // 2 | |56
    // 2 | 890
    // 4 |

    try editor.selections.append(talloc, .{
        .anchor = .{ .row = 0, .col = 3 },
        .cursor = .{ .row = 0, .col = 2 },
    });
    try editor.selections.append(talloc, .{
        .anchor = .{ .row = 0, .col = 3 },
        .cursor = .{ .row = 1, .col = 1 },
    });

    try editor.deleteCharacterBeforeCursors(talloc);

    try std.testing.expectEqualStrings("02\n56\n890\n", editor.text.items);
    try std.testing.expectEqualSlices(
        Selection,
        &.{
            .{ .anchor = .{ .row = 0, .col = 2 }, .cursor = .{ .row = 0, .col = 1 } },
            .{ .anchor = .{ .row = 0, .col = 2 }, .cursor = .{ .row = 1, .col = 0 } },
        },
        editor.selections.items,
    );

    try testOnly_resetEditor(&editor, talloc);

    // 11. Deleting from side-by-side selections where the cursors are touching; cursors are
    //     considered as a single cursor.

    // Before:
    //
    // 1 | 01^2||
    // 2 | ^456
    // 3 | 890
    // 4 |
    //
    // After:
    //
    // 1 | 01+|
    // 2 | ^456
    // 3 | 890
    // 4 |
    //
    // FIXME: I think the selections should be merged here because one of the selections has been
    //        reduced to just the cursor.

    try editor.selections.append(talloc, .{
        .anchor = .{ .row = 0, .col = 2 },
        .cursor = .{ .row = 0, .col = 3 },
    });
    try editor.selections.append(talloc, .{
        .anchor = .{ .row = 1, .col = 0 },
        .cursor = .{ .row = 0, .col = 3 },
    });

    try editor.deleteCharacterBeforeCursors(talloc);

    try std.testing.expectEqualStrings("01\n456\n890\n", editor.text.items);
    try std.testing.expectEqualSlices(
        Selection,
        &.{
            .createCursor(.{ .row = 0, .col = 2 }),
            .{ .anchor = .{ .row = 1, .col = 0 }, .cursor = .{ .row = 0, .col = 2 } },
        },
        editor.selections.items,
    );

    try testOnly_resetEditor(&editor, talloc);

    // 12. Selections collapse into cursor when they become equal after a deletion.

    // Before:
    //
    // 1 | 0^1|^2|
    // 2 | 4^5|6
    // 3 | 890
    // 4 |
    //
    // After:
    //
    // 1 | 0+
    // 2 | 4+6
    // 3 | 890
    // 4 |

    try editor.selections.append(talloc, .{
        .anchor = .{ .row = 0, .col = 1 },
        .cursor = .{ .row = 0, .col = 2 },
    });
    try editor.selections.append(talloc, .{
        .anchor = .{ .row = 0, .col = 2 },
        .cursor = .{ .row = 0, .col = 3 },
    });
    try editor.selections.append(talloc, .{
        .anchor = .{ .row = 1, .col = 1 },
        .cursor = .{ .row = 1, .col = 2 },
    });

    try editor.deleteCharacterBeforeCursors(talloc);

    try std.testing.expectEqualStrings("0\n46\n890\n", editor.text.items);
    try std.testing.expectEqualSlices(
        Selection,
        &.{
            .createCursor(.{ .row = 0, .col = 1 }),
            .createCursor(.{ .row = 1, .col = 1 }),
        },
        editor.selections.items,
    );

    try testOnly_resetEditor(&editor, talloc);

    // == Mix between cursors and selections == //

    // Do this later if needed.
}

test tokenize {
    var editor = try Editor.init(talloc);
    defer editor.deinit(talloc);

    // 1. Empty text.

    try editor.tokenize(talloc);

    try std.testing.expectEqualSlices(
        Token,
        &.{
            .{ .pos = .init, .text = &.{}, .type = .Text },
        },
        editor.tokens.items,
    );

    // 2. Some text.

    try editor.text.appendSlice(talloc, "lorem ipsum\n");
    try editor.tokenize(talloc);

    try std.testing.expectEqual(1, editor.tokens.items.len);

    const token = editor.tokens.items[0];

    try std.testing.expectEqual(Editor.TokenType.Text, token.type);
    try std.testing.expectEqual(Pos.init, token.pos);
    try std.testing.expectEqualStrings("lorem ipsum\n", token.text);
}

test updateLines {
    var editor = try Editor.init(talloc);
    defer editor.deinit(talloc);

    // 1. Empty text.

    try editor.updateLines(talloc);

    // We should always have at least one line.
    try std.testing.expectEqual(1, editor.line_indexes.items.len);
    try std.testing.expectEqualSlices(
        IndexPos,
        &.{.fromInt(0)},
        editor.line_indexes.items,
    );

    // 2. One line.

    try editor.text.appendSlice(talloc, "012");
    try editor.updateLines(talloc);

    try std.testing.expectEqualSlices(
        IndexPos,
        &.{.fromInt(0)},
        editor.line_indexes.items,
    );

    editor.text.clearRetainingCapacity();

    // 3. One line, ends with a new line.

    try editor.text.appendSlice(talloc, "012\n");
    try editor.updateLines(talloc);

    try std.testing.expectEqualSlices(
        IndexPos,
        &.{ .fromInt(0), .fromInt(4) },
        editor.line_indexes.items,
    );

    editor.text.clearRetainingCapacity();

    // 4. Multiple lines.

    try editor.text.appendSlice(talloc, "012\n456\n890");
    try editor.updateLines(talloc);

    try std.testing.expectEqualSlices(
        IndexPos,
        &.{ .fromInt(0), .fromInt(4), .fromInt(8) },
        editor.line_indexes.items,
    );

    editor.text.clearRetainingCapacity();

    // 5. Multiple lines, ends with a new line.

    try editor.text.appendSlice(talloc, "012\n456\n890\n");
    try editor.updateLines(talloc);

    try std.testing.expectEqualSlices(
        IndexPos,
        &.{ .fromInt(0), .fromInt(4), .fromInt(8), .fromInt(12) },
        editor.line_indexes.items,
    );

    editor.text.clearRetainingCapacity();

    // 6. Multiple new lines in a row.

    try editor.text.appendSlice(talloc, "012\n\n\n67\n\n0");
    try editor.updateLines(talloc);

    try std.testing.expectEqualSlices(
        IndexPos,
        &.{ .fromInt(0), .fromInt(4), .fromInt(5), .fromInt(6), .fromInt(9), .fromInt(10) },
        editor.line_indexes.items,
    );
}

test "getLine" {
    var editor = try Editor.init(talloc);
    defer editor.deinit(talloc);

    try editor.text.appendSlice(talloc, "012\n345\n456\n\n");
    try editor.updateLines(talloc);

    try std.testing.expectEqualStrings(
        "012\n",
        editor.getLine(0),
    );
    try std.testing.expectEqualStrings(
        "345\n",
        editor.getLine(1),
    );
    try std.testing.expectEqualStrings(
        "456\n",
        editor.getLine(2),
    );
    try std.testing.expectEqualStrings(
        "\n",
        editor.getLine(3),
    );
    try std.testing.expectEqualStrings(
        "",
        editor.getLine(4),
    );
}

test "refAllDecls" {
    std.testing.refAllDecls(@This());
}
