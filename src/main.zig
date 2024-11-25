const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

const fonn = @import("./fn.zig");
const editor = @import("./editor.zig");
const vsb = @import("./vertical_scroll_bar.zig");
const mb = @import("./menu_bar.zig");

const c_mocha = @import("./themes/catppuccin-mocha.zig");

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
    if (args.len > 1 and (std.mem.eql(u8, args[1], "--version") or std.mem.eql(u8, args[1], "-v"))) {
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

    const button_styles: struct {
        default: vaxis.Style = .{ .fg = c_mocha.text, .bg = c_mocha.surface_0 },
        mouse_down: vaxis.Style = .{ .fg = c_mocha.surface_1, .bg = c_mocha.lavender },
        hover: vaxis.Style = .{ .fg = c_mocha.text, .bg = c_mocha.surface_1 },
        focus: vaxis.Style = .{ .fg = c_mocha.text, .bg = c_mocha.blue },
    } = .{};

    // Allocate scroll bars.
    const scroll_bar = try allocator.create(vsb.VerticalScrollBar);
    scroll_bar.* = .{
        .total_height = 0,
        .screen_height = 0,
        .scroll_offset = 0,
        .scroll_up_button = try allocator.create(vxfw.Button),
        .scroll_down_button = try allocator.create(vxfw.Button),
    };
    scroll_bar.scroll_up_button.* = .{
        .label = "\u{2191}",
        .userdata = scroll_bar,
        .onClick = vsb.VerticalScrollBar.on_up_button_click,
        .style = .{
            .default = button_styles.default,
            .mouse_down = button_styles.mouse_down,
            .hover = button_styles.hover,
            .focus = button_styles.focus,
        },
    };
    scroll_bar.scroll_down_button.* = .{
        .label = "\u{2193}",
        .userdata = scroll_bar,
        .onClick = vsb.VerticalScrollBar.on_down_button_click,
        .style = .{
            .default = button_styles.default,
            .mouse_down = button_styles.mouse_down,
            .hover = button_styles.hover,
            .focus = button_styles.focus,
        },
    };

    const fnApp_children = try allocator.alloc(vxfw.SubSurface, 3);
    defer allocator.free(fnApp_children);

    // Set initial state.
    fnApp.* = .{
        .gpa = allocator,
        .children = fnApp_children,
        .menu_bar = .{
            .menus = try allocator.alloc(*mb.Menu, 2),
        },
        .editor = .{
            .cursor = .{ .line = 0, .column = 0 },
            .lines = lines,
            .gpa = allocator,
            .file = "",
            .vertical_scroll_offset = 0,
            .horizontal_scroll_offset = 0,
            .vertical_scroll_bar = scroll_bar,
            .children = undefined,
        },
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
        fnApp.deinit();

        allocator.destroy(fnApp.editor.vertical_scroll_bar.scroll_up_button);
        allocator.destroy(fnApp.editor.vertical_scroll_bar.scroll_down_button);
        allocator.destroy(fnApp.editor.vertical_scroll_bar);
    }

    // Run app.
    try app.run(fnApp.widget(), .{});
    app.deinit();
}
