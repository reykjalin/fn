const std = @import("std");
const vaxis = @import("vxim").vaxis;
const vxfw = vaxis.vxfw;

const EditorWidget = @import("./EditorWidget.zig");
const mb = @import("./menu_bar.zig");

const c_mocha = @import("./themes/catppuccin-mocha.zig");

const button_styles: struct {
    default: vaxis.Style = .{ .fg = c_mocha.text, .bg = c_mocha.surface_0 },
    mouse_down: vaxis.Style = .{ .fg = c_mocha.surface_1, .bg = c_mocha.lavender },
    hover: vaxis.Style = .{ .fg = c_mocha.text, .bg = c_mocha.surface_1 },
    focus: vaxis.Style = .{ .fg = c_mocha.text, .bg = c_mocha.blue },
} = .{};

pub const Fonn = @This();

editor_widget: *EditorWidget,
menu_bar: mb.MenuBar,
gpa: std.mem.Allocator,
children: []vxfw.SubSurface,

pub fn widget(self: *Fonn) vxfw.Widget {
    return .{
        .userdata = self,
        .eventHandler = Fonn.typeErasedEventHandler,
        .drawFn = Fonn.typeErasedDrawFn,
        .captureHandler = Fonn.typeErasedCaptureHandler,
    };
}

pub fn init(gpa: std.mem.Allocator) !*Fonn {
    var fonn = try gpa.create(Fonn);

    const editor_widget: *EditorWidget = try .init(gpa);

    fonn.* = .{
        .editor_widget = editor_widget,
        .menu_bar = .{
            .menus = try gpa.alloc(*mb.Menu, 2),
        },
        .children = try gpa.alloc(vxfw.SubSurface, 3),
        .gpa = gpa,
    };

    try fonn.setupMenuBar();

    return fonn;
}

pub fn setupMenuBar(self: *Fonn) !void {
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
        .onClick = Fonn.onOpen,
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
        .onClick = Fonn.onSave,
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
        .onClick = Fonn.onQuit,
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
        .onClick = Fonn.onCopy,
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
        .onClick = Fonn.onSave,
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

pub fn deinit(self: *Fonn) void {
    self.editor_widget.deinit();
    self.gpa.destroy(self.editor_widget);

    for (self.menu_bar.menus) |menu| {
        for (menu.actions) |action_button| {
            self.gpa.destroy(action_button);
        }
        self.gpa.free(menu.actions);

        self.gpa.destroy(menu);
    }
    self.gpa.free(self.menu_bar.menus);

    self.gpa.free(self.children);
}

// File menu.
pub fn onOpen(ptr: ?*anyopaque, ctx: *vxfw.EventContext) anyerror!void {
    if (ptr) |p| {
        const self: *Fonn = @ptrCast(@alignCast(p));

        // Make sure all menus are closed after the button is clicked.
        self.closeMenus();

        // Re-focus the editor.
        try ctx.requestFocus(self.editor_widget.widget());
        // Make sure we consume the event and redraw after the menus are closed.
        ctx.consumeAndRedraw();
    }
}
pub fn onSave(ptr: ?*anyopaque, ctx: *vxfw.EventContext) anyerror!void {
    if (ptr) |p| {
        const self: *Fonn = @ptrCast(@alignCast(p));

        try self.saveFile();

        // Make sure all menus are closed after the button is clicked.
        self.closeMenus();

        // Re-focus the editor.
        try ctx.requestFocus(self.editor_widget.widget());
        // Make sure we consume the event and redraw after the menus are closed.
        ctx.consumeAndRedraw();
    }
}
pub fn onQuit(_: ?*anyopaque, ctx: *vxfw.EventContext) anyerror!void {
    ctx.quit = true;
}

// Edit menu.
pub fn onCopy(ptr: ?*anyopaque, ctx: *vxfw.EventContext) anyerror!void {
    if (ptr) |p| {
        const self: *Fonn = @ptrCast(@alignCast(p));

        // Make sure all menus are closed after the button is clicked.
        self.closeMenus();

        // Re-focus the editor.
        try ctx.requestFocus(self.editor_widget.widget());
        // Make sure we consume the event and redraw after the menus are closed.
        ctx.consumeAndRedraw();
    }
}
pub fn onPaste(ptr: ?*anyopaque, ctx: *vxfw.EventContext) anyerror!void {
    if (ptr) |p| {
        const self: *Fonn = @ptrCast(@alignCast(p));

        // Make sure all menus are closed after the button is clicked.
        self.closeMenus();

        // Re-focus the editor.
        try ctx.requestFocus(self.editor_widget.widget());
        // Make sure we consume the event and redraw after the menus are closed.
        ctx.consumeAndRedraw();
    }
}

fn closeMenus(self: *Fonn) void {
    for (self.menu_bar.menus) |menu| {
        menu.is_open = false;
    }
}

fn saveFile(self: *Fonn) !void {
    try self.editor_widget.editor.saveFile();
}

fn typeErasedCaptureHandler(
    ptr: *anyopaque,
    ctx: *vxfw.EventContext,
    event: vxfw.Event,
) anyerror!void {
    const self: *Fonn = @ptrCast(@alignCast(ptr));
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
                self.closeMenus();
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
    const self: *Fonn = @ptrCast(@alignCast(ptr));

    switch (event) {
        .init => {
            return ctx.requestFocus(self.editor_widget.widget());
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
                try self.saveFile();
                ctx.consumeAndRedraw();
            }
        },
        else => {},
    }
}

fn typeErasedDrawFn(
    ptr: *anyopaque,
    ctx: vxfw.DrawContext,
) std.mem.Allocator.Error!vxfw.Surface {
    const self: *Fonn = @ptrCast(@alignCast(ptr));
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
    const editor_surface = try self.editor_widget.widget().draw(ctx.withConstraints(
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
    };
}
