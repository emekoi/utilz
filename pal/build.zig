const std = @import("std");
const build = std.build;

pub fn install(known: anytype) fn (b: *build.Builder) anyerror!void {
    return struct {
        pub fn func(b: *build.Builder) anyerror!void {
            if (try known.getPath(b.allocator, .data)) |dir| {
                var dir_step = b.addInstallDirectory(.{
                    .source_dir = "pal/palettes",
                    .install_subdir = "pal/palettes",
                    .install_dir = build.InstallDir{ .Custom = dir },
                });

                const install_step = b.step("install-palettes", "install included palettes for pal");
                install_step.dependOn(&dir_step.step);
                b.getInstallStep().dependOn(install_step);
            } else {
                return error.FileNotFound;
            }
        }
    }.func;
    // b.getInstallPath(dir: InstallDir, dest_rel_path: []const u8)
}
