const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

pub const VerticalScrollBar = struct {
    total_height: usize,
    screen_height: usize,
    scroll_offset: usize,

    pub fn widget(self: *VerticalScrollBar) vxfw.Widget {
        return .{
            .userdata = self,
            .eventHandler = VerticalScrollBar.typeErasedEventHandler,
            .drawFn = VerticalScrollBar.typeErasedDrawFn,
        };
    }

    pub fn draw(self: *VerticalScrollBar, ctx: vxfw.DrawContext) std.mem.Allocator.Error!vxfw.Surface {
        const max = ctx.max.size();

        const children = try ctx.arena.alloc(vxfw.SubSurface, 1);

        // Draw scroll bar.
        const scroll_area_height = max.height;

        const scroll_bar_height_f: f64 =
            @as(f64, @floatFromInt(self.screen_height)) /
            @as(f64, @floatFromInt(self.total_height)) *
            @as(f64, @floatFromInt(scroll_area_height));
        const scroll_bar_height: usize = @intFromFloat(scroll_bar_height_f);

        const scroll_bar_offset_f: f64 =
            @as(f64, @floatFromInt(scroll_area_height)) /
            @as(f64, @floatFromInt(self.total_height)) *
            @as(f64, @floatFromInt(self.scroll_offset));
        const scroll_bar_offset: usize = @intFromFloat(scroll_bar_offset_f);

        const surface = try vxfw.Surface.init(
            ctx.arena,
            self.widget(),
            .{ .width = 1, .height = scroll_area_height },
        );

        const scrollBarCell: vaxis.Cell = .{
            .char = .{ .grapheme = " " },
            .style = .{ .reverse = true },
        };

        for (scroll_bar_offset..scroll_bar_offset + scroll_bar_height) |i| {
            surface.writeCell(0, @truncate(i), scrollBarCell);
        }

        children[0] = .{
            .surface = surface,
            .origin = .{
                .row = 0,
                .col = 0,
            },
        };

        return .{
            .size = max,
            .widget = self.widget(),
            .buffer = &.{},
            .children = children,
            .handles_mouse = true,
            .focusable = false,
        };
    }

    fn typeErasedEventHandler(_: *anyopaque, _: *vxfw.EventContext, _: vxfw.Event) anyerror!void {}

    fn typeErasedDrawFn(ptr: *anyopaque, ctx: vxfw.DrawContext) std.mem.Allocator.Error!vxfw.Surface {
        const self: *VerticalScrollBar = @ptrCast(@alignCast(ptr));
        return try self.draw(ctx);
    }
};
