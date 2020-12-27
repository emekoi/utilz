const std = @import("std");
const known = @import("known-folders");
const palette = @import("pal/palette.zig");

const heap = std.heap;
const fmt = std.fmt;

pub fn main() !void {
    var gpa = heap.GeneralPurposeAllocator(.{}){
        .backing_allocator = heap.page_allocator,
    };
    var gpa_alloc = &gpa.allocator;
    defer _ = gpa.deinit();
    const home_dir = try known.open(gpa_alloc, .data, .{});
    const palette_dir = blk: {
        if (try known.open(gpa_alloc, .data, .{})) |dir| {
            break :blk dir.makeOpenPath("pal", .{ .iterate = true }) catch {
                break :blk try std.fs.cwd().makeOpenPath("palettes", .{ .iterate = true });
            };
        } else {
            break :blk try std.fs.cwd().makeOpenPath("palettes", .{ .iterate = true });
        }
    };

    const pts = (try std.fs.openDirAbsolute("/dev/pts/", .{ .iterate = true }));
    var pts_iter = pts.iterate();

    // while (try pts_iter.next()) |p| {
    //     _ = fmt.parseInt(usize, p.name, 10) catch continue;
    //     var pty = try pts.openFile(p.name, .{ .read = true, .write = true });
    //     // try pty.writer().print("pty-{} \x1b[48;5;13yyyyym  \x1b[0m\n", .{p.name});
    // }

    var f: std.fs.File = try palette_dir.openFile("solarized", .{});
    defer f.close();

    var l = try palette.Palette.parse(f.reader());

    // std.log.info(".home: {}", .{l});
    try l.apply(std.io.getStdOut().writer());
}
