//! Minimal hand-rolled Roc runtime + value types for probes (mirrors webbox's roc_abi.zig style).
const std = @import("std");

pub const RocStr = extern struct {
    bytes: ?[*]u8,
    capacity_or_alloc_ptr: usize,
    length: usize,
    pub fn slice(s: *const RocStr) []const u8 {
        if (@as(isize, @bitCast(s.length)) < 0) {
            const raw: *const [24]u8 = @ptrCast(s);
            return raw[0 .. raw[23] & 0x7f];
        }
        const b = s.bytes orelse return "";
        return b[0..s.length];
    }
    pub fn from(text: []const u8) RocStr {
        var s: RocStr = .{ .bytes = null, .capacity_or_alloc_ptr = 0, .length = 0 };
        if (text.len <= 23) {
            const raw: *[24]u8 = @ptrCast(&s);
            @memcpy(raw[0..text.len], text);
            raw[23] = @as(u8, @intCast(text.len)) | 0x80;
            return s;
        }
        const data = withHeader(text.len, 1, false);
        @memcpy(data[0..text.len], text);
        return .{ .bytes = data, .capacity_or_alloc_ptr = text.len << 1, .length = text.len };
    }
};

/// NOTE: field order differs from RocStr: ptr, length, capacity.
pub fn RocList(comptime T: type, comptime rc_elems: bool) type {
    return extern struct {
        ptr: ?[*]T,
        length: usize,
        capacity_or_alloc_ptr: usize,
        const Self = @This();
        pub fn items(s: Self) []const T {
            const p = s.ptr orelse return &.{};
            return p[0..s.length];
        }
        pub fn from(xs: []const T) Self {
            if (xs.len == 0) return .{ .ptr = null, .length = 0, .capacity_or_alloc_ptr = 0 };
            const data = withHeader(xs.len * @sizeOf(T), xs.len, rc_elems);
            @memcpy(data[0 .. xs.len * @sizeOf(T)], std.mem.sliceAsBytes(xs));
            return .{ .ptr = @ptrCast(@alignCast(data)), .length = xs.len, .capacity_or_alloc_ptr = xs.len << 1 };
        }
    };
}
pub const Bytes = RocList(u8, false);

fn withHeader(len: usize, count: usize, rc_elems: bool) [*]u8 {
    const w = @sizeOf(usize);
    const hdr: usize = if (rc_elems) 2 * w else w;
    const base: [*]u8 = @ptrCast(roc_alloc(hdr + len, w));
    const data = base + hdr;
    @as(*usize, @ptrCast(@alignCast(data - w))).* = 1;
    if (rc_elems) @as(*usize, @ptrCast(@alignCast(data - 2 * w))).* = count;
    return data;
}

var arena_state: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
pub var bytes_allocated: usize = 0;
pub var allocs: usize = 0;
const header = 16;
fn allocate(len: usize) [*]u8 {
    bytes_allocated += len;
    allocs += 1;
    const got = arena_state.allocator().alignedAlloc(u8, .fromByteUnits(header), header + len) catch @panic("oom");
    std.mem.writeInt(usize, got[0..8], len, .little);
    return got.ptr + header;
}
pub fn reset() void {
    _ = arena_state.reset(.retain_capacity);
}
export fn roc_alloc(len: usize, alignment: usize) callconv(.c) *anyopaque {
    std.debug.assert(alignment <= header);
    return allocate(len);
}
export fn roc_realloc(ptr: *anyopaque, len: usize, alignment: usize) callconv(.c) *anyopaque {
    _ = alignment;
    const old: [*]u8 = @ptrCast(ptr);
    const was = std.mem.readInt(usize, (old - header)[0..8], .little);
    const new = allocate(len);
    @memcpy(new[0..@min(was, len)], old[0..@min(was, len)]);
    return new;
}
export fn roc_dealloc(ptr: *anyopaque, alignment: usize) callconv(.c) void {
    _ = ptr;
    _ = alignment;
}
pub var on_crash: ?*const fn ([]const u8) noreturn = null;
export fn roc_crashed(bytes: [*]const u8, len: usize) callconv(.c) void {
    if (on_crash) |f| f(bytes[0..len]);
    std.debug.print("ROC CRASHED: {s}\n", .{bytes[0..len]});
    std.process.exit(99);
}
export fn roc_dbg(bytes: [*]const u8, len: usize) callconv(.c) void {
    std.debug.print("dbg: {s}\n", .{bytes[0..len]});
}
export fn roc_expect_failed(bytes: [*]const u8, len: usize) callconv(.c) void {
    std.debug.print("expect failed: {s}\n", .{bytes[0..len]});
}

pub fn nowNs() u64 {
    var ts: std.os.linux.timespec = undefined;
    _ = std.os.linux.clock_gettime(.MONOTONIC, &ts);
    return @as(u64, @intCast(ts.sec)) * 1_000_000_000 + @as(u64, @intCast(ts.nsec));
}
