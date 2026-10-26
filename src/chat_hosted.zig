//! **THE ROC CHAT'S ROUTER, AS ANGRY-GOPHER TAKES IT** (docs/ROC-CHAT.md
//! §3, milestone 1): `decide`, the Roc router's decision for a /chat or
//! /channel path (chat/main.roc, chat/Route.roc), and the route it is read
//! into (chat_route.zig). angry-gopher serves the decision with its own Zig;
//! nothing else here touches a request.

const std = @import("std");
const abi = @import("chat_abi.zig");
const route = @import("chat_route.zig");

pub const decide = abi.decide;
pub const Host = abi.Host;
pub const askingOnly = abi.askingOnly;
pub const Routing = abi.Routing;
pub const Decision = route.Decision;
pub const Route = route.Route;
pub const Family = route.Family;
pub const Part = route.Part;
pub const Tail = route.Tail;

/// roc_abi.zig's arena, from `base`, once, as the host starts.
pub fn use(base: std.mem.Allocator) void {
    @import("roc_abi.zig").use(base);
}

/// Or the request's own allocator, freed with the request, before each
/// call (roc_abi.zig `useRequest`): no arena over it.
pub fn useRequest(request: std.mem.Allocator) void {
    @import("roc_abi.zig").useRequest(request);
}

// ── tests: a few decisions through the Roc (angry-gopher's tests hold the
// router to Zig's own parse over a corpus) ────────────────────────────────

const testing = std.testing;

fn answer(member: bool) Host {
    const S = struct {
        fn yes(_: *anyopaque) bool {
            return true;
        }
        fn no(_: *anyopaque) bool {
            return false;
        }
        var dummy: u8 = 0;
    };
    return askingOnly(&S.dummy, if (member) S.yes else S.no);
}

fn expectRoute(sub: []const u8, channel: bool, want: Route, presence: bool) !void {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    // A route the Roc serves itself counts presence itself, then, finding
    // nothing, hands the route to Zig.
    var routing: Routing = .{};
    var got = try decide(arena.allocator(), sub, channel, .GET, routing.host());
    if (got == .serve and routing.marked) got.serve.presence = true;
    const expected: Decision = .{ .serve = .{ .route = want, .presence = presence } };
    if (!got.eql(expected)) {
        std.debug.print("{s}: got {f}, want {f}\n", .{ sub, got, expected });
        return error.TestUnexpectedResult;
    }
}

test "the router: a topic's tails, a channel, an asset before the gate, the gate" {
    use(testing.allocator);
    defer @import("roc_abi.zig").deinit();
    try expectRoute("/c/1_2/general/send", false, .{ .family = .dm, .key = "1_2", .sid = "general", .part = .topic, .tail = .send }, true);
    try expectRoute("/c/1_2/general/uploads/a.png", false, .{ .family = .dm, .key = "1_2", .sid = "general", .part = .topic, .tail = .uploads, .rest = "a.png" }, true);
    try expectRoute("/c/1_2/general/stream", false, .{ .family = .dm, .key = "1_2", .sid = "general", .part = .topic, .tail = .stream }, false);
    try expectRoute("/c/1_2/general/send/x", false, .{ .family = .dm, .key = "1_2", .sid = "general", .part = .topic, .tail = .invalid_send }, true);
    try expectRoute("/c/1_2/bad_id", false, .{ .family = .dm, .key = "1_2", .part = .invalid }, true);
    try expectRoute("/ops/new", true, .{ .family = .channel, .key = "ops", .part = .new }, true);
    try expectRoute("/9ops/x", true, .{ .family = .not_found }, true);
    try expectRoute("/docs/new", false, .{ .family = .docs, .rest = "/new" }, true);
    try expectRoute("/docsX", false, .{ .family = .not_found }, true);
    try expectRoute("/searchX", false, .{ .family = .search, .rest = "X" }, true);
    try expectRoute("/chat.js", false, .{ .family = .asset, .rest = "chat.js" }, false);
    // Bytes that are not UTF-8 come back as they went.
    try expectRoute("/docs/\xff\xfe", false, .{ .family = .docs, .rest = "/\xff\xfe" }, true);

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const away = try decide(arena.allocator(), "/c/1_2/general", false, .GET, answer(false));
    try testing.expectEqualStrings("/login/full?next=/chat/c/1_2/general", away.redirect);
    const asset = try decide(arena.allocator(), "/chat.js", false, .GET, answer(false));
    try testing.expectEqual(Family.asset, asset.serve.route.family);
}

/// A host whose answers a test sets, and which records what it was asked.
const Scripted = struct {
    found: bool = true,
    body: ?[]const u8 = "",
    reactions: ?[]const u8 = "",
    react_answer: u8 = 0,
    pin_ok: bool = true,
    send_to: []const []const u8 = &.{ "/chat/c/1_2", "1" },
    is_async: bool = false,
    hostile_answer: u8 = 0,
    bookmark_ok: bool = true,
    append_ok: bool = true,
    transcript: bool = true,
    linked: bool = false,
    asked: std.ArrayList(u8) = .empty,
    alloc: std.mem.Allocator,

    fn host(self: *Scripted) Host {
        return .{ .ctx = self, .member = member, .presence = presence, .topic = topic, .body = bodyOf, .reactions = reactionsOf, .react = react, .pin = pin, .send_conv = sendConv, .header = header, .hostile = hostile, .viewer = viewer, .bookmark = bookmark, .append = append, .raw = raw, .links = links, .srcs = srcs };
    }
    fn me(ctx: *anyopaque) *Scripted {
        return @ptrCast(@alignCast(ctx));
    }
    fn say(ctx: *anyopaque, comptime fmt: []const u8, args: anytype) void {
        const s = me(ctx);
        s.asked.print(s.alloc, fmt ++ ";", args) catch @panic("oom");
    }
    fn member(ctx: *anyopaque) bool {
        say(ctx, "member", .{});
        return true;
    }
    fn presence(ctx: *anyopaque) void {
        say(ctx, "presence", .{});
    }
    fn topic(ctx: *anyopaque, family: u8, key: []const u8, sid: []const u8) bool {
        say(ctx, "topic {d} {s} {s}", .{ family, key, sid });
        return me(ctx).found;
    }
    fn bodyOf(ctx: *anyopaque, _: u8) ?[]const u8 {
        say(ctx, "body", .{});
        return me(ctx).body;
    }
    fn reactionsOf(ctx: *anyopaque) ?[]const u8 {
        say(ctx, "reactions", .{});
        return me(ctx).reactions;
    }
    fn react(ctx: *anyopaque, msg: u64, emoji: []const u8, on: bool) u8 {
        say(ctx, "react {d} {s} {}", .{ msg, emoji, on });
        return me(ctx).react_answer;
    }
    fn pin(ctx: *anyopaque, pinned: bool) bool {
        say(ctx, "pin {}", .{pinned});
        return me(ctx).pin_ok;
    }
    fn sendConv(ctx: *anyopaque, family: u8, key: []const u8, sid: []const u8) []const []const u8 {
        say(ctx, "send_conv {d} {s} {s}", .{ family, key, sid });
        return me(ctx).send_to;
    }
    fn header(ctx: *anyopaque, name: []const u8) []const []const u8 {
        say(ctx, "header {s}", .{name});
        return if (me(ctx).is_async) &.{"1"} else &.{};
    }
    fn hostile(ctx: *anyopaque, markdown: []const u8) u8 {
        say(ctx, "hostile {s}", .{markdown});
        return me(ctx).hostile_answer;
    }
    fn viewer(ctx: *anyopaque) []const u8 {
        say(ctx, "viewer", .{});
        return "Steve";
    }
    fn bookmark(ctx: *anyopaque, sid: []const u8) bool {
        say(ctx, "bookmark {s}", .{sid});
        return me(ctx).bookmark_ok;
    }
    fn raw(ctx: *anyopaque) bool {
        say(ctx, "raw", .{});
        return me(ctx).transcript;
    }
    fn links(ctx: *anyopaque) bool {
        say(ctx, "links", .{});
        return me(ctx).linked;
    }
    fn srcs(ctx: *anyopaque) []const []const u8 {
        say(ctx, "srcs", .{});
        return &.{};
    }
    fn append(ctx: *anyopaque, sid: []const u8, name: []const u8, markdown: []const u8, cid: []const u8) bool {
        say(ctx, "append {s} {s} {s} {s}", .{ sid, name, markdown, cid });
        return me(ctx).append_ok;
    }
};

fn expectAct(sub: []const u8, channel: bool, method: std.http.Method, script: Scripted, want: Decision, asked: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var s = script;
    s.alloc = arena.allocator();
    const got = try decide(arena.allocator(), sub, channel, method, s.host());
    if (!got.eql(want) or !std.mem.eql(u8, s.asked.items, asked)) {
        std.debug.print("{s}: got {f} asking \"{s}\", want {f} asking \"{s}\"\n", .{ sub, got, s.asked.items, want, asked });
        return error.TestUnexpectedResult;
    }
}

test "a topic's reactions, react, pin and unpin are the Roc's: presence, the topic, the method, then the work" {
    use(testing.allocator);
    defer @import("roc_abi.zig").deinit();
    const a: Scripted = .{ .alloc = undefined };
    const thumbs = "msg=3&emoji=%F0%9F%91%8D&on=0";
    try expectAct("/c/1_2/Plans/react", false, .POST, blk: {
        var s = a;
        s.body = thumbs;
        break :blk s;
    }, .{ .respond = .{ .status = 204 } }, "member;presence;topic 11 1_2 Plans;body;react 3 \u{1F44D} false;");
    try expectAct("/ops/Plans/react", true, .POST, blk: {
        var s = a;
        s.body = "msg=9&emoji=%F0%9F%91%8D";
        s.react_answer = 1;
        break :blk s;
    }, .{ .respond = .{ .status = 400, .body = "react: no such message\n" } }, "member;presence;topic 12 ops Plans;body;react 9 \u{1F44D} true;");
    // The form judged before the store is asked.
    try expectAct("/c/1_2/Plans/react", false, .POST, blk: {
        var s = a;
        s.body = "msg=x&emoji=%F0%9F%91%8D";
        break :blk s;
    }, .{ .respond = .{ .status = 400, .body = "react: msg must be a message number\n" } }, "member;presence;topic 11 1_2 Plans;body;");
    try expectAct("/c/1_2/Plans/react", false, .POST, blk: {
        var s = a;
        s.body = "msg=1&emoji=%F0";
        break :blk s;
    }, .{ .respond = .{ .status = 400, .body = "react: emoji must be one glyph\n" } }, "member;presence;topic 11 1_2 Plans;body;");
    try expectAct("/c/1_2/Plans/react", false, .POST, blk: {
        var s = a;
        s.body = "msg=1&msg=2&emoji=%F0%9F%91%8D";
        break :blk s;
    }, .malformed_form, "member;presence;topic 11 1_2 Plans;body;");
    // The host answered (too big) or failed: nothing more.
    try expectAct("/c/1_2/Plans/react", false, .POST, blk: {
        var s = a;
        s.body = null;
        break :blk s;
    }, .answered, "member;presence;topic 11 1_2 Plans;body;");
    try expectAct("/c/1_2/Plans/react", false, .POST, blk: {
        var s = a;
        s.body = thumbs;
        s.react_answer = 2;
        break :blk s;
    }, .answered, "member;presence;topic 11 1_2 Plans;body;react 3 \u{1F44D} false;");
    // The method after the topic, before the body.
    try expectAct("/c/1_2/Plans/react", false, .GET, a, .{ .not_allowed = .POST }, "member;presence;topic 11 1_2 Plans;");
    try expectAct("/c/1_2/Plans/reactions", false, .HEAD, a, .{ .not_allowed = .GET }, "member;presence;topic 11 1_2 Plans;");
    try expectAct("/c/1_2/Plans/reactions", false, .GET, blk: {
        var s = a;
        s.reactions = "{\"msg\":1}\n";
        break :blk s;
    }, .{ .respond = .{ .status = 200, .content_type = "application/x-ndjson; charset=utf-8", .body = "{\"msg\":1}\n" } }, "member;presence;topic 11 1_2 Plans;reactions;");
    try expectAct("/c/1_2/Plans/reactions", false, .GET, blk: {
        var s = a;
        s.reactions = null;
        break :blk s;
    }, .answered, "member;presence;topic 11 1_2 Plans;reactions;");
    try expectAct("/c/1_2/Plans/pin", false, .POST, a, .{ .respond = .{ .status = 204 } }, "member;presence;topic 11 1_2 Plans;pin true;");
    try expectAct("/ops/Plans/unpin", true, .POST, a, .{ .respond = .{ .status = 204 } }, "member;presence;topic 12 ops Plans;pin false;");
    try expectAct("/c/1_2/Plans/unpin", false, .POST, blk: {
        var s = a;
        s.pin_ok = false;
        break :blk s;
    }, .answered, "member;presence;topic 11 1_2 Plans;pin false;");
    try expectAct("/c/1_2/Plans/pin", false, .PUT, a, .{ .not_allowed = .POST }, "member;presence;topic 11 1_2 Plans;");
    // A topic that is not there, or a conversation that is not the member's:
    // Zig's to answer, presence already counted.
    try expectAct("/c/1_2/Gone/react", false, .POST, blk: {
        var s = a;
        s.found = false;
        break :blk s;
    }, .{ .serve = .{ .route = .{ .family = .dm, .key = "1_2", .sid = "Gone", .part = .topic, .tail = .react }, .presence = false } }, "member;presence;topic 11 1_2 Gone;");
    // A route still Zig's goes there, asking nothing more.
    try expectAct("/c/1_2/Plans/stream", false, .GET, a, .{ .serve = .{ .route = .{ .family = .dm, .key = "1_2", .sid = "Plans", .part = .topic, .tail = .stream }, .presence = false } }, "member;");
}

test "a send is the Roc's: the conversation, the method, the header, the body, the message judged, the bookmark, then the store" {
    use(testing.allocator);
    defer @import("roc_abi.zig").deinit();
    const a: Scripted = .{ .alloc = undefined, .body = "markdown=hi&cid=c-1" };
    const asked = "member;presence;send_conv 11 1_2 Plans;header x-chat-async;body;";
    try expectAct("/c/1_2/Plans/send", false, .POST, a, .{ .redirect = "/chat/c/1_2/Plans" }, asked ++ "hostile hi;viewer;bookmark Plans;append Plans Steve hi c-1;");
    // A channel's send moves no bookmark; an async sender is answered 204.
    try expectAct("/ops/Plans/send", true, .POST, blk: {
        var s = a;
        s.send_to = &.{ "/channel/ops", "0" };
        s.is_async = true;
        break :blk s;
    }, .{ .respond = .{ .status = 204 } }, "member;presence;send_conv 12 ops Plans;header x-chat-async;body;hostile hi;viewer;append Plans Steve hi c-1;");
    // Hostile, a bookmark or a store that failed: the host answered, and
    // nothing after it is asked.
    try expectAct("/c/1_2/Plans/send", false, .POST, blk: {
        var s = a;
        s.hostile_answer = 1;
        break :blk s;
    }, .answered, asked ++ "hostile hi;");
    try expectAct("/c/1_2/Plans/send", false, .POST, blk: {
        var s = a;
        s.hostile_answer = 2;
        break :blk s;
    }, .answered, asked ++ "hostile hi;");
    try expectAct("/c/1_2/Plans/send", false, .POST, blk: {
        var s = a;
        s.bookmark_ok = false;
        break :blk s;
    }, .answered, asked ++ "hostile hi;viewer;bookmark Plans;");
    try expectAct("/c/1_2/Plans/send", false, .POST, blk: {
        var s = a;
        s.append_ok = false;
        break :blk s;
    }, .answered, asked ++ "hostile hi;viewer;bookmark Plans;append Plans Steve hi c-1;");
    // Judged by the Roc before the host is asked to: empty, not UTF-8.
    try expectAct("/c/1_2/Plans/send", false, .POST, blk: {
        var s = a;
        s.body = "markdown=%20%0A";
        break :blk s;
    }, .{ .respond = .{ .status = 400, .body = "not sent: the message is empty\n" } }, asked);
    try expectAct("/c/1_2/Plans/send", false, .POST, blk: {
        var s = a;
        s.body = "markdown=%FF";
        break :blk s;
    }, .{ .respond = .{ .status = 400, .body = "not sent: the message is not UTF-8 text\n" } }, asked);
    // No conversation to send to: back to the Zig, which says why.
    try expectAct("/c/1_2/Plans/send", false, .POST, blk: {
        var s = a;
        s.send_to = &.{};
        break :blk s;
    }, .{ .serve = .{ .route = .{ .family = .dm, .key = "1_2", .sid = "Plans", .part = .topic, .tail = .send }, .presence = false } }, "member;presence;send_conv 11 1_2 Plans;");
    try expectAct("/c/1_2/Plans/send", false, .GET, a, .{ .not_allowed = .POST }, "member;presence;send_conv 11 1_2 Plans;");
}

test "a topic's raw transcript and /chat/links are the Roc's: a transcript the host has not is a plain 404, never handed back" {
    use(testing.allocator);
    defer @import("roc_abi.zig").deinit();
    const a: Scripted = .{ .alloc = undefined };
    try expectAct("/c/1_2/Plans/raw", false, .GET, a, .{ .held = .{ .status = 200, .content_type = "text/plain; charset=utf-8", .nosniff = true } }, "member;presence;topic 11 1_2 Plans;raw;");
    // Found as a topic, but the host read no transcript (gone since).
    try expectAct("/c/1_2/Plans/raw", false, .HEAD, blk: {
        var s = a;
        s.transcript = false;
        break :blk s;
    }, .not_found, "member;presence;topic 11 1_2 Plans;raw;");
    try expectAct("/c/1_2/Plans/raw", false, .POST, a, .{ .not_allowed = .GET }, "member;presence;topic 11 1_2 Plans;");
    // /chat/links asks the viewer, the scripts, then the page; below it, nothing.
    try expectAct("/links/x", false, .GET, a, .not_found, "member;presence;");
}
