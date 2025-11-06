const std = @import("std");
const vxim = @import("vxim");
const vaxis = vxim.vaxis;
const vxfw = vaxis.vxfw;
const builtin = @import("builtin");
const ltf = @import("log_to_file");
const libfn = @import("libfn");

const c_mocha = @import("./themes/catppuccin-mocha.zig");

const Mode = enum {
    normal,
    insert,
};

const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
    mouse: vaxis.Mouse,
    mouse_focus: vaxis.Mouse,
};

const Widget = enum {
    editor,
    dbg,
    file_menu,
    file_menu_save,
    file_menu_quit,
};

const Vxim = vxim.Vxim(Event, Widget);

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

const State = struct {
    gpa: std.mem.Allocator,
    editor: libfn.Editor,
    v_scroll: usize = 0,
    h_scroll: usize = 0,
    mode: Mode = .normal,
};
var state: State = .{ .gpa = undefined, .editor = undefined };

pub fn main() !void {
    const gpa, const is_debug = gpa: {
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
        try writer.flush();
        return;
    }
    if (args.len > 1 and
        (std.mem.eql(u8, args[1], "--version") or std.mem.eql(u8, args[1], "-v")))
    {
        var buffer: [1024]u8 = undefined;
        var stdout = std.fs.File.stdout().writer(&buffer);
        const writer = &stdout.interface;
        try writer.print("0.0.0\n", .{});
        try writer.flush();
        return;
    }

    state.gpa = gpa;
    state.editor = try .init(state.gpa);
    defer state.editor.deinit(state.gpa);

    if (args.len > 1) {
        try state.editor.openFile(state.gpa, args[1]);
    }

    var app: Vxim = .init(gpa);
    defer app.deinit(gpa);

    try app.enterAltScreen();
    try app.setMouseMode(true);

    app._vx.window().showCursor(0, 0);

    try app.startLoop(gpa, update);
}

pub fn update(ctx: Vxim.UpdateContext) !Vxim.UpdateResult {
    switch (ctx.current_event) {
        .key_press => |key| if (state.mode == .normal and key.matches('c', .{ .ctrl = true }))
            return .stop,
        else => {},
    }

    ctx.root_win.clear();

    // Draw editor.
    {
        const scroll_body = ctx.vxim.scrollArea(.editor, ctx.root_win, .{
            .y = 1,
            .height = ctx.root_win.height -| 1,
            .content_height = state.editor.lineCount(),
            .content_width = state.editor.longest_line,
            .v_content_offset = &state.v_scroll,
            .h_content_offset = &state.h_scroll,
        });

        try editor(ctx, scroll_body);

        // Update cursor visibility.
        draw_cursors: {
            if (ctx.vxim.open_menu == .file_menu) {
                scroll_body.hideCursor();
                break :draw_cursors;
            }

            const selection = state.editor.getPrimarySelection();

            const is_selection_row_visible = selection.cursor.row >= state.v_scroll and
                selection.cursor.row < state.v_scroll + scroll_body.height;
            const is_selection_col_visible = selection.cursor.col >= state.h_scroll and
                selection.cursor.col < state.h_scroll + scroll_body.width;

            if (is_selection_row_visible and is_selection_col_visible) {
                const cursor_line = state.editor.getLine(selection.cursor.row);
                const normalized_row = selection.cursor.row -| state.v_scroll;

                const line_with_h_scroll = if (state.h_scroll > cursor_line.len) "" else cursor_line[state.h_scroll..];
                const normalized_col = selection.cursor.getVisualColumnForText(line_with_h_scroll);

                scroll_body.showCursor(@intCast(normalized_col), @intCast(normalized_row));
            } else {
                scroll_body.hideCursor();
            }
        }
    }

    // Draw menubar.
    {
        const menu_bar_action = ctx.vxim.menuBar(ctx.root_win, &.{
            .{
                .name = "File",
                .id = .file_menu,
                .items = &.{
                    .{ .name = "Save", .id = .file_menu_save },
                    .{ .name = "Quit", .id = .file_menu_quit },
                },
            },
        });

        if (menu_bar_action) |a| {
            if (a.id == .file_menu_save and a.action == .clicked) try state.editor.saveFile(state.gpa);
            if (a.id == .file_menu_quit and a.action == .clicked) return .stop;
        }
    }

    // Draw debug info.
    if (builtin.mode == .Debug) {
        const sel = state.editor.getPrimarySelection();
        const cursor_info = try std.fmt.allocPrint(ctx.vxim.arena(), "Cursor: {}", .{
            sel.cursor,
        });

        const line_count = try std.fmt.allocPrint(ctx.vxim.arena(), "lines: {d}", .{state.editor.lineCount()});
        const longest_line = try std.fmt.allocPrint(ctx.vxim.arena(), "longest line: {d}", .{state.editor.longest_line});

        const dbg_width = @max(
            cursor_info.len +| 2,
            line_count.len,
            longest_line.len,
        );
        var dbg_pos: struct { x: u16, y: u16 } = .{ .x = @intCast(ctx.root_win.width -| dbg_width -| 2), .y = 8 };
        const dbg_info = ctx.vxim.window(.dbg, ctx.root_win, .{
            .x = &dbg_pos.x,
            .y = &dbg_pos.y,
            .width = @intCast(dbg_width),
            .height = 5,
        });

        ctx.vxim.text(dbg_info, .{ .text = cursor_info });
        ctx.vxim.text(dbg_info, .{ .text = line_count, .y = 1 });
        ctx.vxim.text(dbg_info, .{ .text = longest_line, .y = 2 });
    }

    // Update cursor shape.
    {
        switch (state.mode) {
            .insert => ctx.root_win.setCursorShape(.beam_blink),
            .normal => ctx.root_win.setCursorShape(.block),
        }
    }

    return .keep_going;
}

fn editor(ctx: Vxim.UpdateContext, container: vaxis.Window) !void {
    std.debug.assert(state.v_scroll < state.editor.lineCount());

    switch (ctx.current_event) {
        .key_press => |key| {
            if (state.mode == .normal) {
                if (key.matches('i', .{})) state.mode = .insert;

                if (key.matches('h', .{})) state.editor.moveSelectionsLeft();
                if (key.matches(vaxis.Key.left, .{})) state.editor.moveSelectionsLeft();
                if (key.matches('j', .{})) state.editor.moveSelectionsDown();
                if (key.matches(vaxis.Key.down, .{})) state.editor.moveSelectionsDown();
                if (key.matches('k', .{})) state.editor.moveSelectionsUp();
                if (key.matches(vaxis.Key.up, .{})) state.editor.moveSelectionsUp();
                if (key.matches('l', .{})) state.editor.moveSelectionsRight();
                if (key.matches(vaxis.Key.right, .{})) state.editor.moveSelectionsRight();
            } else if (state.mode == .insert) {
                if (key.matches(vaxis.Key.enter, .{})) try state.editor.insertTextAtCursors(state.gpa, "\n");
                if (key.matches(vaxis.Key.tab, .{})) try state.editor.insertTextAtCursors(state.gpa, "    ");
                if (key.matches(vaxis.Key.backspace, .{})) try state.editor.deleteCharacterBeforeCursors(state.gpa);
                if (key.matches(vaxis.Key.escape, .{})) state.mode = .normal;

                if (key.matches(vaxis.Key.left, .{})) state.editor.moveSelectionsLeft();
                if (key.matches(vaxis.Key.down, .{})) state.editor.moveSelectionsDown();
                if (key.matches(vaxis.Key.up, .{})) state.editor.moveSelectionsUp();
                if (key.matches(vaxis.Key.right, .{})) state.editor.moveSelectionsRight();

                if (key.matches('c', .{ .ctrl = true })) state.mode = .normal;

                if (key.text) |text| {
                    try state.editor.insertTextAtCursors(state.gpa, text);
                }
            }

            if (key.matches('s', .{ .super = true })) try state.editor.saveFile(state.gpa);
        },
        .mouse => |mouse| if (container.hasMouse(mouse)) |_| {
            if (mouse.button == .left and mouse.type == .press) {
                // We need to make sure we get the mouse row clicked, relative to the window position.
                const mouse_row = mouse.row -| @as(u16, @intCast(container.y_off));
                const clicked_line = mouse_row +| state.v_scroll;

                // We need to make sure we get the mouse column clicked, relative to the container position.
                const mouse_col = mouse.col -| @as(u16, @intCast(container.x_off));
                const clicked_col = mouse_col +| state.h_scroll;

                const row = @min(clicked_line, state.editor.lineCount() -| 1);
                const line = state.editor.getLine(row);

                const line_with_h_scroll = if (state.h_scroll > line.len) "" else line[state.h_scroll..];
                const visual_line_len = if (std.mem.endsWith(u8, line_with_h_scroll, "\n"))
                    line_with_h_scroll.len -| 1
                else
                    line_with_h_scroll.len;

                const col = @min(
                    clicked_col,
                    visual_line_len,
                );

                std.log.debug("clicked: l {d} c {d}", .{ row, col });

                state.editor.selections.clearRetainingCapacity();
                try state.editor.appendSelection(
                    state.gpa,
                    .createCursor(.{ .row = row, .col = col }),
                );
            }
        },
        else => {},
    }

    for (state.v_scroll..state.editor.lineCount()) |idx| {
        const line = state.editor.getLine(idx);

        if (state.h_scroll > line.len -| 1) continue;

        _ = container.printSegment(
            .{ .text = line[state.h_scroll..] },
            .{ .row_offset = @intCast(idx -| state.v_scroll), .wrap = .none },
        );
    }
}

test "refAllDecls" {
    std.testing.refAllDeclsRecursive(@This());
}
