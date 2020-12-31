//  Copyright (c) 2020 emekoi
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
        if (comptime std.mem.eql(u8, fmt, "x")) {
            try std.fmt.format(out_stream, "#{x:0>2}{x:0>2}{x:0>2}", .{ self.r, self.g, self.b });
        } else {
            try std.fmt.format(out_stream, "{};{};{}", .{ self.r, self.g, self.b });
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
            try std.fmt.format(out_stream, "\x1b[48;5;{}m  \x1b[0m", .{i});
        }
        try std.fmt.format(out_stream, "\n", .{});

        while (i < 16) : (i += 1) {
            try std.fmt.format(out_stream, "\x1b[48;5;{}m  \x1b[0m", .{i});
        }
    }

    /// this probably isn't what you want as it resets all theming.
    pub fn reset(out_stream: anytype) !void {
        var i: usize = 0;
        while (i < 16) : (i += 1) {
            try std.fmt.format(out_stream, "\x1b]104;{}\x1b\\", .{i});
        }
        try std.fmt.format(out_stream, "\x1b]110\x1b\\", .{});
        try std.fmt.format(out_stream, "\x1b]111\x1b\\", .{});
        try std.fmt.format(out_stream, "\x1b]112\x1b\\", .{});
    }

    pub fn preview(self: Palette, out_stream: anytype) !void {
        try std.fmt.format(out_stream, "{}\n", .{self.name});
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
            try std.fmt.format(out_stream, "\x1b]4;{};{x}\x1b\\", .{ i, c });
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
        if (comptime std.mem.eql(u8, fmt, "x")) {
            try self.apply(out_stream);
        } else {
            try self.preview(out_stream);
        }
    }
};

pub const PaleteSet = struct {
    const Map = std.AutoArrayHashMap([]const u8, Palette);
    palettes: Map,

    pub fn parse(allocator: *mem.Allocator, name: []const u8, reader: Reader) !PaleteSet {
        var buf = try reader.readAllAlloc(allocator, std.math.maxInt(usize));
        var rem = buf;

        var result = PaleteSet{ .palettes = Map.init(allocator) };

        while (parser.parsePalette(rem)) |r| {
            const entry_name = r.value.name;
            r.value.name = std.fmt.allocPrint(allocator, "{}-{}", .{ name, r.value.name });
            result.palettes.put(entry_name, r.value);
            rem = r.rest;
        } else {
            if (rem != "") {
                return error.InvalidPalette;
            }
        }
    }

    pub fn deinit(self: *PaleteSet) void {
        self.palettes.deinit();
    }
};
