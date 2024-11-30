const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

const vsb = @import("./vertical_scroll_bar.zig");

const c_mocha = @import("./themes/catppuccin-mocha.zig");

pub const TAB_REPLACEMENT = "        ";

pub const Cursor = struct {
    line: usize,
    column: usize,
};

pub const Line = struct {
    text: std.ArrayList(u8),
};

pub const Editor = struct {
    cursor: Cursor,
    lines: std.ArrayList(Line),
    file: []const u8,
    vertical_scroll_offset: usize,
    horizontal_scroll_offset: usize,
    vertical_scroll_bar: *vsb.VerticalScrollBar,
    children: []vxfw.SubSurface,

    gpa: std.mem.Allocator,

    pub fn widget(self: *Editor) vxfw.Widget {
        return .{
            .userdata = self,
            .eventHandler = Editor.typeErasedEventHandler,
            .drawFn = Editor.typeErasedDrawFn,
        };
    }

    pub fn scroll_up(self: *Editor, number_of_lines: usize) void {
        self.vertical_scroll_offset -|= number_of_lines;
    }

    pub fn scroll_down(self: *Editor, number_of_lines: usize) void {
        self.vertical_scroll_offset +|= number_of_lines;

        // Make the upper bound such that there is alwyas at least 1 line visible.
        if (self.vertical_scroll_offset > self.lines.items.len -| 1) {
            self.vertical_scroll_offset = self.lines.items.len -| 1;
        }
    }

    pub fn handleEvent(self: *Editor, ctx: *vxfw.EventContext, event: vxfw.Event) anyerror!void {
        switch (event) {
            .mouse => |mouse| {
                // 1. If the event is over the scrollbar we let the scroll bar handle the event.

                const scroll_bar_origin = self.children[self.children.len - 1].origin;
                if (mouse.col == scroll_bar_origin.col) {
                    return self.vertical_scroll_bar.handleEvent(ctx, event);
                }

                // 2. Handle mouse clicks.

                if (mouse.type == .press and mouse.button == .left) {
                    // Get line bounded to last line.
                    const clicked_row = mouse.row + self.vertical_scroll_offset;
                    const row = if (clicked_row < self.lines.items.len)
                        clicked_row
                    else
                        self.lines.items.len - 1;

                    const clicked_line = self.lines.items[row];

                    // Get column bounded to last column in the clicked line.
                    const no_of_tabs_in_line = std.mem.count(u8, clicked_line.text.items, "\t");
                    // There's a net TAB_REPLACEMENT.len - 1 change in the amount of characters for
                    // each tab.
                    const mouse_col_corrected_for_tabs =
                        mouse.col -|
                        ((TAB_REPLACEMENT.len - 1) * no_of_tabs_in_line);

                    const col = if (mouse_col_corrected_for_tabs < clicked_line.text.items.len)
                        mouse_col_corrected_for_tabs
                    else
                        clicked_line.text.items.len;

                    self.cursor = .{
                        .column = col,
                        .line = row,
                    };

                    try ctx.requestFocus(self.widget());
                    return ctx.consumeAndRedraw();
                }

                // 3. Handle scrolling.

                switch (mouse.button) {
                    .wheel_up => {
                        self.scroll_up(1);
                        return ctx.consumeAndRedraw();
                    },
                    .wheel_down => {
                        self.scroll_down(1);
                        return ctx.consumeAndRedraw();
                    },
                    else => {},
                }
            },
            .mouse_enter => try ctx.setMouseShape(.text),
            .mouse_leave => try ctx.setMouseShape(.default),
            .key_press => |key| {
                // 1. Every time we get a key event intended for the editor we make sure to request
                //    that the editor stay focused.
                //    NOTE: This fixes an issue where _something_ is stealing focus after the first
                //          character is typed into the text editor.
                if (ctx.phase == .at_target) try ctx.requestFocus(self.widget());

                if (key.matches(vaxis.Key.enter, .{})) {
                    // 1. Get current line.
                    var current_line = &self.lines.items[self.cursor.line];

                    // 2. Create a new line struct with the text after the cursor location.
                    var new_line: Line = .{ .text = std.ArrayList(u8).init(self.gpa) };
                    try new_line.text.appendSlice(
                        current_line.text.items[self.cursor.column..],
                    );

                    // 3. Insert the new line below the cursor.
                    try self.lines.insert(self.cursor.line + 1, new_line);

                    // 4. Erase the text after the cursor from the current line.
                    current_line.text.shrinkRetainingCapacity(self.cursor.column);

                    // 5. Move cursor to the start of the new line.
                    self.cursor.line +|= 1;
                    self.cursor.column = 0;

                    // We need to make sure we redraw the widget after changing the text.
                    ctx.consumeAndRedraw();
                } else if (key.matches(vaxis.Key.tab, .{})) {
                    try self.lines.items[self.cursor.line].text.insertSlice(
                        self.cursor.column,
                        "\t",
                    );
                    self.cursor.column +|= 1;

                    // We need to make sure we redraw the widget after changing the text.
                    ctx.consumeAndRedraw();
                } else if (key.matches(vaxis.Key.backspace, .{})) {
                    if (self.cursor.line == 0 and self.cursor.column == 0) {
                        // There's nothing to erase beyond the start of the file.
                        return;
                    } else if (self.cursor.column == 0) {
                        // Join lines.

                        // Cursor will be moved to the _current_ end of the previous line.
                        const new_cursor_pos =
                            self.lines.items[self.cursor.line - 1].text.items.len;

                        // Append current line contents to previous line.
                        try self.lines.items[self.cursor.line - 1].text.appendSlice(
                            self.lines.items[self.cursor.line].text.items,
                        );

                        // Remove current line and free the memory.
                        const removed_element = self.lines.orderedRemove(self.cursor.line);
                        removed_element.text.deinit();

                        // Update cursor position.
                        self.cursor.line -= 1;
                        self.cursor.column = new_cursor_pos;
                    } else {
                        _ = self.lines.items[self.cursor.line].text.orderedRemove(
                            self.cursor.column - 1,
                        );
                        self.cursor.column -= 1;
                    }

                    ctx.consumeAndRedraw();
                } else if (key.matches(vaxis.Key.left, .{})) {
                    if (self.cursor.line == 0 and self.cursor.column == 0) {
                        self.cursor = .{ .line = 0, .column = 0 };
                    } else if (self.cursor.column == 0) {
                        self.cursor.line -= 1;
                        self.cursor.column = self.lines.items[self.cursor.line].text.items.len;
                    } else {
                        self.cursor.column -= 1;
                    }

                    ctx.consumeAndRedraw();
                } else if (key.matches(vaxis.Key.right, .{})) {
                    const current_line = self.lines.items[self.cursor.line];

                    if (self.cursor.line == self.lines.items.len - 1 and
                        self.cursor.column == current_line.text.items.len)
                    {
                        // Do nothing because we're already at the end of the file.
                        return;
                    } else if (self.cursor.column == current_line.text.items.len) {
                        self.cursor.line +|= 1;
                        self.cursor.column = 0;
                    } else {
                        self.cursor.column +|= 1;
                    }

                    ctx.consumeAndRedraw();
                } else if (key.matches(vaxis.Key.up, .{})) {
                    if (self.cursor.line == 0) {
                        self.cursor.column = 0;
                    } else {
                        self.cursor.line -= 1;

                        self.cursor.column = @min(
                            self.lines.items[self.cursor.line].text.items.len,
                            self.cursor.column,
                        );
                    }

                    ctx.consumeAndRedraw();
                } else if (key.matches(vaxis.Key.down, .{})) {
                    if (self.cursor.line == self.lines.items.len - 1) {
                        self.cursor.column = self.lines.items[self.cursor.line].text.items.len;
                    } else {
                        self.cursor.line +|= 1;

                        self.cursor.column = @min(
                            self.lines.items[self.cursor.line].text.items.len,
                            self.cursor.column,
                        );
                    }

                    ctx.consumeAndRedraw();
                } else if (key.matches('d', .{ .ctrl = true })) {
                    self.scroll_down(1);

                    ctx.consumeAndRedraw();
                } else if (key.matches('u', .{ .ctrl = true })) {
                    self.scroll_up(1);

                    ctx.consumeAndRedraw();
                } else if (key.text) |t| {
                    try self.lines.items[self.cursor.line].text.insertSlice(self.cursor.column, t);
                    self.cursor.column +|= 1;

                    // We need to make sure we redraw the widget after changing the text.
                    ctx.consumeAndRedraw();
                }
            },
            else => {},
        }
    }

    pub fn draw(self: *Editor, ctx: vxfw.DrawContext) std.mem.Allocator.Error!vxfw.Surface {
        const max = ctx.max.size();

        // Construct the text spans used to render text in the RichText widget.
        // FIXME: It's probably not very performant to do this on every draw when we have
        //        multiple styled spans. When we get to that point we'll want to only modify
        //        the spans in the line that's been changed, and do this when the key event is
        //        is handled.
        const rte_widgets = try ctx.arena.alloc(vxfw.RichText, self.lines.items.len);
        for (self.lines.items, 0..) |l, i| {
            var spans = std.ArrayList(vxfw.RichText.TextSpan).init(ctx.arena);

            // FIXME: Replace tabs with something other than 4-spaces during render?
            const new_size = std.mem.replacementSize(u8, l.text.items, "\t", TAB_REPLACEMENT);
            const buf = try ctx.arena.alloc(u8, new_size);
            _ = std.mem.replace(u8, l.text.items, "\t", TAB_REPLACEMENT, buf);

            const span: vxfw.RichText.TextSpan = .{
                .text = buf,
                .style = .{ .fg = c_mocha.text, .bg = c_mocha.base },
            };
            try spans.append(span);

            rte_widgets[i] = .{ .text = spans.items };
        }

        // Children contains all the RichText widgets and the scrollbar.
        self.children = try ctx.arena.alloc(vxfw.SubSurface, rte_widgets.len + 1);

        // Draw RichText widgets.
        for (rte_widgets, 0..) |rte, i| {
            const surface = try rte.widget().draw(ctx.withConstraints(
                .{ .width = 1, .height = 1 },
                .{ .width = max.width - 1, .height = max.height },
            ));

            var row: i17 = @intCast(i);
            row -= @intCast(self.vertical_scroll_offset);

            self.children[i] = .{
                .surface = surface,
                .origin = .{
                    .row = row,
                    .col = 0,
                },
            };
        }

        // Draw scrollbar.
        self.vertical_scroll_bar.total_height = self.lines.items.len;
        self.vertical_scroll_bar.screen_height = max.height;
        self.vertical_scroll_bar.scroll_offset = self.vertical_scroll_offset;
        const surface = try self.vertical_scroll_bar.widget().draw(ctx.withConstraints(
            .{ .width = 1, .height = 3 },
            .{ .width = 1, .height = @max(3, max.height) },
        ));

        self.children[self.children.len - 1] = .{
            .surface = surface,
            .origin = .{ .row = 0, .col = max.width - 1 },
        };

        const number_of_tabs_in_line = std.mem.count(
            u8,
            self.lines.items[self.cursor.line].text.items[0..self.cursor.column],
            "\t",
        );

        const screen_cursor_column =
            self.cursor.column -
            number_of_tabs_in_line +
            (TAB_REPLACEMENT.len * number_of_tabs_in_line);

        // We only show the cursor if it's actually visible.
        var cursor: ?vxfw.CursorState = null;
        if (self.cursor.line >= self.vertical_scroll_offset) {
            var row: u16 = @truncate(self.cursor.line);
            row -= @truncate(self.vertical_scroll_offset);

            cursor = .{
                .row = row,
                .col = @truncate(screen_cursor_column),
                .shape = .beam_blink,
            };
        }

        return .{
            .size = max,
            .widget = self.widget(),
            .buffer = &.{},
            .children = self.children,
            .focusable = true,
            .cursor = cursor,
        };
    }

    pub fn get_all_text(self: *Editor, allocator: std.mem.Allocator) ![]u8 {
        // NOTE: No need to deinit because we return the value from `.toOwnedSlice()`.
        var text = std.ArrayList(u8).init(allocator);

        for (self.lines.items, 0..) |line, i| {
            try text.appendSlice(line.text.items);

            // Add a newline if we're not at the last line.
            if (i < self.lines.items.len - 1) try text.appendSlice("\n");
        }

        return text.toOwnedSlice();
    }

    fn typeErasedEventHandler(
        ptr: *anyopaque,
        ctx: *vxfw.EventContext,
        event: vxfw.Event,
    ) anyerror!void {
        const self: *Editor = @ptrCast(@alignCast(ptr));
        try self.handleEvent(ctx, event);
    }

    fn typeErasedDrawFn(
        ptr: *anyopaque,
        ctx: vxfw.DrawContext,
    ) std.mem.Allocator.Error!vxfw.Surface {
        const self: *Editor = @ptrCast(@alignCast(ptr));
        return try self.draw(ctx);
    }
};
