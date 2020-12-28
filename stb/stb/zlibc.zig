//  Copyright (c) 2020 emekoi
//
//  This library is free software; you can redistribute it and/or modify it
//  under the terms of the MIT license. See LICENSE for details.
//

const std = @import("std");

var gpa_alloc_state = std.heap.GeneralPurposeAllocator(.{}){
    .backing_allocator = std.heap.page_allocator,
};

var global_allocator: *std.mem.Allocator = undefined;

fn initAllocFn() void {
    const root = @import("root");
    if (root != @This() and @hasDecl(root, "zig_c_allocator")) {
        global_allocator = root.zig_c_allocator;
    } else {
        global_allocator = &gpa_alloc_state.allocator;
    }
}

var initAlloc = std.once(initAllocFn);

pub export fn zig_assert(ok: c_int) void {
    std.debug.assert(ok != 0);
}

pub export fn zig_malloc(size: usize) ?*c_void {
    initAlloc.call();
    var bytes = global_allocator.alloc(u8, size + @sizeOf(usize)) catch return null;
    std.valgrind.mallocLikeBlock(bytes, 0, false);
    @ptrCast(*usize, @alignCast(@alignOf(usize), bytes.ptr)).* = size;
    return @ptrCast(*c_void, bytes.ptr + @sizeOf(usize));
}

pub export fn zig_free(ptr: ?*c_void) void {
    initAlloc.call();
    if (ptr) |p| {
        var fp = @intToPtr([*]u8, @ptrToInt(p) - @sizeOf(usize));
        const size = @ptrCast(*usize, @alignCast(@alignOf(usize), fp)).* + @sizeOf(usize);
        global_allocator.free(fp[0..size]);
        std.valgrind.freeLikeBlock(fp, 0);
    }
}

pub export fn zig_realloc(ptr: ?*c_void, new: usize) ?*c_void {
    initAlloc.call();
    if (ptr) |p| {
        var old_ptr = @intToPtr([*]u8, @ptrToInt(p) - @sizeOf(usize));
        const old_size = @ptrCast(*usize, @alignCast(@alignOf(usize), old_ptr)).* + @sizeOf(usize);
        var new_ptr = global_allocator.realloc(old_ptr[0..old_size], new + @sizeOf(usize)) catch return null;
        @ptrCast(*usize, @alignCast(@alignOf(usize), new_ptr.ptr)).* = new;
        return @ptrCast(*c_void, new_ptr.ptr + @sizeOf(usize));
    } else return null;
}
