const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;
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
} else .{};

var debug_allocator: std.heap.DebugAllocator(.{}) = .init;

pub fn main() !void {
    var gpa, const is_debug = gpa: {
        break :gpa switch (builtin.mode) {
            .Debug, .ReleaseSafe => .{ debug_allocator.allocator(), true },
            .ReleaseFast, .ReleaseSmall => .{ std.heap.smp_allocator, false },
        };
    };
    defer if (is_debug) {
        _ = debug_allocator.deinit();
    };

    const arena = std.heap.ArenaAllocator.init(gpa);

    // Process arguments.
    const args = try std.process.argsAlloc(gpa);
    defer std.process.argsFree(gpa, args);

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
    var app = try vxfw.App.init(gpa);
    errdefer app.deinit();

    // Initialize Fönn.
    const fnApp = try gpa.create(fonn.Fn);
    defer gpa.destroy(fnApp);

    // Set up initial state.

    const fnApp_children = try gpa.alloc(vxfw.SubSurface, 3);
    defer gpa.free(fnApp_children);

    const editor_widget = try gpa.create(editor.Editor);
    defer gpa.destroy(editor_widget);

    editor_widget.* = .{
        .cursor = .{ .line = 0, .column = 0 },
        .lines = .empty,
        .line_widgets = .empty,
        .gpa = gpa,
        .arena = arena,
        .file = "",
        .scroll_bars = .{
            .scroll_view = .{
                .children = .{
                    .builder = .{
                        .userdata = editor_widget,
                        .buildFn = editor.Editor.editor_line_widget_builder,
                    },
                },
            },
        },
        .children = undefined,
    };
    editor_widget.scroll_bars.scroll_view.wheel_scroll = 1;

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
        .gpa = gpa,
        .children = fnApp_children,
        .menu_bar = .{
            .menus = try gpa.alloc(*mb.Menu, 2),
        },
        .editor = editor_widget,
    };

    try fnApp.init();

    // Free fn state.
    defer {
        for (fnApp.editor.lines.items) |*l| {
            l.text.deinit(gpa);
        }
        fnApp.editor.lines.deinit(gpa);
        fnApp.editor.line_widgets.deinit(gpa);
        fnApp.editor.arena.deinit();
        fnApp.deinit();
    }

    // Run app.
    try app.run(fnApp.widget(), .{});
    app.deinit();
}
