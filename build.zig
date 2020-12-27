const std = @import("std");
const builtin = @import("builtin");
const tools = @import("build_tools.zig");

const Builder = std.build.Builder;
const Pkg = std.build.Pkg;

const binaries = .{
    .{
        .name = "pal",
        .path = "pal/pal.zig",
        .dependencies = .{"known-folders"},
    },
};

const packages = .{
    .{ .name = "known-folders", .path = "deps/known-folders/known-folders.zig" },
    .{ .name = "clap", .path = "deps/zig-clap/clap.zig" },
};

fn addBinary(comptime bin: anytype, b: *Builder, target: std.zig.CrossTarget, mode: builtin.Mode) void {
    const exe = b.addExecutable(bin.name, bin.path);
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    inline for (bin.dependencies) |dep| {
        inline for (packages) |pkg| {
            if (comptime std.mem.eql(u8, pkg.name, dep)) {
                exe.addPackagePath(pkg.name, pkg.path);
            }
        }
    }

    const run_step = b.step(bin.name, "run " ++ bin.name);
    run_step.dependOn(&run_cmd.step);
}

pub fn build(b: *Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    inline for (binaries) |bin| {
        addBinary(bin, b, target, mode);
    }
}
