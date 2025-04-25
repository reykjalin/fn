# ❄️ libfn

[![Build and run Fönn tests](https://github.com/reykjalin/fn/actions/workflows/tests.yml/badge.svg?branch=main)](https://github.com/reykjalin/fn/actions/workflows/tests.yml) [![builds.sr.ht status](https://builds.sr.ht/~reykjalin/fn/commits/main/tests.yml.svg)](https://builds.sr.ht/~reykjalin/fn/commits/main/tests.yml?)

If you're looking for the editor, you can find that in the [./tui](./tui) folder.

`libfn` is an editor engine that I'm working on for fun.
It's currently used to power my toy editor project [Fönn](./tui).

If you're working on a Zig project and want to play around with the library itself you can do so by
installing fun with `zig fetch --save git+https://git.sr.ht/~reykjalin/fn`.
You can also try my toy editor by building the editor from the [./tui](./tui) folder.

My primary goal is to eventually have a modern, capable TUI code editor that's powered by a reusable
editing engine. The engine itself will eventually be exposed as a static library with a C API, but
made in Zig. If I can get this project that far that is :)

A secondary goal is for `fn` to eventually have both a GUI and a TUI powered by this same text
editing "engine".

## libfn build instructions

```sh
# Make sure libfn builds.
zig build check

# Run tests.
zig build test
```

## Usage

```sh
$ zig fetch --save git+https://git.sr.ht/~reykjalin/fn
```

Then, in your `build.zig`:

```zig
const target = b.standardTargetOptions(.{});
const optimize = b.standardOptimizeOption(.{});

const libfn_dep = b.dependency("libfn", .{ .optimize = optimize, .target = target });

const exe = b.addExecutable(.{
    .name = "example",
    .root_source_file = root_source_file,
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("libfn", libfn_dep.module("libfn"));

b.installArtifact(exe);
```

and then you can import it in your code:

```zig
const libfn = @import("libfn");

// ...

const editor: libfn.Editor = .init(allocator);
```
