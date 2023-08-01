const std = @import("std");
const GitRepoStep = @import("GitRepoStep.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const tracy = libTracy(b, .{ target, optimize });
    const exe = b.addExecutable(.{
        .name = "tracy-zig",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    for (tracy.include_dirs.items) |include| {
        exe.include_dirs.append(include) catch {};
    }
    exe.linkLibrary(tracy);
    if (target.isWindows()) {
        exe.linkSystemLibrary("dbghelp");
        exe.linkSystemLibrary("ws2_32");
    }
    exe.linkLibCpp();

    b.installArtifact(tracy);
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", b.fmt("Run the {s} app", .{exe.name}));
    run_step.dependOn(&run_cmd.step);
}

fn libTracy(b: *std.Build, properties: anytype) *std.Build.Step.Compile {
    const tracy = GitRepoStep.create(b, .{
        .url = "https://github.com//wolfpld/tracy.git",
        .branch = "master",
        .sha = "47b724a903dfd4f4ec208e383a956857b2f0a435",
        .fetch_enabled = true,
    });

    const lib = b.addStaticLibrary(.{
        .name = "tracy-zig",
        .target = properties[0],
        .optimize = properties[1],
    });
    lib.defineCMacro("TRACY_ENABLE", "1");
    lib.addIncludePath(.{ .path = "dep/tracy.git/public/" });
    lib.addCSourceFile(.{
        .file = .{ .path = "dep/tracy.git/public/TracyClient.cpp" },
        .flags = &.{ "-Wall", "-Wextra", "-Wshadow" },
    });
    lib.pie = true;
    lib.linkLibCpp();
    lib.step.dependOn(&tracy.step);
    return lib;
}
