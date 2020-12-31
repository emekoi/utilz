//  Copyright (c) 2020 emekoi
//
//  This library is free software; you can redistribute it and/or modify it
//  under the terms of the MIT license. See LICENSE for details.
//

const std = @import("std");
const known = @import("known-folders");
const clap = @import("clap");

const palette = @import("pal/palette.zig");

const fmt = std.fmt;
const fs = std.fs;
const heap = std.heap;
const io = std.io;
const rand = std.rand;

const cli_params = comptime blk: {
    @setEvalBranchQuota(2000);
    break :blk [_]clap.Param(clap.Help){
        clap.parseParam("-h, --help        display this help and exit.") catch unreachable,
        clap.parseParam("-s, --set         select a random palette from <PALETTE>... or from all available palettes.") catch unreachable,
        clap.parseParam("-p, --palette     preview <PALETTE>...") catch unreachable,
        clap.parseParam("-c, --current     set <PALETTE> to the current palette") catch unreachable,
        clap.parseParam("-b, --broadcast   broadcast changes to all ptys.") catch unreachable,
        clap.parseParam("<PALETTE>...") catch unreachable,
    };
};

fn die(comptime fmt_str: []const u8, args: anytype) noreturn {
    std.debug.print(fmt_str ++ "\n", args);
    std.os.exit(1);
}

pub fn main() !void {
    var gpa = heap.GeneralPurposeAllocator(.{}){
        .backing_allocator = heap.page_allocator,
    };
    var gpa_alloc = &gpa.allocator;
    defer _ = gpa.deinit();

    const palette_dir = blk: {
        const cwd = fs.cwd();
        if (try known.open(gpa_alloc, .data, .{})) |dir| {
            break :blk dir.makeOpenPath("pal", .{ .iterate = true }) catch {
                break :blk try cwd.makeOpenPath("palettes", .{ .iterate = true });
            };
        } else {
            break :blk try cwd.makeOpenPath("palettes", .{ .iterate = true });
        }
    };

    var diag: clap.Diagnostic = undefined;
    var args = clap.parse(clap.Help, &cli_params, gpa_alloc, &diag) catch |err| {
        diag.report(io.getStdErr().writer(), err) catch {};

        const w = io.getStdErr().writer();
        try w.print("\n", .{});
        try clap.help(w, &cli_params);
        return;
    };
    defer args.deinit();

    if (args.flag("--help")) {
        const w = io.getStdErr().writer();
        try w.print("pal: {}\n", .{args.exe_arg});
        try clap.help(w, &cli_params);
    } else {
        var buf: [32]u8 = undefined;

        const current_palette: ?palette.Palette = blk: {
            if (args.flag("--current")) {
                var current_file = palette_dir.openFile("current", .{}) catch |e| {
                    die("cannot get current palette: {}", .{e});
                };
                defer current_file.close();

                const cp_name = buf[0..(try current_file.reader().read(&buf))];

                var p_file = try palette_dir.openFile(cp_name, .{});
                defer p_file.close();
                break :blk try palette.Palette.parse(cp_name, p_file.reader());
            } else {
                break :blk null;
            }
        };

        const desired_palette = blk: {
            if (current_palette) |p| {
                break :blk p;
            } else {
                const idx = switch (args.positionals().len) {
                    0 => die("no palette supplied", .{}),
                    1 => 0,
                    else => i: {
                        var r = &rand.Xoroshiro128.init(@intCast(u64, std.time.milliTimestamp())).random;
                        break :i r.uintLessThan(usize, args.positionals().len);
                    },
                };

                const name = args.positionals()[idx];
                var p_file = try palette_dir.openFile(name, .{});
                defer p_file.close();

                break :blk try palette.Palette.parse(name, p_file.reader());
            }
        };

        if (args.flag("--set")) {
            if (args.flag("--broadcast")) {
                const pts = (try std.fs.openDirAbsolute("/dev/pts/", .{ .iterate = true }));
                var pts_iter = pts.iterate();

                while (try pts_iter.next()) |p| {
                    _ = fmt.parseInt(usize, p.name, 10) catch continue;
                    var pty = try pts.openFile(p.name, .{ .read = true, .write = true });
                    try pty.writer().print("{x}", .{desired_palette});
                }
            } else {
                try io.getStdOut().writer().print("{x}", .{desired_palette});
            }
            // TODO(emekoi): should this be a silent failure?
            var current_file: fs.File = palette_dir.createFile("current", .{}) catch return;
            defer current_file.close();

            try current_file.writer().print("{}", .{desired_palette.name});
        } else if (args.flag("--palette")) {
            const stdout = io.getStdOut().writer();

            if (current_palette) |p| {
                try stdout.print("current: {}\n\n", .{p});
            }

            for (args.positionals()) |name| {
                var p_file = try palette_dir.openFile(name, .{});
                defer p_file.close();

                const p = palette.Palette.parse(name, p_file.reader()) catch |_| {
                    die("invalid palette: {}", .{name});
                };
                try stdout.print("{}\n\n", .{p});
            }
        }
    }
}

test "pal" {
    _ = @import("pal/palette.zig");
    _ = @import("pal/parser.zig");
}
