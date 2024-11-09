const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

const editor = @import("./editor.zig");
const vsb = @import("./vertical_scroll_bar.zig");

pub const Fn = struct {
    editor: editor.Editor,
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
