const std = @import("std");
const GitRepoStep = @import("GitRepoStep.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const tracy = libTracy(b, .{ target, optimize });
    buildExample(b, .{
        .target = target,
        .optimize = optimize,
        .lib = tracy,
        .filepath = "examples/hello.zig",
    });
    buildExample(b, .{
        .target = target,
        .optimize = optimize,
        .lib = tracy,
        .filepath = "examples/sleepSort.zig",
    });
    b.installArtifact(tracy);
}

fn buildExample(b: *std.Build, property: BuildInfo) void {
    const exe = b.addExecutable(.{
        .name = property.filename(),
        .root_source_file = .{ .path = property.filepath },
        .target = property.target,
        .optimize = property.optimize,
    });
    for (property.lib.include_dirs.items) |include| {
        exe.include_dirs.append(include) catch {};
    }
    exe.addModule("tracy", module(b));
    exe.linkLibrary(property.lib);
    if (exe.target.isWindows()) {
        exe.linkSystemLibrary("dbghelp");
        exe.linkSystemLibrary("ws2_32");
    }
    exe.linkLibC();

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step(property.filename(), b.fmt("Run the {s} app", .{property.filename()}));
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
        .name = "tracy",
        .target = properties[0],
        .optimize = properties[1],
    });
    lib.defineCMacro("TRACY_ENABLE", "1");
    lib.defineCMacro("TRACY_FIBERS", "1");
    lib.addIncludePath(.{ .path = "dep/tracy.git/public/" });
    lib.addCSourceFile(.{
        .file = .{ .path = "dep/tracy.git/public/TracyClient.cpp" },
        .flags = &.{ "-Wall", "-Wextra", "-Wshadow" },
    });
    lib.pie = true;
    if(lib.target.getAbi() != .msvc)
        lib.linkLibCpp()
    else
        lib.linkLibC();
    lib.step.dependOn(&tracy.step);
    return lib;
}

pub fn module(b: *std.Build) *std.Build.Module {
    return b.createModule(.{
        .source_file = .{
            .path = "src/tracy.zig",
        },
    });
}
const BuildInfo = struct {
    filepath: []const u8,
    lib: *std.Build.Step.Compile,
    target: std.zig.CrossTarget,
    optimize: std.builtin.OptimizeMode,

    fn filename(self: BuildInfo) []const u8 {
        var split = std.mem.split(u8, std.fs.path.basename(self.filepath), ".");
        return split.first();
    }
};
