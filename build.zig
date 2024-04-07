const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Static C library
    const clib = b.addStaticLibrary(.{
        .name = "libduktape",
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    clib.addCSourceFile(.{
        .file = .{ .path = "duktape-2.7.0/duktape.c" },
        .flags = &[_][]const u8{"-fno-sanitize=undefined"},
    });
    clib.addIncludePath(.{ .cwd_relative = "./duktape-2.7.0/" });
    b.installArtifact(clib);

    // Main zig module
    const module = b.addModule("duktape", .{
        .root_source_file = .{ .path = "src/root.zig" },
        .target = target,
        .optimize = optimize,
    });

    module.linkLibrary(clib);

    // Unit tests
    const lib_unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/root.zig" },
        .target = target,
        .optimize = optimize,
    });
    lib_unit_tests.linkLibrary(clib);

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
}
