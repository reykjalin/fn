const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

pub const Menu = struct {
    button: vxfw.Button,
    actions: []*vxfw.Button,
    is_open: bool = false,

    pub fn widget(self: *Menu) vxfw.Widget {
        return .{
            .userdata = self,
            .eventHandler = Menu.typeErasedEventHandler,
            .captureHandler = Menu.typeErasedCaptureHandler,
            .drawFn = Menu.typeErasedDrawFn,
        };
    }

    pub fn draw(self: *Menu, ctx: vxfw.DrawContext) std.mem.Allocator.Error!vxfw.Surface {
        // If the menu is open we need to account for all the actions,
        // otherwise just the menu button.
        const children = try ctx.arena.alloc(
            vxfw.SubSurface,
            if (self.is_open) 1 + self.actions.len else 1,
        );

        // 1. We need to keep track of the final size of the surface to render it properly.

        // Height = number of rows we draw, in other words the menu button + number of actions we
        //          render.
        const height = if (self.is_open) 1 + self.actions.len else 1;
        // We initialize the width to be at least the width of the menu button. If we need more
        // space for the drop-down panel, that will be set when we draw the actions.
        var width = self.button.label.len;

        // 2. Draw the button to open and close the menu.

        const button_surf = try self.button.draw(ctx.withConstraints(
            .{ .width = @intCast(self.button.label.len), .height = 1 },
            .{ .width = @intCast(self.button.label.len), .height = 1 },
        ));
        children[0] = .{
            .surface = button_surf,
            .origin = .{ .row = 0, .col = 0 },
        };

        // 3. Draw actions if the menu is open.

        if (self.is_open) {
            var menu_width: usize = 0;
            for (self.actions) |action| {
                if (menu_width < action.label.len) {
                    menu_width = action.label.len;
                }
            }

            // Update the total surface width if we need a wider surface.
            if (menu_width > width) width = menu_width;

            for (self.actions, 1..) |action, i| {
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
            .size = .{ .width = @intCast(width), .height = @intCast(height) },
            .widget = self.widget(),
            .buffer = &.{},
            .children = children,
            .focusable = true,
        };
    }

    pub fn on_click(ptr: ?*anyopaque, ctx: *vxfw.EventContext) anyerror!void {
        if (ptr) |p| {
            const self: *Menu = @ptrCast(@alignCast(p));
            self.is_open = !self.is_open;

            // We need to manually make sure the event is consumed and that we redraw.
            ctx.consumeAndRedraw();
        }
    }

    fn typeErasedCaptureHandler(
        ptr: *anyopaque,
        ctx: *vxfw.EventContext,
        event: vxfw.Event,
    ) anyerror!void {
        const self: *Menu = @ptrCast(@alignCast(ptr));

        switch (event) {
            .mouse => |_| try ctx.requestFocus(self.widget()),
            else => {},
        }
    }

    fn typeErasedEventHandler(
        _: *anyopaque,
        _: *vxfw.EventContext,
        _: vxfw.Event,
    ) anyerror!void {}

    fn typeErasedDrawFn(
        ptr: *anyopaque,
        ctx: vxfw.DrawContext,
    ) std.mem.Allocator.Error!vxfw.Surface {
        const self: *Menu = @ptrCast(@alignCast(ptr));
        return try self.draw(ctx);
    }
};

pub const MenuBar = struct {
    children: []vxfw.SubSurface = undefined,
    menus: []*Menu,

    // Default the background pane color to ANSI Color 7.
    style: vaxis.Cell.Style = .{ .bg = .{ .index = 7 } },

    pub fn widget(self: *MenuBar) vxfw.Widget {
        return .{
            .userdata = self,
            .eventHandler = MenuBar.typeErasedEventHandler,
            .drawFn = MenuBar.typeErasedDrawFn,
            .captureHandler = MenuBar.typeErasedCaptureHandler,
        };
    }

    pub fn draw(self: *MenuBar, ctx: vxfw.DrawContext) std.mem.Allocator.Error!vxfw.Surface {
        const max = ctx.max.size();

        // We need children for all the menus, as well as the background bar going across the
        // screen.
        self.children = try ctx.arena.alloc(vxfw.SubSurface, self.menus.len + 1);

        // 1. Draw the background for the menu bar.

        var menu_bar_surf = try vxfw.Surface.init(
            ctx.arena,
            self.widget(),
            .{ .width = max.width, .height = 1 },
        );
        @memset(menu_bar_surf.buffer, .{ .style = self.style });
        menu_bar_surf.focusable = true;

        self.children[0] = .{
            .surface = menu_bar_surf,
            .origin = .{ .row = 0, .col = 0 },
        };

        // 2. Draw the menus.

        var current_col: i17 = 0;
        for (self.menus, 1..) |menu, i| {
            const surf = try menu.draw(ctx);

            self.children[i] = .{
                .surface = surf,
                .origin = .{ .row = 0, .col = current_col },
            };

            current_col +|= @intCast(menu.button.label.len);
        }

        return .{
            .size = max,
            .widget = self.widget(),
            .buffer = &.{},
            .children = self.children,
            .focusable = false,
        };
    }

    fn close_menu(_: *MenuBar, menu: *Menu) void {
        menu.is_open = false;
    }

    fn close_menus(self: *MenuBar) void {
        for (self.menus) |menu| {
            self.close_menu(menu);
        }
    }

    fn typeErasedCaptureHandler(
        ptr: *anyopaque,
        ctx: *vxfw.EventContext,
        event: vxfw.Event,
    ) anyerror!void {
        const self: *MenuBar = @ptrCast(@alignCast(ptr));

        switch (event) {
            .mouse => |_| {
                // If a menu is open and we hover over a different menu, open that menu instead.
                const maybe_open_menu = blk: {
                    for (self.menus) |menu| {
                        if (menu.is_open) break :blk menu;
                    }

                    break :blk null;
                };

                if (maybe_open_menu) |open_menu| {
                    for (self.menus) |menu| {
                        if (menu.button.has_mouse and menu != open_menu) {
                            self.close_menu(open_menu);
                            menu.is_open = true;
                            ctx.redraw = true;
                            break;
                        }
                    }
                }
            },
            else => {},
        }
    }

    fn typeErasedEventHandler(
        _: *anyopaque,
        _: *vxfw.EventContext,
        _: vxfw.Event,
    ) anyerror!void {}

    fn typeErasedDrawFn(ptr: *anyopaque, ctx: vxfw.DrawContext) std.mem.Allocator.Error!vxfw.Surface {
        const self: *MenuBar = @ptrCast(@alignCast(ptr));
        return try self.draw(ctx);
    }
};
