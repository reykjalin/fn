const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

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

    gpa: std.mem.Allocator,

    pub fn widget(self: *Editor) vxfw.Widget {
        return .{
            .userdata = self,
            .eventHandler = Editor.typeErasedEventHandler,
            .drawFn = Editor.typeErasedDrawFn,
        };
    }

    pub fn handleEvent(self: *Editor, ctx: *vxfw.EventContext, event: vxfw.Event) anyerror!void {
        switch (event) {
            .key_press => |key| {
                if (key.matches(vaxis.Key.enter, .{})) {
                    const line: Line = .{ .text = std.ArrayList(u8).init(self.gpa) };
                    try self.lines.append(line);

                    self.cursor.line +|= 1;
                    self.cursor.column = 0;

                    // We need to make sure we redraw the widget after changing the text.
                    ctx.consumeAndRedraw();
                } else if (key.matches(vaxis.Key.tab, .{})) {
                    // FIXME: Handle tabs properly without hard-coding spaces.
                    try self.lines.items[self.cursor.line].text.appendSlice("    ");
                    self.cursor.column +|= 4;

                    // We need to make sure we redraw the widget after changing the text.
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
                } else if (key.text) |t| {
                    try self.lines.items[self.cursor.line].text.appendSlice(t);
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
            const span: vxfw.RichText.TextSpan = .{ .text = l.text.items };
            try spans.append(span);

            rte_widgets[i] = .{ .text = spans.items };
        }

        // Draw RichText widgets.
        const children = try ctx.arena.alloc(vxfw.SubSurface, rte_widgets.len);
        for (rte_widgets, 0..) |rte, i| {
            const surface = try rte.widget().draw(ctx);
            children[i] = .{
                .surface = surface,
                .origin = .{ .row = @intCast(i), .col = 0 },
            };
        }

        return .{
            .size = max,
            .widget = self.widget(),
            .buffer = &.{},
            .children = children,
            .focusable = true,
            .cursor = .{
                .row = @truncate(self.cursor.line),
                .col = @truncate(self.cursor.column),
                .shape = .beam,
            },
        };
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
        };
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    var app = try vxfw.App.init(allocator);
    errdefer app.deinit();

    const fnApp = try allocator.create(Fn);
    defer allocator.destroy(fnApp);

    // Set up initial state.
    const line: Line = .{ .text = std.ArrayList(u8).init(allocator) };
    var lines = std.ArrayList(Line).init(allocator);
    try lines.append(line);

    fnApp.* = .{
        .editor = .{
            .cursor = .{ .line = 0, .column = 0 },
            .lines = lines,
            .gpa = allocator,
        },
    };
    defer {
        for (fnApp.editor.lines.items) |l| {
            l.text.deinit();
        }
        fnApp.editor.lines.deinit();
    }

    try app.run(fnApp.widget(), .{});
    app.deinit();
}
