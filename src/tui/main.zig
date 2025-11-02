const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;
const builtin = @import("builtin");
const ltf = @import("log_to_file");

const Fonn = @import("./Fonn.zig");
const mb = @import("./menu_bar.zig");

const c_mocha = @import("./themes/catppuccin-mocha.zig");

// Set some scope levels for the vaxis log scopes and log to file in debug mode.
pub const std_options: std.Options = if (builtin.mode == .Debug) .{
    .log_scope_levels = &.{
        .{ .scope = .vaxis, .level = .info },
        .{ .scope = .vaxis_parser, .level = .info },
    },
    .logFn = ltf.log_to_file,
} else .{
    .logFn = ltf.log_to_file,
};

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

    // Process arguments.
    const args = try std.process.argsAlloc(gpa);
    defer std.process.argsFree(gpa, args);

    if (args.len > 1 and (std.mem.eql(u8, args[1], "--help") or std.mem.eql(u8, args[1], "-h"))) {
        var buffer: [1024]u8 = undefined;
        var stdout = std.fs.File.stdout().writer(&buffer);
        const writer = &stdout.interface;
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
        var buffer: [1024]u8 = undefined;
        var stdout = std.fs.File.stdout().writer(&buffer);
        const writer = &stdout.interface;
        try writer.print("0.0.0\n", .{});
        std.process.exit(0);
    }

    // Initialize vaxis app.
    var app = try vxfw.App.init(gpa);
    errdefer app.deinit();

    // Initialize Fönn.
    const fonn: *Fonn = try .init(gpa);
    defer gpa.destroy(fonn);

    // If we have more than 1 argument, use the last argument as the file to open.
    if (args.len > 1) {
        const file_path = args[args.len - 1];
        try fonn.editor_widget.editor.openFile(gpa, file_path);
    } else {
        // Load an empty file just to initialize the lines correctly.
        try fonn.editor_widget.editor.openFile(gpa, "");
    }

    // Prepare the widgets used to draw the text on the first render.
    // FIXME: there might be a better way to do this? Or at least a better time to do this.
    try fonn.editor_widget.updateLineWidgets();

    // Free fn state.
    defer fonn.deinit();

    // Run app.
    try app.run(fonn.widget(), .{});
    app.deinit();
}

test "refAllDecls" {
    std.testing.refAllDeclsRecursive(@This());
}
