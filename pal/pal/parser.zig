//  Copyright (c) 2020 emekoi
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

fn testParser(comptime parser: anytype, comptime examples: anytype) void {
    inline for (examples) |ex| {
        expectResult(ParserResult(@TypeOf(parser)), .{ .value = ex[1], .rest = ex[2] }, parser(ex[0]));
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
const hex2 = map(u8, toByte2, manyN(2, hex));
const rgb1 = map(Color, toStruct(Color), manyN(3, hex1));
const rgb2 = map(Color, toStruct(Color), manyN(3, hex2));
pub const raw_color = combine(.{
    ascii.char('#'),
    oneOf(.{
        rgb2,
        rgb1,
    }),
});

pub const color = combine(.{
    oneOf(.{ utf8.char('"'), utf8.char('\'') }),
    raw_color,
    oneOf(.{ utf8.char('"'), utf8.char('\'') }),
    ws,
});

test "pal.parser.color" {
    const c = Color{ .r = 0xaa, .g = 0xbb, .b = 0xcc };
    testParser(color, .{
        .{ "'#aabbcc'", c, "" },
        .{ "\"#abc\"", c, "" },
    });
}

const identifier = many(oneOf(.{
    discard(utf8.range('a', 'z')),
    discard(utf8.range('A', 'Z')),
    utf8.char('-'),
}));

pub const section = combine(.{
    ascii.char('['),
    identifier,
    ascii.char(']'),
    ws,
});

test "pal.parser.section" {
    testParser(section, .{
        .{ "[default]", "default", "" },
        .{ "[some-section-name] \n", "some-section-name", "" },
    });
}

const ws = discard(many(oneOf(.{
    utf8.char(' '),
    utf8.char('\n'),
    utf8.char('\r'),
    utf8.char('\t'),
})));

pub const key = combine(.{
    identifier,
    ws,
    utf8.char('='),
    ws,
});

test "pal.parser.key" {
    testParser(key, .{
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
        const List = comptime combine(.{
            ascii.char('['),
            ws,
            parser,
            manyN(n - 1, combine(.{
                combine(.{ delim, ws }),
                parser,
            })),
            opt(combine(.{ delim, ws })),
            ascii.char(']'),
        });

        fn func(str: []const u8) ?Res {
            if (List(str)) |r| {
                var res: Array = undefined;
                for (res[1..]) |*arr, i| {
                    arr.* = r.value[1][i];
                }
                res[0] = r.value[0];
                return Res.init(res, r.rest);
            } else {
                return null;
            }
        }
    }.func;
}

test "pal.parser.arrayN" {
    const array = comptime arrayN(3, color, ascii.char(','));

    const c = Color{ .r = 0xaa, .g = 0xbb, .b = 0xcc };
    testParser(array, .{
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

pub fn comment(s: []const u8) ?Result(void) {
    if (!mem.startsWith(u8, s, "#")) {
        return null;
    } else {
        if (mem.indexOf(u8, s, "\n")) |idx| {
            return Result(void).init({}, s[idx..]);
        } else {
            return Result(void).init({}, "");
        }
    }
}

test "pal.parser.comment" {
    testParser(comment, .{
        .{ "# hello this is a comment", {}, "" },
        .{ "# hello this is a comment\n", {}, "\n" },
    });
}

pub const Value = union(enum) {
    Single: Color,
    Array: [16]Color,
};

pub fn value(str: []const u8) ?Result(Value) {
    const R = Result(Value);
    const A = comptime arrayN(16, color, ascii.char(','));
    if (color(str)) |r| {
        return R.init(Value{ .Single = r.value }, r.rest);
    } else if (A(str)) |r| {
        return R.init(Value{ .Array = r.value }, r.rest);
    } else return null;
}

test "pal.parser.value" {
    testParser(value, .{
        .{ "'#073642'", Value{ .Single = Color{ .r = 0x07, .g = 0x36, .b = 0x42 } }, "" },
        .{ "'#fdf6e3'", Value{ .Single = Color{ .r = 0xfd, .g = 0xf6, .b = 0xe3 } }, "" },
        .{ "'#dc322f'", Value{ .Single = Color{ .r = 0xdc, .g = 0x32, .b = 0x2f } }, "" },
    });
}

pub fn parsePalette(str: []const u8) ?Result(Palette) {
    const Pair = struct {
        k: []const u8,
        v: Value,

        fn getSingle(self: @This()) ?Color {
            switch (self.v) {
                .Single => |c| return c,
                else => return null,
            }
        }

        fn getArray(self: @This()) ?[16]Color {
            switch (self.v) {
                .Array => |c| return c,
                else => return null,
            }
        }
    };

    const Prototype = struct {
        name: []const u8,
        pairs: [4]Pair,
    };

    const pairP = comptime map(Pair, toStruct(Pair), combine(.{ key, value }));
    const protoP = comptime map(Prototype, toStruct(Prototype), combine(.{ section, manyN(4, pairP) }));

    if (protoP(str)) |proto| {
        var result: Palette = undefined;
        result.name = proto.value.name;
        for (proto.value.pairs) |p| {
            if (mem.eql(u8, p.k, "background")) {
                result.background = p.getSingle() orelse return null;
            } else if (mem.eql(u8, p.k, "foreground")) {
                result.foreground = p.getSingle() orelse return null;
            } else if (mem.eql(u8, p.k, "cursor")) {
                result.cursor = p.getSingle() orelse return null;
            } else if (mem.eql(u8, p.k, "colors")) {
                result.colors = p.getArray() orelse return null;
            }
        }
        return Result(Palette).init(result, proto.rest);
    }

    return null;
}

const solarized = blk: {
    @setEvalBranchQuota(10000);

    break :blk Palette{
        .name = "default",
        .background = raw_color("#073642").?.value,
        .foreground = raw_color("#fdf6e3").?.value,
        .cursor = raw_color("#dc322f").?.value,
        .colors = [16]Color{
            raw_color("#073642").?.value,
            raw_color("#dc322f").?.value,
            raw_color("#859900").?.value,
            raw_color("#b58900").?.value,
            raw_color("#268bd2").?.value,
            raw_color("#d33682").?.value,
            raw_color("#2aa198").?.value,
            raw_color("#eee8d5").?.value,
            raw_color("#6c7c80").?.value,
            raw_color("#dc322f").?.value,
            raw_color("#859900").?.value,
            raw_color("#b58900").?.value,
            raw_color("#268bd2").?.value,
            raw_color("#d33682").?.value,
            raw_color("#2aa198").?.value,
            raw_color("#eee8d5").?.value,
        },
    };
};

const solarized_palette_src =
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
;

test "pal.parser.parsePalette" {
    const result = parsePalette(solarized_palette_src);
    std.testing.expect(result != null);

    // expectEquals only check for pointer equality
    // so we have to do this manually
    std.testing.expectEqualSlices(u8, solarized.name, result.?.value.name);
    std.testing.expectEqual(solarized.background, result.?.value.background);
    std.testing.expectEqual(solarized.foreground, result.?.value.foreground);
    std.testing.expectEqual(solarized.cursor, result.?.value.cursor);
    std.testing.expectEqual(solarized.colors, result.?.value.colors);
}

pub fn consume(
    comptime parser: anytype,
    slice: []ParserResult(@TypeOf(parser)),
    str: []const u8,
) ?Result([]ParserResult(@TypeOf(parser))) {
    const Slice = []ParserResult(@TypeOf(parser));
    var idx: usize = 0;
    var rem = str;
    while (parser(rem)) |r| : (idx += 1) {
        if (idx >= slice.len) {
            break;
        } else {
            slice[idx] = r.value;
            rem = r.rest;
        }
    }

    return Result(Slice).init(slice[0..idx], rem);
}

test "pal.parser.consume" {
    const p = comptime ascii.range('a', 'z');
    var arr: [3]u8 = undefined;
    const res = consume(p, &arr, "aaaa");
    std.testing.expect(res != null);
    std.testing.expectEqualSlices(u8, "aaa", arr[0..]);
    std.testing.expectEqualSlices(u8, arr[0..], res.?.value);
    std.testing.expectEqualSlices(u8, "a", res.?.rest);
}

test "pal.parser.parsePalette+consume" {
    var palettes: [2]Palette = undefined;
    const result = consume(parsePalette, &palettes, solarized_palette_src ** 2);
    std.testing.expect(result != null);

    for (result.?.value) |r| {
        std.testing.expectEqualSlices(u8, solarized.name, r.name);
        std.testing.expectEqual(solarized.background, r.background);
        std.testing.expectEqual(solarized.foreground, r.foreground);
        std.testing.expectEqual(solarized.cursor, r.cursor);
        std.testing.expectEqual(solarized.colors, r.colors);
    }
}
