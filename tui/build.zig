const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const root_source_file = b.path("src/main.zig");

    const vaxis_dep = b.dependency("vaxis", .{ .target = target, .optimize = optimize });
    const ltf_dep = b.dependency("log_to_file", .{ .target = target, .optimize = optimize });
    const libfn_dep = b.dependency("libfn", .{ .target = target, .optimize = optimize });

    // Build executable.
    const exe = b.addExecutable(.{
        .name = "fn",
        .root_source_file = root_source_file,
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("vaxis", vaxis_dep.module("vaxis"));
    exe.root_module.addImport("log_to_file", ltf_dep.module("log_to_file"));
    exe.root_module.addImport("libfn", libfn_dep.module("libfn"));
    b.installArtifact(exe);

    // Check step for ZLS build-on-save.
    const exe_check = b.addExecutable(.{
        .name = "fn",
        .root_source_file = root_source_file,
        .target = target,
        .optimize = optimize,
    });
    exe_check.root_module.addImport("vaxis", vaxis_dep.module("vaxis"));
    exe_check.root_module.addImport("log_to_file", ltf_dep.module("log_to_file"));
    exe_check.root_module.addImport("libfn", libfn_dep.module("libfn"));
    const check = b.step("check", "Check if fn compiles");
    check.dependOn(&exe_check.step);

    // Run step.
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // Tests.
    const exe_unit_tests = b.addTest(.{
        .root_source_file = root_source_file,
        .target = target,
        .optimize = optimize,
    });
    exe_unit_tests.root_module.addImport("vaxis", vaxis_dep.module("vaxis"));
    exe_unit_tests.root_module.addImport("log_to_file", ltf_dep.module("log_to_file"));
    exe_unit_tests.root_module.addImport("libfn", libfn_dep.module("libfn"));
    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
