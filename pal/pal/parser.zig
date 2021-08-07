//  Copyright (c) 2020-2021 emekoi
//
//  This library is free software; you can redistribute it and/or modify it
//  under the terms of the MIT license. See LICENSE for details.
//

const std = @import("std");
const palette = @import("palette.zig");

const Palette = palette.Palette;
const Color = palette.Color;

const mem = std.mem;

usingnamespace @import("mecha");

fn testParser(comptime parser: anytype, comptime examples: anytype) !void {
    var fail = std.testing.FailingAllocator.init(std.testing.allocator, 0);

    inline for (examples) |ex| {
        try expectResult(ParserResult(@TypeOf(parser)), .{ .value = ex[1], .rest = ex[2] }, parser(&fail.allocator, ex[0]));
    }
}

fn toByte(v: u8) u8 {
    return v * 0x10 + v;
}

fn toByte2(v: [2]u8) u8 {
    return v[0] * 0x10 + v[1];
}

const hex = convert(u8, toInt(u8, 16), asStr(ascii.digit(16)));
const hex1 = map(u8, toByte, hex);
const hex2 = map(u8, toByte2, manyN(hex, 2, .{}));
const rgb1 = map(Color, toStruct(Color), manyN(hex1, 3, .{}));
const rgb2 = map(Color, toStruct(Color), manyN(hex2, 3, .{}));
pub const raw_color = combine(.{
    ascii.char('#'),
    oneOf(.{
        rgb2,
        rgb1,
    }),
});

const ws = discard(many(oneOf(.{
    utf8.char(' '),
    utf8.char('\n'),
    utf8.char('\r'),
    utf8.char('\t'),
}), .{ .collect = false }));

pub const color = combine(.{
    oneOf(.{ utf8.char('"'), utf8.char('\'') }),
    raw_color,
    oneOf(.{ utf8.char('"'), utf8.char('\'') }),
    ws,
});

test "pal.parser.color" {
    const c = Color{ .r = 0xaa, .g = 0xbb, .b = 0xcc };
    try testParser(color, .{
        .{ "'#aabbcc'", c, "" },
        .{ "\"#abc\"", c, "" },
    });
}

const identifier = many(oneOf(.{
    discard(utf8.range('a', 'z')),
    discard(utf8.range('A', 'Z')),
    utf8.char('-'),
}), .{ .collect = false });

pub const section = combine(.{
    ascii.char('['),
    identifier,
    ascii.char(']'),
    ws,
});

test "pal.parser.section" {
    try testParser(section, .{
        .{ "[default]", "default", "" },
        .{ "[some-section-name] \n", "some-section-name", "" },
    });
}

pub const key = combine(.{
    identifier,
    ws,
    utf8.char('='),
    ws,
});

test "pal.parser.key" {
    try testParser(key, .{
        .{ "key = value", "key", "value" },
        .{ "key \t\n\r =               value", "key", "value" },
    });
}

pub fn arrayN(
    comptime n: usize,
    comptime parser: anytype,
    comptime delim: anytype,
) Parser([n]ParserResult(@TypeOf(parser))) {
    return struct {
        const Array = [n]ParserResult(@TypeOf(parser));
        const Res = Result(Array);
        const List = combine(.{
            ascii.char('['),
            ws,
            parser,
            manyN(combine(.{
                combine(.{ delim, ws }),
                parser,
            }), n - 1, .{}),
            opt(combine(.{ delim, ws })),
            ascii.char(']'),
        });

        fn func(allocator: *mem.Allocator, str: []const u8) Error!Res {
            if (List(allocator, str)) |r| {
                var res: Array = undefined;
                for (res[1..]) |*arr, i| {
                    arr.* = r.value[1][i];
                }
                res[0] = r.value[0];
                return Res{ .value = res, .rest = r.rest };
            } else |err| {
                return err;
            }
        }
    }.func;
}

test "pal.parser.arrayN" {
    const array = comptime arrayN(3, color, ascii.char(','));

    const c = Color{ .r = 0xaa, .g = 0xbb, .b = 0xcc };
    try testParser(array, .{
        .{ "['#aabbcc' ,  \t'#aabbcc','#aabbcc'\r]A", [3]Color{ c, c, c }, "A" },
        .{
            \\[
            \\ '#aabbcc',
            \\ '#aabbcc',
            \\ '#aabbcc'
            \\]
            ,
            [3]Color{ c, c, c },
            "",
        },
    });
}

pub fn comment(allocator: *mem.Allocator, s: []const u8) Error!Result(void) {
    _ = allocator;
    if (!mem.startsWith(u8, s, "#")) {
        return Error.ParserFailed;
    } else {
        if (mem.indexOf(u8, s, "\n")) |idx| {
            return Result(void){ .value = {}, .rest = s[idx..] };
        } else {
            return Result(void){ .value = {}, .rest = "" };
        }
    }
}

test "pal.parser.comment" {
    try testParser(comment, .{
        .{ "# hello this is a comment", {}, "" },
        .{ "# hello this is a comment\n", {}, "\n" },
    });
}

pub const Value = union(enum) {
    Single: Color,
    Array: [16]Color,
};

pub fn value(allocator: *mem.Allocator, str: []const u8) Error!Result(Value) {
    const R = Result(Value);
    const A = comptime arrayN(16, color, ascii.char(','));
    if (color(allocator, str)) |r| {
        return R{ .value = Value{ .Single = r.value }, .rest = r.rest };
    } else |_| {
        if (A(allocator, str)) |r| {
            return R{ .value = Value{ .Array = r.value }, .rest = r.rest };
        } else |err2| return err2;
    }
}

test "pal.parser.value" {
    try testParser(value, .{
        .{ "'#073642'", Value{ .Single = Color{ .r = 0x07, .g = 0x36, .b = 0x42 } }, "" },
        .{ "'#fdf6e3'", Value{ .Single = Color{ .r = 0xfd, .g = 0xf6, .b = 0xe3 } }, "" },
        .{ "'#dc322f'", Value{ .Single = Color{ .r = 0xdc, .g = 0x32, .b = 0x2f } }, "" },
    });
}

pub fn parsePalette(allocator: *mem.Allocator, str: []const u8) Error!Result(Palette) {
    const Pair = struct {
        k: []const u8,
        v: Value,

        fn getSingle(self: @This()) Error!Color {
            switch (self.v) {
                .Single => |c| return c,
                else => return Error.ParserFailed,
            }
        }

        fn getArray(self: @This()) Error![16]Color {
            switch (self.v) {
                .Array => |c| return c,
                else => return Error.ParserFailed,
            }
        }
    };

    const Prototype = struct {
        name: []const u8,
        pairs: [4]Pair,
    };

    const pairP = comptime map(Pair, toStruct(Pair), combine(.{ key, value }));
    const protoP = comptime map(Prototype, toStruct(Prototype), combine(.{
        discard(ws),
        section,
        manyN(pairP, 4, .{}),
        discard(ws),
    }));

    if (protoP(allocator, str)) |proto| {
        var result: Palette = undefined;
        result.name = proto.value.name;
        for (proto.value.pairs) |p| {
            if (mem.eql(u8, p.k, "background")) {
                result.background = try p.getSingle();
            } else if (mem.eql(u8, p.k, "foreground")) {
                result.foreground = try p.getSingle();
            } else if (mem.eql(u8, p.k, "cursor")) {
                result.cursor = try p.getSingle();
            } else if (mem.eql(u8, p.k, "colors")) {
                result.colors = try p.getArray();
            }
        }
        return Result(Palette){ .value = result, .rest = proto.rest };
    } else |err| return err;
}

fn genSolarized() !Palette {
    @setEvalBranchQuota(10000);
    var fail = std.testing.FailingAllocator.init(undefined, 0);

    return Palette{
        .name = "default",
        .background = (try raw_color(&fail.allocator, "#073642")).value,
        .foreground = (try raw_color(&fail.allocator, "#fdf6e3")).value,
        .cursor = (try raw_color(&fail.allocator, "#dc322f")).value,
        .colors = [16]Color{
            (try raw_color(&fail.allocator, "#073642")).value,
            (try raw_color(&fail.allocator, "#dc322f")).value,
            (try raw_color(&fail.allocator, "#859900")).value,
            (try raw_color(&fail.allocator, "#b58900")).value,
            (try raw_color(&fail.allocator, "#268bd2")).value,
            (try raw_color(&fail.allocator, "#d33682")).value,
            (try raw_color(&fail.allocator, "#2aa198")).value,
            (try raw_color(&fail.allocator, "#eee8d5")).value,
            (try raw_color(&fail.allocator, "#6c7c80")).value,
            (try raw_color(&fail.allocator, "#dc322f")).value,
            (try raw_color(&fail.allocator, "#859900")).value,
            (try raw_color(&fail.allocator, "#b58900")).value,
            (try raw_color(&fail.allocator, "#268bd2")).value,
            (try raw_color(&fail.allocator, "#d33682")).value,
            (try raw_color(&fail.allocator, "#2aa198")).value,
            (try raw_color(&fail.allocator, "#eee8d5")).value,
        },
    };
}

const solarized = genSolarized() catch unreachable;

const solarized_palette_src =
    \\
    \\[default]
    \\background='#073642'
    \\foreground='#fdf6e3'
    \\cursor='#dc322f'
    \\colors = [
    \\'#073642',
    \\'#dc322f',
    \\'#859900',
    \\'#b58900',
    \\'#268bd2',
    \\'#d33682',
    \\'#2aa198',
    \\'#eee8d5',
    \\'#6c7c80',
    \\'#dc322f',
    \\'#859900',
    \\'#b58900',
    \\'#268bd2',
    \\'#d33682',
    \\'#2aa198',
    \\'#eee8d5',
    \\]
    \\
;

test "pal.parser.parsePalette" {
    const result = try parsePalette(undefined, solarized_palette_src);

    // expectEquals only check for pointer equality
    // so we have to do this manually
    try std.testing.expectEqualSlices(u8, solarized.name, result.value.name);
    try std.testing.expectEqual(solarized.background, result.value.background);
    try std.testing.expectEqual(solarized.foreground, result.value.foreground);
    try std.testing.expectEqual(solarized.cursor, result.value.cursor);
    try std.testing.expectEqual(solarized.colors, result.value.colors);
}

pub fn consume(
    comptime parser: anytype,
    allocator: *mem.Allocator,
    slice: []ParserResult(@TypeOf(parser)),
    str: []const u8,
) Error!Result([]ParserResult(@TypeOf(parser))) {
    const Slice = []ParserResult(@TypeOf(parser));
    var idx: usize = 0;
    var rem = str;
    while (parser(allocator, rem)) |r| : ({
        idx += 1;
        rem = r.rest;
    }) {
        if (idx >= slice.len) {
            break;
        } else {
            slice[idx] = r.value;
            if (r.rest.len == 0) break;
        }
    } else |err| return err;

    return Result(Slice){ .value = slice[0..idx], .rest = rem };
}

test "pal.parser.consume" {
    var fail = std.testing.FailingAllocator.init(std.testing.allocator, 0);
    const p = comptime ascii.range('a', 'z');
    var arr: [3]u8 = undefined;
    const res = try consume(p, &fail.allocator, &arr, "aaaa");
    try std.testing.expectEqualSlices(u8, "aaa", arr[0..]);
    try std.testing.expectEqualSlices(u8, arr[0..], res.value);
    try std.testing.expectEqualSlices(u8, "a", res.rest);
}

test "pal.parser.parsePalette+consume" {
    const N = 2;
    var fail = std.testing.FailingAllocator.init(std.testing.allocator, 0);
    var palettes: [N]Palette = undefined;
    const result = try consume(parsePalette, &fail.allocator, &palettes, solarized_palette_src ** N);
    for (result.value) |r| {
        try std.testing.expectEqualSlices(u8, solarized.name, r.name);
        try std.testing.expectEqual(solarized.background, r.background);
        try std.testing.expectEqual(solarized.foreground, r.foreground);
        try std.testing.expectEqual(solarized.cursor, r.cursor);
        try std.testing.expectEqual(solarized.colors, r.colors);
    }
}
