# ❄️ Fönn

[![Build and run Fönn tests](https://github.com/reykjalin/fn/actions/workflows/tests.yml/badge.svg?branch=main)](https://github.com/reykjalin/fn/actions/workflows/tests.yml) [![builds.sr.ht status](https://builds.sr.ht/~reykjalin/fn/commits/main/tests.yml.svg)](https://builds.sr.ht/~reykjalin/fn/commits/main/tests.yml?)

A code editor for _fun_.

![Screenshot of the fn TUI modifying its own source code](../screenshots/fn.webp)

This is currently a toy project, but `fn` is stable enough that I'm exclusively using it when working on changes to the editor.

My primary goal is to have a modern, capable TUI code editor.
A secondary goal is for `fn` to eventually have both a GUI and a TUI powered by the same text editing "engine".

## Build instructions

```sh
# Debug build in ./zig-out/bin/fn.
zig build

# Run debug build in current directory.
zig build run

# Open a file with debug build.
zig build run -- path/to/file

# Release build in ~/.local/bin/fn.
zig build -Doptimize=ReleaseSafe --prefix ~/.local
```

## Usage

```sh
$ fn --help
Usage: fn [file]

General options:

  -h, --help     Print fn help
  -v, --version  Print fn version

```
