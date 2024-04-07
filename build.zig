const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addStaticLibrary(.{
        .name = "duktape-zig",
        .root_source_file = .{ .path = "src/root.zig" },
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    lib.addCSourceFile(.{
        .file = .{ .cwd_relative = "./duktape-2.7.0/duktape.c" },
        .flags = &[_][]const u8{"-fno-sanitize=undefined"},
    });
    lib.addIncludePath(.{ .cwd_relative = "./duktape-2.7.0/" });
    b.installArtifact(lib);

    const lib_unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/root.zig" },
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    lib_unit_tests.linkLibrary(lib);

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
}
