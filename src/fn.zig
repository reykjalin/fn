const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

const editor = @import("./editor.zig");
const mb = @import("./menu_bar.zig");

const c_mocha = @import("./themes/catppuccin-mocha.zig");

const button_styles: struct {
    default: vaxis.Style = .{ .fg = c_mocha.text, .bg = c_mocha.surface_0 },
    mouse_down: vaxis.Style = .{ .fg = c_mocha.surface_1, .bg = c_mocha.lavender },
    hover: vaxis.Style = .{ .fg = c_mocha.text, .bg = c_mocha.surface_1 },
    focus: vaxis.Style = .{ .fg = c_mocha.text, .bg = c_mocha.blue },
} = .{};

pub const Fn = struct {
    editor: *editor.Editor,
    menu_bar: mb.MenuBar,
    gpa: std.mem.Allocator,
    children: []vxfw.SubSurface,

    pub fn widget(self: *Fn) vxfw.Widget {
        return .{
            .userdata = self,
            .eventHandler = Fn.typeErasedEventHandler,
            .drawFn = Fn.typeErasedDrawFn,
            .captureHandler = Fn.typeErasedCaptureHandler,
        };
    }

    pub fn init(self: *Fn) !void {
        try self.setup_menu_bar();
    }

    pub fn setup_menu_bar(self: *Fn) !void {
        self.menu_bar.style = .{ .fg = c_mocha.text, .bg = c_mocha.surface_0 };

        const file_menu = try self.gpa.create(mb.Menu);
        file_menu.* = .{
            .button = .{
                .label = " File ",
                .userdata = file_menu,
                .onClick = mb.Menu.on_click,
                .style = .{
                    .default = button_styles.default,
                    .mouse_down = button_styles.mouse_down,
                    .hover = button_styles.hover,
                    .focus = button_styles.focus,
                },
            },
            .actions = try self.gpa.alloc(*vxfw.Button, 3),
        };

        const open_button = try self.gpa.create(vxfw.Button);
        open_button.* = .{
            .label = "Open…  Ctrl+O",
            .userdata = self,
            .onClick = Fn.on_open,
            .style = .{
                .default = button_styles.default,
                .mouse_down = button_styles.mouse_down,
                .hover = button_styles.hover,
                .focus = button_styles.focus,
            },
        };

        const save_button = try self.gpa.create(vxfw.Button);
        save_button.* = .{
            .label = "Save    Cmd+S",
            .userdata = self,
            .onClick = Fn.on_save,
            .style = .{
                .default = button_styles.default,
                .mouse_down = button_styles.mouse_down,
                .hover = button_styles.hover,
                .focus = button_styles.focus,
            },
        };

        const quit_button = try self.gpa.create(vxfw.Button);
        quit_button.* = .{
            .label = "Quit   Ctrl+C",
            .userdata = self,
            .onClick = Fn.on_quit,
            .style = .{
                .default = button_styles.default,
                .mouse_down = button_styles.mouse_down,
                .hover = button_styles.hover,
                .focus = button_styles.focus,
            },
        };

        file_menu.actions[0] = open_button;
        file_menu.actions[1] = save_button;
        file_menu.actions[2] = quit_button;

        const edit_menu = try self.gpa.create(mb.Menu);
        edit_menu.* = .{
            .button = .{
                .label = " Edit ",
                .userdata = edit_menu,
                .onClick = mb.Menu.on_click,
                .style = .{
                    .default = button_styles.default,
                    .mouse_down = button_styles.mouse_down,
                    .hover = button_styles.hover,
                    .focus = button_styles.focus,
                },
            },
            .actions = try self.gpa.alloc(*vxfw.Button, 2),
        };

        const copy_button = try self.gpa.create(vxfw.Button);
        copy_button.* = .{
            .label = " Copy   Cmd+C ",
            .userdata = self,
            .onClick = Fn.on_copy,
            .style = .{
                .default = button_styles.default,
                .mouse_down = button_styles.mouse_down,
                .hover = button_styles.hover,
                .focus = button_styles.focus,
            },
        };

        const paste_button = try self.gpa.create(vxfw.Button);
        paste_button.* = .{
            .label = " Paste  Cmd+V ",
            .userdata = self,
            .onClick = Fn.on_save,
            .style = .{
                .default = button_styles.default,
                .mouse_down = button_styles.mouse_down,
                .hover = button_styles.hover,
                .focus = button_styles.focus,
            },
        };

        edit_menu.actions[0] = copy_button;
        edit_menu.actions[1] = paste_button;

        self.menu_bar.menus[0] = file_menu;
        self.menu_bar.menus[1] = edit_menu;
    }

    pub fn deinit(self: *Fn) void {
        for (self.menu_bar.menus) |menu| {
            for (menu.actions) |action_button| {
                self.gpa.destroy(action_button);
            }
            self.gpa.free(menu.actions);

            self.gpa.destroy(menu);
        }
        self.gpa.free(self.menu_bar.menus);
    }

    // File menu.
    pub fn on_open(ptr: ?*anyopaque, ctx: *vxfw.EventContext) anyerror!void {
        if (ptr) |p| {
            const self: *Fn = @ptrCast(@alignCast(p));

            // Make sure all menus are closed after the button is clicked.
            self.close_menus();

            // Re-focus the editor.
            try ctx.requestFocus(self.editor.widget());
            // Make sure we consume the event and redraw after the menus are closed.
            ctx.consumeAndRedraw();
        }
    }
    pub fn on_save(ptr: ?*anyopaque, ctx: *vxfw.EventContext) anyerror!void {
        if (ptr) |p| {
            const self: *Fn = @ptrCast(@alignCast(p));

            try self.save_file();

            // Make sure all menus are closed after the button is clicked.
            self.close_menus();

            // Re-focus the editor.
            try ctx.requestFocus(self.editor.widget());
            // Make sure we consume the event and redraw after the menus are closed.
            ctx.consumeAndRedraw();
        }
    }
    pub fn on_quit(_: ?*anyopaque, ctx: *vxfw.EventContext) anyerror!void {
        ctx.quit = true;
    }

    // Edit menu.
    pub fn on_copy(ptr: ?*anyopaque, ctx: *vxfw.EventContext) anyerror!void {
        if (ptr) |p| {
            const self: *Fn = @ptrCast(@alignCast(p));

            // Make sure all menus are closed after the button is clicked.
            self.close_menus();

            // Re-focus the editor.
            try ctx.requestFocus(self.editor.widget());
            // Make sure we consume the event and redraw after the menus are closed.
            ctx.consumeAndRedraw();
        }
    }
    pub fn on_paste(ptr: ?*anyopaque, ctx: *vxfw.EventContext) anyerror!void {
        if (ptr) |p| {
            const self: *Fn = @ptrCast(@alignCast(p));

            // Make sure all menus are closed after the button is clicked.
            self.close_menus();

            // Re-focus the editor.
            try ctx.requestFocus(self.editor.widget());
            // Make sure we consume the event and redraw after the menus are closed.
            ctx.consumeAndRedraw();
        }
    }

    fn close_menus(self: *Fn) void {
        for (self.menu_bar.menus) |menu| {
            menu.is_open = false;
        }
    }

    fn save_file(self: *Fn) !void {
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

    fn typeErasedCaptureHandler(
        ptr: *anyopaque,
        ctx: *vxfw.EventContext,
        event: vxfw.Event,
    ) anyerror!void {
        const self: *Fn = @ptrCast(@alignCast(ptr));
        switch (event) {
            .mouse => |mouse| {
                if (mouse.type != .press and mouse.button != .left) return;

                var did_click_a_menu = false;
                for (self.menu_bar.menus) |menu| {
                    if (menu.button.has_mouse) did_click_a_menu = true;

                    for (menu.actions) |action| {
                        if (action.has_mouse) did_click_a_menu = true;
                    }
                }

                // If we clicked outside the menus we close them.
                if (!did_click_a_menu) {
                    self.close_menus();
                    ctx.redraw = true;
                }
            },
            else => {},
        }
    }

    fn typeErasedEventHandler(
        ptr: *anyopaque,
        ctx: *vxfw.EventContext,
        event: vxfw.Event,
    ) anyerror!void {
        const self: *Fn = @ptrCast(@alignCast(ptr));

        switch (event) {
            .init => {
                return ctx.requestFocus(self.editor.widget());
            },
            .focus_out => {
                try ctx.setMouseShape(.default);
            },
            .key_press => |key| {
                if (key.matches('c', .{ .ctrl = true })) {
                    ctx.quit = true;
                    return;
                }

                if (key.matches('s', .{ .super = true })) {
                    try self.save_file();
                }
            },
            else => {},
        }
    }

    fn typeErasedDrawFn(
        ptr: *anyopaque,
        ctx: vxfw.DrawContext,
    ) std.mem.Allocator.Error!vxfw.Surface {
        const self: *Fn = @ptrCast(@alignCast(ptr));
        const max = ctx.max.size();

        const bg_surface = try vxfw.Surface.init(
            ctx.arena,
            self.widget(),
            max,
        );
        @memset(bg_surface.buffer, .{ .style = .{ .bg = c_mocha.base, .fg = c_mocha.text } });

        const menu_bar_surface = try self.menu_bar.widget().draw(ctx.withConstraints(
            .{ .width = max.width, .height = max.height },
            .{ .width = max.width, .height = max.height },
        ));
        const editor_surface = try self.editor.widget().draw(ctx.withConstraints(
            .{ .width = max.width, .height = max.height - 1 },
            .{ .width = max.width, .height = max.height - 1 },
        ));

        self.children[0] = .{
            .surface = bg_surface,
            .origin = .{ .row = 0, .col = 0 },
        };
        self.children[1] = .{
            .surface = editor_surface,
            .origin = .{ .row = 1, .col = 0 },
        };
        // We need the menus to appear over the editor, so we draw them last.
        self.children[2] = .{
            .surface = menu_bar_surface,
            .origin = .{ .row = 0, .col = 0 },
        };

        return .{
            .size = max,
            .widget = self.widget(),
            .buffer = &.{},
            .children = self.children,
            .focusable = false,
        };
    }
};
