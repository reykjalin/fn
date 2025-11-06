const std = @import("std");

const Formatter = @import("../Formatter.zig");

const ZigFmt = @This();

pub fn init() Formatter {
    return .{
        .vtable = &.{
            .format = format,
        },
    };
}

pub fn format(f: *Formatter, gpa: std.mem.Allocator, input: []const u8) anyerror![]const u8 {
    _ = f;
    const log = std.log.scoped(.zig_fmt);

    log.debug("formatting with `zig fmt`:\n{s}", .{input});

    var child = std.process.Child.init(&.{ "zig", "fmt", "--stdin" }, gpa);
    child.stdin_behavior = .Pipe;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;
    errdefer _ = child.kill() catch void;

    try child.spawn();

    const stdin = child.stdin.?;

    var buffer: [4096]u8 = undefined;
    var w = stdin.writer(&buffer);
    _ = try w.interface.writeAll(input);
    try w.interface.flush();

    stdin.close();
    child.stdin = null;

    var out: std.ArrayList(u8) = .empty;
    var err: std.ArrayList(u8) = .empty;
    defer out.deinit(gpa);
    defer err.deinit(gpa);

    // FIXME: maxInt(usize) is probably excessive here?
    try child.collectOutput(gpa, &out, &err, std.math.maxInt(usize));

    log.debug("stdout:\n{s}", .{out.items});
    log.debug("stderr:\n{s}", .{err.items});

    const result = try child.wait();

    log.debug("result: {}", .{result});

    if (result.Exited == 0) return out.toOwnedSlice(gpa);

    return error.FailedToFormat;
}
