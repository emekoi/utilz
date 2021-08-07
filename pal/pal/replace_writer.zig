//  Copyright (c) 2020-2021 emekoi
//
//  This library is free software; you can redistribute it and/or modify it
//  under the terms of the MIT license. See LICENSE for details.
//

const std = @import("std");

pub fn ReplaceWriter(comptime WriterType: type, comptime old: []const u8, comptime new: []const u8) type {
    return struct {
        child_stream: WriterType,

        pub const Error = WriterType.Error;
        pub const Writer = std.io.Writer(*Self, Error, write);

        const Self = @This();

        pub fn write(self: *Self, bytes: []const u8) Error!usize {
            var i: usize = 0;
            var amt: usize = 0;

            while (std.mem.indexOfPos(u8, bytes, i, old)) |idx| {
                amt += old.len + try self.child_stream.write(bytes[i..idx]);
                _ = try self.child_stream.write(new);
                i = idx + old.len;
            } else {
                amt += try self.child_stream.write(bytes[i..]);
            }

            return amt;
        }

        pub fn writer(self: *Self) Writer {
            return .{ .context = self };
        }
    };
}

pub fn replaceWriter(child: anytype, comptime old: []const u8, comptime new: []const u8) ReplaceWriter(@TypeOf(child), old, new) {
    return .{ .child_stream = child };
}
