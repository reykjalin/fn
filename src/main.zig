const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;
const ltf = @import("log_to_file");
const builtin = @import("builtin");

const fonn = @import("./fn.zig");
const editor = @import("./editor.zig");
const mb = @import("./menu_bar.zig");

const c_mocha = @import("./themes/catppuccin-mocha.zig");

// Set some scope levels for the vaxis log scopes and log to file in debug mode.
pub const std_options: std.Options = if (builtin.mode == .Debug) .{
    .log_scope_levels = &.{
        .{ .scope = .vaxis, .level = .info },
        .{ .scope = .vaxis_parser, .level = .info },
    },
    .logFn = ltf.log_to_file,
} else .{};

pub fn main() !void {
    // Set up allocator.
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    // Process arguments.
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len > 1 and (std.mem.eql(u8, args[1], "--help") or std.mem.eql(u8, args[1], "-h"))) {
        const writer = std.io.getStdOut().writer();
        try writer.print("Usage: fn [file]\n", .{});
        try writer.print("\n", .{});
        try writer.print("General options:\n", .{});
        try writer.print("\n", .{});
        try writer.print("  -h, --help     Print fn help\n", .{});
        try writer.print("  -v, --version  Print fn version\n", .{});
        std.process.exit(0);
    }
    if (args.len > 1 and
        (std.mem.eql(u8, args[1], "--version") or std.mem.eql(u8, args[1], "-v")))
    {
        const writer = std.io.getStdOut().writer();
        try writer.print("0.0.0\n", .{});
        std.process.exit(0);
    }

    // Initialize vaxis app.
    var app = try vxfw.App.init(allocator);
    errdefer app.deinit();

    // Initialize Fönn.
    const fnApp = try allocator.create(fonn.Fn);
    defer allocator.destroy(fnApp);

    // Set up initial state.

    const fnApp_children = try allocator.alloc(vxfw.SubSurface, 3);
    defer allocator.free(fnApp_children);

    const editor_widget = try allocator.create(editor.Editor);
    defer allocator.destroy(editor_widget);

    editor_widget.* = .{
        .cursor = .{ .line = 0, .column = 0 },
        .lines = std.ArrayList(editor.Line).init(allocator),
        .line_widgets = std.ArrayList(vxfw.RichText).init(allocator),
        .gpa = allocator,
        .arena = std.heap.ArenaAllocator.init(allocator),
        .file = "",
        .scroll_view = .{
            .children = .{
                .builder = .{
                    .userdata = editor_widget,
                    .buildFn = editor.Editor.editor_line_widget_builder,
                },
            },
        },
        .children = undefined,
    };

    // If we have more than 1 argument, use the last argument as the file to open.
    if (args.len > 1) {
        const file_path = args[args.len - 1];
        try editor_widget.load_file(file_path);
    } else {
        // Load an empty file just to initialize the lines correctly.
        try editor_widget.load_file("");
    }

    // Prepare the widgets used to draw the text on the first render.
    // FIXME: there might be a better way to do this? Or at least a better time to do this.
    try editor_widget.update_line_widgets();

    // Set initial state.
    fnApp.* = .{
        .gpa = allocator,
        .children = fnApp_children,
        .menu_bar = .{
            .menus = try allocator.alloc(*mb.Menu, 2),
        },
        .editor = editor_widget,
    };

    try fnApp.init();

    // Free fn state.
    defer {
        for (fnApp.editor.lines.items) |l| {
            l.text.deinit();
        }
        fnApp.editor.lines.deinit();
        fnApp.editor.line_widgets.deinit();
        fnApp.editor.arena.deinit();
        fnApp.deinit();
    }

    // Run app.
    try app.run(fnApp.widget(), .{});
    app.deinit();
}
