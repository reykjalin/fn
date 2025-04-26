//! Managed editor object for a single file. **All properties are considered private after
//! initialization. Modifying them will result in undefined behavior.** Use the helper methods
//! instead of modifying properties directly.

const std = @import("std");

const Pos = @import("pos.zig").Pos;
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
line_indexes: std.ArrayListUnmanaged(Pos),
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
    try selections.append(allocator, .{ .anchor = .fromInt(0), .cursor = .fromInt(0) });

    var lines: std.ArrayListUnmanaged(Pos) = .empty;
    try lines.append(allocator, .fromInt(0));

    var tokens: std.ArrayListUnmanaged(Token) = .empty;
    try tokens.append(allocator, .{ .pos = .fromInt(0), .text = "", .type = .Text });

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
    // 1. Open the file for reading.

    const file = try std.fs.cwd().openFile(filename, .{ .mode = .read_only });
    defer file.close();

    // 2. Get a reader to read the file.

    var buf_reader = std.io.bufferedReader(file.reader());
    const reader = buf_reader.reader();

    // 3. Read the file and store in state.

    const contents = try reader.readAllAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(contents);

    self.text.clearRetainingCapacity();
    try self.text.appendSlice(allocator, contents);

    // 4. Only after the file has been successfully read do we update file name and other state.

    self.filename.clearRetainingCapacity();
    try self.filename.appendSlice(allocator, filename);

    // 5. Update line start array.

    try self.updateLines(allocator);

    // 6. Tokenize the new text.

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
    _ = self;
    // TODO: implement.
}

/// Moves each selection down one line. Selections will be collapsed to the cursor before they're
/// moved.
pub fn moveSelectionsDown(self: *Editor) void {
    _ = self;
    // TODO: implement.
}

/// Moves each selection left one character. Selections will be collapsed to the cursor before
/// they're moved.
pub fn moveSelectionsLeft(self: *Editor) void {
    _ = self;
    // TODO: implement.
}

/// Moves each selection right one character. Selections will be collapsed to the cursor before
/// they're moved.
pub fn moveSelectionsRight(self: *Editor) void {
    _ = self;
    // TODO: implement.
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
pub fn getLine(self: *const Editor, line: usize) []const u8 {
    std.debug.assert(line < self.line_indexes.items.len);

    const start_idx = self.line_indexes.items[line].toInt();
    const end_idx = if (line < self.line_indexes.items.len -| 1)
        self.line_indexes.items[line + 1].toInt() -| 1
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

    var cursors: std.ArrayListUnmanaged(Pos) = .empty;
    defer cursors.deinit(allocator);

    for (self.selections.items) |selection| {
        var shouldAppend = true;

        // We make sure we only add one of each cursor position to make sure selections where the
        // cursors are touching don't cause 2 deletes.
        for (cursors.items) |cursor| {
            if (cursor == selection.cursor) {
                shouldAppend = false;
                break;
            }
        }

        if (shouldAppend) try cursors.append(allocator, selection.cursor);
    }

    // 2. The selections aren't guaranteed to be in order, so we sort them and make sure we delete
    //    from the back of the text first. That way we don't have to update all the cursors after
    //    each deletion.

    std.mem.sort(Pos, cursors.items, {}, Pos.lessThan);
    std.mem.reverse(Pos, cursors.items);

    // 3. Delete character before each cursor.

    for (cursors.items) |cursor| {
        // We can't delete before the first character in the file, so that's a noop.
        if (cursor.toInt() == 0) continue;

        _ = self.text.orderedRemove(cursor.toInt() - 1);
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
            // FIXME: selections should have equality methods so you don't have to convert to
            //        ranges.
            if (current.strictEql(other)) continue;

            // We move the cursor 1 additional character for every cursor that comes before it.
            if (other.cursor.comesBefore(current.cursor)) movement += 1;
        }

        try orderMap.append(allocator, movement);
    }

    // Need to move the cursors. Since each selection will have resulted in a deleted character we
    // need to move each cursor back equal to it's position in the file.
    for (self.selections.items, orderMap.items) |*selection, movement| {
        if (selection.isCursor()) {
            // FIXME: Make this unicode-aware.
            selection.cursor = .fromInt(selection.cursor.toInt() -| movement);
            selection.anchor = selection.cursor;
            continue;
        }

        // Move both by `movement` if the cursor comes before the anchor in the selection.
        // Otherwise move just the cursor.
        if (selection.cursor.comesBefore(selection.anchor)) {
            // FIXME: Make this unicode-aware.
            selection.cursor = .fromInt(selection.cursor.toInt() -| movement);
            selection.anchor = .fromInt(selection.anchor.toInt() -| movement);
        } else {
            // FIXME: Make this unicode-aware.
            selection.cursor = .fromInt(selection.cursor.toInt() -| movement);

            const is_first_selection_in_file = movement == 1;

            // Anything but the first selection has to move both the anchor and the cursor.
            if (!is_first_selection_in_file) {
                // Since the anchor comes before the cursor in this case we can't include the
                // shift generated by removing the character before the cursor in this selection,
                // so we subtract 1 from the movement.
                // FIXME: Make this unicode aware.
                const anchor_movement = movement -| 1;
                selection.anchor = .fromInt(selection.anchor.toInt() -| anchor_movement);
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
    _ = self;
    _ = allocator;
    _ = text;

    // TODO: implement.
}

/// Inserts the provided text before all selections. Selections will not be cleared, and will
/// instead move with the content such that they will still select the same text.
pub fn insertTextBeforeSelection(self: *Editor, allocator: Allocator, text: []const u8) !void {
    _ = self;
    _ = text;
    _ = allocator;

    // TODO: implement.
}

/// Inserts the provided text after all selections. Selections will not be cleared. The inserted
/// text will instead be appended to the end of each selection.
pub fn insertTextAfterSelection(self: *Editor, allocator: Allocator, text: []const u8) !void {
    _ = self;
    _ = text;
    _ = allocator;

    // TODO: implement.
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
}

/// Tokenizes the text.
/// TODO: Have language extensions implement this and call those functions when relevant.
fn tokenize(self: *Editor, allocator: Allocator) !void {
    self.tokens.clearRetainingCapacity();
    try self.tokens.append(allocator, .{
        .pos = .fromInt(0),
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
pub fn toCoordinatePos(self: *Editor, pos: Pos) CoordinatePos {
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

    const startOfRowIndex: Pos = self.line_indexes.items[row];

    return .{ .row = row, .col = pos.toInt() -| startOfRowIndex.toInt() };
}

/// Returns `true` if any of the current selections overlap, `false` otherwise.
fn hasValidSelections(self: *const Editor) bool {
    for (self.selections.items, 0..) |selection, current_idx| {
        var i = current_idx +| 1;
        while (i < self.selections.items.len) : (i += 1) {
            if (selection.hasOverlap(self.selections.items[i])) return true;
        }
    }

    return false;
}

const talloc = std.testing.allocator;

test toCoordinatePos {
    var editor = try Editor.init(talloc);
    defer editor.deinit(talloc);

    try editor.text.appendSlice(talloc, "012\n456\n890\n");
    // Updating the lines is required to properly calculate the byte-level cursor positions.
    try editor.updateLines(talloc);

    try std.testing.expectEqual(CoordinatePos{ .row = 0, .col = 0 }, editor.toCoordinatePos(.fromInt(0)));
    try std.testing.expectEqual(CoordinatePos{ .row = 0, .col = 2 }, editor.toCoordinatePos(.fromInt(2)));
    try std.testing.expectEqual(CoordinatePos{ .row = 0, .col = 3 }, editor.toCoordinatePos(.fromInt(3)));

    try std.testing.expectEqual(CoordinatePos{ .row = 1, .col = 0 }, editor.toCoordinatePos(.fromInt(4)));
    try std.testing.expectEqual(CoordinatePos{ .row = 1, .col = 1 }, editor.toCoordinatePos(.fromInt(5)));
    try std.testing.expectEqual(CoordinatePos{ .row = 1, .col = 3 }, editor.toCoordinatePos(.fromInt(7)));

    try std.testing.expectEqual(CoordinatePos{ .row = 2, .col = 0 }, editor.toCoordinatePos(.fromInt(8)));
    try std.testing.expectEqual(CoordinatePos{ .row = 2, .col = 2 }, editor.toCoordinatePos(.fromInt(10)));
    try std.testing.expectEqual(CoordinatePos{ .row = 2, .col = 3 }, editor.toCoordinatePos(.fromInt(11)));

    try std.testing.expectEqual(CoordinatePos{ .row = 3, .col = 0 }, editor.toCoordinatePos(.fromInt(12)));
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

test insertTextBeforeSelection {
    var editor = try Editor.init(talloc);
    defer editor.deinit(talloc);

    // 1. Insertion without new line.

    try editor.insertTextBeforeSelection(talloc, "lorem ipsum");

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
    var editor = try Editor.init(talloc);
    defer editor.deinit(talloc);

    // 1. Insertion without new line.

    try editor.insertTextAfterSelection(talloc, "lorem ipsum");

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

    try editor.appendSelection(talloc, .{ .anchor = .fromInt(2), .cursor = .fromInt(3) });
    try editor.appendSelection(talloc, .{ .anchor = .fromInt(6), .cursor = .fromInt(8) });

    try std.testing.expect(!editor.hasValidSelections());

    try editor.appendSelection(talloc, .{ .anchor = .fromInt(3), .cursor = .fromInt(9) });

    try std.testing.expect(!editor.hasValidSelections());
    try std.testing.expectEqualSlices(
        Selection,
        &.{.{ .anchor = .fromInt(2), .cursor = .fromInt(9) }},
        editor.selections.items,
    );

    editor.selections.clearRetainingCapacity();

    // 1 | 01^2|345^67|89
    //               ^  ^  insertion
    // Result:
    //
    // 1 | 01^2|345^678|9

    try editor.appendSelection(talloc, .{ .anchor = .fromInt(2), .cursor = .fromInt(3) });
    try editor.appendSelection(talloc, .{ .anchor = .fromInt(6), .cursor = .fromInt(8) });

    try std.testing.expect(!editor.hasValidSelections());

    try editor.appendSelection(talloc, .{ .anchor = .fromInt(7), .cursor = .fromInt(9) });

    try std.testing.expect(!editor.hasValidSelections());
    try std.testing.expectEqualSlices(
        Selection,
        &.{
            .{ .anchor = .fromInt(2), .cursor = .fromInt(3) },
            .{ .anchor = .fromInt(6), .cursor = .fromInt(9) },
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

    try editor.selections.append(talloc, .{ .anchor = .fromInt(0), .cursor = .fromInt(0) });

    try editor.deleteCharacterBeforeCursors(talloc);

    try std.testing.expectEqualStrings("012\n456\n890\n", editor.text.items);
    try std.testing.expectEqualSlices(
        Selection,
        &.{.{ .anchor = .fromInt(0), .cursor = .fromInt(0) }},
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

    try editor.selections.append(talloc, .{ .anchor = .fromInt(12), .cursor = .fromInt(12) });

    try editor.deleteCharacterBeforeCursors(talloc);

    try std.testing.expectEqualStrings("012\n456\n890", editor.text.items);
    try std.testing.expectEqualSlices(
        Selection,
        &.{.{ .anchor = .fromInt(11), .cursor = .fromInt(11) }},
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

    try editor.selections.append(talloc, .{ .anchor = .fromInt(1), .cursor = .fromInt(1) });

    try editor.deleteCharacterBeforeCursors(talloc);

    try std.testing.expectEqualStrings("12\n456\n890\n", editor.text.items);
    try std.testing.expectEqualSlices(
        Selection,
        &.{.{ .anchor = .fromInt(0), .cursor = .fromInt(0) }},
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

    try editor.selections.append(talloc, .{ .anchor = .fromInt(3), .cursor = .fromInt(3) });
    try editor.selections.append(talloc, .{ .anchor = .fromInt(8), .cursor = .fromInt(8) });

    try editor.deleteCharacterBeforeCursors(talloc);

    try std.testing.expectEqualStrings("01\n456890\n", editor.text.items);
    try std.testing.expectEqualSlices(
        Selection,
        &.{
            .{ .anchor = .fromInt(2), .cursor = .fromInt(2) },
            .{ .anchor = .fromInt(6), .cursor = .fromInt(6) },
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

    try editor.selections.append(talloc, .{ .anchor = .fromInt(1), .cursor = .fromInt(1) });
    try editor.selections.append(talloc, .{ .anchor = .fromInt(2), .cursor = .fromInt(2) });

    try editor.deleteCharacterBeforeCursors(talloc);

    try std.testing.expectEqualStrings("2\n456\n890\n", editor.text.items);
    try std.testing.expectEqualSlices(
        Selection,
        &.{
            .{ .anchor = .fromInt(0), .cursor = .fromInt(0) },
        },
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

    try editor.selections.append(talloc, .{ .anchor = .fromInt(1), .cursor = .fromInt(1) });
    try editor.selections.append(talloc, .{ .anchor = .fromInt(3), .cursor = .fromInt(3) });

    try editor.deleteCharacterBeforeCursors(talloc);

    try std.testing.expectEqualStrings("1\n456\n890\n", editor.text.items);
    try std.testing.expectEqualSlices(
        Selection,
        &.{
            .{ .anchor = .fromInt(0), .cursor = .fromInt(0) },
            .{ .anchor = .fromInt(1), .cursor = .fromInt(1) },
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
        &.{
            .{ .anchor = .fromInt(0), .cursor = .fromInt(0) },
        },
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

    try editor.selections.append(talloc, .{ .anchor = .fromInt(2), .cursor = .fromInt(2) });
    try editor.selections.append(talloc, .{ .anchor = .fromInt(3), .cursor = .fromInt(3) });
    try editor.selections.append(talloc, .{ .anchor = .fromInt(6), .cursor = .fromInt(6) });

    try editor.deleteCharacterBeforeCursors(talloc);

    try std.testing.expectEqualStrings("0\n46\n890\n", editor.text.items);
    try std.testing.expectEqualSlices(
        Selection,
        &.{
            .{ .anchor = .fromInt(1), .cursor = .fromInt(1) },
            .{ .anchor = .fromInt(3), .cursor = .fromInt(3) },
        },
        editor.selections.items,
    );

    try testOnly_resetEditor(&editor, talloc);

    // Same test, but the selections appear in a different order.

    try editor.selections.append(talloc, .{ .anchor = .fromInt(2), .cursor = .fromInt(2) });
    try editor.selections.append(talloc, .{ .anchor = .fromInt(6), .cursor = .fromInt(6) });
    try editor.selections.append(talloc, .{ .anchor = .fromInt(3), .cursor = .fromInt(3) });

    try editor.deleteCharacterBeforeCursors(talloc);

    try std.testing.expectEqualStrings("0\n46\n890\n", editor.text.items);
    try std.testing.expectEqualSlices(
        Selection,
        &.{
            .{ .anchor = .fromInt(1), .cursor = .fromInt(1) },
            .{ .anchor = .fromInt(3), .cursor = .fromInt(3) },
        },
        editor.selections.items,
    );

    try testOnly_resetEditor(&editor, talloc);

    // Same test, but the selections appear in a different order.

    try editor.selections.append(talloc, .{ .anchor = .fromInt(6), .cursor = .fromInt(6) });
    try editor.selections.append(talloc, .{ .anchor = .fromInt(3), .cursor = .fromInt(3) });
    try editor.selections.append(talloc, .{ .anchor = .fromInt(2), .cursor = .fromInt(2) });

    try editor.deleteCharacterBeforeCursors(talloc);

    try std.testing.expectEqualStrings("0\n46\n890\n", editor.text.items);
    try std.testing.expectEqualSlices(
        Selection,
        &.{
            .{ .anchor = .fromInt(3), .cursor = .fromInt(3) },
            .{ .anchor = .fromInt(1), .cursor = .fromInt(1) },
        },
        editor.selections.items,
    );

    try testOnly_resetEditor(&editor, talloc);

    // Same test, but the selections appear in a different order.

    try editor.selections.append(talloc, .{ .anchor = .fromInt(6), .cursor = .fromInt(6) });
    try editor.selections.append(talloc, .{ .anchor = .fromInt(2), .cursor = .fromInt(2) });
    try editor.selections.append(talloc, .{ .anchor = .fromInt(3), .cursor = .fromInt(3) });

    try editor.deleteCharacterBeforeCursors(talloc);

    try std.testing.expectEqualStrings("0\n46\n890\n", editor.text.items);
    try std.testing.expectEqualSlices(
        Selection,
        &.{
            .{ .anchor = .fromInt(3), .cursor = .fromInt(3) },
            .{ .anchor = .fromInt(1), .cursor = .fromInt(1) },
        },
        editor.selections.items,
    );

    try testOnly_resetEditor(&editor, talloc);

    // Same test, but the selections appear in a different order.

    try editor.selections.append(talloc, .{ .anchor = .fromInt(2), .cursor = .fromInt(2) });
    try editor.selections.append(talloc, .{ .anchor = .fromInt(3), .cursor = .fromInt(3) });
    try editor.selections.append(talloc, .{ .anchor = .fromInt(6), .cursor = .fromInt(6) });

    try editor.deleteCharacterBeforeCursors(talloc);

    try std.testing.expectEqualStrings("0\n46\n890\n", editor.text.items);
    try std.testing.expectEqualSlices(
        Selection,
        &.{
            .{ .anchor = .fromInt(1), .cursor = .fromInt(1) },
            .{ .anchor = .fromInt(3), .cursor = .fromInt(3) },
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

    try editor.selections.append(talloc, .{ .anchor = .fromInt(2), .cursor = .fromInt(7) });

    try editor.deleteCharacterBeforeCursors(talloc);

    try std.testing.expectEqualStrings("012\n45\n890\n", editor.text.items);
    try std.testing.expectEqualSlices(
        Selection,
        &.{
            .{ .anchor = .fromInt(2), .cursor = .fromInt(6) },
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

    try editor.selections.append(talloc, .{ .anchor = .fromInt(2), .cursor = .fromInt(3) });

    try editor.deleteCharacterBeforeCursors(talloc);

    try std.testing.expectEqualStrings("01\n456\n890\n", editor.text.items);
    try std.testing.expectEqual(1, editor.selections.items.len);
    try std.testing.expect(editor.selections.items[0].isCursor());
    try std.testing.expectEqualSlices(
        Selection,
        &.{
            .{ .anchor = .fromInt(2), .cursor = .fromInt(2) },
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

    try editor.selections.append(talloc, .{ .anchor = .fromInt(2), .cursor = .fromInt(3) });
    try editor.selections.append(talloc, .{ .anchor = .fromInt(5), .cursor = .fromInt(7) });
    try editor.selections.append(talloc, .{ .anchor = .fromInt(8), .cursor = .fromInt(9) });

    try editor.deleteCharacterBeforeCursors(talloc);

    try std.testing.expectEqualStrings("01\n45\n90\n", editor.text.items);
    try std.testing.expectEqualSlices(
        Selection,
        &.{
            .{ .anchor = .fromInt(2), .cursor = .fromInt(2) },
            .{ .anchor = .fromInt(4), .cursor = .fromInt(5) },
            .{ .anchor = .fromInt(6), .cursor = .fromInt(6) },
        },
        editor.selections.items,
    );

    try testOnly_resetEditor(&editor, talloc);

    // Same test, selections in a different order.

    try editor.selections.append(talloc, .{ .anchor = .fromInt(5), .cursor = .fromInt(7) });
    try editor.selections.append(talloc, .{ .anchor = .fromInt(2), .cursor = .fromInt(3) });
    try editor.selections.append(talloc, .{ .anchor = .fromInt(8), .cursor = .fromInt(9) });

    try editor.deleteCharacterBeforeCursors(talloc);

    try std.testing.expectEqualStrings("01\n45\n90\n", editor.text.items);
    try std.testing.expectEqualSlices(
        Selection,
        &.{
            .{ .anchor = .fromInt(4), .cursor = .fromInt(5) },
            .{ .anchor = .fromInt(2), .cursor = .fromInt(2) },
            .{ .anchor = .fromInt(6), .cursor = .fromInt(6) },
        },
        editor.selections.items,
    );

    try testOnly_resetEditor(&editor, talloc);

    // Same test, selections in a different order.

    try editor.selections.append(talloc, .{ .anchor = .fromInt(8), .cursor = .fromInt(9) });
    try editor.selections.append(talloc, .{ .anchor = .fromInt(2), .cursor = .fromInt(3) });
    try editor.selections.append(talloc, .{ .anchor = .fromInt(5), .cursor = .fromInt(7) });

    try editor.deleteCharacterBeforeCursors(talloc);

    try std.testing.expectEqualStrings("01\n45\n90\n", editor.text.items);
    try std.testing.expectEqualSlices(
        Selection,
        &.{
            .{ .anchor = .fromInt(6), .cursor = .fromInt(6) },
            .{ .anchor = .fromInt(2), .cursor = .fromInt(2) },
            .{ .anchor = .fromInt(4), .cursor = .fromInt(5) },
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

    try editor.selections.append(talloc, .{ .anchor = .fromInt(1), .cursor = .fromInt(2) });
    try editor.selections.append(talloc, .{ .anchor = .fromInt(2), .cursor = .fromInt(3) });

    try editor.deleteCharacterBeforeCursors(talloc);

    try std.testing.expectEqualStrings("0\n456\n890\n", editor.text.items);
    try std.testing.expectEqualSlices(
        Selection,
        &.{
            .{ .anchor = .fromInt(1), .cursor = .fromInt(1) },
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

    try editor.selections.append(talloc, .{ .anchor = .fromInt(0), .cursor = .fromInt(2) });
    try editor.selections.append(talloc, .{ .anchor = .fromInt(2), .cursor = .fromInt(4) });

    try editor.deleteCharacterBeforeCursors(talloc);

    try std.testing.expectEqualStrings("02456\n890\n", editor.text.items);
    try std.testing.expectEqualSlices(
        Selection,
        &.{
            .{ .anchor = .fromInt(0), .cursor = .fromInt(1) },
            .{ .anchor = .fromInt(1), .cursor = .fromInt(2) },
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
    // After:
    // FIXME: Should the selections be merged here?
    //
    // 1 | 0|2^+456
    // 2 | 890
    // 4 |

    try editor.selections.append(talloc, .{ .anchor = .fromInt(3), .cursor = .fromInt(2) });
    try editor.selections.append(talloc, .{ .anchor = .fromInt(3), .cursor = .fromInt(4) });

    try editor.deleteCharacterBeforeCursors(talloc);

    try std.testing.expectEqualStrings("02456\n890\n", editor.text.items);
    try std.testing.expectEqualSlices(
        Selection,
        &.{
            .{ .anchor = .fromInt(2), .cursor = .fromInt(1) },
            .{ .anchor = .fromInt(2), .cursor = .fromInt(2) },
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

    try editor.selections.append(talloc, .{ .anchor = .fromInt(3), .cursor = .fromInt(2) });
    try editor.selections.append(talloc, .{ .anchor = .fromInt(3), .cursor = .fromInt(5) });

    try editor.deleteCharacterBeforeCursors(talloc);

    try std.testing.expectEqualStrings("02\n56\n890\n", editor.text.items);
    try std.testing.expectEqualSlices(
        Selection,
        &.{
            .{ .anchor = .fromInt(2), .cursor = .fromInt(1) },
            .{ .anchor = .fromInt(2), .cursor = .fromInt(3) },
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

    try editor.selections.append(talloc, .{ .anchor = .fromInt(2), .cursor = .fromInt(3) });
    try editor.selections.append(talloc, .{ .anchor = .fromInt(4), .cursor = .fromInt(3) });

    try editor.deleteCharacterBeforeCursors(talloc);

    try std.testing.expectEqualStrings("01\n456\n890\n", editor.text.items);
    try std.testing.expectEqualSlices(
        Selection,
        &.{
            .{ .anchor = .fromInt(2), .cursor = .fromInt(2) },
            .{ .anchor = .fromInt(3), .cursor = .fromInt(2) },
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

    try editor.selections.append(talloc, .{ .anchor = .fromInt(1), .cursor = .fromInt(2) });
    try editor.selections.append(talloc, .{ .anchor = .fromInt(2), .cursor = .fromInt(3) });
    try editor.selections.append(talloc, .{ .anchor = .fromInt(5), .cursor = .fromInt(6) });

    try editor.deleteCharacterBeforeCursors(talloc);

    try std.testing.expectEqualStrings("0\n46\n890\n", editor.text.items);
    try std.testing.expectEqualSlices(
        Selection,
        &.{
            .{ .anchor = .fromInt(1), .cursor = .fromInt(1) },
            .{ .anchor = .fromInt(3), .cursor = .fromInt(3) },
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
            .{ .pos = .fromInt(0), .text = &.{}, .type = .Text },
        },
        editor.tokens.items,
    );

    // 2. Some text.

    try editor.text.appendSlice(talloc, "lorem ipsum\n");
    try editor.tokenize(talloc);

    try std.testing.expectEqual(1, editor.tokens.items.len);

    const token = editor.tokens.items[0];

    try std.testing.expectEqual(Editor.TokenType.Text, token.type);
    try std.testing.expectEqual(Pos.fromInt(0), token.pos);
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
        Pos,
        &.{.fromInt(0)},
        editor.line_indexes.items,
    );

    // 2. One line.

    try editor.text.appendSlice(talloc, "012");
    try editor.updateLines(talloc);

    try std.testing.expectEqualSlices(
        Pos,
        &.{.fromInt(0)},
        editor.line_indexes.items,
    );

    editor.text.clearRetainingCapacity();

    // 3. One line, ends with a new line.

    try editor.text.appendSlice(talloc, "012\n");
    try editor.updateLines(talloc);

    try std.testing.expectEqualSlices(
        Pos,
        &.{ .fromInt(0), .fromInt(4) },
        editor.line_indexes.items,
    );

    editor.text.clearRetainingCapacity();

    // 4. Multiple lines.

    try editor.text.appendSlice(talloc, "012\n456\n890");
    try editor.updateLines(talloc);

    try std.testing.expectEqualSlices(
        Pos,
        &.{ .fromInt(0), .fromInt(4), .fromInt(8) },
        editor.line_indexes.items,
    );

    editor.text.clearRetainingCapacity();

    // 5. Multiple lines, ends with a new line.

    try editor.text.appendSlice(talloc, "012\n456\n890\n");
    try editor.updateLines(talloc);

    try std.testing.expectEqualSlices(
        Pos,
        &.{ .fromInt(0), .fromInt(4), .fromInt(8), .fromInt(12) },
        editor.line_indexes.items,
    );

    editor.text.clearRetainingCapacity();

    // 6. Multiple new lines in a row.

    try editor.text.appendSlice(talloc, "012\n\n\n67\n\n0");
    try editor.updateLines(talloc);

    try std.testing.expectEqualSlices(
        Pos,
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
        "012",
        editor.getLine(0),
    );
    try std.testing.expectEqualStrings(
        "345",
        editor.getLine(1),
    );
    try std.testing.expectEqualStrings(
        "456",
        editor.getLine(2),
    );
    try std.testing.expectEqualStrings(
        "",
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
