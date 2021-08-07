//  Copyright (c) 2020-2021 emekoi
//
//  This library is free software; you can redistribute it and/or modify it
//  under the terms of the MIT license. See LICENSE for details.
//

const std = @import("std");
const stb = @import("stb");
const palette = @import("palette.zig");

const mem = std.mem;

const Color = palette.Color;

// silenty destroys alpha by using the alpha channel to store other info
// only supports generating palettes of up to 256 colors
const MedianCut = struct {
    allocator: *mem.Allocator,
    image: stb.Image,

    fn init(allocator: *mem.Allocator, image: stb.Image) MedianCut {
        return .{ .allocator = allocator, .image = image };
    }

    fn cut(self: *MedianCut, comptime n: u8) ![n]Color {
        return error.Todo;
    }
};

fn sortRGB(colors: []u32) void {
    const impl = struct {
        fn lt(context: void, a: u32, b: u32) bool {
            return a < b;
        }
    };
    std.sort.sort(u8, colors, {}, cmp);
}
