const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

const Editor = struct {
    rich_text: vxfw.RichText,
    children: [1]vxfw.SubSurface = undefined,
    text: std.ArrayList(u8),

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
                if (key.text) |t| {
                    try self.text.appendSlice(t);

                    ctx.consumeAndRedraw();
                }
            },
            .focus_in => {
                return ctx.requestFocus(self.rich_text.widget());
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
        var spans = std.ArrayList(vxfw.RichText.TextSpan).init(ctx.arena);
        const span: vxfw.RichText.TextSpan = .{ .text = self.text.items };
        try spans.append(span);
        self.rich_text.text = spans.items;

        // Draw the RichText widget with the spans.
        const rich_text_surface = try self.rich_text.widget().draw(ctx);
        self.children[0] = .{
            .surface = rich_text_surface,
            .origin = .{ .row = 0, .col = 0 },
        };

        return .{
            .size = max,
            .widget = self.widget(),
            .buffer = &.{},
            .children = &self.children,
            .focusable = true,
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

    const text: vxfw.RichText.TextSpan = .{ .text = "" };
    fnApp.* = .{
        .editor = .{
            .rich_text = .{ .text = &.{text} },
            .text = std.ArrayList(u8).init(allocator),
        },
    };
    defer fnApp.editor.text.deinit();

    try app.run(fnApp.widget(), .{});
    app.deinit();
}
