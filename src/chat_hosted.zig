//! **THE ROC CHAT'S ROUTER, AS ANGRY-GOPHER TAKES IT** (docs/ROC-CHAT.md
//! §3, milestone 1): `decide`, the Roc router's decision for a /chat or
//! /channel path (chat/main.roc, chat/Route.roc), and the route it is read
//! into (chat_route.zig). angry-gopher serves the decision with its own Zig;
//! nothing else here touches a request.

const std = @import("std");
const abi = @import("chat_abi.zig");
const route = @import("chat_route.zig");

pub const decide = abi.decide;
pub const Member = abi.Member;
pub const Decision = route.Decision;
pub const Route = route.Route;
pub const Family = route.Family;
pub const Part = route.Part;
pub const Tail = route.Tail;

/// roc_abi.zig's arena, from `base`, once, as the host starts.
pub fn use(base: std.mem.Allocator) void {
    @import("roc_abi.zig").use(base);
}

// ── tests: a few decisions through the Roc (angry-gopher's tests hold the
// router to Zig's own parse over a corpus) ────────────────────────────────

const testing = std.testing;

fn answer(member: bool) Member {
    const S = struct {
        fn yes(_: *anyopaque) bool {
            return true;
        }
        fn no(_: *anyopaque) bool {
            return false;
        }
        var dummy: u8 = 0;
    };
    return .{ .ctx = &S.dummy, .ask = if (member) S.yes else S.no };
}

fn expectRoute(sub: []const u8, channel: bool, want: Route, presence: bool) !void {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const got = try decide(arena.allocator(), sub, channel, answer(true));
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
    try expectRoute("/msg/\xff\xfe", false, .{ .family = .msg, .rest = "\xff\xfe" }, true);

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const away = try decide(arena.allocator(), "/c/1_2/general", false, answer(false));
    try testing.expectEqualStrings("/login/full?next=/chat/c/1_2/general", away.redirect);
    const asset = try decide(arena.allocator(), "/chat.js", false, answer(false));
    try testing.expectEqual(Family.asset, asset.serve.route.family);
}
