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
        try writer.print("  -v, --version  Print fn help\n", .{});
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
    var lines = std.ArrayList(editor.Line).init(allocator);

    // If we have more than 1 argument, use the last argument as the file to open.
    if (args.len > 1) {
        const file_path = args[args.len - 1];

        // Open the file to read its contents.
        if (std.fs.cwd().openFile(file_path, .{ .mode = .read_only })) |file| {
            defer file.close();

            // Get a buffered reader to read the file.
            var buf_reader = std.io.bufferedReader(file.reader());
            const reader = buf_reader.reader();

            // We'll use an arraylist to read line-by-line.
            var line = std.ArrayList(u8).init(allocator);
            defer line.deinit();

            const writer = line.writer();

            while (reader.streamUntilDelimiter(writer, '\n', null)) {
                // Clear the line so we can use it.
                defer line.clearRetainingCapacity();

                // Move the line contents into a Line struct.
                var l: editor.Line = .{ .text = std.ArrayList(u8).init(allocator) };
                try l.text.appendSlice(line.items);

                // Append the line contents to the initial state.
                try lines.append(l);
            } else |err| switch (err) {
                // Handle the last line of the file.
                error.EndOfStream => {
                    // Move the line contents into a Line struct.
                    var l: editor.Line = .{ .text = std.ArrayList(u8).init(allocator) };
                    try l.text.appendSlice(line.items);

                    // Append the line contents to the initial state.
                    try lines.append(l);
                },
                else => return err,
            }
        } else |_| {
            // We're not interested in doing anything with the errors here, except make sure a line
            // is initialized.
            const line: editor.Line = .{ .text = std.ArrayList(u8).init(allocator) };
            try lines.append(line);
        }
    } else {
        const line: editor.Line = .{ .text = std.ArrayList(u8).init(allocator) };
        try lines.append(line);
    }

    const fnApp_children = try allocator.alloc(vxfw.SubSurface, 3);
    defer allocator.free(fnApp_children);

    const editor_widget = try allocator.create(editor.Editor);
    defer allocator.destroy(editor_widget);

    editor_widget.* = .{
        .cursor = .{ .line = 0, .column = 0 },
        .lines = lines,
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

    if (args.len > 1) {
        fnApp.editor.file = args[args.len - 1];
    }

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
