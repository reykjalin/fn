const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

pub const VerticalScrollBar = struct {
    total_height: usize,
    screen_height: usize,
    scroll_offset: usize,
    scroll_up_button: *vxfw.Button,
    scroll_down_button: *vxfw.Button,

    pub fn widget(self: *VerticalScrollBar) vxfw.Widget {
        return .{
            .userdata = self,
            .eventHandler = VerticalScrollBar.typeErasedEventHandler,
            .drawFn = VerticalScrollBar.typeErasedDrawFn,
        };
    }

    pub fn on_up_button_click(_: ?*anyopaque, _: *vxfw.EventContext) anyerror!void {}

    pub fn on_down_button_click(_: ?*anyopaque, _: *vxfw.EventContext) anyerror!void {}

    pub fn handleEvent(_: *VerticalScrollBar, _: *vxfw.EventContext, _: vxfw.Event) anyerror!void {}

    pub fn draw(self: *VerticalScrollBar, ctx: vxfw.DrawContext) std.mem.Allocator.Error!vxfw.Surface {
        const max = ctx.max.size();

        const children = try ctx.arena.alloc(vxfw.SubSurface, 3);

        // Draw scroll up button.
        const button_surface = try self.scroll_up_button.draw(ctx.withConstraints(
            .{ .width = 1, .height = 1 },
            .{ .width = 1, .height = 1 },
        ));

        children[0] = .{
            .surface = button_surface,
            .origin = .{
                .row = 0,
                .col = 0,
            },
        };

        // Draw scroll bar.
        const scroll_area_height = max.height - 2;

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
            .{ .width = 1, .height = scroll_area_height - 1 },
        );

        const scrollBarCell: vaxis.Cell = .{
            .char = .{ .grapheme = " " },
            .style = .{ .reverse = true },
        };

        for (scroll_bar_offset..scroll_bar_offset + scroll_bar_height) |i| {
            surface.writeCell(0, @truncate(i), scrollBarCell);
        }

        children[1] = .{
            .surface = surface,
            .origin = .{
                .row = 1,
                .col = 0,
            },
        };

        // Draw scroll down button.
        const down_surf = try self.scroll_down_button.draw(ctx.withConstraints(
            .{ .width = 1, .height = 1 },
            .{ .width = 1, .height = 1 },
        ));
        children[2] = .{
            .surface = down_surf,
            .origin = .{
                .row = max.height - 1,
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

    fn typeErasedEventHandler(ptr: *anyopaque, ctx: *vxfw.EventContext, event: vxfw.Event) anyerror!void {
        const self: *VerticalScrollBar = @ptrCast(@alignCast(ptr));
        try self.handleEvent(ctx, event);
    }

    fn typeErasedDrawFn(ptr: *anyopaque, ctx: vxfw.DrawContext) std.mem.Allocator.Error!vxfw.Surface {
        const self: *VerticalScrollBar = @ptrCast(@alignCast(ptr));
        return try self.draw(ctx);
    }
};
