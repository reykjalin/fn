const std = @import("std");
const vaxis = @import("vaxis");
const libfn = @import("libfn");

const vxfw = vaxis.vxfw;
const Editor = libfn.Editor;

const c_mocha = @import("./themes/catppuccin-mocha.zig");

pub const TAB_REPLACEMENT = "        ";

const Mode = enum {
    normal,
    insert,
    select,
};

pub const EditorWidget = @This();

editor: Editor,
line_widgets: std.ArrayListUnmanaged(vxfw.RichText),
scroll_bars: vxfw.ScrollBars,
children: []vxfw.SubSurface,
mode: Mode = .normal,

gpa: std.mem.Allocator,
arena_state: std.heap.ArenaAllocator,

pub fn init(gpa: std.mem.Allocator) !*EditorWidget {
    const editor: Editor = try .init(gpa);

    const editor_widget = try gpa.create(EditorWidget);
    editor_widget.* = .{
        .editor = editor,
        .line_widgets = .empty,
        .children = &.{},
        .scroll_bars = .{
            .scroll_view = .{
                .children = .{
                    .builder = .{
                        .userdata = editor_widget,
                        .buildFn = EditorWidget.editorLineWidgetBuilder,
                    },
                },
                .wheel_scroll = 1,
            },
        },
        .gpa = gpa,
        .arena_state = std.heap.ArenaAllocator.init(gpa),
    };

    return editor_widget;
}

pub fn deinit(self: *EditorWidget) void {
    self.editor.deinit(self.gpa);
    self.line_widgets.deinit(self.gpa);
    self.arena_state.deinit();
}

pub fn widget(self: *EditorWidget) vxfw.Widget {
    return .{
        .userdata = self,
        .eventHandler = EditorWidget.typeErasedEventHandler,
        .drawFn = EditorWidget.typeErasedDrawFn,
    };
}

fn typeErasedEventHandler(
    ptr: *anyopaque,
    ctx: *vxfw.EventContext,
    event: vxfw.Event,
) anyerror!void {
    const self: *EditorWidget = @ptrCast(@alignCast(ptr));
    try self.handleEvent(ctx, event);
}

fn typeErasedDrawFn(
    ptr: *anyopaque,
    ctx: vxfw.DrawContext,
) std.mem.Allocator.Error!vxfw.Surface {
    const self: *EditorWidget = @ptrCast(@alignCast(ptr));
    return try self.draw(ctx);
}

/// Make sure the cursor is in a valid position, and moves it to a valid position if it's not.
pub fn ensureCursorIsValid(self: *EditorWidget) void {
    // Make sure editor cursor is still valid.
    self.cursor.line = @min(self.cursor.line, self.len() - 1);
    const current_line = self.lines.items[self.cursor.line];
    self.cursor.column = @min(self.cursor.column, current_line.len());

    // Make sure scroll view cursor is still valid.
    self.scroll_bars.scroll_view.cursor = @intCast(self.cursor.line);
}

pub fn scrollUp(self: *EditorWidget, number_of_lines: u8) void {
    _ = self.scroll_bars.scroll_view.scroll.linesUp(number_of_lines);
}

pub fn scrollDown(self: *EditorWidget, number_of_lines: u8) void {
    _ = self.scroll_bars.scroll_view.scroll.linesDown(number_of_lines);
}

pub fn handleEvent(self: *EditorWidget, ctx: *vxfw.EventContext, event: vxfw.Event) anyerror!void {
    switch (event) {
        .mouse => |mouse| {
            if (mouse.type == .press) try ctx.requestFocus(self.widget());

            // 1. Handle mouse clicks.

            if (mouse.type == .press and mouse.button == .left) {
                // Get line bounded to last line.
                const clicked_row = mouse.row + self.scroll_bars.scroll_view.scroll.top;
                const row = if (clicked_row < self.editor.lineCount())
                    clicked_row
                else
                    self.editor.lineCount() - 1;

                const clicked_line = self.editor.getLine(row);

                // Get column bounded to last column in the clicked line.
                const no_of_tabs_in_line = std.mem.count(u8, clicked_line, "\t");
                // There's a net TAB_REPLACEMENT.len - 1 change in the amount of characters for
                // each tab.
                const mouse_col_corrected_for_tabs =
                    mouse.col -|
                    ((TAB_REPLACEMENT.len - 1) * no_of_tabs_in_line);

                const scroll_view_cursor_offset: usize =
                    if (self.scroll_bars.scroll_view.draw_cursor)
                        2
                    else
                        0;

                const max_col_click_allowed = if (self.scroll_bars.scroll_view.draw_cursor)
                    clicked_line.len + 2
                else
                    clicked_line.len;
                const col = if (mouse_col_corrected_for_tabs < max_col_click_allowed)
                    mouse_col_corrected_for_tabs -| scroll_view_cursor_offset
                else
                    clicked_line.len;

                // Clicking should clear all selections.
                self.editor.selections.clearRetainingCapacity();
                try self.editor.appendSelection(
                    self.gpa,
                    .createCursor(.{ .row = row, .col = col }),
                );
                self.scroll_bars.scroll_view.cursor = @intCast(row);

                try ctx.requestFocus(self.widget());
                return ctx.consumeAndRedraw();
            }
        },
        .mouse_enter => try ctx.setMouseShape(.text),
        .mouse_leave => try ctx.setMouseShape(.default),
        .paste => |pasted_text| {
            defer self.gpa.free(pasted_text);

            // FIXME: I don't actually know if this works. I can't trigger the paste event from
            //        Ghostty.
            std.log.debug("received paste: '{s}'", .{pasted_text});
            try self.editor.insertTextAtCursors(self.gpa, pasted_text);
        },
        .key_press => |key| {
            switch (self.mode) {
                .select => {
                    if (key.matches('v', .{}) or key.matches(vaxis.Key.escape, .{})) {
                        self.mode = .normal;
                        ctx.consumeAndRedraw();
                    } else if (key.matches('l', .{}) or key.matches(vaxis.Key.right, .{})) {
                        for (self.editor.selections.items) |*s| {
                            s.cursor.col +|= 1;
                        }
                        ctx.consumeAndRedraw();
                    } else if (key.matches('h', .{}) or key.matches(vaxis.Key.left, .{})) {
                        for (self.editor.selections.items) |*s| {
                            s.cursor.col -|= 1;
                        }
                        ctx.consumeAndRedraw();
                    }
                },
                .normal => {
                    if (key.matches('h', .{}) or key.matches(vaxis.Key.left, .{})) {
                        self.editor.moveSelectionsLeft();
                        ctx.consumeAndRedraw();
                    } else if (key.matches('l', .{}) or key.matches(vaxis.Key.right, .{})) {
                        self.editor.moveSelectionsRight();
                        ctx.consumeAndRedraw();
                    } else if (key.matches('j', .{}) or key.matches(vaxis.Key.down, .{})) {
                        self.editor.moveSelectionsDown();
                        ctx.consumeAndRedraw();
                    } else if (key.matches('k', .{}) or key.matches(vaxis.Key.up, .{})) {
                        self.editor.moveSelectionsUp();
                        ctx.consumeAndRedraw();
                    } else if (key.matches('w', .{})) {
                        self.editor.selectNextWord();
                        ctx.consumeAndRedraw();
                    } else if (key.matches('b', .{})) {
                        self.editor.selectPreviousWord();
                        ctx.consumeAndRedraw();
                    } else if (key.matches('d', .{})) {
                        self.editor.copySelectionsContent();
                        try self.editor.deleteCharacterBeforeCursors(self.gpa);
                        ctx.consumeAndRedraw();
                    } else if (key.matches('v', .{})) {
                        self.mode = .select;
                        ctx.consumeAndRedraw();
                    } else if (key.matches('i', .{})) {
                        self.editor.moveCursorBeforeAnchorForAllSelections();

                        // Make sure we anchor the cursor position to the end of the line it's
                        // currently on.
                        for (self.editor.selections.items) |*s| {
                            const line = self.editor.getLine(s.cursor.row);
                            s.cursor.col = @min(s.cursor.col, line.len);
                        }

                        self.mode = .insert;
                        ctx.consumeAndRedraw();
                    } else if (key.matches('a', .{})) {
                        self.editor.moveCursorAfterAnchorForAllSelections();

                        // Make sure we anchor the cursor position to the end of the line it's
                        // currently on.
                        for (self.editor.selections.items) |*s| {
                            const line = self.editor.getLine(s.cursor.row);
                            s.cursor.col = @min(s.cursor.col, line.len);
                        }

                        // Make sure the cursor beam appears after the character under the cursor.
                        // FIXME: This should probably be some sort of API in `libfn.Editor`.
                        for (self.editor.selections.items) |*s| {
                            if (s.isCursor()) {
                                const line = self.editor.getLine(s.cursor.row);

                                // Nothing to do if we're at the end of the file.
                                if (s.cursor.row == self.editor.lineCount() - 1 and
                                    s.cursor.col == line.len) continue;

                                s.cursor.col +|= 1;

                                // Move down if we're at the end of a line.
                                if (s.cursor.col >= line.len) {
                                    s.cursor.row +|= 1;
                                    s.cursor.col = 0;
                                }
                            }
                        }
                        self.mode = .insert;
                        ctx.consumeAndRedraw();
                    }
                },
                .insert => {
                    // FIXME: Ensure primary selection is visible in scroll view after edits.
                    if (key.matches(vaxis.Key.escape, .{}) or key.matches('c', .{ .ctrl = true })) {
                        for (self.editor.selections.items) |*s| {
                            if (s.isCursor()) continue;
                            if (s.cursor.col == 0 and s.cursor.row == 0) continue;

                            if (s.cursor.col == 0) {
                                s.cursor.row -= 1;
                                const line = self.editor.getLine(s.cursor.row);
                                s.cursor.col = line.len;
                            } else {
                                s.cursor.col -|= 1;
                            }
                        }

                        self.mode = .normal;
                        ctx.consumeAndRedraw();
                    } else if (key.matches(vaxis.Key.enter, .{})) {
                        try self.editor.insertTextAtCursors(self.gpa, "\n");

                        // We need to make sure we redraw the widget after changing the text.
                        ctx.consumeAndRedraw();
                    } else if (key.matches(vaxis.Key.tab, .{})) {
                        const spacing = if (std.mem.eql(
                            u8,
                            ".zig",
                            std.fs.path.extension(self.editor.filename.items),
                        ))
                            "    "
                        else
                            "\t";

                        try self.editor.insertTextAtCursors(self.gpa, spacing);

                        // We need to make sure we redraw the widget after changing the text.
                        ctx.consumeAndRedraw();
                    } else if (key.matches(vaxis.Key.backspace, .{ .super = true })) {
                        self.editor.deleteToStartOfLine();

                        ctx.consumeAndRedraw();
                    } else if (key.matches(vaxis.Key.backspace, .{})) {
                        try self.editor.deleteCharacterBeforeCursors(self.gpa);

                        ctx.consumeAndRedraw();
                    } else if (key.matches(vaxis.Key.left, .{ .alt = true })) {
                        self.editor.selectPreviousWord();

                        ctx.consumeAndRedraw();
                    } else if (key.matches(vaxis.Key.left, .{})) {
                        self.editor.moveSelectionsLeft();

                        ctx.consumeAndRedraw();
                    } else if (key.matches(vaxis.Key.right, .{ .alt = true })) {
                        self.editor.selectNextWord();

                        ctx.consumeAndRedraw();
                    } else if (key.matches(vaxis.Key.right, .{})) {
                        self.editor.moveSelectionsRight();

                        ctx.consumeAndRedraw();
                    } else if (key.matches(vaxis.Key.up, .{})) {
                        self.editor.moveSelectionsUp();

                        ctx.consumeAndRedraw();
                    } else if (key.matches(vaxis.Key.down, .{})) {
                        self.editor.moveSelectionsDown();

                        ctx.consumeAndRedraw();
                    } else if (key.matches(vaxis.Key.left, .{ .super = true }) or
                        key.matches('a', .{ .ctrl = true }))
                    {
                        self.editor.moveSelectionsToStartOfLine();

                        ctx.consumeAndRedraw();
                    } else if (key.matches(vaxis.Key.right, .{ .super = true }) or
                        key.matches('e', .{ .ctrl = true }))
                    {
                        self.editor.moveSelectionsToEndOfLine();

                        ctx.consumeAndRedraw();
                    } else if (key.text) |t| {
                        std.log.debug("inserting text: '{s}'", .{t});
                        try self.editor.insertTextAtCursors(self.gpa, t);

                        // We need to make sure we redraw the widget after changing the text.
                        ctx.consumeAndRedraw();
                    }
                },
            }

            if (!ctx.consume_event) try self.scroll_bars.scroll_view.handleEvent(ctx, event);
        },
        else => {},
    }

    // Update the line widgets only right before we redraw the text on screen.
    if (ctx.redraw) try self.updateLineWidgets();
}

/// Re-creates the list of RichText widgets used to render file contents.
/// FIXME: Find the right time to call this.
/// FIXME: It's probably not very performant to do this on every draw when we have
///        multiple styled spans. When we get to that point we'll want to only modify
///        the spans in the line that's been changed, and do this when the key event is
///        is handled.
pub fn updateLineWidgets(self: *EditorWidget) !void {
    self.line_widgets.clearRetainingCapacity();

    _ = self.arena_state.reset(.retain_capacity);
    const arena = self.arena_state.allocator();

    var it = std.mem.splitScalar(u8, self.editor.text.items, '\n');
    var line_nr: usize = 0;

    // Get a sorted array of selections
    var selections: std.ArrayListUnmanaged(libfn.Selection) = .empty;
    try selections.ensureTotalCapacityPrecise(arena, self.editor.selections.items.len);
    selections.appendSliceAssumeCapacity(self.editor.selections.items);
    std.mem.sort(libfn.Selection, selections.items, {}, libfn.Selection.lessThan);

    const primary_selection = self.editor.getPrimarySelection();
    const cursor = primary_selection.cursor;
    const before = primary_selection.toRange().before();
    const after = primary_selection.toRange().after();

    while (it.next()) |line| : (line_nr += 1) {
        var spans: std.ArrayListUnmanaged(vxfw.RichText.TextSpan) = .empty;

        // Add the correct styling for selections and cursors.
        if (line_nr == cursor.row) {
            const line_to_before = @min(before.col, line.len);
            const number_of_tabs_before_before = std.mem.count(
                u8,
                line[0..line_to_before],
                "\t",
            );
            const screen_before_column =
                // Our representation of where in the line of text the anchor is.
                before.col -
                // Use the right width for all tab characters.
                number_of_tabs_before_before +
                (TAB_REPLACEMENT.len * number_of_tabs_before_before);

            const line_to_after = @min(after.col, line.len);
            const number_of_tabs_before_after = std.mem.count(
                u8,
                line[0..line_to_after],
                "\t",
            );
            const screen_after_column =
                // Our representation of where in the line of text the cursor is.
                after.col -
                // Use the right width for all tab characters.
                number_of_tabs_before_after +
                (TAB_REPLACEMENT.len * number_of_tabs_before_after);

            const before_col: u16 = @truncate(@min(screen_before_column, line.len));
            const after_col: u16 = @truncate(@min(screen_after_column, line.len));

            var before_before_col: std.ArrayListUnmanaged(u8) = .empty;
            var before_col_to_after_col: std.ArrayListUnmanaged(u8) = .empty;
            var after_after_col: std.ArrayListUnmanaged(u8) = .empty;

            if (before_col != 0) try before_before_col.appendSlice(arena, line[0..before_col]);

            if (before_col != after_col) {
                try before_col_to_after_col.appendSlice(arena, line[before_col..after_col]);
            }

            if (after_col < line.len) try after_after_col.appendSlice(
                arena,
                line[after_col..],
            ) else try after_after_col.appendSlice(arena, " ");

            try spans.append(arena, .{ .text = before_before_col.items });
            try spans.append(arena, .{
                .text = before_col_to_after_col.items,
                .style = .{ .bg = c_mocha.surface_2 },
            });
            try spans.append(arena, .{ .text = after_after_col.items });
        } else {
            try spans.append(arena, .{
                .text = if (std.mem.eql(u8, line, "")) " " else line,
            });
        }

        try self.line_widgets.append(self.gpa, .{
            .text = spans.items,
            .softwrap = false,
        });
    }
}

pub fn editorLineWidgetBuilder(ptr: *const anyopaque, idx: usize, _: usize) ?vxfw.Widget {
    const self: *const EditorWidget = @ptrCast(@alignCast(ptr));

    if (idx >= self.line_widgets.items.len) return null;

    return self.line_widgets.items[idx].widget();
}

pub fn draw(self: *EditorWidget, ctx: vxfw.DrawContext) std.mem.Allocator.Error!vxfw.Surface {
    const max = ctx.max.size();

    // Children contains the ScrollView with the text in the current file.
    self.children = try ctx.arena.alloc(vxfw.SubSurface, 1);

    // 1. Draw ScrollView with a list of RichText widgets to render the text.

    self.scroll_bars.scroll_view.item_count = @intCast(self.editor.line_indexes.items.len);
    self.scroll_bars.estimated_content_height = @intCast(self.editor.line_indexes.items.len);

    const scroll_view: vxfw.SubSurface = .{
        .origin = .{ .row = 0, .col = 0 },
        .surface = try self.scroll_bars.draw(ctx),
    };

    self.children[0] = scroll_view;

    // 2. Configure the cursor location.

    const cursor = self.editor.getPrimarySelection().cursor;
    var cursor_state: ?vxfw.CursorState = null;

    if (cursor.row >= self.scroll_bars.scroll_view.scroll.top) {
        const line = self.editor.getLine(cursor.row);
        const cursor_col = if (std.mem.eql(u8, line, "\n") or std.mem.eql(u8, line, ""))
            0
        else if (cursor.row == self.editor.lineCount() -| 1 and !std.mem.endsWith(u8, line, "\n"))
            @min(cursor.col, line.len)
        else if (self.mode == .insert)
            @min(cursor.col, line.len)
        else
            @min(cursor.col, line.len -| 1);
        const number_of_tabs_in_line = std.mem.count(
            u8,
            line[0..@min(cursor.col, line.len)],
            "\t",
        );

        const screen_cursor_column =
            // Our representation of where in the line of text the cursor is.
            cursor_col -
            // Use the right width for all tab characters.
            number_of_tabs_in_line +
            (TAB_REPLACEMENT.len * number_of_tabs_in_line);

        // We only show the cursor if it's actually visible.
        var row: u16 = @truncate(cursor.row);
        row -= @truncate(self.scroll_bars.scroll_view.scroll.top);
        const col: u16 = @truncate(screen_cursor_column);

        cursor_state = .{
            .row = row,
            .col = col,
            .shape = if (self.mode == .insert) .beam_blink else .block,
        };
    }

    return .{
        .size = max,
        .widget = self.widget(),
        .buffer = &.{},
        .children = self.children,
        .cursor = cursor_state,
    };
}
