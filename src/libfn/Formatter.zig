const std = @import("std");

const Formatter = @This();

vtable: *const VTable,

pub const VTable = struct {
    format: *const fn (f: *Formatter, gpa: std.mem.Allocator, input: []const u8) anyerror![]const u8 = format,
};

/// Runs a formatter on the provided input, and returns the formatted output. Caller owns the
/// returned memory.
pub fn format(f: *Formatter, gpa: std.mem.Allocator, input: []const u8) anyerror![]const u8 {
    return try f.vtable.format(f, gpa, input);
}
