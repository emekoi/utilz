<h1 align="center">stb</h1>

a small wrapper for `stb_image` that integrates with zig's allocator interface.

## example
```zig
const std = @import("std");

// if this is not defined and public stb will use
// a GeneralPurposeAllocator backed by a PageAllocator 
pub var zig_c_allocator: *std.mem.Allocator = undefined;

pub fn main() !void {
    var gpa_alloc_state = std.heap.GeneralPurposeAllocator(.{}){
        .backing_allocator = std.heap.page_allocator,
    };
    defer std.debug.assert(!gpa_alloc_state.deinit());
    zig_c_allocator = &gpa_alloc_state.allocator;

    var img_file = try std.fs.cwd().openFile(std.os.argv[1][0..std.mem.len(std.os.argv[1])], .{ .intended_io_mode = .blocking });
    defer img_file.close();

    var img = try Image.fromStream(.BGRA, img_file, zig_c_allocator);
    defer img.deinit();

    std.debug.warn("width: {}, height: {}\n", .{ img.width, img.height });
}

```