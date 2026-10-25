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
    const m = member orelse @panic("roc_chat_member: Roc asked outside a call (chat_abi.decide sets it)");
    return m.ask(m.ctx);
}

/// The router's decision for `sub` (under /chat, or /channel when
/// `channel`), its bytes copied into `alloc`, the Roc call ended.
pub fn decide(alloc: std.mem.Allocator, sub: []const u8, channel: bool, who: Member) !Decision {
    member = who;
    defer member = null;
    const a = roc_chat_handle(.{ .sub = .from(sub), .channel = channel });
    defer roc.end();
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
