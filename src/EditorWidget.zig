const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

const libfn = @import("libfn.zig");
const Editor = libfn.Editor;

const c_mocha = @import("./themes/catppuccin-mocha.zig");

pub const TAB_REPLACEMENT = "        ";

const Mode = enum {
    normal,
    insert,
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

                const clicked_line_start_index = self.editor.line_indexes.items[row].toInt();
                const cursor_pos = clicked_line_start_index +| col;

                // Clicking should clear all selections.
                self.editor.selections.clearRetainingCapacity();
                try self.editor.appendSelection(self.gpa, .{
                    .cursor = .fromInt(cursor_pos),
                    .anchor = .fromInt(cursor_pos),
                });
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
            try self.editor.insertTextBeforeSelection(self.gpa, pasted_text);
        },
        .key_press => |key| {
            switch (self.mode) {
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
                    } else if (key.matches('i', .{})) {
                        self.editor.moveCursorBeforeAnchorForAllSelections();
                        self.mode = .insert;
                        ctx.consumeAndRedraw();
                    } else if (key.matches('a', .{})) {
                        self.editor.moveCursorAfterAnchorForAllSelections();
                        self.mode = .insert;
                        ctx.consumeAndRedraw();
                    }
                },
                .insert => {
                    // FIXME: Ensure primary selection is visible in scroll view after edits.
                    if (key.matches(vaxis.Key.escape, .{}) or key.matches('c', .{ .ctrl = true })) {
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

    while (it.next()) |line| {
        var spans: std.ArrayListUnmanaged(vxfw.RichText.TextSpan) = .empty;

        try spans.append(arena, .{
            .text = if (std.mem.eql(u8, line, "")) " " else line,
        });

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

    const cursor = self.editor.toCoordinatePos(self.editor.getPrimarySelection().cursor);
    const number_of_tabs_in_line = std.mem.count(
        u8,
        self.editor.getLine(cursor.row)[0..cursor.col],
        "\t",
    );

    // Extra padding for the scroll view's cursor width, if it's going to be drawn.
    const scroll_view_cursor_padding: u16 = if (self.scroll_bars.scroll_view.draw_cursor) 2 else 0;

    const screen_cursor_column =
        // Our representation of where in the line of text the cursor is.
        cursor.col -
        // Use the right width for all tab characters.
        number_of_tabs_in_line +
        (TAB_REPLACEMENT.len * number_of_tabs_in_line) +
        scroll_view_cursor_padding;

    // We only show the cursor if it's actually visible.
    var cursor_state: ?vxfw.CursorState = null;
    if (cursor.row >= self.scroll_bars.scroll_view.scroll.top) {
        var row: u16 = @truncate(cursor.row);
        row -= @truncate(self.scroll_bars.scroll_view.scroll.top);

        cursor_state = .{
            .row = row,
            .col = @truncate(screen_cursor_column),
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
