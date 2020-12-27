const std = @import("std");
const mem = std.mem;

const Writer = std.fs.File.Writer;
const Reader = std.fs.File.Reader;

const Color = struct {
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
    fg: Color,
    bg: Color,
    cursor: Color,
    colors: [16]Color,

    pub fn showCurrent(writer: Writer) Writer.Error!void {
        var i: usize = 0;

        while (i < 8) : (i += 1) {
            try writer.print("\x1b[48;5;{}m  \x1b[0m", .{i});
        }
        try writer.print("\n", .{});

        while (i < 16) : (i += 1) {
            try writer.print("\x1b[48;5;{}m  \x1b[0m", .{i});
        }
        try writer.print("\n", .{});
    }

    /// this probably isn't what you want as it resets all theming
    pub fn reset(writer: Writer) Writer.Error!void {
        var i: usize = 0;
        while (i < 16) : (i += 1) {
            try writer.print("\x1b]104;{}\x1b\\", .{i});
        }

        try pty.writer().print("\x1b]110\x1b\\", .{});
        try pty.writer().print("\x1b]111\x1b\\", .{});
        try pty.writer().print("\x1b]112\x1b\\", .{});
    }

    pub fn preview(self: Palette, writer: Writer) Writer.Error!void {
        for (self.colors[0..8]) |c| {
            try writer.print("\x1b[48;2;{}m  \x1b[0m", .{c});
        }
        try writer.print("\n", .{});

        for (self.colors[8..16]) |c| {
            try writer.print("\x1b[48;2;{}m  \x1b[0m", .{c});
        }
        try writer.print("\n", .{});
    }

    pub fn apply(self: Palette, writer: Writer) Writer.Error!void {
        for (self.colors[0..16]) |c, i| {
            try writer.print("\x1b]4;{};{x}\x1b\\", .{ i, c });
        }
        try writer.print("\x1b]10;{x}\x1b\\", .{self.fg});
        try writer.print("\x1b]11;{x}\x1b\\", .{self.bg});
        try writer.print("\x1b]12;{x}\x1b\\", .{self.cursor});
    }

    pub fn parse(reader: Reader) !Palette {
        var buf: [32]u8 = undefined;
        var result: Palette = undefined;
        var bytes: [3]u8 = undefined;

        while (try reader.readUntilDelimiterOrEof(&buf, '\n')) |line| {
            var toks = mem.split(line, "=");
            const color = toks.next() orelse return error.InvalidPalette;
            try std.fmt.hexToBytes(&bytes, toks.next() orelse return error.InvalidPalette);

            if (mem.eql(u8, color, "background")) {
                result.bg = Color.fromSlice(&bytes);
            } else if (mem.eql(u8, color, "foreground")) {
                result.fg = Color.fromSlice(&bytes);
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
