const std = @import("std");
const builtin = @import("builtin");
const sys = @import("build_sys.zig");

const Builder = std.build.Builder;

const packages = [_]sys.Package{
    .{
        .name = "pal",
        .source = .{ .Local = "pal/pal.zig" },
        .dependencies = &[_]sys.Package{
            .{
                .name = "known-folders",
                .source = .{ .Git = .{ "https://github.com/ziglibs/known-folders.git", "known-folders/known-folders.zig" } },
            },
            .{
                .name = "clap",
                .source = .{ .Git = .{ "https://github.com/Hejsil/zig-clap.git", "zig-clap/clap.zig" } },
            },
        },
    },
};

pub fn build(b: *Builder) !void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    for (packages) |p| {
        try p.build(b, target, mode);
    }
}
