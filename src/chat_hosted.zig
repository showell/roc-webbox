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
pub const Count = abi.Count;
pub const CountStatus = route.CountStatus;
pub const Rendered = abi.Rendered;
pub const RenderStatus = route.RenderStatus;
pub const Message = abi.Message;
pub const Hostility = route.Hostility;
pub const ReadStatus = route.ReadStatus;
pub const Read = abi.Read;
pub const Listing = abi.Listing;
pub const Entry = abi.Entry;
pub const EntryKind = route.EntryKind;
pub const Conv = abi.Conv;
pub const Account = abi.Account;
pub const Accounts = abi.Accounts;
pub const AccountKind = route.AccountKind;
pub const AccountRead = abi.AccountRead;

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
/// the member is 1, Steve, in channel ops with 3; account 2 is Debbie.
const Scripted = struct {
    /// Every account, as Host.accounts! hands them; null when the read
    /// failed.
    accounts: ?[]const abi.Account = &.{ steve, .{ .id = "2", .name = .{ .found = "Debbie" }, .kind = .member } },
    /// Every channel, in the listing's order: `channels/` lists each as
    /// `<name>.channel`, and that file reads as `read`.
    channels: []const Channel = &.{.{ .name = "ops", .read = .{ .found = "1\n3\n" } }},
    /// The conversation's topics: every `.../sessions` folder lists each as
    /// `<topic>.md`, a file.
    topics: []const []const u8 = &.{"Plans"},
    body: ?[]const u8 = "",
    /// A topic's message count, or a count that failed.
    count: abi.Count = .{ .counted = 3 },
    /// Whether an appended line is stored.
    append_line_ok: bool = true,
    /// The files under the chat root, each as read; any other is missing.
    files: []const File = &.{},
    /// Whether a write or a remove succeeds.
    write_ok: bool = true,
    /// The page's data, or none when it failed.
    page: []const []const u8 = &.{},
    is_async: bool = false,
    hostile_answer: route.Hostility = .fine,
    /// Whether markdown renders (as `<p>` around it), and whether a
    /// message's block is stored.
    render_ok: bool = true,
    store_ok: bool = true,
    transcript: bool = true,
    linked: bool = false,
    asked: std.ArrayList(u8) = .empty,
    alloc: std.mem.Allocator,

    const File = struct { path: []const u8, read: abi.Read };
    const Channel = struct { name: []const u8, read: abi.Read };

    fn host(self: *Scripted) Host {
        return .{ .ctx = self, .member = member, .presence = presence, .accounts = accountsOf, .me = meId, .now = nowOf, .body = bodyOf, .publish = publish, .append_line = appendLine, .message_count = messageCount, .read = readOf, .write = writeOf, .remove = removeOf, .list = listOf, .fail = failOf, .fail_account = failAccountOf, .malformed_channel = malformed, .page = pageOf, .header = header, .hostile = hostile, .render = render, .store_message = storeMessage, .fan_out = fanOut, .raw = raw, .links = links, .srcs = srcs };
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
    fn accountsOf(ctx: *anyopaque) abi.Accounts {
        say(ctx, "accounts", .{});
        return .{ .found = me(ctx).accounts orelse return .failed };
    }
    fn bodyOf(ctx: *anyopaque, _: route.Form) ?[]const u8 {
        say(ctx, "body", .{});
        return me(ctx).body;
    }
    /// The key and the bytes exactly, escaped, so a frame's every byte shows.
    fn publish(ctx: *anyopaque, key: []const u8, bytes: []const u8) void {
        say(ctx, "publish {s} {f}", .{ key, std.zig.fmtString(bytes) });
    }
    fn appendLine(ctx: *anyopaque, path: []const u8, line: []const u8) bool {
        say(ctx, "append_line {s} {s}", .{ path, line });
        return me(ctx).append_line_ok;
    }
    fn messageCount(ctx: *anyopaque, conv: Conv, sid: []const u8) abi.Count {
        sayConv(ctx, "count", conv);
        say(ctx, " {s}", .{sid});
        return me(ctx).count;
    }
    fn nowOf(_: *anyopaque) i64 {
        return 1761400000;
    }
    fn readOf(ctx: *anyopaque, path: []const u8) abi.Read {
        say(ctx, "read {s}", .{path});
        const s = me(ctx);
        for (s.files) |f| if (std.mem.eql(u8, f.path, path)) return f.read;
        for (s.channels) |c| {
            const file = std.fmt.allocPrint(s.alloc, "channels/{s}.channel", .{c.name}) catch @panic("oom");
            if (std.mem.eql(u8, file, path)) return c.read;
        }
        return .missing;
    }
    fn listOf(ctx: *anyopaque, path: []const u8) abi.Listing {
        say(ctx, "list {s}", .{path});
        const s = me(ctx);
        var out: std.ArrayList(abi.Entry) = .empty;
        if (std.mem.eql(u8, path, "channels")) {
            for (s.channels) |c| out.append(s.alloc, .{ .name = std.fmt.allocPrint(s.alloc, "{s}.channel", .{c.name}) catch @panic("oom"), .kind = .file }) catch @panic("oom");
        } else if (std.mem.endsWith(u8, path, "/sessions")) {
            for (s.topics) |t| out.append(s.alloc, .{ .name = std.fmt.allocPrint(s.alloc, "{s}.md", .{t}) catch @panic("oom"), .kind = .file }) catch @panic("oom");
        } else return .missing;
        return .{ .found = out.items };
    }
    fn malformed(ctx: *anyopaque, channel: []const u8) void {
        say(ctx, "malformed {s}", .{channel});
    }
    fn writeOf(ctx: *anyopaque, path: []const u8, bytes: []const u8) bool {
        say(ctx, "write {s} {s}", .{ path, bytes });
        return me(ctx).write_ok;
    }
    fn removeOf(ctx: *anyopaque, path: []const u8) bool {
        say(ctx, "remove {s}", .{path});
        return me(ctx).write_ok;
    }
    fn failOf(ctx: *anyopaque, e: anyerror) void {
        say(ctx, "fail {t}", .{e});
    }
    fn failAccountOf(ctx: *anyopaque, which: abi.AccountRead, id: []const u8) void {
        say(ctx, "fail {t} {s}", .{ which, id });
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
    fn render(ctx: *anyopaque, markdown: []const u8) abi.Rendered {
        say(ctx, "render {s}", .{markdown});
        const s = me(ctx);
        if (!s.render_ok) return .failed;
        return .{ .rendered = std.fmt.allocPrint(s.alloc, "<p>{s}</p>", .{markdown}) catch @panic("oom") };
    }
    /// The block escaped and every field of the message in Chat.Message's
    /// order, so a record laid out wrong across the seam shows.
    fn storeMessage(ctx: *anyopaque, conv: Conv, sid: []const u8, block: []const u8, index: u64, m: abi.Message) bool {
        sayConv(ctx, "store", conv);
        say(ctx, " {s} {f} {d} {s}|{s}|{s}|{s}|{s}", .{ sid, std.zig.fmtString(block), index, m.id, m.from, m.at, m.uid, m.markdown });
        return me(ctx).store_ok;
    }
    fn fanOut(ctx: *anyopaque, conv: Conv, sid: []const u8, m: abi.Message, index: u64) void {
        sayConv(ctx, "fan_out", conv);
        say(ctx, " {s} {s}|{s}|{s}|{s}|{s} {d}", .{ sid, m.id, m.from, m.at, m.uid, m.markdown, index });
    }
};

const steve: abi.Account = .{ .id = "1", .name = .{ .found = "Steve" }, .kind = .member };

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

/// What finding DM 1_2's topic Plans asks: the accounts (whether 2 is one,
/// and its name, the title, before the topics, as findTopic read them),
/// the topics (the DM's sessions folder, listed).
const dm_topic = "member;presence;accounts;list 1_2/sessions;";
/// And channel ops's: its member file, its topics.
const ops_topic = "member;presence;read channels/ops.channel;list channels/ops/sessions;";

/// What recording topic `sid` as where the member resumes DM 1_2 asks, both
/// bookmarks missing: the topic last viewed there, then the DM last in,
/// each read and written as a line.
inline fn bookmarked(comptime sid: []const u8) []const u8 {
    return comptime "read users/1/last-sessions/1_2;write users/1/last-sessions/1_2 " ++ sid ++ "\n;read users/1/last-conv;write users/1/last-conv 1_2\n;";
}

/// A frame as the scripted host says a publish of it: chat_frame
/// reactionFrame's bytes around the sidecar's `line`, escaped.
fn frameSaid(comptime line: []const u8) []const u8 {
    return std.fmt.comptimePrint("{f}", .{std.zig.fmtString("event: reaction\ndata: " ++ line ++ "\n\n")});
}

/// Steve's 👍 on message 3 taken back, at the scripted host's time.
const thumbs_line = "{\"msg\":3,\"uid\":\"1\",\"from\":\"Steve\",\"emoji\":\"\u{1F44D}\",\"on\":false,\"at\":\"2025-10-25T13:46:40Z\"}";
/// What storing it in DM 1_2's topic Plans asks: the count, the line
/// appended to the sidecar, then its frame on the topic's key.
const stored_thumbs = "count dm 1_2 /chat/c/1_2 [1,2] Plans;append_line 1_2/sessions/Plans.reactions.jsonl " ++ thumbs_line ++ ";publish 1_2/Plans " ++ frameSaid(thumbs_line) ++ ";";

test "a topic's reactions, react, pin and unpin are the Roc's: presence, the conversation and topic found, the method, then the work" {
    use(testing.allocator);
    defer @import("roc_abi.zig").deinit();
    const a: Scripted = .{ .alloc = undefined };
    const thumbs = "msg=3&emoji=%F0%9F%91%8D&on=0";
    // Stored: the reactor's name from the accounts the DM was found by, the
    // count, the line appended to the sidecar, then its frame published on
    // the topic's key.
    try expectAct("/c/1_2/Plans/react", false, .POST, blk: {
        var s = a;
        s.body = thumbs;
        break :blk s;
    }, .{ .respond = .{ .status = 204 } }, dm_topic ++ "body;" ++ stored_thumbs);
    // A channel's reactor is asked for by name; message 4 of 3 is none.
    try expectAct("/ops/Plans/react", true, .POST, blk: {
        var s = a;
        s.body = "msg=4&emoji=%F0%9F%91%8D";
        break :blk s;
    }, .{ .respond = .{ .status = 400, .body = "react: no such message\n" } }, ops_topic ++ "body;accounts;count channel ops /channel/ops [1,3] Plans;");
    try expectAct("/ops/Plans/react", true, .POST, blk: {
        var s = a;
        s.body = "msg=0&emoji=%F0%9F%91%8D";
        break :blk s;
    }, .{ .respond = .{ .status = 400, .body = "react: no such message\n" } }, ops_topic ++ "body;accounts;count channel ops /channel/ops [1,3] Plans;");
    // Message 1 is the first; a topic with none has no message 1.
    try expectAct("/ops/Plans/react", true, .POST, blk: {
        var s = a;
        s.body = "msg=1&emoji=%F0%9F%91%8D";
        break :blk s;
    }, .{ .respond = .{ .status = 204 } }, ops_topic ++ "body;accounts;count channel ops /channel/ops [1,3] Plans;append_line channels/ops/sessions/Plans.reactions.jsonl {\"msg\":1,\"uid\":\"1\",\"from\":\"Steve\",\"emoji\":\"\u{1F44D}\",\"on\":true,\"at\":\"2025-10-25T13:46:40Z\"};publish ops/Plans " ++ comptime frameSaid("{\"msg\":1,\"uid\":\"1\",\"from\":\"Steve\",\"emoji\":\"\u{1F44D}\",\"on\":true,\"at\":\"2025-10-25T13:46:40Z\"}") ++ ";");
    try expectAct("/ops/Plans/react", true, .POST, blk: {
        var s = a;
        s.body = "msg=1&emoji=%F0%9F%91%8D";
        s.count = .{ .counted = 0 };
        break :blk s;
    }, .{ .respond = .{ .status = 400, .body = "react: no such message\n" } }, ops_topic ++ "body;accounts;count channel ops /channel/ops [1,3] Plans;");
    // **A COUNT THAT FAILED IS NO ANSWER**: nothing stored, nothing sent.
    try expectAct("/c/1_2/Plans/react", false, .POST, blk: {
        var s = a;
        s.body = thumbs;
        s.count = .failed;
        break :blk s;
    }, .answered, dm_topic ++ "body;count dm 1_2 /chat/c/1_2 [1,2] Plans;");
    // **A LINE NOT STORED IS NEVER SENT**: no publish after a failed append.
    try expectAct("/c/1_2/Plans/react", false, .POST, blk: {
        var s = a;
        s.body = thumbs;
        s.append_line_ok = false;
        break :blk s;
    }, .answered, dm_topic ++ "body;count dm 1_2 /chat/c/1_2 [1,2] Plans;append_line 1_2/sessions/Plans.reactions.jsonl " ++ thumbs_line ++ ";");
    // The reactor's name that will not read: the request fails with it, and
    // nothing is counted, stored or sent.
    try expectAct("/ops/Plans/react", true, .POST, blk: {
        var s = a;
        s.body = thumbs;
        s.accounts = &.{ .{ .id = "1", .name = .unreadable, .kind = .member }, .{ .id = "2", .name = .{ .found = "Debbie" }, .kind = .member } };
        break :blk s;
    }, .answered, ops_topic ++ "body;accounts;fail name 1;");
    try expectAct("/ops/Plans/react", true, .POST, blk: {
        var s = a;
        s.body = thumbs;
        s.accounts = null;
        break :blk s;
    }, .answered, ops_topic ++ "body;accounts;");
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
    // The method after the topic, before the body.
    try expectAct("/c/1_2/Plans/react", false, .GET, a, .{ .not_allowed = .POST }, dm_topic);
    try expectAct("/c/1_2/Plans/reactions", false, .HEAD, a, .{ .not_allowed = .GET }, dm_topic);
    // The sidecar is the Roc's file: as stored, none yet (readReactions's
    // "": no events), or a read that failed (the host's 500).
    const sidecar = "1_2/sessions/Plans.reactions.jsonl";
    const ndjson = "application/x-ndjson; charset=utf-8";
    try expectAct("/c/1_2/Plans/reactions", false, .GET, blk: {
        var s = a;
        s.files = &.{.{ .path = sidecar, .read = .{ .found = "{\"msg\":1}\n" } }};
        break :blk s;
    }, .{ .respond = .{ .status = 200, .content_type = ndjson, .body = "{\"msg\":1}\n" } }, dm_topic ++ "read " ++ sidecar ++ ";");
    try expectAct("/c/1_2/Plans/reactions", false, .GET, a, .{ .respond = .{ .status = 200, .content_type = ndjson, .body = "" } }, dm_topic ++ "read " ++ sidecar ++ ";");
    try expectAct("/c/1_2/Plans/reactions", false, .GET, blk: {
        var s = a;
        s.files = &.{.{ .path = sidecar, .read = .failed }};
        break :blk s;
    }, .answered, dm_topic ++ "read " ++ sidecar ++ ";");
    try expectAct("/ops/Plans/reactions", true, .GET, a, .{ .respond = .{ .status = 200, .content_type = ndjson, .body = "" } }, ops_topic ++ "read channels/ops/sessions/Plans.reactions.jsonl;");
    // The set is the Roc's (ChatState.pinned), and its file's name: read,
    // changed, written back sorted by bytes, or removed when emptied. A
    // missing file is no pins.
    const pins = "users/1/pinned-sessions/1_2";
    try expectAct("/c/1_2/Plans/pin", false, .POST, a, .{ .respond = .{ .status = 204 } }, dm_topic ++ "read " ++ pins ++ ";write " ++ pins ++ " Plans\n;");
    try expectAct("/c/1_2/Plans/pin", false, .POST, blk: {
        var s = a;
        s.files = &.{.{ .path = pins, .read = .{ .found = "b\r\n  a\n\nPlans\n" } }};
        break :blk s;
    }, .{ .respond = .{ .status = 204 } }, dm_topic ++ "read " ++ pins ++ ";write " ++ pins ++ " Plans\na\nb\n;");
    try expectAct("/ops/Plans/unpin", true, .POST, a, .{ .respond = .{ .status = 204 } }, ops_topic ++ "read users/1/pinned-sessions/ops;remove users/1/pinned-sessions/ops;");
    try expectAct("/c/1_2/Plans/unpin", false, .POST, blk: {
        var s = a;
        s.files = &.{.{ .path = pins, .read = .{ .found = "Other\nPlans\n" } }};
        s.write_ok = false;
        break :blk s;
    }, .answered, dm_topic ++ "read " ++ pins ++ ";write " ++ pins ++ " Other\n;");
    // **A SET THAT WILL NOT READ IS NOT AN EMPTY SET**: a failed read (a
    // pins file that is a folder) writes nothing, where a missing one
    // would have written the pin alone.
    try expectAct("/c/1_2/Plans/pin", false, .POST, blk: {
        var s = a;
        s.files = &.{.{ .path = pins, .read = .failed }};
        break :blk s;
    }, .answered, dm_topic ++ "read " ++ pins ++ ";");
    try expectAct("/ops/Plans/unpin", true, .POST, blk: {
        var s = a;
        s.files = &.{.{ .path = "users/1/pinned-sessions/ops", .read = .failed }};
        break :blk s;
    }, .answered, ops_topic ++ "read users/1/pinned-sessions/ops;");
    try expectAct("/c/1_2/Plans/pin", false, .PUT, a, .{ .not_allowed = .POST }, dm_topic);
    // A topic found without case.
    try expectAct("/c/1_2/plans/pin", false, .PUT, a, .{ .not_allowed = .POST }, dm_topic);
    // A topic that is not there, or a conversation that is not the member's:
    // Zig's to answer, presence already counted.
    const gone: Decision = .{ .serve = .{ .route = .{ .family = .dm, .key = "1_2", .sid = "Gone", .part = .topic, .tail = .react }, .presence = false } };
    try expectAct("/c/1_2/Gone/react", false, .POST, a, gone, dm_topic);
    try expectAct("/c/1_2/Gone/react", false, .POST, blk: {
        var s = a;
        s.accounts = &.{steve};
        break :blk s;
    }, gone, "member;presence;accounts;");
    // Not one of the pair, a pair not canonical: no account asked.
    try expectAct("/c/2_3/Plans/react", false, .POST, a, .{ .serve = .{ .route = .{ .family = .dm, .key = "2_3", .sid = "Plans", .part = .topic, .tail = .react }, .presence = false } }, "member;presence;");
    try expectAct("/c/2_1/Plans/react", false, .POST, a, .{ .serve = .{ .route = .{ .family = .dm, .key = "2_1", .sid = "Plans", .part = .topic, .tail = .react }, .presence = false } }, "member;presence;");
    try expectAct("/dev/Plans/pin", true, .POST, a, .{ .serve = .{ .route = .{ .family = .channel, .key = "dev", .sid = "Plans", .part = .topic, .tail = .pin }, .presence = false } }, "member;presence;read channels/dev.channel;");
    // A route still Zig's goes there, asking nothing more.
    try expectAct("/c/1_2/Plans/stream", false, .GET, a, .{ .serve = .{ .route = .{ .family = .dm, .key = "1_2", .sid = "Plans", .part = .topic, .tail = .stream }, .presence = false } }, "member;");
}

test "a DM's page and landing, and the DM with yourself: the title the Roc's, a page's bookmark before its data" {
    use(testing.allocator);
    defer @import("roc_abi.zig").deinit();
    const a: Scripted = .{ .alloc = undefined };
    // A page whose data failed: the bookmark was asked first.
    try expectAct("/c/1_2/Plans", false, .GET, a, .answered, dm_topic ++ bookmarked("Plans") ++ "page dm 1_2 /chat/c/1_2 [1,2] Plans;");
    try expectAct("/c/1_2/Plans", false, .GET, blk: {
        var s = a;
        s.write_ok = false;
        break :blk s;
    }, .answered, dm_topic ++ "read users/1/last-sessions/1_2;write users/1/last-sessions/1_2 Plans\n;");
    // A channel's page moves no bookmark.
    try expectAct("/ops/Plans", true, .GET, a, .answered, ops_topic ++ "page channel ops /channel/ops [1,3] Plans;");
    // The landing: the first topic, or the page offering one, titled by the
    // partner's id when the account has no name.
    try expectAct("/c/1_2", false, .GET, a, .{ .redirect = "/chat/c/1_2/Plans" }, "member;presence;accounts;list 1_2/sessions;");
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var s: Scripted = .{ .alloc = arena.allocator(), .topics = &.{}, .accounts = &.{ steve, .{ .id = "2", .name = .{ .found = "" }, .kind = .guest } } };
    const got = try decide(arena.allocator(), "/c/1_2", false, .GET, s.host());
    try testing.expectEqualStrings("member;presence;accounts;list 1_2/sessions;srcs;", s.asked.items);
    try testing.expect(std.mem.indexOf(u8, got.respond.body, "Chat w/2") != null);
    // The DM with yourself: one member, its partner yourself.
    try expectAct("/c/1_1/Plans/reactions", false, .GET, a, .{ .respond = .{ .status = 200, .content_type = "application/x-ndjson; charset=utf-8", .body = "" } }, "member;presence;accounts;list 1_1/sessions;read 1_1/sessions/Plans.reactions.jsonl;");
}

/// What storing a message asks, step by step: message 4 (index 3, the
/// scripted count) of topic `sid` in `conv` (as `sayConv` says it), the
/// conversation's key `key`, by member 1 named `name`, at the scripted
/// time. The count, the render, the store (the block escaped, then the
/// message's fields), the frame on the topic's key, then the fan-out.
const Sent = struct { count: []const u8, render: []const u8, store: []const u8, publish: []const u8, fan_out: []const u8 };

fn sent(comptime conv: []const u8, comptime key: []const u8, comptime sid: []const u8, comptime name: []const u8, comptime md: []const u8, comptime cid: []const u8) Sent {
    const at = "2025-10-25T13:46:40Z";
    const id = sid ++ "_4";
    const block = "\n\n-------------\nMSG_" ++ id ++ "\nfrom: " ++ name ++ "\ndate: " ++ at ++ "\nuid: 1\n\n" ++ md;
    const frame = "id: 3\ndata: {\"index\":3,\"from\":\"" ++ name ++ "\",\"from_uid\":\"1\",\"at\":\"" ++ at ++ "\",\"html\":\"<p>" ++ md ++ "</p>\",\"markdown\":\"" ++ md ++ "\",\"id\":\"" ++ id ++ "\"" ++ (if (cid.len == 0) "" else ",\"cid\":\"" ++ cid ++ "\"") ++ "}\n\n";
    const message = id ++ "|" ++ name ++ "|" ++ at ++ "|1|" ++ md;
    return comptime .{
        .count = "count " ++ conv ++ " " ++ sid ++ ";",
        .render = "render " ++ md ++ ";",
        .store = std.fmt.comptimePrint("store {s} {s} {f} 3 {s};", .{ conv, sid, std.zig.fmtString(block), message }),
        .publish = std.fmt.comptimePrint("publish {s}/{s} {f};", .{ key, sid, std.zig.fmtString(frame) }),
        .fan_out = "fan_out " ++ conv ++ " " ++ sid ++ " " ++ message ++ " 3;",
    };
}

/// The whole of a message stored and sent.
fn sentAll(comptime s: Sent) []const u8 {
    return comptime s.count ++ s.render ++ s.store ++ s.publish ++ s.fan_out;
}

const dm_said = "dm 1_2 /chat/c/1_2 [1,2]";

test "a message is the Roc's: no author, no message; the count, the id, the stamp, the block and the frame made before the store; then the store, the publish and the fan-out, in that order; nothing after a step that failed" {
    use(testing.allocator);
    defer @import("roc_abi.zig").deinit();
    const a: Scripted = .{ .alloc = undefined, .body = "markdown=hi&cid=c-1" };
    const before = "member;presence;accounts;header x-chat-async;body;hostile hi;" ++ bookmarked("Plans");
    const plans = comptime sent(dm_said, "1_2", "Plans", "Steve", "hi", "c-1");
    try expectAct("/c/1_2/Plans/send", false, .POST, a, .{ .redirect = "/chat/c/1_2/Plans" }, before ++ comptime sentAll(plans));
    // **NO AUTHOR, NO MESSAGE**: the member's name empty fails the request
    // with appendMessage's error, nothing counted, stored or sent.
    try expectAct("/c/1_2/Plans/send", false, .POST, blk: {
        var s = a;
        s.accounts = &.{ .{ .id = "1", .name = .{ .found = "" }, .kind = .member }, .{ .id = "2", .name = .{ .found = "Debbie" }, .kind = .member } };
        break :blk s;
    }, .answered, before ++ "fail NoAuthor;");
    // A count that failed: nothing rendered, stored or sent.
    try expectAct("/c/1_2/Plans/send", false, .POST, blk: {
        var s = a;
        s.count = .failed;
        break :blk s;
    }, .answered, before ++ plans.count);
    // **THE FRAME IS MADE BEFORE THE STORE**: a render that failed stores nothing.
    try expectAct("/c/1_2/Plans/send", false, .POST, blk: {
        var s = a;
        s.render_ok = false;
        break :blk s;
    }, .answered, before ++ plans.count ++ plans.render);
    // **A MESSAGE NOT STORED IS NEVER SENT**: no publish, no fan-out.
    try expectAct("/c/1_2/Plans/send", false, .POST, blk: {
        var s = a;
        s.store_ok = false;
        break :blk s;
    }, .answered, before ++ plans.count ++ plans.render ++ plans.store);
    // A topic's first message is index 0: its id `_1`, its block with no
    // separator before it, its frame `id: 0`.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var first = a;
    first.alloc = arena.allocator();
    first.count = .{ .counted = 0 };
    first.body = "markdown=one";
    _ = try decide(arena.allocator(), "/c/1_2/Plans/send", false, .POST, first.host());
    const at = "2025-10-25T13:46:40Z";
    for ([_][]const u8{
        "store " ++ dm_said ++ " Plans MSG_Plans_1\\nfrom: Steve\\ndate: " ++ at ++ "\\nuid: 1\\n\\none 0 Plans_1|Steve|" ++ at ++ "|1|one;",
        "publish 1_2/Plans id: 0\\ndata: {\\\"index\\\":0,",
        "fan_out " ++ dm_said ++ " Plans Plans_1|Steve|" ++ at ++ "|1|one 0;",
    }) |want| if (std.mem.indexOf(u8, first.asked.items, want) == null) {
        std.debug.print("not asked: {s}\nin: {s}\n", .{ want, first.asked.items });
        return error.TestUnexpectedResult;
    };
}

test "a send is the Roc's: the conversation, the method, the header, the body, the message judged, the bookmark, then the store" {
    use(testing.allocator);
    defer @import("roc_abi.zig").deinit();
    const a: Scripted = .{ .alloc = undefined, .body = "markdown=hi&cid=c-1" };
    // The accounts are read (the partner's name with them, as the Zig read
    // the title before a send), once.
    const found = "member;presence;accounts;";
    const asked = found ++ "header x-chat-async;body;";
    try expectAct("/c/1_2/Plans/send", false, .POST, a, .{ .redirect = "/chat/c/1_2/Plans" }, asked ++ "hostile hi;" ++ bookmarked("Plans") ++ comptime sentAll(sent(dm_said, "1_2", "Plans", "Steve", "hi", "c-1")));
    // A channel's send moves no bookmark; an async sender is answered 204.
    try expectAct("/ops/Plans/send", true, .POST, blk: {
        var s = a;
        s.is_async = true;
        break :blk s;
    }, .{ .respond = .{ .status = 204 } }, "member;presence;read channels/ops.channel;header x-chat-async;body;hostile hi;accounts;" ++ comptime sentAll(sent("channel ops /channel/ops [1,3]", "ops", "Plans", "Steve", "hi", "c-1")));
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
        s.write_ok = false;
        break :blk s;
    }, .answered, asked ++ "hostile hi;read users/1/last-sessions/1_2;write users/1/last-sessions/1_2 Plans\n;");
    try expectAct("/c/1_2/Plans/send", false, .POST, blk: {
        var s = a;
        s.store_ok = false;
        break :blk s;
    }, .answered, asked ++ "hostile hi;" ++ bookmarked("Plans") ++ comptime blk: {
        const s = sent(dm_said, "1_2", "Plans", "Steve", "hi", "c-1");
        break :blk s.count ++ s.render ++ s.store;
    });
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
        s.accounts = &.{steve};
        break :blk s;
    }, .{ .serve = .{ .route = .{ .family = .dm, .key = "1_2", .sid = "Plans", .part = .topic, .tail = .send }, .presence = false } }, "member;presence;accounts;");
    try expectAct("/c/1_2/Plans/send", false, .GET, a, .{ .not_allowed = .POST }, found);
    // A new topic in a DM: the bookmark, the first message, the announcement
    // in its highest general<N>, each with the conversation.
    try expectAct("/c/1_2/new", false, .POST, blk: {
        var s = a;
        s.body = "topic=Ideas";
        s.topics = &.{ "general2", "Plans" };
        break :blk s;
    }, .{ .respond = .{ .status = 200, .content_type = "application/json; charset=utf-8", .body = "{\"conv\":\"1_2\",\"sid\":\"Ideas\"}" } }, "member;presence;accounts;body;list 1_2/sessions;" ++ bookmarked("Ideas") ++ comptime sentAll(sent(dm_said, "1_2", "Ideas", "Steve", "hi", "")) ++ "list 1_2/sessions;" ++ sentAll(sent(dm_said, "1_2", "general2", "Steve", "New topic: [Ideas](/chat/c/1_2/Ideas)", "")));
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

test "the member's bookmarks are the Roc's files: the topic last viewed first, then the DM last in, each written only when it changed, and read back to resume" {
    use(testing.allocator);
    defer @import("roc_abi.zig").deinit();
    const a: Scripted = .{ .alloc = undefined };
    const page = "page dm 1_2 /chat/c/1_2 [1,2] Plans;";
    const ls = "users/1/last-sessions/1_2";
    const lc = "users/1/last-conv";
    // Both already say so, whitespace around them: nothing written.
    try expectAct("/c/1_2/Plans", false, .GET, blk: {
        var s = a;
        s.files = &.{ .{ .path = ls, .read = .{ .found = "Plans\r\n" } }, .{ .path = lc, .read = .{ .found = " \t1_2 \n" } } };
        break :blk s;
    }, .answered, dm_topic ++ "read " ++ ls ++ ";read " ++ lc ++ ";" ++ page);
    // Only the topic changed; only the DM changed.
    try expectAct("/c/1_2/Plans", false, .GET, blk: {
        var s = a;
        s.files = &.{ .{ .path = ls, .read = .{ .found = "Other\n" } }, .{ .path = lc, .read = .{ .found = "1_2" } } };
        break :blk s;
    }, .answered, dm_topic ++ "read " ++ ls ++ ";write " ++ ls ++ " Plans\n;read " ++ lc ++ ";" ++ page);
    try expectAct("/c/1_2/Plans", false, .GET, blk: {
        var s = a;
        s.files = &.{ .{ .path = ls, .read = .{ .found = "Plans" } }, .{ .path = lc, .read = .{ .found = "1_3\n" } } };
        break :blk s;
    }, .answered, dm_topic ++ "read " ++ ls ++ ";read " ++ lc ++ ";write " ++ lc ++ " 1_2\n;" ++ page);
    // A bookmark that will not read is written again (the write says
    // whether it can be: a real host has failed the request already).
    try expectAct("/c/1_2/Plans", false, .GET, blk: {
        var s = a;
        s.files = &.{ .{ .path = ls, .read = .failed }, .{ .path = lc, .read = .{ .found = "1_2\n" } } };
        break :blk s;
    }, .answered, dm_topic ++ "read " ++ ls ++ ";write " ++ ls ++ " Plans\n;read " ++ lc ++ ";" ++ page);
    // /chat reads them back: the DM last in, then where it resumes.
    try expectAct("", false, .GET, blk: {
        var s = a;
        s.topics = &.{ "Other", "Plans" };
        s.files = &.{ .{ .path = ls, .read = .{ .found = "\tPlans \r\n" } }, .{ .path = lc, .read = .{ .found = " 1_2\r\n" } } };
        break :blk s;
    }, .{ .redirect = "/chat/c/1_2/Plans" }, "member;presence;read " ++ lc ++ ";list 1_2/sessions;read " ++ ls ++ ";");
    // The feeds are the member's files too, named by the Roc.
    for ([_][2][]const u8{ .{ "/images", "users/1/images.md" }, .{ "/code", "users/1/code.md" } }) |feed| {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        var s: Scripted = .{ .alloc = arena.allocator() };
        _ = try decide(arena.allocator(), feed[0], false, .GET, s.host());
        try testing.expectEqualStrings(try std.fmt.allocPrint(arena.allocator(), "member;presence;accounts;read {s};srcs;", .{feed[1]}), s.asked.items);
    }
}

test "/chat/msg: every channel's roster, which are the member's, and their order, are the Roc's; a malformed one skipped and counted" {
    use(testing.allocator);
    defer @import("roc_abi.zig").deinit();
    // Only the member: no DM to search.
    const a: Scripted = .{ .alloc = undefined, .accounts = &.{steve} };
    // channels/ listed, each member file read in the listing's order, not
    // sorted: the member is in ops, Zed and a name that sorts high, not in
    // zeta. Every topic list has Plans, so the first of the member's by
    // bytes (`Z` before `o`) is the one.
    const four = "member;presence;accounts;list channels;read channels/ops.channel;read channels/zeta.channel;read channels/\xffhigh.channel;read channels/Zed.channel;";
    try expectAct("/msg/Plans_1", false, .GET, blk: {
        var s = a;
        s.channels = &.{ .{ .name = "ops", .read = .{ .found = "1\n3\n" } }, .{ .name = "zeta", .read = .{ .found = "2" } }, .{ .name = "\xffhigh", .read = .{ .found = "1" } }, .{ .name = "Zed", .read = .{ .found = "# us\r\n 1\t\n" } } };
        break :blk s;
    }, .{ .found = "/channel/Zed/Plans#msg-Plans_1" }, four ++ "list channels/Zed/sessions;");
    // In none: nothing to search.
    try expectAct("/msg/Plans_1", false, .GET, blk: {
        var s = a;
        s.channels = &.{ .{ .name = "zeta", .read = .{ .found = "2" } }, .{ .name = "ops", .read = .{ .found = "" } } };
        break :blk s;
    }, .not_found, "member;presence;accounts;list channels;read channels/zeta.channel;read channels/ops.channel;");
    // **A MALFORMED CHANNEL IS SKIPPED AND COUNTED** as it is met (Abad
    // would be first by bytes); one gone since the listing is skipped,
    // uncounted.
    try expectAct("/msg/Plans_1", false, .GET, blk: {
        var s = a;
        s.channels = &.{ .{ .name = "Abad", .read = .{ .found = "1\nnot a uid\n" } }, .{ .name = "Agone", .read = .missing }, .{ .name = "ops", .read = .{ .found = "1\n" } }, .{ .name = "Adup", .read = .{ .found = "1\n1\n" } } };
        break :blk s;
    }, .{ .found = "/channel/ops/Plans#msg-Plans_1" }, "member;presence;accounts;list channels;read channels/Abad.channel;malformed Abad;read channels/Agone.channel;read channels/ops.channel;read channels/Adup.channel;malformed Adup;list channels/ops/sessions;");
    // A member file that will not read: nothing past it is read, and no
    // channel searched (the host has failed the request); one malformed
    // before it was counted already, as the Zig counted it.
    try expectAct("/msg/Plans_1", false, .GET, blk: {
        var s = a;
        s.channels = &.{ .{ .name = "Abad", .read = .{ .found = "x\n" } }, .{ .name = "ops", .read = .failed }, .{ .name = "Zed", .read = .{ .found = "1\n" } } };
        break :blk s;
    }, .not_found, "member;presence;accounts;list channels;read channels/Abad.channel;malformed Abad;read channels/ops.channel;");
}

test "a channel's member file is the Roc's: a malformed one fails its own route by its reason (never the 404 of a channel not the member's); a missing one is no channel" {
    use(testing.allocator);
    defer @import("roc_abi.zig").deinit();
    const a: Scripted = .{ .alloc = undefined };
    for ([_][]const u8{ "1\n../../x\n", "1\n3 # Claude\n", "1\n2\n1\n", "007\n", "+7\n" }) |bad| {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        var s = a;
        s.alloc = arena.allocator();
        s.channels = &.{.{ .name = "ops", .read = .{ .found = bad } }};
        _ = try decide(arena.allocator(), "/ops/Plans", true, .GET, s.host());
        try testing.expectEqualStrings("member;presence;read channels/ops.channel;fail MalformedChannel;", s.asked.items);
    }
    const none: Decision = .{ .serve = .{ .route = .{ .family = .channel, .key = "dev", .part = .landing }, .presence = false } };
    try expectAct("/dev", true, .GET, a, none, "member;presence;read channels/dev.channel;");
}

test "a conversation's topics are the Roc's: its sessions folder listed, a folder named x.md no topic, and sorted by bytes" {
    use(testing.allocator);
    defer @import("roc_abi.zig").deinit();
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const S = struct {
        fn list(ctx: *anyopaque, path: []const u8) abi.Listing {
            Scripted.say(ctx, "list {s}", .{path});
            return .{ .found = &.{ .{ .name = "b.md", .kind = .file }, .{ .name = "x.md", .kind = .dir }, .{ .name = "a.md", .kind = .other }, .{ .name = "notes.txt", .kind = .file } } };
        }
    };
    var s: Scripted = .{ .alloc = arena.allocator() };
    var h = s.host();
    h.list = S.list;
    // The landing goes to the first by bytes: a link counts, a folder not.
    const got = try decide(arena.allocator(), "/c/1_2", false, .GET, h);
    try testing.expectEqualStrings("/chat/c/1_2/a", got.redirect);
    try testing.expectEqualStrings("member;presence;accounts;list 1_2/sessions;", s.asked.items);
}

/// What `sub` asked of a scripted host, `script` as given.
fn askedOf(arena: std.mem.Allocator, sub: []const u8, channel: bool, method: std.http.Method, script: Scripted) ![]const u8 {
    var s = script;
    s.alloc = arena;
    _ = try decide(arena, sub, channel, method, s.host());
    return s.asked.items;
}

test "the accounts are asked of the host at most once a request: once by every route that looks one up, never by one that does not" {
    use(testing.allocator);
    defer @import("roc_abi.zig").deinit();
    const send: Scripted = .{ .alloc = undefined, .body = "markdown=hi" };
    const Case = struct { sub: []const u8, channel: bool = false, method: std.http.Method = .GET, script: Scripted = .{ .alloc = undefined }, times: usize };
    const cases = [_]Case{
        // A DM: found, titled, its viewer named, all from one asking.
        .{ .sub = "/c/1_2/Plans", .times = 1 },
        .{ .sub = "/c/1_2", .script = .{ .alloc = undefined, .topics = &.{} }, .times = 1 },
        .{ .sub = "/c/1_2/Plans/send", .method = .POST, .script = send, .times = 1 },
        .{ .sub = "/c/1_2/new", .method = .POST, .script = .{ .alloc = undefined, .body = "topic=Ideas" }, .times = 1 },
        // A channel: only what names the viewer asks.
        .{ .sub = "/ops/Plans", .channel = true, .times = 0 },
        .{ .sub = "/ops/Plans/pin", .channel = true, .method = .POST, .times = 0 },
        // A reaction names its reactor: a DM's from the accounts it was
        // found by, a channel's asked for it.
        .{ .sub = "/c/1_2/Plans/react", .method = .POST, .script = .{ .alloc = undefined, .body = "msg=1&emoji=%F0%9F%91%8D" }, .times = 1 },
        .{ .sub = "/ops/Plans/react", .channel = true, .method = .POST, .script = .{ .alloc = undefined, .body = "msg=1&emoji=%F0%9F%91%8D" }, .times = 1 },
        .{ .sub = "/ops", .channel = true, .script = .{ .alloc = undefined, .topics = &.{} }, .times = 1 },
        .{ .sub = "/ops/Plans/send", .channel = true, .method = .POST, .script = send, .times = 1 },
        .{ .sub = "/ops/new", .channel = true, .method = .POST, .script = .{ .alloc = undefined, .body = "topic=Ideas" }, .times = 1 },
        // The member's own pages, the conversations, a message's topic.
        .{ .sub = "", .times = 1 },
        .{ .sub = "/links", .times = 1 },
        .{ .sub = "/images", .times = 1 },
        .{ .sub = "/conversations", .times = 1 },
        .{ .sub = "/msg/Plans_1", .times = 1 },
    };
    for (cases) |c| {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const asked = try askedOf(arena.allocator(), c.sub, c.channel, c.method, c.script);
        if (std.mem.count(u8, asked, "accounts;") != c.times) {
            std.debug.print("{s}: asked \"{s}\", want accounts {d} times\n", .{ c.sub, asked, c.times });
            return error.TestUnexpectedResult;
        }
    }
}

test "accounts that will not read fail the request: never \"no such account\" handed back to the Zig, never a viewer named \"\"" {
    use(testing.allocator);
    defer @import("roc_abi.zig").deinit();
    const a: Scripted = .{ .alloc = undefined, .accounts = null, .body = "markdown=hi" };
    // A DM's other half: the route is not handed to the Zig as not the
    // member's (its 404), and nothing after is asked.
    try expectAct("/c/1_2/Plans", false, .GET, a, .answered, "member;presence;accounts;");
    try expectAct("/c/1_2/Plans/send", false, .POST, a, .answered, "member;presence;accounts;");
    try expectAct("/c/1_2", false, .GET, a, .answered, "member;presence;accounts;");
    // A viewer: no message stored under "".
    try expectAct("/ops/Plans/send", true, .POST, a, .answered, "member;presence;read channels/ops.channel;header x-chat-async;body;hostile hi;accounts;");
    try expectAct("/links", false, .GET, a, .answered, "member;presence;accounts;");
    try expectAct("", false, .GET, a, .answered, "member;presence;read users/1/last-conv;accounts;");
    // The roster: no conversations, no message searched for.
    try expectAct("/conversations", false, .GET, a, .answered, "member;presence;accounts;");
    try expectAct("/msg/Plans_1", false, .GET, a, .answered, "member;presence;accounts;");
}

test "an account that will not read fails only what reads it, with its own read's error: its name the DM it titles, the viewer's own name the pages that name them, the roster on the first in the disk's order; never no account, never a name of \"\"" {
    use(testing.allocator);
    defer @import("roc_abi.zig").deinit();
    const debbie_unnamed: abi.Account = .{ .id = "2", .name = .unreadable, .kind = .member };
    const named = [_]abi.Account{ steve, debbie_unnamed };
    const a: Scripted = .{ .alloc = undefined, .accounts = &named, .body = "markdown=hi" };
    // The partner's name: every topic route and a send (the title, read
    // before the topics and before a send's tail) fail with it, nothing
    // after asked; never handed to the Zig as not the member's.
    try expectAct("/c/1_2/Plans", false, .GET, a, .answered, "member;presence;accounts;fail name 2;");
    try expectAct("/c/1_2/Plans/reactions", false, .GET, a, .answered, "member;presence;accounts;fail name 2;");
    try expectAct("/c/1_2/Plans/send", false, .POST, a, .answered, "member;presence;accounts;fail name 2;");
    // The roster reads a member's name: the conversations and a message's
    // topic fail with it.
    try expectAct("/conversations", false, .GET, a, .answered, "member;presence;accounts;fail name 2;");
    try expectAct("/msg/Plans_1", false, .GET, a, .answered, "member;presence;accounts;fail name 2;");
    // **WHAT NEVER READ IT IS SERVED**: a landing with a topic, the
    // member's own pages, a new topic (the viewer's name only).
    try expectAct("/c/1_2", false, .GET, a, .{ .redirect = "/chat/c/1_2/Plans" }, "member;presence;accounts;list 1_2/sessions;");
    try expectAct("/c/1_2/new", false, .POST, blk: {
        var s = a;
        s.body = "topic=Ideas";
        s.topics = &.{"Plans"};
        break :blk s;
    }, .{ .respond = .{ .status = 200, .content_type = "application/json; charset=utf-8", .body = "{\"conv\":\"1_2\",\"sid\":\"Ideas\"}" } }, "member;presence;accounts;body;list 1_2/sessions;" ++ bookmarked("Ideas") ++ comptime sentAll(sent(dm_said, "1_2", "Ideas", "Steve", "hi", "")) ++ "list 1_2/sessions;");
    for ([_][]const u8{ "/links", "/images", "" }) |sub| {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const asked = try askedOf(arena.allocator(), sub, false, .GET, a);
        if (std.mem.indexOf(u8, asked, "fail") != null) {
            std.debug.print("{s}: asked \"{s}\", read no other account\n", .{ sub, asked });
            return error.TestUnexpectedResult;
        }
    }
    // The landing with no topic reads the title, then fails with it.
    try expectAct("/c/1_2", false, .GET, blk: {
        var s = a;
        s.topics = &.{};
        break :blk s;
    }, .answered, "member;presence;accounts;list 1_2/sessions;fail name 2;");
    // The viewer's own name: every page that names them, and a send.
    const me_unnamed = [_]abi.Account{ .{ .id = "1", .name = .unreadable, .kind = .member }, .{ .id = "2", .name = .{ .found = "Debbie" }, .kind = .member } };
    const m: Scripted = .{ .alloc = undefined, .accounts = &me_unnamed, .body = "markdown=hi" };
    try expectAct("/links", false, .GET, m, .answered, "member;presence;accounts;fail name 1;");
    try expectAct("/images", false, .GET, m, .answered, "member;presence;accounts;fail name 1;");
    try expectAct("/ops/Plans/send", true, .POST, m, .answered, "member;presence;read channels/ops.channel;header x-chat-async;body;hostile hi;accounts;fail name 1;");
    // A guest's name: never read by the roster, read by its DM's title.
    const guest_unnamed = [_]abi.Account{ steve, .{ .id = "2", .name = .unreadable, .kind = .guest } };
    const g: Scripted = .{ .alloc = undefined, .accounts = &guest_unnamed };
    {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        var s = g;
        s.alloc = arena.allocator();
        const got = try decide(arena.allocator(), "/conversations", false, .GET, s.host());
        try testing.expectEqual(@as(u16, 200), got.respond.status);
        try testing.expectEqualStrings("member;presence;accounts;", s.asked.items);
    }
    try expectAct("/c/1_2/Plans", false, .GET, g, .answered, "member;presence;accounts;fail name 2;");
    // A password whose stat failed: the roster fails with it, the agent's
    // too; the DM it is half of is found and titled all the same.
    const unkind = [_]abi.Account{ steve, .{ .id = "2", .name = .{ .found = "Debbie" }, .kind = .unreadable } };
    const k: Scripted = .{ .alloc = undefined, .accounts = &unkind };
    try expectAct("/conversations", false, .GET, k, .answered, "member;presence;accounts;fail kind 2;");
    try expectAct("/c/1_2/Plans/reactions", false, .GET, k, .{ .respond = .{ .status = 200, .content_type = "application/x-ndjson; charset=utf-8", .body = "" } }, "member;presence;accounts;list 1_2/sessions;read 1_2/sessions/Plans.reactions.jsonl;");
    // **THE ROSTER FAILS ON THE FIRST, IN THE DISK'S ORDER**, as
    // listAuthorized read them: a name before a kind after it; one account
    // with both, its kind (the password is read first).
    const order = [_]abi.Account{ steve, .{ .id = "5", .name = .unreadable, .kind = .agent }, .{ .id = "2", .name = .{ .found = "Debbie" }, .kind = .unreadable } };
    try expectAct("/conversations", false, .GET, .{ .alloc = undefined, .accounts = &order }, .answered, "member;presence;accounts;fail name 5;");
    const both = [_]abi.Account{ steve, .{ .id = "2", .name = .unreadable, .kind = .unreadable } };
    try expectAct("/conversations", false, .GET, .{ .alloc = undefined, .accounts = &both }, .answered, "member;presence;accounts;fail kind 2;");
}

test "the accounts are the Roc's to read: a guest's DM is opened, the roster is members and the agent by numeric id, and a name is cut of its line end" {
    use(testing.allocator);
    defer @import("roc_abi.zig").deinit();
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const huge = "99999999999999999999";
    const all = [_]abi.Account{
        .{ .id = "1", .name = .{ .found = "Steve\r\n" }, .kind = .member },
        .{ .id = "10", .name = .{ .found = "Ten\r\n" }, .kind = .member },
        .{ .id = "9", .name = .{ .found = " Nine  x" }, .kind = .member },
        .{ .id = "4", .name = .{ .found = "Guest" }, .kind = .guest },
        .{ .id = huge, .name = .{ .found = "Big" }, .kind = .member },
        .{ .id = "3", .name = .{ .found = "Claude" }, .kind = .agent },
    };
    var s: Scripted = .{ .alloc = arena.allocator(), .accounts = &all };
    const got = try decide(arena.allocator(), "/conversations", false, .GET, s.host());
    const body = got.respond.body;
    // One too big for an i64 counts as 0, first; then 3, 9, 10 (by bytes 10
    // would come before 9); never the guest, never the member.
    var at: usize = 0;
    for ([_][]const u8{ "{\"id\":\"" ++ huge ++ "\",\"name\":\"Big\"}", "{\"id\":\"3\",\"name\":\"Claude\"}", "{\"id\":\"9\",\"name\":\" Nine  x\"}", "{\"id\":\"10\",\"name\":\"Ten\"}" }) |want| {
        const i = std.mem.indexOfPos(u8, body, at, want) orelse {
            std.debug.print("{s} not after {d} in {s}\n", .{ want, at, body });
            return error.TestUnexpectedResult;
        };
        at = i + want.len;
    }
    try testing.expect(std.mem.indexOf(u8, body, "Guest") == null and std.mem.indexOf(u8, body, "\"id\":\"1\"") == null);
    // A guest is an account: its DM is the member's, titled by its name;
    // the viewer's name cut of its CR LF as it is stored.
    const guest: Scripted = .{ .alloc = undefined, .accounts = &all, .body = "markdown=hi" };
    try expectAct("/c/1_4/Plans/send", false, .POST, guest, .{ .redirect = "/chat/c/1_4/Plans" }, "member;presence;accounts;header x-chat-async;body;hostile hi;read users/1/last-sessions/1_4;write users/1/last-sessions/1_4 Plans\n;read users/1/last-conv;write users/1/last-conv 1_4\n;" ++ comptime sentAll(sent("dm 1_4 /chat/c/1_4 [1,4]", "1_4", "Plans", "Steve", "hi", "")));
    // Not an account: the Zig's to answer.
    try expectAct("/c/1_5/Plans/send", false, .POST, guest, .{ .serve = .{ .route = .{ .family = .dm, .key = "1_5", .sid = "Plans", .part = .topic, .tail = .send }, .presence = false } }, "member;presence;accounts;");
}
