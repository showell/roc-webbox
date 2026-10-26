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
/// Chat.roc's `Conv`, as Roc hands it to a hosted function.
pub const ConvRec = extern struct { base: RocBytes, key: RocBytes, members: roc.RocBytesList, family: Family };

comptime {
    const w = @sizeOf(usize);
    std.debug.assert(@sizeOf(RocBytes) == 3 * w and @sizeOf(Request) == 4 * w and @sizeOf(RouteRec) == 10 * w and @sizeOf(Answer) == 20 * w and @sizeOf(Got) == 4 * w and @sizeOf(ConvRec) == 10 * w);
}

/// **A CONVERSATION THE ROC FOUND TO BE THE MEMBER'S** (chat/main.roc
/// `find!`), handed to each hosted function that works on one: the host
/// holds no conversation between calls. `family` is `.dm` or `.channel`;
/// `members` each member once. Its bytes are the call's.
pub const Conv = struct {
    family: Family,
    key: []const u8,
    base: []const u8,
    members: []const []const u8,

    fn of(r: ConvRec) Conv {
        const items = r.members.slice();
        const members = roc.alloc().alloc([]const u8, items.len) catch @panic("roc_chat: out of memory for a conversation's members");
        for (items, members) |*it, *m| m.* = it.slice();
        return .{ .family = r.family, .key = r.key.slice(), .base = r.base.slice(), .members = members };
    }
};

extern fn roc_chat_handle(req: Request) callconv(.c) Answer;

/// **WHAT ANSWERS THE HOSTED FUNCTIONS** during a call: the host's, with its
/// own context (the request, its `Io`). Set by `decide` for the call alone.
/// Bytes handed in are the call's, good until it ends; bytes handed back
/// are the host's, copied into the call here.
pub const Host = struct {
    ctx: *anyopaque,
    /// Host.member!.
    member: *const fn (ctx: *anyopaque) bool,
    /// Host.presence!.
    presence: *const fn (ctx: *anyopaque) void,
    /// Host.account!: whether account `id` exists.
    account: *const fn (ctx: *anyopaque, id: []const u8) bool = noAccount,
    /// Host.name!: account `id`'s name, or "".
    name: *const fn (ctx: *anyopaque, id: []const u8) []const u8 = noKeyBytes,
    /// Host.channel_members!: none when there is no such channel.
    channel_members: *const fn (ctx: *anyopaque, name: []const u8) []const []const u8 = noKeyList,
    /// Host.body!: read to `which` form's limit; null
    /// when the host answered (too big) or failed.
    body: *const fn (ctx: *anyopaque, which: route_mod.Form) ?[]const u8,
    /// Host.reactions!: topic `sid`'s sidecar in `conv`; null when it failed.
    reactions: *const fn (ctx: *anyopaque, conv: Conv, sid: []const u8) ?[]const u8,
    /// Host.react!.
    react: *const fn (ctx: *anyopaque, conv: Conv, sid: []const u8, msg: u64, emoji: []const u8, on: bool) route_mod.Reacted,
    /// Host.pins!: the member's pinned file for `conv` ("" for none); null
    /// when the read failed, never "".
    pins: *const fn (ctx: *anyopaque, conv: Conv) ?[]const u8,
    /// Host.write_pins!, Host.remove_pins!: that file written as the Roc
    /// made it, or removed; false when it failed.
    write_pins: *const fn (ctx: *anyopaque, conv: Conv, bytes: []const u8) bool,
    remove_pins: *const fn (ctx: *anyopaque, conv: Conv) bool,
    /// Host.page!: topic `sid`'s page's data in `conv` (Pages.roc reads
    /// it), or none when it failed.
    page: *const fn (ctx: *anyopaque, conv: Conv, sid: []const u8) []const []const u8 = noPage,
    /// Host.srcs!: where a page names each script, as `name, src` pairs.
    srcs: *const fn (ctx: *anyopaque) []const []const u8 = noSrcs,
    /// Host.me!, Host.viewer!, Host.last_conv!: the member's id, name, and
    /// last DM.
    me: *const fn (ctx: *anyopaque) []const u8 = noBytes,
    viewer: *const fn (ctx: *anyopaque) []const u8 = noBytes,
    last_conv: *const fn (ctx: *anyopaque) []const u8 = noBytes,
    /// Host.last_viewed!: the topic the member last viewed in DM `conv`, or "".
    last_viewed: *const fn (ctx: *anyopaque, conv: []const u8) []const u8 = noKeyBytes,
    /// Host.now!: the request's time, Unix seconds.
    now: *const fn (ctx: *anyopaque) i64 = noNow,
    /// Host.topics!: a DM's or a channel's topics.
    topics: *const fn (ctx: *anyopaque, family: Family, key: []const u8) []const []const u8 = noTopics,
    /// Host.channels!, Host.members!: the member's channels; every member as
    /// `id, name` pairs.
    channels: *const fn (ctx: *anyopaque) []const []const u8 = noList,
    members: *const fn (ctx: *anyopaque) []const []const u8 = noList,
    /// Host.bookmark!: topic `sid` recorded as where the member resumes DM
    /// `conv`; Host.append!: a message appended to topic `sid` of `conv`.
    /// False when they failed.
    bookmark: *const fn (ctx: *anyopaque, conv: Conv, sid: []const u8) bool = noBookmark,
    append: *const fn (ctx: *anyopaque, conv: Conv, sid: []const u8, name: []const u8, markdown: []const u8, cid: []const u8) bool = noAppend,
    /// Host.header!: a request header's value, or none.
    header: *const fn (ctx: *anyopaque, name: []const u8) []const []const u8 = noHeader,
    /// Host.hostile!.
    hostile: *const fn (ctx: *anyopaque, markdown: []const u8) route_mod.Hostility = noHostile,
    /// Host.raw!: whether the host holds topic `sid`'s transcript in
    /// `conv`, for a `held` answer.
    raw: *const fn (ctx: *anyopaque, conv: Conv, sid: []const u8) bool = noRaw,
    /// Host.links!: whether the host holds the member's links page
    /// rendered, for a `held` answer.
    links: *const fn (ctx: *anyopaque) bool = noHeld,
    /// Host.feed!: the member's images.md or code.md, or none.
    feed: *const fn (ctx: *anyopaque, which: route_mod.Feed) []const []const u8 = noFeed,
    /// Host.recent!: the member's recent rows, nine fields each, or none.
    recent: *const fn (ctx: *anyopaque) []const []const u8 = noList,
};

fn noHeld(_: *anyopaque) bool {
    @panic("links asked of a host that does not answer it");
}
fn noRaw(_: *anyopaque, _: Conv, _: []const u8) bool {
    @panic("raw asked of a host that does not answer it");
}
fn noFeed(_: *anyopaque, _: route_mod.Feed) []const []const u8 {
    @panic("feed asked of a host that does not answer it");
}
fn noAccount(_: *anyopaque, _: []const u8) bool {
    @panic("account asked of a host that does not answer it");
}
fn noKeyList(_: *anyopaque, _: []const u8) []const []const u8 {
    @panic("channel_members asked of a host that does not answer it");
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
fn noNow(_: *anyopaque) i64 {
    @panic("now asked of a host that does not answer it");
}
fn noBookmark(_: *anyopaque, _: Conv, _: []const u8) bool {
    @panic("bookmark asked of a host that does not answer it");
}
fn noAppend(_: *anyopaque, _: Conv, _: []const u8, _: []const u8, _: []const u8, _: []const u8) bool {
    @panic("append asked of a host that does not answer it");
}

fn noTopics(_: *anyopaque, _: Family, _: []const u8) []const []const u8 {
    @panic("topics asked of a host that does not answer it");
}
fn noPage(_: *anyopaque, _: Conv, _: []const u8) []const []const u8 {
    @panic("page asked of a host that does not answer it");
}
fn noList(_: *anyopaque) []const []const u8 {
    @panic("a hosted list asked of a host that does not answer it");
}
fn noSrcs(_: *anyopaque) []const []const u8 {
    @panic("srcs asked of a host that does not answer it");
}
var host: ?Host = null;

/// **A HOST FOR THE ROUTER ALONE**, for a test of its decisions: it says
/// whether the one asking is a member, records whether the Roc counted
/// presence itself, and has no conversation for the member (no id, no
/// channel), so a route the Roc serves goes to Zig as every other does.
pub const Routing = struct {
    member: bool = true,
    asked: bool = false,
    /// The Roc counted the request as presence itself (a route it serves).
    marked: bool = false,

    pub fn host(r: *Routing) Host {
        var h = askingOnly(r, ask);
        h.presence = mark;
        // The routes the Roc serves outright meet a member with nothing: no
        // id (so no DM is theirs), no last DM, no other members, no
        // channels, no topics.
        h.me = empty;
        h.viewer = empty;
        h.last_conv = empty;
        h.channel_members = noMembers;
        h.srcs = nothing;
        h.members = nothing;
        h.channels = nothing;
        h.topics = noTopicsHere;
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
    fn noMembers(_: *anyopaque, _: []const u8) []const []const u8 {
        return &.{};
    }
    fn noTopicsHere(_: *anyopaque, _: Family, _: []const u8) []const []const u8 {
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
        fn body(_: *anyopaque, _: route_mod.Form) ?[]const u8 {
            @panic("body asked of a host that only answers who is asking");
        }
        fn topicBytes(_: *anyopaque, _: Conv, _: []const u8) ?[]const u8 {
            @panic("reactions asked of a host that only answers who is asking");
        }
        fn pins(_: *anyopaque, _: Conv) ?[]const u8 {
            @panic("pins asked of a host that only answers who is asking");
        }
        fn react(_: *anyopaque, _: Conv, _: []const u8, _: u64, _: []const u8, _: bool) route_mod.Reacted {
            @panic("react asked of a host that only answers who is asking");
        }
        fn writePins(_: *anyopaque, _: Conv, _: []const u8) bool {
            @panic("write_pins asked of a host that only answers who is asking");
        }
        fn removePins(_: *anyopaque, _: Conv) bool {
            @panic("remove_pins asked of a host that only answers who is asking");
        }
    };
    return .{ .ctx = ctx, .member = ask, .presence = No.presence, .body = No.body, .reactions = No.topicBytes, .react = No.react, .pins = No.pins, .write_pins = No.writePins, .remove_pins = No.removePins };
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

export fn roc_chat_account(id: RocBytes) callconv(.c) bool {
    const h = current("account");
    return h.account(h.ctx, id.slice());
}

export fn roc_chat_name(id: RocBytes) callconv(.c) RocBytes {
    const h = current("name");
    return .from(h.name(h.ctx, id.slice()));
}

export fn roc_chat_channel_members(name: RocBytes) callconv(.c) roc.RocBytesList {
    const h = current("channel_members");
    return .from(h.channel_members(h.ctx, name.slice()));
}

export fn roc_chat_body(which: route_mod.Form) callconv(.c) Got {
    const h = current("body");
    return got(h.body(h.ctx, which));
}

export fn roc_chat_reactions(conv: ConvRec, sid: RocBytes) callconv(.c) Got {
    const h = current("reactions");
    return got(h.reactions(h.ctx, .of(conv), sid.slice()));
}

export fn roc_chat_react(conv: ConvRec, sid: RocBytes, msg: u64, emoji: RocBytes, on: bool) callconv(.c) route_mod.Reacted {
    const h = current("react");
    return h.react(h.ctx, .of(conv), sid.slice(), msg, emoji.slice(), on);
}

export fn roc_chat_pins(conv: ConvRec) callconv(.c) Got {
    const h = current("pins");
    return got(h.pins(h.ctx, .of(conv)));
}

export fn roc_chat_write_pins(conv: ConvRec, bytes: RocBytes) callconv(.c) bool {
    const h = current("write_pins");
    return h.write_pins(h.ctx, .of(conv), bytes.slice());
}

export fn roc_chat_remove_pins(conv: ConvRec) callconv(.c) bool {
    const h = current("remove_pins");
    return h.remove_pins(h.ctx, .of(conv));
}

export fn roc_chat_page(conv: ConvRec, sid: RocBytes) callconv(.c) roc.RocBytesList {
    const h = current("page");
    return .from(h.page(h.ctx, .of(conv), sid.slice()));
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

export fn roc_chat_last_viewed(conv: RocBytes) callconv(.c) RocBytes {
    const h = current("last_viewed");
    return .from(h.last_viewed(h.ctx, conv.slice()));
}

export fn roc_chat_now() callconv(.c) i64 {
    const h = current("now");
    return h.now(h.ctx);
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

export fn roc_chat_bookmark(conv: ConvRec, sid: RocBytes) callconv(.c) bool {
    const h = current("bookmark");
    return h.bookmark(h.ctx, .of(conv), sid.slice());
}

export fn roc_chat_append(conv: ConvRec, sid: RocBytes, name: RocBytes, markdown: RocBytes, cid: RocBytes) callconv(.c) bool {
    const h = current("append");
    return h.append(h.ctx, .of(conv), sid.slice(), name.slice(), markdown.slice(), cid.slice());
}

export fn roc_chat_header(name: RocBytes) callconv(.c) roc.RocBytesList {
    const h = current("header");
    return .from(h.header(h.ctx, name.slice()));
}

export fn roc_chat_hostile(markdown: RocBytes) callconv(.c) route_mod.Hostility {
    const h = current("hostile");
    return h.hostile(h.ctx, markdown.slice());
}

export fn roc_chat_raw(conv: ConvRec, sid: RocBytes) callconv(.c) bool {
    const h = current("raw");
    return h.raw(h.ctx, .of(conv), sid.slice());
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
