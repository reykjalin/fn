const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const root_source_file = b.path("src/libfn/libfn.zig");

    // Build zig module.
    const libfn = b.addModule("libfn", .{
        .root_source_file = root_source_file,
        .target = target,
        .optimize = optimize,
    });

    // Check step for ZLS build-on-save.
    const libfn_check = b.addLibrary(.{
        .name = "libfn",
        .root_module = libfn,
        .linkage = .static,
    });
    const check = b.step("check", "Check if libfn compiles");
    check.dependOn(&libfn_check.step);

    // Tests.
    const libfn_unit_tests = b.addTest(.{
        .root_module = libfn,
        .target = target,
        .optimize = optimize,
    });
    const run_libfn_unit_tests = b.addRunArtifact(libfn_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_libfn_unit_tests.step);

    // Docs.
    const install_docs = b.addInstallDirectory(.{
        .source_dir = libfn_check.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });
    const docs = b.step("docs", "Build libfn library docs");
    docs.dependOn(&install_docs.step);

    const tui = b.option(bool, "tui", "include this option to build the TUI") orelse false;

    // TUI.
    if (tui) {
        const vaxis = b.lazyDependency("vaxis", .{ .target = target, .optimize = optimize });
        const ltf = b.lazyDependency("log_to_file", .{ .target = target, .optimize = optimize });

        if (vaxis) |vaxis_dep| {
            if (ltf) |ltf_dep| {
                const exe = b.addExecutable(.{
                    .name = "fn",
                    .root_source_file = b.path("src/tui/main.zig"),
                    .target = target,
                    .optimize = optimize,
                });
                exe.root_module.addImport("vaxis", vaxis_dep.module("vaxis"));
                exe.root_module.addImport("log_to_file", ltf_dep.module("log_to_file"));
                exe.root_module.addImport("libfn", libfn);

                // Run step.
                const run_cmd = b.addRunArtifact(exe);
                run_cmd.step.dependOn(b.getInstallStep());
                const run_step = b.step("run", "Run the app");
                run_step.dependOn(&run_cmd.step);
                if (b.args) |args| run_cmd.addArgs(args);

                // Build TUI.
                b.installArtifact(exe);
            }
        }
    }
}
