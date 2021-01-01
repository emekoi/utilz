//  Copyright (c) 2020 emekoi
//
//  This library is free software; you can redistribute it and/or modify it
//  under the terms of the MIT license. See LICENSE for details.
//

const std = @import("std");
const known = @import("known-folders");
const clap = @import("clap");

const palette = @import("pal/palette.zig");
const replaceWriter = @import("pal/replace_writer.zig").replaceWriter;

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

fn die(comptime fmt_str: []const u8, args: anytype) u8 {
    std.debug.print(fmt_str ++ "\n", args);
    return 1;
}

fn paletteLocal() !fs.Dir {
    return try fs.cwd().makeOpenPath("pal", .{});
}

fn getPalette(set: *palette.PaleteSet, full_name: []const u8, dir: fs.Dir) !palette.Palette {
    var name_iter = std.mem.split(full_name, "-");
    const base = name_iter.next().?;

    if (set.get(full_name)) |p| {
        return p;
    }

    var p_file = try dir.openFile(base, .{});
    defer p_file.close();

    try set.add(base, p_file.reader());
    return set.get(full_name) orelse error.InvalidPalette;
}

pub fn main() !u8 {
    var gpa = heap.GeneralPurposeAllocator(.{}){
        .backing_allocator = heap.page_allocator,
    };
    var gpa_alloc = &gpa.allocator;
    defer _ = gpa.deinit();

    const stderr = replaceWriter(io.getStdErr().writer(), "\t", "  ").writer();

    var palette_set = palette.PaleteSet.init(gpa_alloc);
    defer palette_set.deinit();

    const pal_dir = blk: {
        if (try known.open(gpa_alloc, .data, .{})) |dir| {
            break :blk dir.makeOpenPath("pal", .{}) catch try paletteLocal();
        } else {
            break :blk try paletteLocal();
        }
    };

    const palette_dir = try pal_dir.makeOpenPath("palettes", .{});

    var diag: clap.Diagnostic = undefined;
    var args = clap.parse(clap.Help, &cli_params, gpa_alloc, &diag) catch |err| {
        diag.report(stderr, err) catch {};

        try stderr.print("\n", .{});
        try clap.help(stderr, &cli_params);
        return 0;
    };
    defer args.deinit();

    if (args.flag("--help")) {
        try stderr.print("pal: {} [options] [palettes]\n", .{args.exe_arg});
        try clap.help(stderr, &cli_params);
        return 0;
    }

    var buf: [32]u8 = undefined;

    const current_palette: ?palette.Palette = blk: {
        if (args.flag("--current")) {
            var current_file = pal_dir.openFile("current", .{}) catch |e| {
                return die("cannot get current palette: {}", .{e});
            };
            defer current_file.close();

            const cp_name = std.mem.trim(u8, buf[0..(try current_file.reader().read(&buf))], " \n\r\t");

            break :blk getPalette(&palette_set, cp_name, palette_dir) catch |e| {
                return die("invalid palette \"{}\" set as current palette: {}", .{ cp_name, e });
            };
        } else {
            break :blk null;
        }
    };

    if (args.flag("--set")) {
        const desired_palette = blk: {
            if (current_palette) |p| {
                break :blk p;
            } else {
                const idx = switch (args.positionals().len) {
                    0 => {
                        try stderr.print("no palette supplied\n\n", .{});
                        try stderr.print("pal: {} [options] [palettes]\n", .{args.exe_arg});
                        try clap.help(stderr, &cli_params);
                        std.os.exit(1);
                    },
                    1 => 0,
                    else => i: {
                        var r = &rand.Xoroshiro128.init(@intCast(u64, std.time.milliTimestamp())).random;
                        break :i r.uintLessThan(usize, args.positionals().len);
                    },
                };

                break :blk getPalette(&palette_set, args.positionals()[idx], palette_dir) catch {
                    return die("invalid palette: {}", .{args.positionals()[idx]});
                };
            }
        };

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

        var current_file: fs.File = pal_dir.createFile("current", .{}) catch |e| {
            return die("cannot access current palette file: {}", .{e});
        };
        defer current_file.close();

        try current_file.writer().print("{}", .{desired_palette.name});
    } else if (args.flag("--palette")) {
        const stdout = io.getStdOut().writer();

        if (current_palette) |p| {
            try stdout.print("current: {}\n\n", .{p});
        }

        for (args.positionals()) |name| {
            var p = getPalette(&palette_set, name, palette_dir) catch {
                try stdout.print("invalid palette: {}\n\n", .{name});
                continue;
            };

            try stdout.print("{}\n\n", .{p});
        }
    } else {
        try stderr.print("pal: {} [options] [palettes]\n", .{args.exe_arg});
        try clap.help(stderr, &cli_params);
    }

    return 0;
}

test "pal" {
    _ = @import("pal/palette.zig");
    _ = @import("pal/parser.zig");
}
