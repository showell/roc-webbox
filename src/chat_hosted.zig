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
pub const Form = route.Form;
pub const Reacted = route.Reacted;
pub const Hostility = route.Hostility;
pub const Feed = route.Feed;
pub const Conv = abi.Conv;

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

/// A host whose answers a test sets, and which records what it was asked:
/// the member is 1, in channel ops with 3; account 2 is Debbie.
const Scripted = struct {
    /// Whether the DM's other half is an account.
    account_ok: bool = true,
    /// The partner's stored name ("" for none).
    partner: []const u8 = "Debbie",
    /// The channel's members.
    ops: []const []const u8 = &.{ "1", "3" },
    /// The conversation's topics.
    topics: []const []const u8 = &.{"Plans"},
    body: ?[]const u8 = "",
    reactions: ?[]const u8 = "",
    react_answer: route.Reacted = .stored,
    /// The pinned file read, or null when the read failed.
    pins: ?[]const u8 = "",
    /// Whether writing or removing it succeeds.
    pin_ok: bool = true,
    /// The page's data, or none when it failed.
    page: []const []const u8 = &.{},
    is_async: bool = false,
    hostile_answer: route.Hostility = .fine,
    bookmark_ok: bool = true,
    append_ok: bool = true,
    transcript: bool = true,
    linked: bool = false,
    asked: std.ArrayList(u8) = .empty,
    alloc: std.mem.Allocator,

    fn host(self: *Scripted) Host {
        return .{ .ctx = self, .member = member, .presence = presence, .account = account, .name = name, .channel_members = channelMembers, .topics = topicsOf, .me = meId, .body = bodyOf, .reactions = reactionsOf, .react = react, .pins = pinsOf, .write_pins = writePins, .remove_pins = removePins, .page = pageOf, .header = header, .hostile = hostile, .viewer = viewer, .bookmark = bookmark, .append = append, .raw = raw, .links = links, .srcs = srcs };
    }
    fn me(ctx: *anyopaque) *Scripted {
        return @ptrCast(@alignCast(ctx));
    }
    fn say(ctx: *anyopaque, comptime fmt: []const u8, args: anytype) void {
        const s = me(ctx);
        s.asked.print(s.alloc, fmt ++ ";", args) catch @panic("oom");
    }
    /// A conversation as the Roc handed it: every field, so a record laid
    /// out wrong across the seam shows.
    fn sayConv(ctx: *anyopaque, what: []const u8, conv: Conv) void {
        const s = me(ctx);
        s.asked.print(s.alloc, "{s} {t} {s} {s} [", .{ what, conv.family, conv.key, conv.base }) catch @panic("oom");
        for (conv.members, 0..) |m, i| s.asked.print(s.alloc, "{s}{s}", .{ if (i == 0) "" else ",", m }) catch @panic("oom");
        s.asked.appendSlice(s.alloc, "]") catch @panic("oom");
    }
    fn member(ctx: *anyopaque) bool {
        say(ctx, "member", .{});
        return true;
    }
    fn presence(ctx: *anyopaque) void {
        say(ctx, "presence", .{});
    }
    fn meId(_: *anyopaque) []const u8 {
        return "1";
    }
    fn account(ctx: *anyopaque, id: []const u8) bool {
        say(ctx, "account {s}", .{id});
        return me(ctx).account_ok;
    }
    fn name(ctx: *anyopaque, id: []const u8) []const u8 {
        say(ctx, "name {s}", .{id});
        return me(ctx).partner;
    }
    fn channelMembers(ctx: *anyopaque, channel: []const u8) []const []const u8 {
        say(ctx, "channel_members {s}", .{channel});
        return if (std.mem.eql(u8, channel, "ops")) me(ctx).ops else &.{};
    }
    fn topicsOf(ctx: *anyopaque, family: route.Family, key: []const u8) []const []const u8 {
        say(ctx, "topics {t} {s}", .{ family, key });
        return me(ctx).topics;
    }
    fn bodyOf(ctx: *anyopaque, _: route.Form) ?[]const u8 {
        say(ctx, "body", .{});
        return me(ctx).body;
    }
    fn reactionsOf(ctx: *anyopaque, conv: Conv, sid: []const u8) ?[]const u8 {
        sayConv(ctx, "reactions", conv);
        say(ctx, " {s}", .{sid});
        return me(ctx).reactions;
    }
    fn react(ctx: *anyopaque, conv: Conv, sid: []const u8, msg: u64, emoji: []const u8, on: bool) route.Reacted {
        sayConv(ctx, "react", conv);
        say(ctx, " {s} {d} {s} {}", .{ sid, msg, emoji, on });
        return me(ctx).react_answer;
    }
    fn pinsOf(ctx: *anyopaque, conv: Conv) ?[]const u8 {
        say(ctx, "pins {s}", .{conv.key});
        return me(ctx).pins;
    }
    fn writePins(ctx: *anyopaque, conv: Conv, bytes: []const u8) bool {
        say(ctx, "write_pins {s} {s}", .{ conv.key, bytes });
        return me(ctx).pin_ok;
    }
    fn removePins(ctx: *anyopaque, conv: Conv) bool {
        say(ctx, "remove_pins {s}", .{conv.key});
        return me(ctx).pin_ok;
    }
    fn pageOf(ctx: *anyopaque, conv: Conv, sid: []const u8) []const []const u8 {
        sayConv(ctx, "page", conv);
        say(ctx, " {s}", .{sid});
        return me(ctx).page;
    }
    fn header(ctx: *anyopaque, header_name: []const u8) []const []const u8 {
        say(ctx, "header {s}", .{header_name});
        return if (me(ctx).is_async) &.{"1"} else &.{};
    }
    fn hostile(ctx: *anyopaque, markdown: []const u8) route.Hostility {
        say(ctx, "hostile {s}", .{markdown});
        return me(ctx).hostile_answer;
    }
    fn viewer(ctx: *anyopaque) []const u8 {
        say(ctx, "viewer", .{});
        return "Steve";
    }
    fn bookmark(ctx: *anyopaque, conv: Conv, sid: []const u8) bool {
        say(ctx, "bookmark {s} {s}", .{ conv.key, sid });
        return me(ctx).bookmark_ok;
    }
    fn raw(ctx: *anyopaque, conv: Conv, sid: []const u8) bool {
        say(ctx, "raw {s} {s}", .{ conv.key, sid });
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
    fn append(ctx: *anyopaque, conv: Conv, sid: []const u8, author: []const u8, markdown: []const u8, cid: []const u8) bool {
        sayConv(ctx, "append", conv);
        say(ctx, " {s} {s} {s} {s}", .{ sid, author, markdown, cid });
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

/// What finding DM 1_2's topic Plans asks: whether 2 is an account, 2's
/// name (the title, before the topics, as findTopic read them), the topics.
const dm_topic = "member;presence;account 2;name 2;topics dm 1_2;";
/// And channel ops's: its members, its topics.
const ops_topic = "member;presence;channel_members ops;topics channel ops;";

test "a topic's reactions, react, pin and unpin are the Roc's: presence, the conversation and topic found, the method, then the work" {
    use(testing.allocator);
    defer @import("roc_abi.zig").deinit();
    const a: Scripted = .{ .alloc = undefined };
    const thumbs = "msg=3&emoji=%F0%9F%91%8D&on=0";
    try expectAct("/c/1_2/Plans/react", false, .POST, blk: {
        var s = a;
        s.body = thumbs;
        break :blk s;
    }, .{ .respond = .{ .status = 204 } }, dm_topic ++ "body;react dm 1_2 /chat/c/1_2 [1,2] Plans 3 \u{1F44D} false;");
    try expectAct("/ops/Plans/react", true, .POST, blk: {
        var s = a;
        s.body = "msg=9&emoji=%F0%9F%91%8D";
        s.react_answer = .no_such_message;
        break :blk s;
    }, .{ .respond = .{ .status = 400, .body = "react: no such message\n" } }, ops_topic ++ "body;react channel ops /channel/ops [1,3] Plans 9 \u{1F44D} true;");
    // The form judged before the store is asked.
    try expectAct("/c/1_2/Plans/react", false, .POST, blk: {
        var s = a;
        s.body = "msg=x&emoji=%F0%9F%91%8D";
        break :blk s;
    }, .{ .respond = .{ .status = 400, .body = "react: msg must be a message number\n" } }, dm_topic ++ "body;");
    try expectAct("/c/1_2/Plans/react", false, .POST, blk: {
        var s = a;
        s.body = "msg=1&emoji=%F0";
        break :blk s;
    }, .{ .respond = .{ .status = 400, .body = "react: emoji must be one glyph\n" } }, dm_topic ++ "body;");
    try expectAct("/c/1_2/Plans/react", false, .POST, blk: {
        var s = a;
        s.body = "msg=1&msg=2&emoji=%F0%9F%91%8D";
        break :blk s;
    }, .malformed_form, dm_topic ++ "body;");
    // The host answered (too big) or failed: nothing more.
    try expectAct("/c/1_2/Plans/react", false, .POST, blk: {
        var s = a;
        s.body = null;
        break :blk s;
    }, .answered, dm_topic ++ "body;");
    try expectAct("/c/1_2/Plans/react", false, .POST, blk: {
        var s = a;
        s.body = thumbs;
        s.react_answer = .failed;
        break :blk s;
    }, .answered, dm_topic ++ "body;react dm 1_2 /chat/c/1_2 [1,2] Plans 3 \u{1F44D} false;");
    // The method after the topic, before the body.
    try expectAct("/c/1_2/Plans/react", false, .GET, a, .{ .not_allowed = .POST }, dm_topic);
    try expectAct("/c/1_2/Plans/reactions", false, .HEAD, a, .{ .not_allowed = .GET }, dm_topic);
    try expectAct("/c/1_2/Plans/reactions", false, .GET, blk: {
        var s = a;
        s.reactions = "{\"msg\":1}\n";
        break :blk s;
    }, .{ .respond = .{ .status = 200, .content_type = "application/x-ndjson; charset=utf-8", .body = "{\"msg\":1}\n" } }, dm_topic ++ "reactions dm 1_2 /chat/c/1_2 [1,2] Plans;");
    try expectAct("/c/1_2/Plans/reactions", false, .GET, blk: {
        var s = a;
        s.reactions = null;
        break :blk s;
    }, .answered, dm_topic ++ "reactions dm 1_2 /chat/c/1_2 [1,2] Plans;");
    // The set is the Roc's (ChatState.pinned): read, changed, written back
    // sorted by bytes, or removed when emptied.
    try expectAct("/c/1_2/Plans/pin", false, .POST, a, .{ .respond = .{ .status = 204 } }, dm_topic ++ "pins 1_2;write_pins 1_2 Plans\n;");
    try expectAct("/c/1_2/Plans/pin", false, .POST, blk: {
        var s = a;
        s.pins = "b\r\n  a\n\nPlans\n";
        break :blk s;
    }, .{ .respond = .{ .status = 204 } }, dm_topic ++ "pins 1_2;write_pins 1_2 Plans\na\nb\n;");
    try expectAct("/ops/Plans/unpin", true, .POST, a, .{ .respond = .{ .status = 204 } }, ops_topic ++ "pins ops;remove_pins ops;");
    try expectAct("/c/1_2/Plans/unpin", false, .POST, blk: {
        var s = a;
        s.pins = "Other\nPlans\n";
        s.pin_ok = false;
        break :blk s;
    }, .answered, dm_topic ++ "pins 1_2;write_pins 1_2 Other\n;");
    // A set that will not read is not an empty set: nothing is written.
    try expectAct("/c/1_2/Plans/pin", false, .POST, blk: {
        var s = a;
        s.pins = null;
        break :blk s;
    }, .answered, dm_topic ++ "pins 1_2;");
    try expectAct("/c/1_2/Plans/pin", false, .PUT, a, .{ .not_allowed = .POST }, dm_topic);
    // A topic found without case.
    try expectAct("/c/1_2/plans/pin", false, .PUT, a, .{ .not_allowed = .POST }, dm_topic);
    // A topic that is not there, or a conversation that is not the member's:
    // Zig's to answer, presence already counted.
    const gone: Decision = .{ .serve = .{ .route = .{ .family = .dm, .key = "1_2", .sid = "Gone", .part = .topic, .tail = .react }, .presence = false } };
    try expectAct("/c/1_2/Gone/react", false, .POST, a, gone, dm_topic);
    try expectAct("/c/1_2/Gone/react", false, .POST, blk: {
        var s = a;
        s.account_ok = false;
        break :blk s;
    }, gone, "member;presence;account 2;");
    // Not one of the pair, a pair not canonical: no account asked.
    try expectAct("/c/2_3/Plans/react", false, .POST, a, .{ .serve = .{ .route = .{ .family = .dm, .key = "2_3", .sid = "Plans", .part = .topic, .tail = .react }, .presence = false } }, "member;presence;");
    try expectAct("/c/2_1/Plans/react", false, .POST, a, .{ .serve = .{ .route = .{ .family = .dm, .key = "2_1", .sid = "Plans", .part = .topic, .tail = .react }, .presence = false } }, "member;presence;");
    try expectAct("/dev/Plans/pin", true, .POST, a, .{ .serve = .{ .route = .{ .family = .channel, .key = "dev", .sid = "Plans", .part = .topic, .tail = .pin }, .presence = false } }, "member;presence;channel_members dev;");
    // A route still Zig's goes there, asking nothing more.
    try expectAct("/c/1_2/Plans/stream", false, .GET, a, .{ .serve = .{ .route = .{ .family = .dm, .key = "1_2", .sid = "Plans", .part = .topic, .tail = .stream }, .presence = false } }, "member;");
}

test "a DM's page and landing, and the DM with yourself: the title the Roc's, a page's bookmark before its data" {
    use(testing.allocator);
    defer @import("roc_abi.zig").deinit();
    const a: Scripted = .{ .alloc = undefined };
    // A page whose data failed: the bookmark was asked first.
    try expectAct("/c/1_2/Plans", false, .GET, a, .answered, dm_topic ++ "bookmark 1_2 Plans;page dm 1_2 /chat/c/1_2 [1,2] Plans;");
    try expectAct("/c/1_2/Plans", false, .GET, blk: {
        var s = a;
        s.bookmark_ok = false;
        break :blk s;
    }, .answered, dm_topic ++ "bookmark 1_2 Plans;");
    // A channel's page moves no bookmark.
    try expectAct("/ops/Plans", true, .GET, a, .answered, ops_topic ++ "page channel ops /channel/ops [1,3] Plans;");
    // The landing: the first topic, or the page offering one, titled by the
    // partner's id when the account has no name.
    try expectAct("/c/1_2", false, .GET, a, .{ .redirect = "/chat/c/1_2/Plans" }, "member;presence;account 2;topics dm 1_2;");
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var s: Scripted = .{ .alloc = arena.allocator(), .topics = &.{}, .partner = "" };
    const got = try decide(arena.allocator(), "/c/1_2", false, .GET, s.host());
    try testing.expectEqualStrings("member;presence;account 2;topics dm 1_2;name 2;viewer;srcs;", s.asked.items);
    try testing.expect(std.mem.indexOf(u8, got.respond.body, "Chat w/2") != null);
    // The DM with yourself: one member, its partner yourself.
    try expectAct("/c/1_1/Plans/reactions", false, .GET, a, .{ .respond = .{ .status = 200, .content_type = "application/x-ndjson; charset=utf-8", .body = "" } }, "member;presence;account 1;name 1;topics dm 1_1;reactions dm 1_1 /chat/c/1_1 [1] Plans;");
}

test "a send is the Roc's: the conversation, the method, the header, the body, the message judged, the bookmark, then the store" {
    use(testing.allocator);
    defer @import("roc_abi.zig").deinit();
    const a: Scripted = .{ .alloc = undefined, .body = "markdown=hi&cid=c-1" };
    // The partner's name is read, as the Zig read the title before a send.
    const found = "member;presence;account 2;name 2;";
    const asked = found ++ "header x-chat-async;body;";
    try expectAct("/c/1_2/Plans/send", false, .POST, a, .{ .redirect = "/chat/c/1_2/Plans" }, asked ++ "hostile hi;viewer;bookmark 1_2 Plans;append dm 1_2 /chat/c/1_2 [1,2] Plans Steve hi c-1;");
    // A channel's send moves no bookmark; an async sender is answered 204.
    try expectAct("/ops/Plans/send", true, .POST, blk: {
        var s = a;
        s.is_async = true;
        break :blk s;
    }, .{ .respond = .{ .status = 204 } }, "member;presence;channel_members ops;header x-chat-async;body;hostile hi;viewer;append channel ops /channel/ops [1,3] Plans Steve hi c-1;");
    // Hostile, a bookmark or a store that failed: the host answered, and
    // nothing after it is asked.
    try expectAct("/c/1_2/Plans/send", false, .POST, blk: {
        var s = a;
        s.hostile_answer = .refused;
        break :blk s;
    }, .answered, asked ++ "hostile hi;");
    try expectAct("/c/1_2/Plans/send", false, .POST, blk: {
        var s = a;
        s.hostile_answer = .failed;
        break :blk s;
    }, .answered, asked ++ "hostile hi;");
    try expectAct("/c/1_2/Plans/send", false, .POST, blk: {
        var s = a;
        s.bookmark_ok = false;
        break :blk s;
    }, .answered, asked ++ "hostile hi;viewer;bookmark 1_2 Plans;");
    try expectAct("/c/1_2/Plans/send", false, .POST, blk: {
        var s = a;
        s.append_ok = false;
        break :blk s;
    }, .answered, asked ++ "hostile hi;viewer;bookmark 1_2 Plans;append dm 1_2 /chat/c/1_2 [1,2] Plans Steve hi c-1;");
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
        s.account_ok = false;
        break :blk s;
    }, .{ .serve = .{ .route = .{ .family = .dm, .key = "1_2", .sid = "Plans", .part = .topic, .tail = .send }, .presence = false } }, "member;presence;account 2;");
    try expectAct("/c/1_2/Plans/send", false, .GET, a, .{ .not_allowed = .POST }, found);
    // A new topic in a DM: the bookmark, the first message, the announcement
    // in its highest general<N>, each with the conversation.
    try expectAct("/c/1_2/new", false, .POST, blk: {
        var s = a;
        s.body = "topic=Ideas";
        s.topics = &.{ "general2", "Plans" };
        break :blk s;
    }, .{ .respond = .{ .status = 200, .content_type = "application/json; charset=utf-8", .body = "{\"conv\":\"1_2\",\"sid\":\"Ideas\"}" } }, "member;presence;account 2;body;topics dm 1_2;viewer;bookmark 1_2 Ideas;append dm 1_2 /chat/c/1_2 [1,2] Ideas Steve hi ;topics dm 1_2;append dm 1_2 /chat/c/1_2 [1,2] general2 Steve New topic: [Ideas](/chat/c/1_2/Ideas) ;");
}

test "a topic's raw transcript and /chat/links are the Roc's: a transcript the host has not is a plain 404, never handed back" {
    use(testing.allocator);
    defer @import("roc_abi.zig").deinit();
    const a: Scripted = .{ .alloc = undefined };
    try expectAct("/c/1_2/Plans/raw", false, .GET, a, .{ .held = .{ .status = 200, .content_type = "text/plain; charset=utf-8", .nosniff = true } }, dm_topic ++ "raw 1_2 Plans;");
    // Found as a topic, but the host read no transcript (gone since).
    try expectAct("/c/1_2/Plans/raw", false, .HEAD, blk: {
        var s = a;
        s.transcript = false;
        break :blk s;
    }, .not_found, dm_topic ++ "raw 1_2 Plans;");
    try expectAct("/c/1_2/Plans/raw", false, .POST, a, .{ .not_allowed = .GET }, dm_topic);
    // /chat/links asks the viewer, the scripts, then the page; below it, nothing.
    try expectAct("/links/x", false, .GET, a, .not_found, "member;presence;");
}
