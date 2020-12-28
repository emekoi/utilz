//  Copyright (c) 2020 emekoi
//
//  This library is free software; you can redistribute it and/or modify it
//  under the terms of the MIT license. See LICENSE for details.
//

const stb = @cImport({
    // @cInclude("stb/stb_image_resize.h");
    @cDefine("STBI_ASSERT(x)", "zig_assert(x)");
    @cDefine("STBI_MALLOC(x)", "zig_malloc(x)");
    @cDefine("STBI_REALLOC(x, n)", "zig_realloc(x, n)");
    @cDefine("STBI_FREE(x)", "zig_free(x)");
    @cDefine("STBI_NO_STDIO", {});
    @cInclude("stb_image.h");
});

const std = @import("std");

comptime {
    _ = @import("stb/zlibc.zig");
}

const debug = std.debug;
const fs = std.fs;
const mem = std.mem;
const io = std.io;

pub const Format = enum {
    RGBA,
    ARGB,
    ABGR,
    BGRA,

    const u5x4 = std.meta.Vector(4, u5);

    pub fn shiftMask(self: Format) u5x4 {
        return switch (self) {
            .BGRA => u5x4{ 16, 8, 0, 24 },
            .RGBA => u5x4{ 0, 8, 16, 24 },
            .ARGB => u5x4{ 8, 16, 24, 0 },
            .ABGR => u5x4{ 24, 16, 8, 0 },
        };
    }
};

pub const Image = struct {
    allocator: *mem.Allocator,
    width: u16,
    height: u16,
    bytes: []u8,

    fn io_cb(comptime S: type) type {
        return struct {
            fn read(user: ?*c_void, data: [*c]u8, size: c_int) callconv(.C) c_int {
                nosuspend {
                    var stream = @ptrCast(?*S, @alignCast(@alignOf(S), user)).?.*;
                    const bytes_read = stream.read(data[0..@intCast(usize, size)]) catch |e| {
                        debug.panic("unable to read from stream of type {}: {}", .{ @typeName(S), e });
                    };
                    return @intCast(c_int, bytes_read);
                }
            }
            fn skip(user: ?*c_void, size: c_int) callconv(.C) void {
                nosuspend {
                    var stream = @ptrCast(?*S, @alignCast(@alignOf(S), user)).?.*;
                    stream.seekBy(@as(isize, size)) catch |e| {
                        debug.panic("unable to seek stream of type {}: {}", .{ @typeName(S), e });
                    };
                }
            }
            fn eof(user: ?*c_void) callconv(.C) c_int {
                nosuspend {
                    var stream = @ptrCast(?*S, @alignCast(@alignOf(S), user)).?.*;
                    var pos = stream.getPos() catch |e| {
                        debug.panic("unable to get current position for stream of type {}: {}", .{ @typeName(S), e });
                    };
                    var end = stream.getEndPos() catch |e| {
                        debug.panic("unable to get end position for stream of type {}: {}", .{ @typeName(S), e });
                    };
                    return if (pos == end) 1 else 0;
                }
            }

            fn cb() stb.stbi_io_callbacks {
                return .{
                    .read = read,
                    .skip = skip,
                    .eof = eof,
                };
            }
        };
    }

    fn loadPixels(comptime fmt: Format, dst: []u8, src: []const u8) void {
        var src_32 = @ptrCast([*]const u32, @alignCast(@alignOf([*]u32), src.ptr))[0 .. src.len / 4];
        var dst_32 = @ptrCast([*]u32, @alignCast(@alignOf([*]u32), dst.ptr))[0 .. dst.len / 4];
        const dst_mask = fmt.shiftMask();
        for (src_32) |s, i| {
            const v = (@splat(4, s) >> Format.RGBA.shiftMask());
            const v_comp = v & @splat(4, @as(u32, 0xff));
            dst_32[i] = @reduce(.Or, v_comp << dst_mask);
        }
    }

    fn initImage(comptime fmt: Format, allocator: *mem.Allocator, pixels: [*c]const u8, data: [3]c_int) !Image {
        var result: Image = .{
            .allocator = allocator,
            .width = @intCast(u16, data[0]),
            .height = @intCast(u16, data[1]),
            .bytes = undefined,
        };
        const len = @intCast(usize, result.width) * @intCast(usize, result.height) * 4;
        result.bytes = try allocator.alloc(u8, len);
        loadPixels(fmt, result.bytes, pixels[0..len]);
        return result;
    }

    pub fn deinit(self: *Image) void {
        self.allocator.free(self.bytes);
    }

    pub fn fromStream(comptime fmt: Format, stream: anytype, allocator: *mem.Allocator) !Image {
        const cb = io_cb(@TypeOf(stream));
        var stream_v = stream;

        var data: [3]c_int = undefined;
        var pixels = stb.stbi_load_from_callbacks(&cb.cb(), @ptrCast(*c_void, &stream_v), &data[0], &data[1], &data[2], 4);
        if (pixels) |p| {
            defer stb.stbi_image_free(p);
            return initImage(fmt, allocator, p, data);
        } else {
            return error.StbError;
        }
    }

    pub fn fromBytes(comptime fmt: Format, allocator: *mem.Allocator, bytes: []const u8) !Image {
        var data: [3]c_int = undefined;
        var pixels = stb.stbi_load_from_memory(bytes.ptr, @intCast(c_int, bytes.len), &data[0], &data[1], &data[2], 4);
        if (pixels) |p| {
            defer stb.stbi_image_free(p);
            return initImage(fmt, allocator, p, data);
        } else {
            return error.StbError;
        }
    }
};
