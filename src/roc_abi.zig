//! **ROC'S SIDE OF THE SEAM**: what the Roc app's archive (app/*.roc, built
//! for the platform in platform/) needs from any host, and the values it
//! hands across:
//!
//!   - the runtime: `roc_alloc`, `roc_realloc`, `roc_dealloc` and
//!     `roc_crashed`;
//!   - `RocStr`, and the records `roc_handle` takes and answers.
//!
//! The platform's hosted functions, the file effects, are each host's own:
//! roc_files.zig over webbox's store (the real one, on every webbox host),
//! and demo/wasm_host.zig over the page's storage (a stand-in for testing
//! the client in a browser). No operating system call is made here, and the
//! file builds for any target Roc builds for.
//!
//! **ONE CALL AT A TIME**: webbox runs one handler at a time (and a browser
//! one script), so the call's arena is held here, emptied by `end`.

const std = @import("std");

/// A Roc `Str` (roc's builtins/str.zig, `RocStr`). Three words; a string
/// that fits in two words and a byte (23 bytes on a 64-bit target, 11 on
/// wasm32) is held in them (`small`): the last byte its length with the top
/// bit set. A big string's bytes are an allocation whose refcount, a word,
/// is just before them.
pub const RocStr = extern struct {
    bytes: ?[*]u8,
    capacity_or_alloc_ptr: usize,
    length: usize,

    const small_most = @sizeOf(RocStr) - 1;

    fn isSmall(s: *const RocStr) bool {
        return @as(isize, @bitCast(s.length)) < 0;
    }

    /// The bytes, wherever they are held: for a small string, in `s`
    /// itself, so good only while `s` is.
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

/// A Roc `List(U8)` (roc's builtins/list.zig): pointer, length, then the
/// capacity (shifted, as `RocStr.from` makes a string's), the bytes after a
/// refcount word.
pub const RocBytes = extern struct {
    ptr: ?[*]u8,
    length: usize,
    capacity_or_alloc_ptr: usize,

    pub fn slice(b: *const RocBytes) []const u8 {
        const p = b.ptr orelse return "";
        return p[0..b.length];
    }

    /// A new list holding `bytes`, in the call's arena.
    pub fn from(bytes: []const u8) RocBytes {
        if (bytes.len == 0) return .{ .ptr = null, .length = 0, .capacity_or_alloc_ptr = 0 };
        const data = withRefcount(bytes.len);
        @memcpy(data[0..bytes.len], bytes);
        return .{ .ptr = data, .length = bytes.len, .capacity_or_alloc_ptr = bytes.len << 1 };
    }
};

/// A Roc `List(List(U8))`: a list whose elements are refcounted (each a
/// `List(U8)`) has two words before them, the element count and then the
/// refcount (the crash probe's p8/rt.zig, which took it from Roc's
/// builtins).
pub const RocBytesList = extern struct {
    ptr: ?[*]RocBytes,
    length: usize,
    capacity_or_alloc_ptr: usize,

    pub fn slice(l: *const RocBytesList) []const RocBytes {
        const p = l.ptr orelse return &.{};
        return p[0..l.length];
    }

    /// A new list of `items`, each copied, in the call's arena.
    pub fn from(items: []const []const u8) RocBytesList {
        if (items.len == 0) return .{ .ptr = null, .length = 0, .capacity_or_alloc_ptr = 0 };
        const w = @sizeOf(usize);
        const base = allocate(2 * w + items.len * @sizeOf(RocBytes), w);
        std.mem.writeInt(usize, base[0..w], items.len, .little);
        std.mem.writeInt(usize, base[w..][0..w], 1, .little);
        const elems: [*]RocBytes = @ptrCast(@alignCast(base + 2 * w));
        for (items, 0..) |it, k| elems[k] = .from(it);
        return .{ .ptr = elems, .length = items.len, .capacity_or_alloc_ptr = items.len << 1 };
    }
};

/// What the app is handed for a request (platform/Http.roc's `Request`):
/// fields in Roc's order, by alignment and then by name.
pub const Request = extern struct { body: RocStr, method: RocStr, path: RocStr, user: RocStr };

/// What the app answers (`Response`).
pub const Response = extern struct { body: RocStr, content_type: RocStr, status: u16 };

/// What `File.read_raw!` answers: `status` one of the three below, `text`
/// the file's, or the reason it could not be read.
pub const Read = extern struct { text: RocStr, status: u8 };
pub const read_found: u8 = 0;
pub const read_absent: u8 = 1;
pub const read_failed: u8 = 2;

extern fn roc_handle(req: Request) callconv(.c) Response;

comptime {
    const w = @sizeOf(usize);
    std.debug.assert(@sizeOf(RocStr) == 3 * w and @sizeOf(Request) == 12 * w and @sizeOf(Response) == 7 * w and @sizeOf(Read) == 4 * w);
}

// ── the call ────────────────────────────────────────────────────────────────

/// Everything Roc allocates in a call, dropped at its `end`: so `roc_dealloc`
/// frees nothing, and the refcounts of what the host hands Roc need no
/// keeping (a string the host never releases is one Roc copies before it
/// changes it, never one it frees).
var arena: ?std.heap.ArenaAllocator = null;

/// **OR NO ARENA OF ITS OWN**: a host whose allocator is already freed as
/// a whole when the request ends (angry-gopher's: the kernel's request heap
/// on metal, webbox's arena per request on Linux) hands it to `useRequest`
/// before each call, and Roc allocates on it directly. An arena over an
/// arena only costs: Zig's arena grows a node that does not fit by the size
/// asked as well as what is used (a 2N node for N bytes), and nothing is
/// handed back before the request ends anyway.
var direct: ?std.mem.Allocator = null;

/// The arena, from `base`, once, as the host starts: `base` lives as long
/// as the process.
pub fn use(base: std.mem.Allocator) void {
    direct = null;
    arena = .init(base);
}

/// The request's own allocator, for the calls made while it is answered:
/// what Roc takes stays the request's, and goes with it.
pub fn useRequest(request: std.mem.Allocator) void {
    if (arena) |*a| a.deinit();
    arena = null;
    direct = request;
}

/// The arena's memory back to `base` (a test's, done).
pub fn deinit() void {
    if (arena) |*a| a.deinit();
    arena = null;
    direct = null;
}

/// The app's answer to one request. Its strings are in the call's arena:
/// good until `end`.
pub fn call(method: []const u8, path: []const u8, body: []const u8, user: []const u8) Response {
    enter() catch @panic("roc_abi.call: a Roc call inside another, or beside one (docs/ROC-CHAT.md R1)");
    defer leave();
    const was = if (shared) roc_hooks.enter(@This());
    defer if (shared) roc_hooks.leave(was);
    return roc_handle(.{ .body = .from(body), .method = .from(method), .path = .from(path), .user = .from(user) });
}

// ── one call at a time (docs/ROC-CHAT.md R1, P7) ───────────────────────────

/// **ONE ROC CALL AT A TIME, AND NO ROC OUTSIDE ONE**: compiled Roc reaches
/// memory through four context-free functions, so a call made beside
/// another (another thread, on Linux) or inside another (a render, on metal,
/// nested in a network pump) would share the one arena and corrupt it. The
/// word is set by compare-and-swap as a call starts, so both are caught
/// (a plain "inside a call?" flag would pass both), and the runtime's four
/// refuse to run with it clear.
var busy = std.atomic.Value(bool).init(false);

/// A Roc call starts: refused when one is open.
pub fn enter() error{RocReentered}!void {
    if (busy.cmpxchgStrong(false, true, .acquire, .monotonic) != null) return error.RocReentered;
}

/// The call is over.
pub fn leave() void {
    busy.store(false, .release);
}

/// Whether a Roc call is open (a hosted function's check).
pub fn inCall() bool {
    return busy.load(.monotonic);
}

fn inside(comptime what: []const u8) void {
    if (!inCall()) @panic(what ++ ": Roc ran outside a call (docs/ROC-CHAT.md R1)");
}

/// The call's memory, all of it, back to the arena's base: none of it is
/// kept for the next call (keeping it grew one node to the call's whole
/// size, and a failure to was silent). On the request's own allocator,
/// nothing: the request's end frees it.
pub fn end() void {
    if (arena) |*a| _ = a.reset(.free_all);
}

/// The call's allocator: what a hosted function's answer is made in.
pub fn alloc() std.mem.Allocator {
    if (direct) |d| return d;
    return arena.?.allocator();
}

/// Whether `path`, as the app names a file, stays under the data root: not
/// empty, not absolute, never through `..` (as cobble-webbox's chat_files).
pub fn inRoot(path: []const u8) bool {
    if (path.len == 0 or path[0] == '/') return false;
    var parts = std.mem.splitScalar(u8, path, '/');
    while (parts.next()) |p| if (std.mem.eql(u8, p, "..")) return false;
    return true;
}

// ── the runtime ─────────────────────────────────────────────────────────────

/// Whether another Roc app shares the binary (roc_hooks.zig, which the
/// binary's root declares): then the root exports the four below and `call`
/// brackets the app's; alone, they are exported here.
/// A root may declare it empty (`struct {}`: a host that forwards whatever
/// its application declares), which is none.
const shared = @hasDecl(@import("root"), "roc_hooks") and @hasDecl(@import("root").roc_hooks, "enter");
const roc_hooks = if (shared) @import("root").roc_hooks else struct {};

comptime {
    if (!shared) {
        @export(&roc_alloc, .{ .name = "roc_alloc" });
        @export(&roc_realloc, .{ .name = "roc_realloc" });
        @export(&roc_dealloc, .{ .name = "roc_dealloc" });
        @export(&roc_crashed, .{ .name = "roc_crashed" });
    }
}

/// Each allocation's size, just before what Roc is given, so `roc_realloc`
/// knows how much to copy. 16 bytes: Roc asks for at most 16's alignment.
const header = 16;

fn allocate(len: usize, alignment: usize) [*]u8 {
    std.debug.assert(alignment <= header);
    // **OUT OF MEMORY IS A CRASH OF THE CALL**: `crashed`, which inside a
    // guarded call (chat_abi.zig) jumps back to its start, so the request is
    // a 500 and the machine goes on; never a panic that takes every user
    // down with one request's size.
    const got = alloc().alignedAlloc(u8, .fromByteUnits(header), header + len) catch crashed("roc_alloc: out of memory");
    std.mem.writeInt(usize, got[0..@sizeOf(usize)], len, .little);
    return got.ptr + header;
}

/// `len` bytes of string data after a refcount word set to 1, as Roc's
/// `allocateWithRefcount` lays them (the word is a `usize`).
pub fn withRefcount(len: usize) [*]u8 {
    const w = @sizeOf(usize);
    const base = allocate(w + len, w);
    std.mem.writeInt(usize, base[0..w], 1, .little);
    return base + w;
}

pub fn roc_alloc(len: usize, alignment: usize) callconv(.c) *anyopaque {
    inside("roc_alloc");
    return allocate(len, alignment);
}

pub fn roc_realloc(ptr: *anyopaque, len: usize, alignment: usize) callconv(.c) *anyopaque {
    inside("roc_realloc");
    const old: [*]u8 = @ptrCast(ptr);
    const was = std.mem.readInt(usize, (old - header)[0..@sizeOf(usize)], .little);
    const new = allocate(len, alignment);
    @memcpy(new[0..@min(was, len)], old[0..@min(was, len)]);
    return new;
}

pub fn roc_dealloc(ptr: *anyopaque, alignment: usize) callconv(.c) void {
    inside("roc_dealloc");
    _ = ptr;
    _ = alignment;
}

/// What a Roc crash (an overflow, a `crash`: a bug in the app) does: by
/// default the host stops, saying Roc's message; a host may say it its own
/// way (the browser's console).
pub var crashed: *const fn (message: []const u8) noreturn = stop;

fn stop(message: []const u8) noreturn {
    std.debug.panic("roc crashed: {s}", .{message});
}

pub fn roc_crashed(bytes: [*]const u8, len: usize) callconv(.c) void {
    crashed(bytes[0..len]);
}

test "a string small and big, there and back" {
    use(std.testing.allocator);
    defer deinit();
    for ([_][]const u8{ "", "GET", &@as([23]u8, @splat('x')), &@as([24]u8, @splat('y')), &@as([1000]u8, @splat('z')) }) |t| {
        const s = RocStr.from(t);
        try std.testing.expectEqualStrings(t, s.slice());
        try std.testing.expectEqual(t.len <= 23, s.isSmall());
    }
}

test "a path that would leave the data root is refused" {
    try std.testing.expect(!inRoot("/etc/passwd"));
    try std.testing.expect(!inRoot("todo/../../x"));
    try std.testing.expect(!inRoot(""));
    try std.testing.expect(inRoot("todos.json"));
}
