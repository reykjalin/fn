const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

pub const Menu = struct {
    button: vxfw.Button,
    actions: std.ArrayList(*vxfw.Button),
    is_open: bool = false,

    pub fn widget(self: *Menu) vxfw.Widget {
        return .{
            .userdata = self,
            .eventHandler = Menu.typeErasedEventHandler,
            .drawFn = Menu.typeErasedDrawFn,
        };
    }

    pub fn handleEvent(self: *Menu, ctx: *vxfw.EventContext, event: vxfw.Event) anyerror!void {
        switch (event) {
            .mouse => |_| try ctx.requestFocus(self.widget()),
            else => {},
        }
    }

    pub fn draw(self: *Menu, ctx: vxfw.DrawContext) std.mem.Allocator.Error!vxfw.Surface {
        const children = try ctx.arena.alloc(
            vxfw.SubSurface,
            if (self.is_open) 1 + self.actions.items.len else 1,
        );

        const button_surf = try self.button.draw(ctx.withConstraints(
            .{ .width = @intCast(self.button.label.len), .height = 1 },
            .{ .width = @intCast(self.button.label.len), .height = 1 },
        ));
        children[0] = .{
            .surface = button_surf,
            .origin = .{ .row = 0, .col = 0 },
        };

        if (self.is_open) {
            var menu_width: usize = 0;
            for (self.actions.items) |action| {
                if (menu_width < action.label.len) {
                    menu_width = action.label.len;
                }
            }

            for (self.actions.items, 1..) |action, i| {
                const action_surf = try action.widget().draw(ctx.withConstraints(
                    .{ .width = @intCast(action.label.len), .height = 1 },
                    .{ .width = @intCast(menu_width), .height = 1 },
                ));

                children[i] = .{
                    .surface = action_surf,
                    .origin = .{ .row = @intCast(i), .col = 0 },
                };
            }
        }

        return .{
            .size = ctx.max.size(),
            .widget = self.widget(),
            .buffer = &.{},
            .children = children,
            .handles_mouse = true,
            .focusable = true,
        };
    }

    pub fn on_click(ptr: ?*anyopaque, _: *vxfw.EventContext) anyerror!void {
        if (ptr) |p| {
            const self: *Menu = @ptrCast(@alignCast(p));
            self.is_open = !self.is_open;
        }
    }

    fn typeErasedEventHandler(ptr: *anyopaque, ctx: *vxfw.EventContext, event: vxfw.Event) anyerror!void {
        const self: *Menu = @ptrCast(@alignCast(ptr));
        try self.handleEvent(ctx, event);
    }

    fn typeErasedDrawFn(ptr: *anyopaque, ctx: vxfw.DrawContext) std.mem.Allocator.Error!vxfw.Surface {
        const self: *Menu = @ptrCast(@alignCast(ptr));
        return try self.draw(ctx);
    }
};

pub const MenuBar = struct {
    children: []vxfw.SubSurface = undefined,
    menus: std.ArrayList(*Menu),

    pub fn widget(self: *MenuBar) vxfw.Widget {
        return .{
            .userdata = self,
            .eventHandler = MenuBar.typeErasedEventHandler,
            .drawFn = MenuBar.typeErasedDrawFn,
        };
    }

    pub fn handleEvent(self: *MenuBar, ctx: *vxfw.EventContext, event: vxfw.Event) anyerror!void {
        switch (event) {
            .mouse => |_| try ctx.requestFocus(self.widget()),
            else => {},
        }
    }

    pub fn draw(self: *MenuBar, ctx: vxfw.DrawContext) std.mem.Allocator.Error!vxfw.Surface {
        const max = ctx.max.size();
        self.children = try ctx.arena.alloc(vxfw.SubSurface, self.menus.items.len);

        for (self.menus.items, 0..) |menu, i| {
            const surf = try menu.draw(ctx);

            // FIXME: Draw the menu if it's open.

            // FIXME: Need to move .col based on each menu item's width.
            self.children[i] = .{
                .surface = surf,
                .origin = .{ .row = 0, .col = 0 },
            };
        }

        // Catppuccin fg: Text, bg: Surface 1.
        const style = .{
            .fg = .{ .rgb = .{ 205, 214, 244 } },
            .bg = .{ .rgb = .{ 61, 71, 90 } },
        };
        var menu_bar_surf = try vxfw.Surface.initWithChildren(
            ctx.arena,
            self.widget(),
            .{ .width = max.width, .height = 1 },
            self.children,
        );
        @memset(menu_bar_surf.buffer, .{ .style = style });
        menu_bar_surf.focusable = true;
        menu_bar_surf.handles_mouse = true;

        return menu_bar_surf;
    }

    fn typeErasedEventHandler(ptr: *anyopaque, ctx: *vxfw.EventContext, event: vxfw.Event) anyerror!void {
        const self: *MenuBar = @ptrCast(@alignCast(ptr));
        try self.handleEvent(ctx, event);
    }

    fn typeErasedDrawFn(ptr: *anyopaque, ctx: vxfw.DrawContext) std.mem.Allocator.Error!vxfw.Surface {
        const self: *MenuBar = @ptrCast(@alignCast(ptr));
        return try self.draw(ctx);
    }
};
