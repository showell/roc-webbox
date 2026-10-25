//! **ROC'S SIDE OF THE SEAM**: what the Roc app's archive (app/*.roc, built
//! for the platform in platform/) needs from its host, and the strings it
//! hands across.
//!
//!   - the runtime: `roc_alloc`, `roc_realloc`, `roc_dealloc` and
//!     `roc_crashed`;
//!   - the platform's hosted functions (platform/main.roc's `hosted`): the
//!     file effects, over webbox's store, under the data root;
//!   - `RocStr`, and the records `roc_handle` takes and answers.
//!
//! Nothing here calls the operating system: the effects go through
//! webbox.store and the `Io` the host hands each request, so the same file
//! serves on webbox's Linux host and its bare-metal one.
//!
//! **ONE CALL AT A TIME**: webbox runs one handler at a time, so the state a
//! call needs (its `Io`, its arena) is held here, set by `begin` and
//! dropped by `end`.

const std = @import("std");
const webbox = @import("webbox");
const Io = std.Io;
const store = webbox.store;

/// A Roc `Str` (roc's builtins/str.zig, `RocStr`). Three words; a string of
/// at most 23 bytes is held in them (`small`): the last byte its length
/// with the top bit set. A big string's bytes are an allocation whose
/// refcount, a word, is just before them.
pub const RocStr = extern struct {
    bytes: ?[*]u8,
    capacity_or_alloc_ptr: usize,
    length: usize,

    const small_most = @sizeOf(RocStr) - 1;

    fn isSmall(s: *const RocStr) bool {
        return @as(isize, @bitCast(s.length)) < 0;
    }

    /// The bytes, wherever they are held.
    pub fn slice(s: *const RocStr) []const u8 {
        if (s.isSmall()) {
            const raw: *const [@sizeOf(RocStr)]u8 = @ptrCast(s);
            return raw[0 .. raw[small_most] & 0x7f];
        }
        const b = s.bytes orelse return "";
        return b[0..s.length];
    }

    /// A new string holding `text`, in the call's arena: small when it fits,
    /// as Roc makes them, else an allocation with refcount 1.
    pub fn from(text: []const u8) RocStr {
        var s: RocStr = .{ .bytes = null, .capacity_or_alloc_ptr = 0, .length = 0 };
        if (text.len <= small_most) {
            const raw: *[@sizeOf(RocStr)]u8 = @ptrCast(&s);
            @memcpy(raw[0..text.len], text);
            raw[small_most] = @as(u8, @intCast(text.len)) | 0x80;
            return s;
        }
        const data = withRefcount(text.len);
        @memcpy(data[0..text.len], text);
        return .{ .bytes = data, .capacity_or_alloc_ptr = text.len << 1, .length = text.len };
    }
};

/// What the app is handed for a request (platform/Http.roc's `Request`):
/// fields in Roc's order, by alignment and then by name.
pub const Request = extern struct { body: RocStr, method: RocStr, path: RocStr };

/// What the app answers (`Response`).
pub const Response = extern struct { body: RocStr, content_type: RocStr, status: u16 };

/// What `File.read_raw!` answers.
const Read = extern struct { text: RocStr, status: u8 };
const read_found: u8 = 0;
const read_absent: u8 = 1;
const read_failed: u8 = 2;

extern fn roc_handle(req: Request) callconv(.c) Response;

comptime {
    std.debug.assert(@sizeOf(RocStr) == 24 and @sizeOf(Request) == 72 and @sizeOf(Response) == 56 and @sizeOf(Read) == 32);
}

// ── the call ────────────────────────────────────────────────────────────────

/// Everything Roc allocates in a call, dropped at its `end`: so `roc_dealloc`
/// frees nothing, and the refcounts of what the host hands Roc need no
/// keeping (a string the host never releases is one Roc copies before it
/// changes it, never one it frees).
var arena: ?std.heap.ArenaAllocator = null;
var call_io: ?Io = null;
var data_root: []const u8 = "data";

/// Where the app's files go, once, as the site starts: `base` lives as long
/// as the process.
pub fn use(base: std.mem.Allocator, root: []const u8) void {
    arena = .init(base);
    data_root = root;
}

/// The arena's memory back to `base` (a test's root, done).
pub fn deinit() void {
    arena.?.deinit();
    arena = null;
}

/// The app's answer to one request. Its strings are in the call's arena:
/// good until `end`.
pub fn handle(io: Io, method: []const u8, path: []const u8, body: []const u8) Response {
    call_io = io;
    return roc_handle(.{ .body = .from(body), .method = .from(method), .path = .from(path) });
}

/// The call's memory, all of it, back to the arena (kept for the next call).
pub fn end() void {
    call_io = null;
    _ = arena.?.reset(.retain_capacity);
}

fn alloc() std.mem.Allocator {
    return arena.?.allocator();
}

// ── the runtime ─────────────────────────────────────────────────────────────

/// Each allocation's size, just before what Roc is given, so `roc_realloc`
/// knows how much to copy. 16 bytes: Roc asks for at most 16's alignment.
const header = 16;

fn allocate(len: usize, alignment: usize) [*]u8 {
    std.debug.assert(alignment <= header);
    const got = alloc().alignedAlloc(u8, .fromByteUnits(header), header + len) catch @panic("roc_alloc: out of memory");
    std.mem.writeInt(usize, got[0..8], len, .little);
    return got.ptr + header;
}

/// `len` bytes of string data after a refcount word set to 1, as Roc's
/// `allocateWithRefcount` lays them.
fn withRefcount(len: usize) [*]u8 {
    const base = allocate(8 + len, 8);
    std.mem.writeInt(isize, base[0..8], 1, .little);
    return base + 8;
}

export fn roc_alloc(len: usize, alignment: usize) callconv(.c) *anyopaque {
    return allocate(len, alignment);
}

export fn roc_realloc(ptr: *anyopaque, len: usize, alignment: usize) callconv(.c) *anyopaque {
    const old: [*]u8 = @ptrCast(ptr);
    const was = std.mem.readInt(usize, (old - header)[0..8], .little);
    const new = allocate(len, alignment);
    @memcpy(new[0..@min(was, len)], old[0..@min(was, len)]);
    return new;
}

export fn roc_dealloc(ptr: *anyopaque, alignment: usize) callconv(.c) void {
    _ = ptr;
    _ = alignment;
}

/// A Roc crash (an overflow, a `crash`) is a bug in the app: the host stops,
/// saying Roc's message.
export fn roc_crashed(bytes: [*]const u8, len: usize) callconv(.c) void {
    std.debug.panic("roc crashed: {s}", .{bytes[0..len]});
}

// ── the hosted functions (platform/File.roc) ────────────────────────────────

/// The most of a file `File.read!` answers.
pub const read_most = 1 << 20;

/// `path` under the data root, or null when it would leave it (absolute, or
/// through `..`), as cobble-webbox's chat_files does.
fn under(path: []const u8) ?[]const u8 {
    if (path.len == 0 or path[0] == '/') return null;
    var parts = std.mem.splitScalar(u8, path, '/');
    while (parts.next()) |p| if (std.mem.eql(u8, p, "..")) return null;
    return std.fs.path.join(alloc(), &.{ data_root, path }) catch null;
}

export fn roc_file_read(path: RocStr) callconv(.c) Read {
    const p = under(path.slice()) orelse return .{ .text = .from("a path outside the data root"), .status = read_failed };
    const got = store.readOrNull(call_io.?, alloc(), p, .limited(read_most)) catch |e| return .{ .text = .from(@errorName(e)), .status = read_failed };
    const text = got orelse return .{ .text = .from(""), .status = read_absent };
    return .{ .text = .from(text), .status = read_found };
}

export fn roc_file_write(path: RocStr, text: RocStr) callconv(.c) RocStr {
    const p = under(path.slice()) orelse return .from("a path outside the data root");
    store.replace(call_io.?, alloc(), p, text.slice(), .{}) catch |e| return .from(@errorName(e));
    return .from("");
}

export fn roc_file_delete(path: RocStr) callconv(.c) RocStr {
    const p = under(path.slice()) orelse return .from("a path outside the data root");
    store.remove(call_io.?, alloc(), p) catch |e| return .from(@errorName(e));
    return .from("");
}

test "a string small and big, there and back" {
    use(std.testing.allocator, "data");
    defer deinit();
    for ([_][]const u8{ "", "GET", &@as([23]u8, @splat('x')), &@as([24]u8, @splat('y')), &@as([1000]u8, @splat('z')) }) |t| {
        const s = RocStr.from(t);
        try std.testing.expectEqualStrings(t, s.slice());
        try std.testing.expectEqual(t.len <= 23, s.isSmall());
    }
}

test "a path that would leave the data root is refused" {
    use(std.testing.allocator, "data");
    defer deinit();
    try std.testing.expect(under("/etc/passwd") == null);
    try std.testing.expect(under("todo/../../x") == null);
    try std.testing.expect(under("") == null);
    try std.testing.expectEqualStrings("data/todo/todos.json", under("todo/todos.json").?);
}
