//! Tracy bindings from Zig compiler
//
// The MIT License (Expat)
//
// Copyright (c) 2015-2022, Zig contributors
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//

// Thx: zls developers - https://github.com/zigtools/zls

const std = @import("std");
const c = @cImport({
    @cDefine("TRACY_ENABLE", "1");
    @cInclude("tracy/TracyC.h");
});

pub const callstack_depth = 10;

pub const TracyCZoneCtx = extern struct {
    id: u32,
    active: c_int,

    pub inline fn end(self: @This()) void {
        ___tracy_emit_zone_end(self);
    }

    pub inline fn addText(self: @This(), text: []const u8) void {
        ___tracy_emit_zone_text(self, text.ptr, text.len);
    }

    pub inline fn setName(self: @This(), name: []const u8) void {
        ___tracy_emit_zone_name(self, name.ptr, name.len);
    }

    pub inline fn setColor(self: @This(), color: u32) void {
        ___tracy_emit_zone_color(self, color);
    }

    pub inline fn setValue(self: @This(), value: u64) void {
        ___tracy_emit_zone_value(self, value);
    }
};

const Ctx = TracyCZoneCtx;

pub inline fn trace(comptime src: std.builtin.SourceLocation) Ctx {
    return ___tracy_emit_zone_begin(&.{
        .name = null,
        .function = src.fn_name.ptr,
        .file = src.file.ptr,
        .line = 1,
        .color = 0,
    }, 1);
}

pub inline fn traceNamed(comptime src: std.builtin.SourceLocation, comptime name: [:0]const u8) Ctx {

    // TODO: the below `.line = 1,` should be `.line = src.line`, this is blocked by
    //       https://github.com/ziglang/zig/issues/13315

    return ___tracy_emit_zone_begin(&.{
        .name = name.ptr,
        .function = src.fn_name.ptr,
        .file = src.file.ptr,
        .line = 1,
        .color = 0,
    }, 1);
}

pub fn tracyAllocator(allocator: std.mem.Allocator) TracyAllocator(null) {
    return TracyAllocator(null).init(allocator);
}

pub fn TracyAllocator(comptime name: ?[:0]const u8) type {
    return struct {
        parent_allocator: std.mem.Allocator,

        const Self = @This();

        pub fn init(parent_allocator: std.mem.Allocator) Self {
            return .{
                .parent_allocator = parent_allocator,
            };
        }

        pub fn allocator(self: *Self) std.mem.Allocator {
            return .{
                .ptr = self,
                .vtable = &.{
                    .alloc = allocFn,
                    .resize = resizeFn,
                    .free = freeFn,
                },
            };
        }

        fn allocFn(ptr: *anyopaque, len: usize, ptr_align: u8, ret_addr: usize) ?[*]u8 {
            const self: *Self = @ptrCast(@alignCast(ptr));
            const result = self.parent_allocator.rawAlloc(len, ptr_align, ret_addr);
            if (result) |data| {
                if (len != 0) {
                    if (name) |n| {
                        allocNamed(data, len, n);
                    } else {
                        alloc(data, len);
                    }
                }
            } else {
                messageColor("allocation failed", 0xFF0000);
            }
            return result;
        }

        fn resizeFn(ptr: *anyopaque, buf: []u8, buf_align: u8, new_len: usize, ret_addr: usize) bool {
            const self: *Self = @ptrCast(@alignCast(ptr));
            if (self.parent_allocator.rawResize(buf, buf_align, new_len, ret_addr)) {
                if (name) |n| {
                    freeNamed(buf.ptr, n);
                    allocNamed(buf.ptr, new_len, n);
                } else {
                    free(buf.ptr);
                    alloc(buf.ptr, new_len);
                }

                return true;
            }

            // during normal operation the compiler hits this case thousands of times due to this
            // emitting messages for it is both slow and causes clutter
            return false;
        }

        fn freeFn(ptr: *anyopaque, buf: []u8, buf_align: u8, ret_addr: usize) void {
            const self: *Self = @ptrCast(@alignCast(ptr));
            self.parent_allocator.rawFree(buf, buf_align, ret_addr);
            // this condition is to handle free being called on an empty slice that was never even allocated
            // example case: `std.process.getSelfExeSharedLibPaths` can return `&[_][:0]u8{}`
            if (buf.len != 0) {
                if (name) |n| {
                    freeNamed(buf.ptr, n);
                } else {
                    free(buf.ptr);
                }
            }
        }
    };
}

// This function only accepts comptime known strings, see `messageCopy` for runtime strings
pub inline fn message(comptime msg: [:0]const u8) void {
    c.___tracy_emit_messageL(msg.ptr, 0);
}

// This function only accepts comptime known strings, see `messageColorCopy` for runtime strings
pub inline fn messageColor(comptime msg: [:0]const u8, color: u32) void {
    c.___tracy_emit_messageLC(msg.ptr, color, 0);
}

pub inline fn messageCopy(msg: []const u8) void {
    c.___tracy_emit_message(msg.ptr, msg.len, 0);
}

pub inline fn messageColorCopy(msg: [:0]const u8, color: u32) void {
    c.___tracy_emit_messageC(msg.ptr, msg.len, color, 0);
}

pub inline fn frameMark() void {
    c.___tracy_emit_frame_mark(null);
}

pub inline fn frameMarkNamed(comptime name: [:0]const u8) void {
    c.___tracy_emit_frame_mark(name.ptr);
}

pub inline fn namedFrame(comptime name: [:0]const u8) Frame(name) {
    frameMarkStart(name);
    return .{};
}

pub fn Frame(comptime name: [:0]const u8) type {
    return struct {
        pub fn end(_: @This()) void {
            frameMarkEnd(name);
        }
    };
}

inline fn frameMarkStart(comptime name: [:0]const u8) void {
    c.___tracy_emit_frame_mark_start(name.ptr);
}

inline fn frameMarkEnd(comptime name: [:0]const u8) void {
    c.___tracy_emit_frame_mark_end(name.ptr);
}

inline fn alloc(ptr: [*]u8, len: usize) void {
    c.___tracy_emit_memory_alloc(ptr, len, 0);
}

inline fn allocNamed(ptr: [*]u8, len: usize, comptime name: [:0]const u8) void {
    c.___tracy_emit_memory_alloc_named(ptr, len, 0, name.ptr);
}

inline fn free(ptr: [*]u8) void {
    c.___tracy_emit_memory_free(ptr, 0);
}

inline fn freeNamed(ptr: [*]u8, comptime name: [:0]const u8) void {
    c.___tracy_emit_memory_free_named(ptr, 0, name.ptr);
}

extern fn ___tracy_emit_zone_begin(
    srcloc: *const ___tracy_source_location_data,
    active: c_int,
) TracyCZoneCtx;
extern fn ___tracy_emit_zone_begin_callstack(
    srcloc: *const ___tracy_source_location_data,
    depth: c_int,
    active: c_int,
) TracyCZoneCtx;
extern fn ___tracy_emit_zone_text(ctx: TracyCZoneCtx, txt: [*]const u8, size: usize) void;
extern fn ___tracy_emit_zone_name(ctx: TracyCZoneCtx, txt: [*]const u8, size: usize) void;
extern fn ___tracy_emit_zone_color(ctx: TracyCZoneCtx, color: u32) void;
extern fn ___tracy_emit_zone_value(ctx: TracyCZoneCtx, value: u64) void;
extern fn ___tracy_emit_zone_end(ctx: TracyCZoneCtx) void;
const ___tracy_source_location_data = extern struct {
    name: ?[*:0]const u8,
    function: [*:0]const u8,
    file: [*:0]const u8,
    line: u32,
    color: u32,
};
