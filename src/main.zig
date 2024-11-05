const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

const Fn = struct {
    editor: vxfw.RichText,
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
                const t: vxfw.RichText.TextSpan = .{ .text = "Welcome to Fönn!" };
                self.editor = .{
                    .text = &.{t},
                    .softwrap = false,
                };

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

        const x = max.width / 2 -| 8;
        const y = max.height / 2;

        const editor_surface = try self.editor.widget().draw(ctx);

        self.children[0] = .{
            .surface = editor_surface,
            .origin = .{ .row = y, .col = x },
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

    fnApp.* = .{ .editor = .{ .text = undefined } };

    try app.run(fnApp.widget(), .{});
    app.deinit();
}
