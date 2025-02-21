// AUTHOR: Kristófer R. <kristofer@thorlaksson.com>
// LICENSE: MIT

const std = @import("std");

const Pos = @import("pos.zig").Pos;
const Range = @import("range.zig");
const Selection = @import("selection.zig");

/// Managed editor object for a single file. **All properties are considered private after
/// initialization. Modifying them will result in undefined behavior.** Use the helper methods
/// instead of modifying properties directly.
const Editor = @This();

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

    self.text.clearRetainingCapacity();
    try reader.readAllArrayList(&self.text, std.math.maxInt(usize));

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
        var shouldAppend = true;

        // We make sure we only add one of each cursor position to make sure selections where the
        // cursors are touching don't cause 2 deletes.
        for (cursors.items) |cursor| {
            if (cursor == selection.cursor) {
                shouldAppend = false;
                break;
            }
        }

        if (shouldAppend) try cursors.append(selection.cursor);
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
    try self.updateLines();

    // Need to re-tokenize.
    try self.tokenize();

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

    var orderMap = std.ArrayList(usize).init(self.allocator);
    defer orderMap.deinit();

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

        try orderMap.append(movement);
    }

    // Need to move the cursors. Since each selection will have resulted in a deleted character we
    // need to move each cursor back equal to it's position in the file.
    for (self.selections.items, orderMap.items) |*selection, movement| {
        if (selection.isCursor()) {
            // FIXME: Make this unicode-aware.
            selection.cursor = Pos.fromInt(selection.cursor.toInt() -| movement);
            selection.anchor = selection.cursor;
            continue;
        }

        // Move both by `movement` if the cursor comes before the anchor in the selection.
        // Otherwise move just the cursor.
        if (selection.cursor.comesBefore(selection.anchor)) {
            // FIXME: Make this unicode-aware.
            selection.cursor = Pos.fromInt(selection.cursor.toInt() -| movement);
            selection.anchor = Pos.fromInt(selection.anchor.toInt() -| movement);
        } else {
            // FIXME: Make this unicode-aware.
            selection.cursor = Pos.fromInt(selection.cursor.toInt() -| movement);

            const is_first_selection_in_file = movement == 1;

            // Anything but the first selection has to move both the anchor and the cursor.
            if (!is_first_selection_in_file) {
                // Since the anchor comes before the cursor in this case we can't include the
                // shift generated by removing the character before the cursor in this selection,
                // so we subtract 1 from the movement.
                // FIXME: Make this unicode aware.
                const anchor_movement = movement -| 1;
                selection.anchor = Pos.fromInt(selection.anchor.toInt() -| anchor_movement);
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

fn testOnly_resetEditor(editor: *Editor) !void {
    editor.text.clearRetainingCapacity();
    try editor.text.appendSlice("012\n456\n890\n");
    try editor.updateLines();
    editor.selections.clearRetainingCapacity();
}

test deleteCharacterBeforeCursors {
    var editor = try Editor.init(std.testing.allocator);
    defer editor.deinit();

    try testOnly_resetEditor(&editor);

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

    try editor.selections.append(.{ .anchor = Pos.fromInt(0), .cursor = Pos.fromInt(0) });

    try editor.deleteCharacterBeforeCursors();

    try std.testing.expectEqualStrings("012\n456\n890\n", editor.text.items);
    try std.testing.expectEqualSlices(
        Selection,
        &.{.{ .anchor = Pos.fromInt(0), .cursor = Pos.fromInt(0) }},
        editor.selections.items,
    );

    try testOnly_resetEditor(&editor);

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

    try editor.selections.append(.{ .anchor = Pos.fromInt(12), .cursor = Pos.fromInt(12) });

    try editor.deleteCharacterBeforeCursors();

    try std.testing.expectEqualStrings("012\n456\n890", editor.text.items);
    try std.testing.expectEqualSlices(
        Selection,
        &.{.{ .anchor = Pos.fromInt(11), .cursor = Pos.fromInt(11) }},
        editor.selections.items,
    );

    try testOnly_resetEditor(&editor);

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

    try editor.selections.append(.{ .anchor = Pos.fromInt(1), .cursor = Pos.fromInt(1) });

    try editor.deleteCharacterBeforeCursors();

    try std.testing.expectEqualStrings("12\n456\n890\n", editor.text.items);
    try std.testing.expectEqualSlices(
        Selection,
        &.{.{ .anchor = Pos.fromInt(0), .cursor = Pos.fromInt(0) }},
        editor.selections.items,
    );

    try testOnly_resetEditor(&editor);

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

    try editor.selections.append(.{ .anchor = Pos.fromInt(3), .cursor = Pos.fromInt(3) });
    try editor.selections.append(.{ .anchor = Pos.fromInt(8), .cursor = Pos.fromInt(8) });

    try editor.deleteCharacterBeforeCursors();

    try std.testing.expectEqualStrings("01\n456890\n", editor.text.items);
    try std.testing.expectEqualSlices(
        Selection,
        &.{
            .{ .anchor = Pos.fromInt(2), .cursor = Pos.fromInt(2) },
            .{ .anchor = Pos.fromInt(6), .cursor = Pos.fromInt(6) },
        },
        editor.selections.items,
    );

    try testOnly_resetEditor(&editor);

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

    try editor.selections.append(.{ .anchor = Pos.fromInt(1), .cursor = Pos.fromInt(1) });
    try editor.selections.append(.{ .anchor = Pos.fromInt(2), .cursor = Pos.fromInt(2) });

    try editor.deleteCharacterBeforeCursors();

    try std.testing.expectEqualStrings("2\n456\n890\n", editor.text.items);
    try std.testing.expectEqualSlices(
        Selection,
        &.{
            .{ .anchor = Pos.fromInt(0), .cursor = Pos.fromInt(0) },
        },
        editor.selections.items,
    );

    try testOnly_resetEditor(&editor);

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

    try editor.selections.append(.{ .anchor = Pos.fromInt(1), .cursor = Pos.fromInt(1) });
    try editor.selections.append(.{ .anchor = Pos.fromInt(3), .cursor = Pos.fromInt(3) });

    try editor.deleteCharacterBeforeCursors();

    try std.testing.expectEqualStrings("1\n456\n890\n", editor.text.items);
    try std.testing.expectEqualSlices(
        Selection,
        &.{
            .{ .anchor = Pos.fromInt(0), .cursor = Pos.fromInt(0) },
            .{ .anchor = Pos.fromInt(1), .cursor = Pos.fromInt(1) },
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

    try editor.deleteCharacterBeforeCursors();

    try std.testing.expectEqualStrings("\n456\n890\n", editor.text.items);
    try std.testing.expectEqualSlices(
        Selection,
        &.{
            .{ .anchor = Pos.fromInt(0), .cursor = Pos.fromInt(0) },
        },
        editor.selections.items,
    );

    try testOnly_resetEditor(&editor);

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

    try editor.selections.append(.{ .anchor = Pos.fromInt(2), .cursor = Pos.fromInt(2) });
    try editor.selections.append(.{ .anchor = Pos.fromInt(3), .cursor = Pos.fromInt(3) });
    try editor.selections.append(.{ .anchor = Pos.fromInt(6), .cursor = Pos.fromInt(6) });

    try editor.deleteCharacterBeforeCursors();

    try std.testing.expectEqualStrings("0\n46\n890\n", editor.text.items);
    try std.testing.expectEqualSlices(
        Selection,
        &.{
            .{ .anchor = Pos.fromInt(1), .cursor = Pos.fromInt(1) },
            .{ .anchor = Pos.fromInt(3), .cursor = Pos.fromInt(3) },
        },
        editor.selections.items,
    );

    try testOnly_resetEditor(&editor);

    // Same test, but the selections appear in a different order.

    try editor.selections.append(.{ .anchor = Pos.fromInt(2), .cursor = Pos.fromInt(2) });
    try editor.selections.append(.{ .anchor = Pos.fromInt(6), .cursor = Pos.fromInt(6) });
    try editor.selections.append(.{ .anchor = Pos.fromInt(3), .cursor = Pos.fromInt(3) });

    try editor.deleteCharacterBeforeCursors();

    try std.testing.expectEqualStrings("0\n46\n890\n", editor.text.items);
    try std.testing.expectEqualSlices(
        Selection,
        &.{
            .{ .anchor = Pos.fromInt(1), .cursor = Pos.fromInt(1) },
            .{ .anchor = Pos.fromInt(3), .cursor = Pos.fromInt(3) },
        },
        editor.selections.items,
    );

    try testOnly_resetEditor(&editor);

    // Same test, but the selections appear in a different order.

    try editor.selections.append(.{ .anchor = Pos.fromInt(6), .cursor = Pos.fromInt(6) });
    try editor.selections.append(.{ .anchor = Pos.fromInt(3), .cursor = Pos.fromInt(3) });
    try editor.selections.append(.{ .anchor = Pos.fromInt(2), .cursor = Pos.fromInt(2) });

    try editor.deleteCharacterBeforeCursors();

    try std.testing.expectEqualStrings("0\n46\n890\n", editor.text.items);
    try std.testing.expectEqualSlices(
        Selection,
        &.{
            .{ .anchor = Pos.fromInt(3), .cursor = Pos.fromInt(3) },
            .{ .anchor = Pos.fromInt(1), .cursor = Pos.fromInt(1) },
        },
        editor.selections.items,
    );

    try testOnly_resetEditor(&editor);

    // Same test, but the selections appear in a different order.

    try editor.selections.append(.{ .anchor = Pos.fromInt(6), .cursor = Pos.fromInt(6) });
    try editor.selections.append(.{ .anchor = Pos.fromInt(2), .cursor = Pos.fromInt(2) });
    try editor.selections.append(.{ .anchor = Pos.fromInt(3), .cursor = Pos.fromInt(3) });

    try editor.deleteCharacterBeforeCursors();

    try std.testing.expectEqualStrings("0\n46\n890\n", editor.text.items);
    try std.testing.expectEqualSlices(
        Selection,
        &.{
            .{ .anchor = Pos.fromInt(3), .cursor = Pos.fromInt(3) },
            .{ .anchor = Pos.fromInt(1), .cursor = Pos.fromInt(1) },
        },
        editor.selections.items,
    );

    try testOnly_resetEditor(&editor);

    // Same test, but the selections appear in a different order.

    try editor.selections.append(.{ .anchor = Pos.fromInt(2), .cursor = Pos.fromInt(2) });
    try editor.selections.append(.{ .anchor = Pos.fromInt(3), .cursor = Pos.fromInt(3) });
    try editor.selections.append(.{ .anchor = Pos.fromInt(6), .cursor = Pos.fromInt(6) });

    try editor.deleteCharacterBeforeCursors();

    try std.testing.expectEqualStrings("0\n46\n890\n", editor.text.items);
    try std.testing.expectEqualSlices(
        Selection,
        &.{
            .{ .anchor = Pos.fromInt(1), .cursor = Pos.fromInt(1) },
            .{ .anchor = Pos.fromInt(3), .cursor = Pos.fromInt(3) },
        },
        editor.selections.items,
    );

    try testOnly_resetEditor(&editor);

    // == Selections == //

    // 6. Deleting in a selection should shrink the selection.

    // 7. Shrinking a selection to a cursor should make that selection a cursor.

    // 8. Selections are moved correctly even if they're out of order in the selections array.

    // 9. Deleting from side-by-side selections where the anchor from one touches the cursor from
    //    the other.

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

    try editor.selections.append(.{ .anchor = Pos.fromInt(3), .cursor = Pos.fromInt(2) });
    try editor.selections.append(.{ .anchor = Pos.fromInt(3), .cursor = Pos.fromInt(4) });

    try editor.deleteCharacterBeforeCursors();

    try std.testing.expectEqualStrings("02456\n890\n", editor.text.items);
    try std.testing.expectEqualSlices(
        Selection,
        &.{
            .{ .anchor = Pos.fromInt(2), .cursor = Pos.fromInt(1) },
            .{ .anchor = Pos.fromInt(2), .cursor = Pos.fromInt(2) },
        },
        editor.selections.items,
    );

    try testOnly_resetEditor(&editor);

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

    try editor.selections.append(.{ .anchor = Pos.fromInt(3), .cursor = Pos.fromInt(2) });
    try editor.selections.append(.{ .anchor = Pos.fromInt(3), .cursor = Pos.fromInt(5) });

    try editor.deleteCharacterBeforeCursors();

    try std.testing.expectEqualStrings("02\n56\n890\n", editor.text.items);
    try std.testing.expectEqualSlices(
        Selection,
        &.{
            .{ .anchor = Pos.fromInt(2), .cursor = Pos.fromInt(1) },
            .{ .anchor = Pos.fromInt(2), .cursor = Pos.fromInt(3) },
        },
        editor.selections.items,
    );

    try testOnly_resetEditor(&editor);

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

    try editor.selections.append(.{ .anchor = Pos.fromInt(2), .cursor = Pos.fromInt(3) });
    try editor.selections.append(.{ .anchor = Pos.fromInt(4), .cursor = Pos.fromInt(3) });

    try editor.deleteCharacterBeforeCursors();

    try std.testing.expectEqualStrings("01\n456\n890\n", editor.text.items);
    try std.testing.expectEqualSlices(
        Selection,
        &.{
            .{ .anchor = Pos.fromInt(2), .cursor = Pos.fromInt(2) },
            .{ .anchor = Pos.fromInt(3), .cursor = Pos.fromInt(2) },
        },
        editor.selections.items,
    );

    try testOnly_resetEditor(&editor);

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

    // 13. Deleting from overlapping selections. Test cursor inside the other with other cursor both
    //     before and after. Test anchor inside the other with other cursor both before and after.
    //     Test selections merging if they become equal (strict vs. non-strict equal might matter?).

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

test "refAllDecls" {
    std.testing.refAllDecls(@This());
}
