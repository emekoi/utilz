//  Copyright (c) 2020-2021 emekoi
//
//  This library is free software; you can redistribute it and/or modify it
//  under the terms of the MIT license. See LICENSE for details.
//

const std = @import("std");
const parser = @import("parser.zig");

const mem = std.mem;

const Writer = std.fs.File.Writer;
const Reader = std.fs.File.Reader;

pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,

    pub fn fromSlice(slice: []const u8) Color {
        return .{
            .r = slice[0],
            .g = slice[1],
            .b = slice[2],
        };
    }

    pub fn format(
        self: Color,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        out_stream: anytype,
    ) !void {
        _ = options;
        if (comptime std.mem.eql(u8, fmt, "x")) {
            try std.fmt.format(out_stream, "#{x:0>2}{x:0>2}{x:0>2}", .{ self.r, self.g, self.b });
        } else {
            try std.fmt.format(out_stream, "{d};{d};{d}", .{ self.r, self.g, self.b });
        }
    }
};

pub const Palette = struct {
    name: []const u8,
    foreground: Color,
    background: Color,
    cursor: Color,
    colors: [16]Color,

    /// prefer manually loading and parsing the palette file to this function.
    pub fn showCurrent(out_stream: anytype) !void {
        var i: usize = 0;

        while (i < 8) : (i += 1) {
            try std.fmt.format(out_stream, "\x1b[48;5;{d}m  \x1b[0m", .{i});
        }
        try std.fmt.format(out_stream, "\n", .{});

        while (i < 16) : (i += 1) {
            try std.fmt.format(out_stream, "\x1b[48;5;{d}m  \x1b[0m", .{i});
        }
    }

    /// this probably isn't what you want as it resets all theming.
    pub fn reset(out_stream: anytype) !void {
        var i: usize = 0;
        while (i < 16) : (i += 1) {
            try std.fmt.format(out_stream, "\x1b]104;{d}\x1b\\", .{i});
        }
        try std.fmt.format(out_stream, "\x1b]110\x1b\\", .{});
        try std.fmt.format(out_stream, "\x1b]111\x1b\\", .{});
        try std.fmt.format(out_stream, "\x1b]112\x1b\\", .{});
    }

    pub fn preview(self: Palette, out_stream: anytype) !void {
        try std.fmt.format(out_stream, "{s}\n", .{self.name});
        for (self.colors[0..8]) |c| {
            try std.fmt.format(out_stream, "\x1b[48;2;{}m  \x1b[0m", .{c});
        }
        try std.fmt.format(out_stream, "\n", .{});
        for (self.colors[8..16]) |c| {
            try std.fmt.format(out_stream, "\x1b[48;2;{}m  \x1b[0m", .{c});
        }
    }

    pub fn apply(self: Palette, out_stream: anytype) !void {
        for (self.colors[0..16]) |c, i| {
            try std.fmt.format(out_stream, "\x1b]4;{d};{x}\x1b\\", .{ i, c });
        }
        try std.fmt.format(out_stream, "\x1b]10;{x}\x1b\\", .{self.foreground});
        try std.fmt.format(out_stream, "\x1b]11;{x}\x1b\\", .{self.background});
        try std.fmt.format(out_stream, "\x1b]12;{x}\x1b\\", .{self.cursor});
    }

    pub fn format(
        self: Palette,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        out_stream: anytype,
    ) !void {
        _ = options;
        if (comptime std.mem.eql(u8, fmt, "x")) {
            try self.apply(out_stream);
        } else if (comptime std.mem.eql(u8, fmt, "s")) {
            try std.fmt.format(out_stream, "[{s}]\n", .{self.name});
            try std.fmt.format(out_stream, "foreground = \"{x}\"\n", .{self.foreground});
            try std.fmt.format(out_stream, "background = \"{x}\"\n", .{self.background});
            try std.fmt.format(out_stream, "cursor = \"{x}\"\n", .{self.cursor});
            try std.fmt.format(out_stream, "colors = [\n", .{});
            for (self.colors[0..16]) |c| {
                try std.fmt.format(out_stream, "  \"{x}\",\n", .{c});
            }
            try std.fmt.format(out_stream, "]", .{});
        } else {
            try self.preview(out_stream);
        }
    }

    // deprecated: use a PaletteSet
    pub fn parseOldFormat(name: []const u8, reader: Reader) !Palette {
        var buf: [32]u8 = undefined;
        var result: Palette = undefined;
        var bytes: [3]u8 = undefined;

        result.name = name;

        while (try reader.readUntilDelimiterOrEof(&buf, '\n')) |line| {
            var toks = mem.split(line, "=");
            const color = toks.next() orelse return error.InvalidPalette;
            try std.fmt.hexToBytes(&bytes, toks.next() orelse return error.InvalidPalette);

            if (mem.eql(u8, color, "background")) {
                result.background = Color.fromSlice(&bytes);
            } else if (mem.eql(u8, color, "foreground")) {
                result.foreground = Color.fromSlice(&bytes);
            } else if (mem.eql(u8, color, "cursor")) {
                result.cursor = Color.fromSlice(&bytes);
            } else if (mem.startsWith(u8, color, "color")) {
                const idx = try std.fmt.parseUnsigned(usize, mem.trimLeft(u8, color, "color"), 10);
                if (idx < result.colors.len) {
                    result.colors[idx] = Color.fromSlice(&bytes);
                }
            }
        }

        return result;
    }
};

pub const PaletteSet = struct {
    const Map = std.StringHashMap(Palette);
    const List = std.ArrayList([]const u8);

    // the Map does not free keys or values so we use the List to track values
    allocator: *mem.Allocator,
    profiles: List,
    palettes: Map,

    pub fn init(allocator: *mem.Allocator) PaletteSet {
        return PaletteSet{
            .allocator = allocator,
            .palettes = Map.init(allocator),
            .profiles = List.init(allocator),
        };
    }

    pub fn add(self: *PaletteSet, name: []const u8, reader: Reader) !void {
        var buf = try reader.readAllAlloc(self.allocator, std.math.maxInt(usize));
        defer self.allocator.free(buf);

        var rem = @as([]const u8, buf);
        while (parser.parsePalette(undefined, rem)) |*r| : (rem = r.rest) {
            var new_name = try self.profiles.addOne();
            new_name.* = try std.fmt.allocPrint(self.allocator, "{s}:{s}", .{ name, r.value.name });
            if (std.mem.eql(u8, r.value.name, "default")) {
                r.value.name = new_name.*[0..name.len];
            } else {
                r.value.name = new_name.*;
            }
            try self.palettes.put(new_name.*, r.value);
        } else |_| {
            if (rem.len != 0) {
                return error.InvalidPalette;
            }
        }
    }

    pub fn get(self: *PaletteSet, name: []const u8) ?Palette {
        if (self.palettes.get(name)) |p| {
            return p;
        } else {
            const full_name = std.fmt.allocPrint(self.allocator, "{s}:default", .{name}) catch return null;
            defer self.allocator.free(full_name);
            return self.palettes.get(full_name);
        }
    }

    pub fn deinit(self: *PaletteSet) void {
        self.palettes.deinit();
        for (self.profiles.items) |n| {
            self.allocator.free(n);
        }
        self.profiles.deinit();
    }
};
