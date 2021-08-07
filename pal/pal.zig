//  Copyright (c) 2020-2021 emekoi
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

const cli_params = blk: {
    @setEvalBranchQuota(2000);
    break :blk [_]clap.Param(clap.Help){
        clap.parseParam("-h, --help         display this help and exit.") catch unreachable,
        clap.parseParam("-s, --set          set the current palettes to <PALETTE> or a random palette from <PALETTE>...") catch unreachable,
        clap.parseParam("-p, --preview      preview <PALETTE>...") catch unreachable,
        clap.parseParam("-c, --current      set <PALETTE> to the current palette") catch unreachable,
        clap.parseParam("-b, --broadcast    broadcast changes to all ptys.") catch unreachable,
        clap.parseParam("-r, --random       select a random palette from all available palettes") catch unreachable,
        clap.parseParam("<PALETTE>...") catch unreachable,
    };
};

fn die(comptime fmt_str: []const u8, args: anytype) u8 {
    std.debug.print(fmt_str ++ "\n", args);
    return 1;
}

fn printHelp(msg: ?[]const u8, exe_arg: ?[]const u8, exit: u8) noreturn {
    const stderr = replaceWriter(io.getStdErr().writer(), "\t", "  ").writer();

    if (msg) |m| stderr.print("{s}\n\n", .{m}) catch {};
    stderr.print("pal: {s} [options] [palettes]\n", .{exe_arg}) catch {};
    clap.help(stderr, &cli_params) catch {};
    std.os.exit(exit);
}

fn paletteLocal() !fs.Dir {
    return try fs.cwd().makeOpenPath("pal", .{});
}

fn getPalette(set: *palette.PaletteSet, name: []const u8, dir: fs.Dir) !palette.Palette {
    const idx = std.mem.indexOf(u8, name, ":") orelse name.len;
    const base = name[0..idx];

    if (set.get(name)) |p| {
        return p;
    }

    var p_file = try dir.openFile(base, .{});
    defer p_file.close();

    try set.add(base, p_file.reader());
    return set.get(name) orelse error.InvalidPalette;
}

fn setPalette(pal: palette.Palette, broadcast: bool) !void {
    if (broadcast) {
        const pts = (try std.fs.openDirAbsolute("/dev/pts/", .{ .iterate = true }));
        var pts_iter = pts.iterate();

        while (try pts_iter.next()) |p| {
            // verify this *looks* like a pty
            _ = fmt.parseInt(usize, p.name, 10) catch continue;
            var pty = try pts.openFile(p.name, .{ .read = false, .write = true });
            try pty.writer().print("{x}", .{pal});
        }
    } else {
        try io.getStdOut().writer().print("{x}", .{pal});
    }
}

fn globalPaletteSet(allocator: *std.mem.Allocator, palette_dir: fs.Dir) !palette.PaletteSet {
    var set = palette.PaletteSet.init(allocator);
    var palette_iter = palette_dir.iterate();

    while (try palette_iter.next()) |pal| {
        var file = try palette_dir.openFile(pal.name, .{});
        defer file.close();

        try set.add(pal.name, file.reader());
    }

    return set;
}

fn fisherYates(comptime T: type, rng: *rand.Random, slice: []T) void {
    var i: usize = slice.len - 1;
    while (i > 0) : (i -= 1) {
        const j = rng.uintLessThan(usize, i + 1);
        std.mem.swap(T, &slice[i], &slice[j]);
    }
}

pub fn main() !u8 {
    var gpa = heap.GeneralPurposeAllocator(.{}){
        .backing_allocator = heap.page_allocator,
    };
    var gpa_alloc = &gpa.allocator;
    defer _ = gpa.deinit();

    const stderr = replaceWriter(io.getStdErr().writer(), "\t", "  ").writer();

    var palette_set = palette.PaletteSet.init(gpa_alloc);
    defer palette_set.deinit();

    const pal_dir = blk: {
        if (try known.open(gpa_alloc, .data, .{})) |dir| {
            break :blk dir.makeOpenPath("pal", .{}) catch try paletteLocal();
        } else {
            break :blk try paletteLocal();
        }
    };

    const palette_dir = try pal_dir.makeOpenPath("palettes", .{ .iterate = true });

    var diag: clap.Diagnostic = undefined;
    var args = clap.parse(
        clap.Help,
        &cli_params,
        .{ .allocator = gpa_alloc, .diagnostic = &diag },
    ) catch |err| {
        diag.report(stderr, err) catch {};
        try stderr.print("\n", .{});
        printHelp("no palette supplied", null, 1);
    };
    defer args.deinit();

    if (args.flag("--help")) {
        printHelp("no palette supplied", args.exe_arg, 0);
    }

    var buf: [32]u8 = undefined;

    const current_palette: ?palette.Palette = blk: {
        if (args.flag("--current")) {
            var file = pal_dir.openFile("current", .{}) catch |e| {
                return die("cannot get current palette: {}", .{e});
            };
            defer file.close();

            const cp_name = std.mem.trim(u8, buf[0..(try file.reader().read(&buf))], " \n\r\t");

            break :blk getPalette(&palette_set, cp_name, palette_dir) catch |e| {
                return die("invalid palette \"{s}\" set as current palette: {}", .{ cp_name, e });
            };
        } else {
            break :blk null;
        }
    };

    var global_set = try globalPaletteSet(gpa_alloc, palette_dir);
    defer global_set.deinit();
    var rng = &rand.Xoroshiro128.init(@intCast(u64, std.time.milliTimestamp())).random;
    fisherYates([]const u8, rng, global_set.profiles.items);

    if (args.flag("--set")) {
        const desired_palette = blk: {
            if (current_palette) |p| {
                break :blk p;
            } else switch (args.positionals().len) {
                0 => {
                    if (args.flag("--random")) {
                        var slice = global_set.profiles.items;
                        var name = slice[rng.uintLessThan(usize, slice.len)];
                        break :blk global_set.palettes.getPtr(name).?.*;
                    } else {
                        printHelp("no palette supplied", args.exe_arg, 0);
                    }
                },
                else => |len| {
                    const idx = if (len > 1) rng.uintLessThan(usize, len) else 0;

                    break :blk getPalette(&palette_set, args.positionals()[idx], palette_dir) catch {
                        return die("invalid palette: {s}", .{args.positionals()[idx]});
                    };
                },
            }
        };

        try setPalette(desired_palette, args.flag("--broadcast"));

        var current_file: fs.File = pal_dir.createFile("current", .{}) catch |e| {
            return die("cannot access current palette file: {s}", .{e});
        };
        defer current_file.close();

        try current_file.writer().print("{s}", .{desired_palette.name});
    } else if (args.flag("--preview")) {
        const stdout = io.getStdOut().writer();

        if (current_palette) |p| {
            try stdout.print("*{}\n", .{p});
            if (args.positionals().len > 0) {
                try stdout.print("\n", .{});
            }
        }

        if (args.positionals().len == 0 or args.flag("--random")) {
            //const n = std.fmt.parseInt(usize, count, 10) catch {
            //    return die("expected natural number got '{s}'", .{count});
            //};

            const take = std.math.clamp(10, 0, global_set.profiles.items.len);
            for (global_set.profiles.items[0..take]) |name, i| {
                try stdout.print("{}\n", .{global_set.palettes.get(name).?});
                if (i != take - 1) {
                    try stdout.print("\n", .{});
                }
            }
        } else {
            for (args.positionals()) |name, i| {
                var p = getPalette(&palette_set, name, palette_dir) catch {
                    try stdout.print("invalid palette: {s}\n\n", .{name});
                    continue;
                };

                try stdout.print("{}\n", .{p});
                if (i != args.positionals().len - 1) {
                    try stdout.print("\n", .{});
                }
            }
        }
    } else {
        printHelp(null, args.exe_arg, 0);
    }

    return 0;
}

test "pal" {
    std.testing.refAllDecls(@This());
    // _ = @import("pal/palette.zig");
    // _ = @import("pal/parser.zig");
}
