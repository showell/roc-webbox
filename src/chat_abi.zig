//! **THE ROC CHAT'S SIDE OF THE SEAM** (chat/platform/): the records
//! `roc_chat_handle` takes and answers, laid out as Roc lays them (fields
//! by alignment, then by name; sizes asserted below), and the hosted
//! functions (chat/platform/Host.roc), each answered by the host's `Host`
//! for the call. The runtime and the call's arena are roc_abi.zig's, shared
//! with any other Roc app in the binary.
//!
//! **THE DECISION LEAVES THE CALL**: `decide` copies what Roc answered into
//! the caller's allocator and ends the call before it returns, so the Zig
//! that serves a delegated route runs with no Roc call open (docs/ROC-CHAT.md
//! R1): its writes, and on metal the network pumps inside them, nest
//! nothing. A route the Roc serves itself (C4) writes through the hosted
//! functions, inside the call, as §6.2's send will: a pump there runs the
//! kernel's turn and its fixed Zig render, never a handler, and the busy
//! word refuses any Roc call beside this one.

const std = @import("std");
const roc = @import("roc_abi.zig");
const route_mod = @import("chat_route.zig");
const sljmp = @import("sljmp.zig");
pub const Route = route_mod.Route;
pub const Decision = route_mod.Decision;

pub const RocBytes = roc.RocBytes;

const Family = route_mod.Family;
const Method = route_mod.Method;

/// Chat.roc's `Request`.
pub const Request = extern struct { sub: RocBytes, channel: bool, method: Method };
/// Chat.roc's `Route`.
pub const RouteRec = extern struct { key: RocBytes, rest: RocBytes, sid: RocBytes, family: Family, part: route_mod.Part, tail: route_mod.Tail };
/// Chat.roc's `Answer`.
pub const Answer = extern struct { body: RocBytes, content_type: RocBytes, location: RocBytes, route: RouteRec, status: u16, allow: Method, kind: route_mod.Kind, nosniff: bool, presence: bool };
/// Host.roc's `{ ok : Bool, bytes : List(U8) }`.
pub const Got = extern struct { bytes: RocBytes, ok: bool };

comptime {
    const w = @sizeOf(usize);
    std.debug.assert(@sizeOf(RocBytes) == 3 * w and @sizeOf(Request) == 4 * w and @sizeOf(RouteRec) == 10 * w and @sizeOf(Answer) == 20 * w and @sizeOf(Got) == 4 * w);
}

extern fn roc_chat_handle(req: Request) callconv(.c) Answer;

/// **WHAT ANSWERS THE HOSTED FUNCTIONS** during a call: the host's, with its
/// own context (the request, its `Io`, the topic it found). Set by `decide`
/// for the call alone. Bytes handed in are the call's, good until it ends;
/// bytes handed back are the host's, copied into the call here.
pub const Host = struct {
    ctx: *anyopaque,
    /// Host.member!.
    member: *const fn (ctx: *anyopaque) bool,
    /// Host.presence!.
    presence: *const fn (ctx: *anyopaque) void,
    /// Host.topic!.
    topic: *const fn (ctx: *anyopaque, family: Family, key: []const u8, sid: []const u8) bool,
    /// Host.body!: read to `which` form's limit; null
    /// when the host answered (too big) or failed.
    body: *const fn (ctx: *anyopaque, which: route_mod.Form) ?[]const u8,
    /// Host.reactions!: null when it failed.
    reactions: *const fn (ctx: *anyopaque) ?[]const u8,
    /// Host.react!.
    react: *const fn (ctx: *anyopaque, msg: u64, emoji: []const u8, on: bool) route_mod.Reacted,
    /// Host.pin!: false when it failed.
    pin: *const fn (ctx: *anyopaque, pinned: bool) bool,
    /// Host.landing!: none when the conversation is not the member's (or
    /// the lookup failed); else its base and first topic, and when it has
    /// none, the viewer and the conversation's title.
    landing: *const fn (ctx: *anyopaque, family: Family, key: []const u8) []const []const u8 = noLanding,
    /// Host.page!: the conversation page's data (Pages.roc reads it), or
    /// none when it failed.
    page: *const fn (ctx: *anyopaque) []const []const u8 = noPage,
    /// Host.srcs!: where a page names each script, as `name, src` pairs.
    srcs: *const fn (ctx: *anyopaque) []const []const u8 = noSrcs,
    /// Host.me!, Host.viewer!, Host.last_conv!: the member's id, name, and
    /// last DM.
    me: *const fn (ctx: *anyopaque) []const u8 = noBytes,
    viewer: *const fn (ctx: *anyopaque) []const u8 = noBytes,
    last_conv: *const fn (ctx: *anyopaque) []const u8 = noBytes,
    /// Host.resume_topic!: where the member resumes DM `conv`.
    resume_topic: *const fn (ctx: *anyopaque, conv: []const u8) []const u8 = noKeyBytes,
    /// Host.topics!: a DM's or a channel's topics.
    topics: *const fn (ctx: *anyopaque, family: Family, key: []const u8) []const []const u8 = noLanding,
    /// Host.channels!, Host.members!: the member's channels; every member as
    /// `id, name` pairs.
    channels: *const fn (ctx: *anyopaque) []const []const u8 = noPage,
    members: *const fn (ctx: *anyopaque) []const []const u8 = noPage,
    /// Host.conv!: a conversation for a new topic, or none.
    conv: *const fn (ctx: *anyopaque, family: Family, key: []const u8) []const []const u8 = noLanding,
    /// Host.bookmark!, Host.append!: false when they failed.
    bookmark: *const fn (ctx: *anyopaque, sid: []const u8) bool = noBookmark,
    append: *const fn (ctx: *anyopaque, sid: []const u8, name: []const u8, markdown: []const u8, cid: []const u8) bool = noAppend,
    /// Host.send_conv!: a topic to send to, or none.
    send_conv: *const fn (ctx: *anyopaque, family: Family, key: []const u8, sid: []const u8) []const []const u8 = noSendConv,
    /// Host.header!: a request header's value, or none.
    header: *const fn (ctx: *anyopaque, name: []const u8) []const []const u8 = noHeader,
    /// Host.hostile!.
    hostile: *const fn (ctx: *anyopaque, markdown: []const u8) route_mod.Hostility = noHostile,
    /// Host.raw!, Host.links!: whether the host holds the topic's
    /// transcript, the member's links page rendered, for a `held` answer.
    raw: *const fn (ctx: *anyopaque) bool = noHeld,
    links: *const fn (ctx: *anyopaque) bool = noHeld,
    /// Host.feed!: the member's images.md or code.md, or none.
    feed: *const fn (ctx: *anyopaque, which: route_mod.Feed) []const []const u8 = noFeed,
    /// Host.recent!: the member's recent rows, nine fields each, or none.
    recent: *const fn (ctx: *anyopaque) []const []const u8 = noPage,
};

fn noHeld(_: *anyopaque) bool {
    @panic("raw or links asked of a host that does not answer it");
}
fn noFeed(_: *anyopaque, _: route_mod.Feed) []const []const u8 {
    @panic("feed asked of a host that does not answer it");
}

fn noSendConv(_: *anyopaque, _: Family, _: []const u8, _: []const u8) []const []const u8 {
    @panic("send_conv asked of a host that does not answer it");
}
fn noHeader(_: *anyopaque, _: []const u8) []const []const u8 {
    @panic("header asked of a host that does not answer it");
}
fn noHostile(_: *anyopaque, _: []const u8) route_mod.Hostility {
    @panic("hostile asked of a host that does not answer it");
}

fn noBytes(_: *anyopaque) []const u8 {
    @panic("a hosted read asked of a host that does not answer it");
}
fn noKeyBytes(_: *anyopaque, _: []const u8) []const u8 {
    @panic("a hosted read asked of a host that does not answer it");
}
fn noBookmark(_: *anyopaque, _: []const u8) bool {
    @panic("bookmark asked of a host that does not answer it");
}
fn noAppend(_: *anyopaque, _: []const u8, _: []const u8, _: []const u8, _: []const u8) bool {
    @panic("append asked of a host that does not answer it");
}

fn noLanding(_: *anyopaque, _: Family, _: []const u8) []const []const u8 {
    @panic("landing asked of a host that does not answer it");
}
fn noPage(_: *anyopaque) []const []const u8 {
    @panic("page asked of a host that does not answer it");
}
fn noSrcs(_: *anyopaque) []const []const u8 {
    @panic("srcs asked of a host that does not answer it");
}
var host: ?Host = null;

/// **A HOST FOR THE ROUTER ALONE**, for a test of its decisions: it says
/// whether the one asking is a member, records whether the Roc counted
/// presence itself, and finds no topic, so a route the Roc serves goes to
/// Zig as every other does. Nothing else is asked once no topic is found.
pub const Routing = struct {
    member: bool = true,
    asked: bool = false,
    /// The Roc counted the request as presence itself (a route it serves).
    marked: bool = false,

    pub fn host(r: *Routing) Host {
        var h = askingOnly(r, ask);
        h.presence = mark;
        h.topic = none;
        h.landing = noConv;
        h.conv = noConv;
        // The routes the Roc serves outright meet a member with nothing: no
        // last DM, no other members, no channels, no topics.
        h.me = empty;
        h.viewer = empty;
        h.last_conv = empty;
        h.srcs = nothing;
        h.members = nothing;
        h.channels = nothing;
        h.topics = noConv;
        h.send_conv = noSendTo;
        h.links = holdsNone;
        h.feed = noFile;
        h.recent = nothing;
        return h;
    }
    fn of(ctx: *anyopaque) *Routing {
        return @ptrCast(@alignCast(ctx));
    }
    fn ask(ctx: *anyopaque) bool {
        of(ctx).asked = true;
        return of(ctx).member;
    }
    fn mark(ctx: *anyopaque) void {
        of(ctx).marked = true;
    }
    fn none(_: *anyopaque, _: Family, _: []const u8, _: []const u8) bool {
        return false;
    }
    fn noConv(_: *anyopaque, _: Family, _: []const u8) []const []const u8 {
        return &.{};
    }
    fn noSendTo(_: *anyopaque, _: Family, _: []const u8, _: []const u8) []const []const u8 {
        return &.{};
    }
    fn empty(_: *anyopaque) []const u8 {
        return "";
    }
    fn nothing(_: *anyopaque) []const []const u8 {
        return &.{};
    }
    fn holdsNone(_: *anyopaque) bool {
        return false;
    }
    fn noFile(_: *anyopaque, _: route_mod.Feed) []const []const u8 {
        return &.{};
    }
};

/// A host that answers who is asking and nothing else, for a test of the
/// router alone: any other hosted call is a panic.
pub fn askingOnly(ctx: *anyopaque, ask: *const fn (ctx: *anyopaque) bool) Host {
    const No = struct {
        fn presence(_: *anyopaque) void {
            @panic("presence asked of a host that only answers who is asking");
        }
        fn topic(_: *anyopaque, _: Family, _: []const u8, _: []const u8) bool {
            @panic("topic asked of a host that only answers who is asking");
        }
        fn bytes(_: *anyopaque) ?[]const u8 {
            @panic("bytes asked of a host that only answers who is asking");
        }
        fn body(_: *anyopaque, _: route_mod.Form) ?[]const u8 {
            @panic("body asked of a host that only answers who is asking");
        }
        fn react(_: *anyopaque, _: u64, _: []const u8, _: bool) route_mod.Reacted {
            @panic("react asked of a host that only answers who is asking");
        }
        fn pin(_: *anyopaque, _: bool) bool {
            @panic("pin asked of a host that only answers who is asking");
        }
    };
    return .{ .ctx = ctx, .member = ask, .presence = No.presence, .topic = No.topic, .body = No.body, .reactions = No.bytes, .react = No.react, .pin = No.pin };
}

/// The call's host, or a panic for a hosted function Roc ran outside one.
fn current(comptime name: []const u8) Host {
    if (!roc.inCall()) @panic("roc_chat_" ++ name ++ ": Roc asked outside a call (docs/ROC-CHAT.md R1)");
    return host orelse @panic("roc_chat_" ++ name ++ ": Roc asked outside a call (chat_abi.decide sets it)");
}

fn got(bytes: ?[]const u8) Got {
    const b = bytes orelse return .{ .bytes = .from(""), .ok = false };
    return .{ .bytes = .from(b), .ok = true };
}

export fn roc_chat_member() callconv(.c) bool {
    const h = current("member");
    return h.member(h.ctx);
}

export fn roc_chat_presence() callconv(.c) void {
    const h = current("presence");
    h.presence(h.ctx);
}

export fn roc_chat_topic(family: Family, key: RocBytes, sid: RocBytes) callconv(.c) bool {
    const h = current("topic");
    return h.topic(h.ctx, family, key.slice(), sid.slice());
}

export fn roc_chat_body(which: route_mod.Form) callconv(.c) Got {
    const h = current("body");
    return got(h.body(h.ctx, which));
}

export fn roc_chat_reactions() callconv(.c) Got {
    const h = current("reactions");
    return got(h.reactions(h.ctx));
}

export fn roc_chat_react(msg: u64, emoji: RocBytes, on: bool) callconv(.c) route_mod.Reacted {
    const h = current("react");
    return h.react(h.ctx, msg, emoji.slice(), on);
}

export fn roc_chat_pin(pinned: bool) callconv(.c) bool {
    const h = current("pin");
    return h.pin(h.ctx, pinned);
}

export fn roc_chat_landing(family: Family, key: RocBytes) callconv(.c) roc.RocBytesList {
    const h = current("landing");
    return .from(h.landing(h.ctx, family, key.slice()));
}

export fn roc_chat_page() callconv(.c) roc.RocBytesList {
    const h = current("page");
    return .from(h.page(h.ctx));
}

export fn roc_chat_me() callconv(.c) RocBytes {
    const h = current("me");
    return .from(h.me(h.ctx));
}

export fn roc_chat_viewer() callconv(.c) RocBytes {
    const h = current("viewer");
    return .from(h.viewer(h.ctx));
}

export fn roc_chat_last_conv() callconv(.c) RocBytes {
    const h = current("last_conv");
    return .from(h.last_conv(h.ctx));
}

export fn roc_chat_resume_topic(conv: RocBytes) callconv(.c) RocBytes {
    const h = current("resume_topic");
    return .from(h.resume_topic(h.ctx, conv.slice()));
}

export fn roc_chat_topics(family: Family, key: RocBytes) callconv(.c) roc.RocBytesList {
    const h = current("topics");
    return .from(h.topics(h.ctx, family, key.slice()));
}

export fn roc_chat_channels() callconv(.c) roc.RocBytesList {
    const h = current("channels");
    return .from(h.channels(h.ctx));
}

export fn roc_chat_members() callconv(.c) roc.RocBytesList {
    const h = current("members");
    return .from(h.members(h.ctx));
}

export fn roc_chat_conv(family: Family, key: RocBytes) callconv(.c) roc.RocBytesList {
    const h = current("conv");
    return .from(h.conv(h.ctx, family, key.slice()));
}

export fn roc_chat_bookmark(sid: RocBytes) callconv(.c) bool {
    const h = current("bookmark");
    return h.bookmark(h.ctx, sid.slice());
}

export fn roc_chat_append(sid: RocBytes, name: RocBytes, markdown: RocBytes, cid: RocBytes) callconv(.c) bool {
    const h = current("append");
    return h.append(h.ctx, sid.slice(), name.slice(), markdown.slice(), cid.slice());
}

export fn roc_chat_send_conv(family: Family, key: RocBytes, sid: RocBytes) callconv(.c) roc.RocBytesList {
    const h = current("send_conv");
    return .from(h.send_conv(h.ctx, family, key.slice(), sid.slice()));
}

export fn roc_chat_header(name: RocBytes) callconv(.c) roc.RocBytesList {
    const h = current("header");
    return .from(h.header(h.ctx, name.slice()));
}

export fn roc_chat_hostile(markdown: RocBytes) callconv(.c) route_mod.Hostility {
    const h = current("hostile");
    return h.hostile(h.ctx, markdown.slice());
}

export fn roc_chat_raw() callconv(.c) bool {
    const h = current("raw");
    return h.raw(h.ctx);
}

export fn roc_chat_feed(which: route_mod.Feed) callconv(.c) roc.RocBytesList {
    const h = current("feed");
    return .from(h.feed(h.ctx, which));
}

export fn roc_chat_recent() callconv(.c) roc.RocBytesList {
    const h = current("recent");
    return .from(h.recent(h.ctx));
}

export fn roc_chat_links() callconv(.c) bool {
    const h = current("links");
    return h.links(h.ctx);
}

export fn roc_chat_srcs() callconv(.c) roc.RocBytesList {
    const h = current("srcs");
    return .from(h.srcs(h.ctx));
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
/// written through `out` only on the way that returns normally. The
/// request's strings are made here, after `setjmp`: they are the call's
/// first allocations, and one that fails must jump back to this frame,
/// not to one already gone.
noinline fn guarded(sub: []const u8, channel: bool, method: Method, out: *Answer) bool {
    if (sljmp.setjmp(&jump) != 0) return false;
    out.* = roc_chat_handle(.{ .sub = .from(sub), .channel = channel, .method = method });
    return true;
}

/// The router's decision for `sub` (under /chat, or /channel when
/// `channel`) asked with `method`, its bytes copied into `alloc`, the Roc
/// call ended. A Roc crash is `error.RocCrashed`; a call inside or beside
/// another, `error.RocReentered`.
pub fn decide(alloc: std.mem.Allocator, sub: []const u8, channel: bool, method: std.http.Method, with: Host) !Decision {
    try roc.enter();
    defer roc.leave();
    host = with;
    defer host = null;
    const was = roc.crashed;
    roc.crashed = crashed;
    defer roc.crashed = was;
    defer roc.end();
    var a: Answer = undefined;
    if (!guarded(sub, channel, .of(method), &a)) return error.RocCrashed;
    return switch (a.kind) {
        .serve => .{ .serve = .{ .presence = a.presence, .route = .{
            .family = a.route.family,
            .part = a.route.part,
            .tail = a.route.tail,
            .key = try alloc.dupe(u8, a.route.key.slice()),
            .rest = try alloc.dupe(u8, a.route.rest.slice()),
            .sid = try alloc.dupe(u8, a.route.sid.slice()),
        } } },
        .redirect => .{ .redirect = try alloc.dupe(u8, a.location.slice()) },
        .respond => .{ .respond = .{ .status = a.status, .content_type = try alloc.dupe(u8, a.content_type.slice()), .body = try alloc.dupe(u8, a.body.slice()), .nosniff = a.nosniff } },
        .not_allowed => .{ .not_allowed = switch (a.allow) {
            .get => .GET,
            .head => .HEAD,
            .post => .POST,
            .other => std.debug.panic("roc_chat_handle: a 405 allowing no method", .{}),
        } },
        .answered => .answered,
        .malformed => .malformed_form,
        .not_found => .not_found,
        .found => .{ .found = try alloc.dupe(u8, a.location.slice()) },
        .held => .{ .held = .{ .status = a.status, .content_type = try alloc.dupe(u8, a.content_type.slice()), .nosniff = a.nosniff, .before = try alloc.dupe(u8, a.body.slice()), .after = try alloc.dupe(u8, a.location.slice()) } },
    };
}
