//! **THE ROC CHAT'S SIDE OF THE SEAM** (chat/platform/): the records
//! `roc_chat_handle` takes and answers, laid out as Roc lays them (fields
//! by alignment, then by name; sizes asserted below), and the one hosted
//! function, `roc_chat_member`. The runtime and the call's arena are
//! roc_abi.zig's, shared with any other Roc app in the binary.
//!
//! **THE DECISION LEAVES THE CALL**: `decide` copies what Roc answered into
//! the caller's allocator and ends the call before it returns, so the Zig
//! that serves the route runs with no Roc call open (docs/ROC-CHAT.md R1):
//! its writes, and on metal the network pumps inside them, nest nothing.

const std = @import("std");
const roc = @import("roc_abi.zig");
const route_mod = @import("chat_route.zig");
const sljmp = @import("sljmp.zig");
pub const Route = route_mod.Route;
pub const Decision = route_mod.Decision;

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
        const data = roc.withRefcount(bytes.len);
        @memcpy(data[0..bytes.len], bytes);
        return .{ .ptr = data, .length = bytes.len, .capacity_or_alloc_ptr = bytes.len << 1 };
    }
};

/// Chat.roc's `Request`.
pub const Request = extern struct { sub: RocBytes, channel: bool };
/// Chat.roc's `Route`.
pub const RouteRec = extern struct { key: RocBytes, rest: RocBytes, sid: RocBytes, family: u8, part: u8, tail: u8 };
/// Chat.roc's `Answer`.
pub const Answer = extern struct { location: RocBytes, route: RouteRec, kind: u8, presence: bool };

comptime {
    const w = @sizeOf(usize);
    std.debug.assert(@sizeOf(RocBytes) == 3 * w and @sizeOf(Request) == 4 * w and @sizeOf(RouteRec) == 10 * w and @sizeOf(Answer) == 14 * w);
}

extern fn roc_chat_handle(req: Request) callconv(.c) Answer;

/// What answers `Host.member!` during a call: the host's, with its own
/// context (the request, its `Io`). Set by `decide` for the call alone.
pub const Member = struct {
    ctx: *anyopaque,
    ask: *const fn (ctx: *anyopaque) bool,
};
var member: ?Member = null;

export fn roc_chat_member() callconv(.c) bool {
    if (!roc.inCall()) @panic("roc_chat_member: Roc asked outside a call (docs/ROC-CHAT.md R1)");
    const m = member orelse @panic("roc_chat_member: Roc asked outside a call (chat_abi.decide sets it)");
    return m.ask(m.ctx);
}

// ── a crash is a 500 (docs/ROC-CHAT.md R3, P9) ─────────────────────────────

/// **A ROC CRASH ENDS THE CALL, NOT THE SERVER**: a Roc `crash`, an
/// overflow or a failed allocation calls `roc_crashed`, which, inside a
/// call, jumps back to where the call began (`guarded`), so `decide`
/// answers `error.RocCrashed` and the site a 500. On metal, a crash that
/// stopped the machine would restart it, and a crash a stored request
/// causes would do so on every request. What Roc held is the call's arena,
/// dropped with it; what the host did inside the call (only answering
/// `member`) holds nothing.
var jump: sljmp.JmpBuf = undefined;

/// The last crash's message, for a test or a log (cut to its size).
pub var last_crash: [256]u8 = undefined;
pub var last_crash_len: usize = 0;

fn crashed(message: []const u8) noreturn {
    last_crash_len = @min(message.len, last_crash.len);
    @memcpy(last_crash[0..last_crash_len], message[0..last_crash_len]);
    sljmp.longjmp(&jump, 1);
}

/// The call, or null when Roc crashed inside it. Nothing of this frame is
/// read after the jump back but what `setjmp` answers: the answer is
/// written through `out` only on the way that returns normally.
noinline fn guarded(req: Request, out: *Answer) bool {
    if (sljmp.setjmp(&jump) != 0) return false;
    out.* = roc_chat_handle(req);
    return true;
}

/// The router's decision for `sub` (under /chat, or /channel when
/// `channel`), its bytes copied into `alloc`, the Roc call ended. A Roc
/// crash is `error.RocCrashed`; a call inside or beside another,
/// `error.RocReentered`.
pub fn decide(alloc: std.mem.Allocator, sub: []const u8, channel: bool, who: Member) !Decision {
    try roc.enter();
    defer roc.leave();
    member = who;
    defer member = null;
    const was = roc.crashed;
    roc.crashed = crashed;
    defer roc.crashed = was;
    defer roc.end();
    var a: Answer = undefined;
    if (!guarded(.{ .sub = .from(sub), .channel = channel }, &a)) return error.RocCrashed;
    if (a.kind == 1) return .{ .redirect = try alloc.dupe(u8, a.location.slice()) };
    if (a.kind != 0) std.debug.panic("roc_chat_handle answered kind {d}", .{a.kind});
    return .{ .serve = .{ .presence = a.presence, .route = .{
        .family = std.enums.fromInt(route_mod.Family, a.route.family) orelse std.debug.panic("roc_chat_handle: family {d}", .{a.route.family}),
        .part = std.enums.fromInt(route_mod.Part, a.route.part) orelse std.debug.panic("roc_chat_handle: part {d}", .{a.route.part}),
        .tail = std.enums.fromInt(route_mod.Tail, a.route.tail) orelse std.debug.panic("roc_chat_handle: tail {d}", .{a.route.tail}),
        .key = try alloc.dupe(u8, a.route.key.slice()),
        .rest = try alloc.dupe(u8, a.route.rest.slice()),
        .sid = try alloc.dupe(u8, a.route.sid.slice()),
    } } };
}
