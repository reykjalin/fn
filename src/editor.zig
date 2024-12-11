const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

const c_mocha = @import("./themes/catppuccin-mocha.zig");

pub const TAB_REPLACEMENT = "        ";

pub const Position = struct {
    line: usize,
    column: usize,

    pub fn to_cursor(self: *Position) Cursor {
        return .{ .line = self.line, .column = self.column };
    }
};

pub const Cursor = struct {
    line: usize,
    column: usize,

    pub fn to_position(self: *Cursor) Position {
        return .{ .line = self.line, .column = self.column };
    }
};

pub const Line = struct {
    text: std.ArrayList(u8),

    /// Returns the length of the line.
    /// TODO: Make this UTF-8 grapheme aware.
    pub fn len(self: *const Line) usize {
        return self.text.items.len;
    }
};

pub const Editor = struct {
    cursor: Cursor,
    lines: std.ArrayList(Line),
    line_widgets: std.ArrayList(vxfw.RichText),
    file: []const u8,
    scroll_view: vxfw.ScrollView,
    children: []vxfw.SubSurface,

    gpa: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,

    pub fn widget(self: *Editor) vxfw.Widget {
        return .{
            .userdata = self,
            .eventHandler = Editor.typeErasedEventHandler,
            .drawFn = Editor.typeErasedDrawFn,
        };
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

    pub fn scroll_up(self: *Editor, number_of_lines: u8) void {
        _ = self.scroll_view.scroll.linesUp(number_of_lines);
    }

    pub fn scroll_down(self: *Editor, number_of_lines: u8) void {
        _ = self.scroll_view.scroll.linesDown(number_of_lines);
    }

    pub fn handleEvent(self: *Editor, ctx: *vxfw.EventContext, event: vxfw.Event) anyerror!void {
        switch (event) {
            .mouse => |mouse| {
                if (mouse.type == .press) try ctx.requestFocus(self.widget());

                // 1. Handle mouse clicks.

                if (mouse.type == .press and mouse.button == .left) {
                    // Get line bounded to last line.
                    const clicked_row = mouse.row + self.scroll_view.scroll.top;
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

                    const scroll_view_cursor_offset: usize = if (self.scroll_view.draw_cursor)
                        2
                    else
                        0;

                    const max_col_click_allowed = if (self.scroll_view.draw_cursor)
                        clicked_line.text.items.len + 2
                    else
                        clicked_line.text.items.len;
                    const col = if (mouse_col_corrected_for_tabs < max_col_click_allowed)
                        mouse_col_corrected_for_tabs -| scroll_view_cursor_offset
                    else
                        clicked_line.text.items.len;

                    self.cursor = .{
                        .column = col,
                        .line = row,
                    };
                    self.scroll_view.cursor = @intCast(row);

                    try ctx.requestFocus(self.widget());
                    return ctx.consumeAndRedraw();
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
                    // Insert newline and move cursor to the new line.
                    try self.insert_new_line_at(self.cursor.to_position());
                    self.move_cursor_to(.{
                        .line = self.cursor.line +| 1,
                        .column = 0,
                    });

                    // Make sure the cursor is visible.
                    self.scroll_view.ensureScroll();

                    // We need to make sure we redraw the widget after changing the text.
                    ctx.consumeAndRedraw();
                } else if (key.matches(vaxis.Key.tab, .{})) {
                    const spacing = if (std.mem.eql(u8, ".zig", std.fs.path.extension(self.file)))
                        "    "
                    else
                        "\t";

                    try self.lines.items[self.cursor.line].text.insertSlice(
                        self.cursor.column,
                        spacing,
                    );
                    self.cursor.column +|= spacing.len;

                    // Make sure the cursor is visible.
                    self.scroll_view.ensureScroll();

                    // We need to make sure we redraw the widget after changing the text.
                    ctx.consumeAndRedraw();
                } else if (key.matches(vaxis.Key.backspace, .{ .super = true })) {
                    try self.delete_to_start_of_line();

                    // Make sure the cursor is visible.
                    self.scroll_view.ensureScroll();

                    ctx.consumeAndRedraw();
                } else if (key.matches(vaxis.Key.backspace, .{})) {
                    try self.delete_character_before_cursor();

                    // Make sure the cursor is visible.
                    self.scroll_view.ensureScroll();

                    ctx.consumeAndRedraw();
                } else if (key.matches(vaxis.Key.left, .{ .alt = true })) {
                    self.move_to_start_of_word();

                    // Make sure the cursor is visible.
                    self.scroll_view.ensureScroll();

                    ctx.consumeAndRedraw();
                } else if (key.matches(vaxis.Key.left, .{})) {
                    self.move_cursor_one_column_left();

                    // Make sure the cursor is visible.
                    self.scroll_view.ensureScroll();

                    ctx.consumeAndRedraw();
                } else if (key.matches(vaxis.Key.right, .{ .alt = true })) {
                    self.move_to_end_of_word();

                    // Make sure the cursor is visible.
                    self.scroll_view.ensureScroll();

                    ctx.consumeAndRedraw();
                } else if (key.matches(vaxis.Key.right, .{})) {
                    self.move_cursor_one_column_right();

                    // Make sure the cursor is visible.
                    self.scroll_view.ensureScroll();

                    ctx.consumeAndRedraw();
                } else if (key.matches(vaxis.Key.up, .{})) {
                    self.move_cursor_one_line_up();

                    // Make sure the cursor is visible.
                    self.scroll_view.ensureScroll();

                    ctx.consumeAndRedraw();
                } else if (key.matches(vaxis.Key.down, .{})) {
                    self.move_cursor_one_line_down();

                    // Make sure the cursor is visible.
                    self.scroll_view.ensureScroll();

                    ctx.consumeAndRedraw();
                } else if (key.matches('d', .{ .ctrl = true })) {
                    self.scroll_down(1);
                    self.move_cursor_one_line_down();

                    self.scroll_view.ensureScroll();

                    ctx.consumeAndRedraw();
                } else if (key.matches('u', .{ .ctrl = true })) {
                    self.scroll_up(1);
                    self.move_cursor_one_line_up();

                    self.scroll_view.ensureScroll();

                    ctx.consumeAndRedraw();
                } else if (key.text) |t| {
                    try self.lines.items[self.cursor.line].text.insertSlice(self.cursor.column, t);
                    self.cursor.column +|= 1;

                    // Make sure the cursor is visible.
                    self.scroll_view.ensureScroll();

                    // We need to make sure we redraw the widget after changing the text.
                    ctx.consumeAndRedraw();
                }
            },
            else => {},
        }

        try self.update_line_widgets();
    }

    /// Re-creates the list of RichText widgets used to render file contents.
    /// FIXME: Find the right time to call this.
    /// FIXME: It's probably not very performant to do this on every draw when we have
    ///        multiple styled spans. When we get to that point we'll want to only modify
    ///        the spans in the line that's been changed, and do this when the key event is
    ///        is handled.
    pub fn update_line_widgets(self: *Editor) !void {
        // 1. Reset the memory arena.
        _ = self.arena.reset(.retain_capacity);
        const allocator = self.arena.allocator();

        // 2. Clear the current widgets.

        self.line_widgets.clearRetainingCapacity();

        // 3. Create a RichText widget for each of the lines in the file.

        for (self.lines.items) |line| {
            // 4. Create all the spans that will represent the text in the RichText widget.

            var spans = std.ArrayList(vxfw.RichText.TextSpan).init(allocator);

            // We have to make sure widgets for empty lines contain _something_ so they're actually
            // rendered.
            if (line.len() == 0) {
                try spans.append(.{ .text = " " });
                try self.line_widgets.append(.{ .text = spans.items });
                continue;
            }

            // 5. Put the right text in the span.

            // FIXME: Replace tabs with something other than 4-spaces during render?
            const new_size = std.mem.replacementSize(u8, line.text.items, "\t", TAB_REPLACEMENT);
            const buf = try allocator.alloc(u8, new_size);
            _ = std.mem.replace(u8, line.text.items, "\t", TAB_REPLACEMENT, buf);

            const span: vxfw.RichText.TextSpan = .{
                .text = buf,
                .style = .{ .fg = c_mocha.text, .bg = c_mocha.base },
            };
            try spans.append(span);

            // 6. Add the spans to the list of line widgets.

            try self.line_widgets.append(.{
                .text = spans.items,
                .softwrap = false,
            });
        }
    }

    pub fn editor_line_widget_builder(ptr: *const anyopaque, idx: usize, _: usize) ?vxfw.Widget {
        const self: *const Editor = @ptrCast(@alignCast(ptr));

        if (idx >= self.line_widgets.items.len) return null;

        return self.line_widgets.items[idx].widget();
    }

    pub fn draw(self: *Editor, ctx: vxfw.DrawContext) std.mem.Allocator.Error!vxfw.Surface {
        const max = ctx.max.size();

        // Children contains the ScrollView with the text in the current file.
        self.children = try ctx.arena.alloc(vxfw.SubSurface, 1);

        // 1. Draw ScrollView with a list of RichText widgets to render the text.

        self.scroll_view.draw_cursor = true;

        var scroll_view: vxfw.SubSurface = .{
            .origin = .{ .row = 0, .col = 0 },
            .surface = try self.scroll_view.draw(ctx),
        };
        scroll_view.surface.focusable = true;

        self.children[0] = scroll_view;

        // 2. Configure the cursor location.

        const number_of_tabs_in_line = std.mem.count(
            u8,
            self.lines.items[self.cursor.line].text.items[0..self.cursor.column],
            "\t",
        );

        // Extra padding for the scroll view's cursor width, if it's going to be drawn.
        const scroll_view_cursor_padding: u16 = if (self.scroll_view.draw_cursor) 2 else 0;

        const screen_cursor_column =
            // Our representation of where in the line of text the cursor is.
            self.cursor.column -
            // Use the right width for all tab characters.
            number_of_tabs_in_line +
            (TAB_REPLACEMENT.len * number_of_tabs_in_line) +
            scroll_view_cursor_padding;

        // We only show the cursor if it's actually visible.
        var cursor: ?vxfw.CursorState = null;
        if (self.cursor.line >= self.scroll_view.scroll.top) {
            var row: u16 = @truncate(self.cursor.line);
            row -= @truncate(self.scroll_view.scroll.top);

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

    /// Asserts that the provided position is valid. A position is valid if it's:
    ///   (1) on one of the lines in the editor; and
    ///   (2) between the start and the end of that line, inclusive.
    ///
    /// Example:
    ///   the quick brown fox
    ///   ^        ^         ^
    ///   |        |         |- end of the line is a valid position because the cursor can be on
    ///   |        |            either side of the character at any given position.
    ///   |        |
    ///   |        |- middle of the line is also valid.
    ///   |
    ///   |- start of the line (column == 0) must also be valid.
    fn assert_position_is_valid(self: *Editor, pos: Position) void {
        // 1. Assert that the line position is valid.
        std.debug.assert(pos.line >= 0 and pos.line < self.lines.items.len);

        // 2. Get line at position.
        const current_line = self.lines.items[self.cursor.line];

        // 3. Assert that the character position is valid.
        //    Since you can move the cursor to the end of the current line the length of the current
        //    line is a valid position.
        std.debug.assert(pos.column >= 0 and pos.column <= current_line.len());
    }

    /// Returns the number of lines in the editor.
    fn len(self: *Editor) usize {
        return self.lines.items.len;
    }

    /// Delete the character before the current cursor.
    /// TODO: Should this receive a cursor instead? Or a position? We'll likely see once we support
    ///       multiple selections.
    fn delete_character_before_cursor(self: *Editor) !void {
        // 1. If we're at the start of the file, there's nothing to do.

        if (self.cursor.line == 0 and self.cursor.column == 0) {
            return;
        }

        // 2. Otherwise, if we're at the start of a line we have to join it with the line before it.

        if (self.cursor.column == 0) {
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

            return;
        }

        // 3. Finally, if we're not at the start of a line we remove 1 character before the cursor
        //    and update the cursor position.

        {
            _ = self.lines.items[self.cursor.line].text.orderedRemove(
                self.cursor.column - 1,
            );
            self.cursor.column -= 1;
        }
    }

    /// Delete from the current cursor position to the start of the line.
    /// TODO: Should this receive a position instead? We'll likely see once we support multiple
    ///       selections.
    fn delete_to_start_of_line(self: *Editor) !void {
        // 1. If we're at the start of the line we just do a regular "erase one character"
        //    operation because we just want to join the lines around the cursor. We get that for
        //    free by using the "erase one character" function.

        if (self.cursor.column == 0) {
            try self.delete_character_before_cursor();

            return;
        }

        // 2. Otherwise erase from the start of the line to the cursor position.

        var current_line = &self.lines.items[self.cursor.line];

        // We need a copy of the memory because when we clear the current line any pointers will be
        // invalidated.
        const current_line_copy = try current_line.text.clone();
        defer current_line_copy.deinit();

        const remaining_text = current_line_copy.items[self.cursor.column..];

        // Replace the line with the text from the cursor onwards.
        current_line.text.clearRetainingCapacity();
        try current_line.text.appendSlice(remaining_text);

        // 3. Move the cursor to the start of the line.

        self.cursor.column = 0;
    }

    fn move_to_end_of_word(self: *Editor) void {
        // Can't move beyond the end of the file.
        const last_line = self.lines.getLast();
        if (self.cursor.line >= self.lines.items.len - 1 and
            self.cursor.column == last_line.len()) return;

        // 1. If we're at the end of the current line we start searching from the start of the next
        //    line.

        if (self.cursor.column == self.lines.items[self.cursor.line].len()) {
            // We've already guaranteed we're not at the end of the file so we know another line is
            // available after the current line.
            self.move_cursor_one_line_down();
            self.cursor.column = 0;
        }

        const current_line = self.lines.items[self.cursor.line];

        // 2. Find end of the current word by searching for the nearest whitespace character after
        //    the cursor.

        const whitespace_after_cursor_idx = std.mem.indexOfAny(
            u8,
            current_line.text.items[self.cursor.column..],
            " \t",
        );

        // 3. If there's no whitespace found we can move to the end of the line because we've
        //    already verified that we're not at the end of the current line.

        if (whitespace_after_cursor_idx == null) {
            self.cursor.column = current_line.len();
            return;
        }

        // The actual index of the whitespace needs to take into account where we started searching
        // from.
        const whitespace_after_cursor = self.cursor.column + whitespace_after_cursor_idx.?;

        // 4. If the whitespace position is different from the current position we've found the end
        //    of the current word.

        if (self.cursor.column != whitespace_after_cursor) {
            self.cursor.column = whitespace_after_cursor;
            return;
        }

        // 5. Otherwise we find the start of the next word starting from the whitespace character.

        const start_of_next_word_idx = std.mem.indexOfNone(
            u8,
            current_line.text.items[whitespace_after_cursor..],
            " \t",
        );

        // 6. If there is no next word we have to restart the search from the start of the next
        //    line since the line ends in whitespace.

        if (start_of_next_word_idx == null) {
            self.move_cursor_one_line_down();
            self.cursor.column = 0;
            self.move_to_end_of_word();
            return;
        }

        // 6. Otherwise we continue to search for the end of the current word by looking for the
        //    next whitespace character.

        // The actual start of the next word nees to take into account where we started searching
        // from.
        const start_of_next_word = whitespace_after_cursor + start_of_next_word_idx.?;

        const end_of_next_word_idx = std.mem.indexOfAny(
            u8,
            current_line.text.items[start_of_next_word..],
            " \t",
        );

        // Update cursor position to just before the whitespace (end of the word), or the end of
        // the line if no whitespace was found.
        self.cursor.column = if (end_of_next_word_idx) |i| start_of_next_word + i else current_line.len();
    }

    fn move_to_start_of_word(self: *Editor) void {
        // Can't move before the start of the file.
        if (self.cursor.line == 0 and self.cursor.column == 0) return;

        // 1. If we're at the start of the line we start searching from the end of the previous
        //    line.

        if (self.cursor.column == 0) {
            self.move_cursor_one_line_up();
            self.cursor.column = self.lines.items[self.cursor.line].len();
        }

        var current_line = self.lines.items[self.cursor.line];

        // 2. Find the start of the current word by searching for the nearest whitespace character
        //    before the cursor.

        const whitespace_before_cursor_idx = std.mem.lastIndexOfAny(
            u8,
            current_line.text.items[0..self.cursor.column],
            " \t", // Tab or space only since newlines aren't in the line array.
        );

        // 2. If there is no whitespace found we can just move to the start of the line because we
        //    already checked if we're at the start, meaning that if no whitespace is found the
        //    current word must extend to the start of the line.

        if (whitespace_before_cursor_idx == null) {
            self.cursor.column = 0;
            return;
        }

        // 3. If the character after this whitespace is different from the character at the current
        //    position we've found the the new position for the cursor.

        if (whitespace_before_cursor_idx.? + 1 != self.cursor.column) {
            self.cursor.column = whitespace_before_cursor_idx.? + 1;
            return;
        }

        // 4. Otherwise, we were already at the start of a word, so we must search from the end of
        //    the previous word.

        const end_of_previous_word_idx = std.mem.lastIndexOfNone(
            u8,
            current_line.text.items[0..whitespace_before_cursor_idx.?],
            " \t",
        );

        // 5. If there is no previous word we have to restart the search from the end of the
        //    previous line.

        if (end_of_previous_word_idx == null) {
            self.move_cursor_one_line_up();
            self.cursor.column = self.lines.items[self.cursor.line].len();
            self.move_to_start_of_word();
            return;
        }

        // 6. Otherwise we find the start of the current word.

        const whitespace_before_word_idx = std.mem.lastIndexOfAny(
            u8,
            current_line.text.items[0..end_of_previous_word_idx.?],
            " \t",
        );

        // If no non-whitespace character is found the start of the current word must be at the start of the line.
        self.cursor.column = if (whitespace_before_word_idx) |i| i + 1 else 0;
    }

    /// Moves the cursor one line up, while making sure the cursor column position stays valid.
    fn move_cursor_one_line_up(self: *Editor) void {
        // 1. If we're already at the first line move the cursor to the start of the line.
        if (self.cursor.line == 0) {
            self.cursor.column = 0;
            return;
        }

        // 2. Otherwise move the cursor one line up, and make sure the column is valid.

        self.cursor.line -|= 1;
        self.scroll_view.cursor -|= 1;

        self.cursor.column = @min(
            self.lines.items[self.cursor.line].text.items.len,
            self.cursor.column,
        );
    }

    /// Moves the cursor one line down, while making sure the cursor column position stays valid.
    fn move_cursor_one_line_down(self: *Editor) void {
        // 1. If we're at the end of the file, move cursor to the end of the current line.

        if (self.cursor.line == self.lines.items.len - 1) {
            self.cursor.column = self.lines.items[self.cursor.line].text.items.len;
            return;
        }

        // 2. Otherwise, move the cursor one line down, and make sure the column is valid.

        self.cursor.line +|= 1;
        self.scroll_view.cursor +|= 1;

        self.cursor.column = @min(
            self.lines.items[self.cursor.line].text.items.len,
            self.cursor.column,
        );
    }

    /// Move cursor one column right. Wraps the position to the next line if the cursor is already
    /// at the end of the current line. If the cursor is already and the end of the file this
    /// function does nothing.
    fn move_cursor_one_column_right(self: *Editor) void {
        const current_line = self.lines.items[self.cursor.line];

        // 1. Do nothing if we're at the end of the file.

        if (self.cursor.line == self.lines.items.len - 1 and
            self.cursor.column == current_line.text.items.len)
        {
            return;
        }

        // 2. If we're at the end of the line, move to the start of the next line.

        if (self.cursor.column == current_line.text.items.len) {
            self.cursor.column = 0;
            self.move_cursor_one_line_down();

            return;
        }

        // 3. Otherwise, move one column right.
        self.cursor.column +|= 1;
    }

    /// Move the cursor one column left. Wraps the position to the previous line if the cursor is
    /// already at the start of the current line. If the cursor is already at the start of the file
    /// this function does nothing.
    fn move_cursor_one_column_left(self: *Editor) void {
        // 1. If we're already at the start of the file, do nothing.

        if (self.cursor.line == 0 and self.cursor.column == 0) return;

        // 2. If we're at the start of the line, move to the end of the previous line.

        if (self.cursor.column == 0) {
            self.move_cursor_one_line_up();
            self.cursor.column = self.lines.items[self.cursor.line].text.items.len;

            return;
        }

        // 3. Otherwise move the cursor one column left.

        self.cursor.column -= 1;
    }

    /// Moves the cursor behind the character at position `pos`. Asserts that the position is valid.
    fn move_cursor_to(self: *Editor, pos: Position) void {
        self.assert_position_is_valid(pos);

        self.cursor.line = pos.line;
        self.cursor.column = pos.column;

        self.scroll_view.cursor = @intCast(pos.line);
    }

    /// Insert a new line behind the character at position `pos`. Asserts that the position is
    /// valid.
    fn insert_new_line_at(self: *Editor, pos: Position) !void {
        self.assert_position_is_valid(pos);

        // 1. Get the line at `pos`.
        var current_line = &self.lines.items[pos.line];

        // 2. Create a new line struct with the text after the character position.
        var new_line: Line = .{ .text = std.ArrayList(u8).init(self.gpa) };
        try new_line.text.appendSlice(
            current_line.text.items[pos.column..],
        );

        // 3. Insert the new line below the line at `pos`.
        try self.lines.insert(pos.line + 1, new_line);

        // 4. Erase the text after the character position from the line at `pos`.
        current_line.text.shrinkRetainingCapacity(pos.column);
    }
};
