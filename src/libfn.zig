//! `libfn` is a text editing engine that (will eventually) come with all kinds of features
//! built-in. Things like managing multiple selections, insertions, deletions, undo/redo, will all
//! be supported out of the box. The core will also do tokenization via tree-sitter and offer a
//! Language Server integration. Essentially: everything you need for a decent code editor.
//!
//! Currently `libfn` can only load files into a very basic text buffer. These docs will be updated
//! as new features will be added.

const std = @import("std");

pub const Pos = @import("pos.zig").Pos;
pub const Range = @import("Range.zig");
pub const Selection = @import("Selection.zig");
pub const Editor = @import("Editor.zig");

test {
    std.testing.refAllDecls(@This());
}
