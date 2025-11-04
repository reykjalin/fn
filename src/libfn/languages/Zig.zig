const std = @import("std");

const Zig = @This();

const Language = @import("../Language.zig");
const ZigFmt = @import("../formatters/ZigFmt.zig");

pub fn init() Language {
    return .{
        .formatter = ZigFmt.init(),
    };
}
