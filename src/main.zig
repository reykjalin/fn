const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

const vsb = @import("./vertical_scroll_bar.zig");

const TAB_REPLACEMENT = "        ";

const Cursor = struct {
    line: usize,
    column: usize,
};

const Line = struct {
    text: std.ArrayList(u8),
};

const Editor = struct {
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
                    // There's a net TAB_REPLACEMENT.len - 1 change in the amount of characters for each tab.
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
                    ctx.redraw = true;
                }

                switch (mouse.button) {
                    .wheel_up => {
                        self.scroll_up(1);
                        ctx.consumeAndRedraw();
                    },
                    .wheel_down => {
                        self.scroll_down(1);
                        ctx.consumeAndRedraw();
                    },
                    else => {},
                }
            },
            .mouse_leave => try ctx.setMouseShape(.default),
            .key_press => |key| {
                if (key.matches(vaxis.Key.enter, .{})) {
                    // FIXME: Insert newlines at cursor.
                    const line: Line = .{ .text = std.ArrayList(u8).init(self.gpa) };
                    try self.lines.append(line);

                    self.cursor.line +|= 1;
                    self.cursor.column = 0;

                    // We need to make sure we redraw the widget after changing the text.
                    ctx.consumeAndRedraw();
                } else if (key.matches(vaxis.Key.tab, .{})) {
                    // FIXME: Insert tabs at cursor.
                    try self.lines.items[self.cursor.line].text.append('\t');
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
                        const new_cursor_pos = self.lines.items[self.cursor.line - 1].text.items.len;

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
                        _ = self.lines.items[self.cursor.line].text.orderedRemove(self.cursor.column - 1);
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

                    if (self.cursor.line == self.lines.items.len - 1 and self.cursor.column == current_line.text.items.len) {
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

            const span: vxfw.RichText.TextSpan = .{ .text = buf };
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
            .handles_mouse = true,
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

    fn typeErasedEventHandler(ptr: *anyopaque, ctx: *vxfw.EventContext, event: vxfw.Event) anyerror!void {
        const self: *Editor = @ptrCast(@alignCast(ptr));
        try self.handleEvent(ctx, event);
    }

    fn typeErasedDrawFn(ptr: *anyopaque, ctx: vxfw.DrawContext) std.mem.Allocator.Error!vxfw.Surface {
        const self: *Editor = @ptrCast(@alignCast(ptr));
        return try self.draw(ctx);
    }
};

const Fn = struct {
    editor: Editor,
    gpa: std.mem.Allocator,
    children: [1]vxfw.SubSurface = undefined,

    pub fn widget(self: *Fn) vxfw.Widget {
        return .{
            .userdata = self,
            .eventHandler = Fn.typeErasedEventHandler,
            .drawFn = Fn.typeErasedDrawFn,
        };
    }

    fn typeErasedEventHandler(ptr: *anyopaque, ctx: *vxfw.EventContext, event: vxfw.Event) anyerror!void {
        const self: *Fn = @ptrCast(@alignCast(ptr));

        switch (event) {
            .init => {
                return ctx.requestFocus(self.editor.widget());
            },
            .key_press => |key| {
                if (key.matches('c', .{ .ctrl = true })) {
                    ctx.quit = true;
                    return;
                }

                if (key.matches('s', .{ .super = true })) {
                    // If we haven't loaded a file there's nothing to do.
                    if (self.editor.file.len == 0) return;

                    // FIXME: Add some assertions that the file hasn't changed.
                    const file = std.fs.cwd().createFile(self.editor.file, .{ .truncate = true }) catch return;
                    defer file.close();

                    // FIXME: Just use a `Writer` instead of writing a bunch of bytes straight to
                    //        the file.
                    const text_to_save = try self.editor.get_all_text(self.gpa);
                    defer self.gpa.free(text_to_save);

                    try file.writeAll(text_to_save);
                }
            },
            else => {},
        }
    }

    fn typeErasedDrawFn(ptr: *anyopaque, ctx: vxfw.DrawContext) std.mem.Allocator.Error!vxfw.Surface {
        const self: *Fn = @ptrCast(@alignCast(ptr));
        const max = ctx.max.size();

        const editor_surface = try self.editor.widget().draw(ctx);

        self.children[0] = .{
            .surface = editor_surface,
            .origin = .{ .row = 0, .col = 0 },
        };

        return .{
            .size = max,
            .widget = self.widget(),
            .buffer = &.{},
            .children = &self.children,
            .focusable = false,
        };
    }
};

pub fn main() !void {
    // Set up allocator.
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    // Process arguments.
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len > 1 and (std.mem.eql(u8, args[1], "--help") or std.mem.eql(u8, args[1], "-h"))) {
        const writer = std.io.getStdOut().writer();
        try writer.print("Usage: fn [file]\n", .{});
        try writer.print("\n", .{});
        try writer.print("General options:\n", .{});
        try writer.print("\n", .{});
        try writer.print("  -h, --help     Print fn help\n", .{});
        try writer.print("  -v, --version  Print fn help\n", .{});
        std.process.exit(0);
    }
    if (args.len > 1 and (std.mem.eql(u8, args[1], "--version") or std.mem.eql(u8, args[1], "-v"))) {
        const writer = std.io.getStdOut().writer();
        try writer.print("0.0.0\n", .{});
        std.process.exit(0);
    }

    // Initialize vaxis app.
    var app = try vxfw.App.init(allocator);
    errdefer app.deinit();

    // Initialize Fönn.
    const fnApp = try allocator.create(Fn);
    defer allocator.destroy(fnApp);

    // Set up initial state.
    var lines = std.ArrayList(Line).init(allocator);

    // If we have more than 1 argument, use the last argument as the file to open.
    if (args.len > 1) {
        const file_path = args[args.len - 1];

        // Open the file to read its contents.
        if (std.fs.cwd().openFile(file_path, .{ .mode = .read_only })) |file| {
            defer file.close();

            // Get a buffered reader to read the file.
            var buf_reader = std.io.bufferedReader(file.reader());
            const reader = buf_reader.reader();

            // We'll use an arraylist to read line-by-line.
            var line = std.ArrayList(u8).init(allocator);
            defer line.deinit();

            const writer = line.writer();

            while (reader.streamUntilDelimiter(writer, '\n', null)) {
                // Clear the line so we can use it.
                defer line.clearRetainingCapacity();

                // Move the line contents into a Line struct.
                var l: Line = .{ .text = std.ArrayList(u8).init(allocator) };
                try l.text.appendSlice(line.items);

                // Append the line contents to the initial state.
                try lines.append(l);
            } else |err| switch (err) {
                // Handle the last line of the file.
                error.EndOfStream => {
                    // Move the line contents into a Line struct.
                    var l: Line = .{ .text = std.ArrayList(u8).init(allocator) };
                    try l.text.appendSlice(line.items);

                    // Append the line contents to the initial state.
                    try lines.append(l);
                },
                else => return err,
            }
        } else |_| {
            // We're not interested in doing anything with the errors here, except make sure a line
            // is initialized.
            const line: Line = .{ .text = std.ArrayList(u8).init(allocator) };
            try lines.append(line);
        }
    } else {
        const line: Line = .{ .text = std.ArrayList(u8).init(allocator) };
        try lines.append(line);
    }

    // Allocate scroll bars.
    const scroll_bar = try allocator.create(vsb.VerticalScrollBar);
    scroll_bar.* = .{
        .total_height = 0,
        .screen_height = 0,
        .scroll_offset = 0,
        .scroll_up_button = try allocator.create(vxfw.Button),
        .scroll_down_button = try allocator.create(vxfw.Button),
    };
    scroll_bar.scroll_up_button.* = .{
        .label = "\u{2191}",
        .userdata = scroll_bar,
        .onClick = vsb.VerticalScrollBar.on_up_button_click,
    };
    scroll_bar.scroll_down_button.* = .{
        .label = "\u{2193}",
        .userdata = scroll_bar,
        .onClick = vsb.VerticalScrollBar.on_down_button_click,
    };

    // Set initial state.
    fnApp.* = .{
        .gpa = allocator,
        .editor = .{
            .cursor = .{ .line = 0, .column = 0 },
            .lines = lines,
            .gpa = allocator,
            .file = "",
            .vertical_scroll_offset = 0,
            .horizontal_scroll_offset = 0,
            .vertical_scroll_bar = scroll_bar,
            .children = undefined,
        },
    };

    if (args.len > 1) {
        fnApp.editor.file = args[args.len - 1];
    }

    // Free fn state.
    defer {
        for (fnApp.editor.lines.items) |l| {
            l.text.deinit();
        }
        fnApp.editor.lines.deinit();

        allocator.destroy(fnApp.editor.vertical_scroll_bar.scroll_up_button);
        allocator.destroy(fnApp.editor.vertical_scroll_bar.scroll_down_button);
        allocator.destroy(fnApp.editor.vertical_scroll_bar);
    }

    // Run app.
    try app.run(fnApp.widget(), .{});
    app.deinit();
}
