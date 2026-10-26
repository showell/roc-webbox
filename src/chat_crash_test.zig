//! **A ROC CRASH IS A 500, AND THE NEXT REQUEST IS SERVED** (docs/ROC-CHAT.md
//! R3, P9), and **ONE ROC CALL AT A TIME** (R1, P7): chat_abi.zig's `decide`
//! over the planted crash (chat/test/crash.roc, linked here in place of the
//! router; never into a server).

const std = @import("std");
const testing = std.testing;
const abi = @import("chat_abi.zig");
const roc = @import("roc_abi.zig");

const Asker = struct {
    member: bool = true,
    /// When set, the asker starts a Roc call of its own, inside this one.
    nest: bool = false,
    nested: ?anyerror = null,

    fn ask(ctx: *anyopaque) bool {
        const self: *Asker = @ptrCast(@alignCast(ctx));
        if (self.nest) {
            var inner: Asker = .{};
            if (abi.decide(testing.allocator, "/ok", false, .GET, inner.member_())) |_| {} else |e| self.nested = e;
        }
        return self.member;
    }

    fn member_(self: *Asker) abi.Host {
        return abi.askingOnly(self, ask);
    }
};

/// A host whose files are one, `users/1/ok` ("hi"), and one that will not
/// read, `users/1/broken`; it records what it was asked and how it failed.
const Files = struct {
    asked: std.ArrayList(u8) = .empty,
    failed: ?anyerror = null,

    fn host(f: *Files) abi.Host {
        var h = abi.askingOnly(f, yes);
        h.read = read;
        h.write = write;
        h.remove = remove;
        h.fail = fail;
        return h;
    }
    fn of(ctx: *anyopaque) *Files {
        return @ptrCast(@alignCast(ctx));
    }
    fn yes(_: *anyopaque) bool {
        return true;
    }
    fn say(ctx: *anyopaque, what: []const u8, path: []const u8) void {
        of(ctx).asked.print(testing.allocator, "{s} {s};", .{ what, path }) catch @panic("oom");
    }
    fn read(ctx: *anyopaque, path: []const u8) abi.Read {
        say(ctx, "read", path);
        if (std.mem.eql(u8, path, "users/1/ok")) return .{ .found = "hi" };
        if (std.mem.eql(u8, path, "users/1/broken")) {
            fail(ctx, error.IsDir);
            return .failed;
        }
        return .missing;
    }
    fn write(ctx: *anyopaque, path: []const u8, _: []const u8) bool {
        say(ctx, "write", path);
        return true;
    }
    fn remove(ctx: *anyopaque, path: []const u8) bool {
        say(ctx, "remove", path);
        return true;
    }
    fn fail(ctx: *anyopaque, e: anyerror) void {
        if (of(ctx).failed == null) of(ctx).failed = e;
    }
};

/// What `sub` answered, what the host was asked, and how it failed.
fn probe(sub: []const u8, want_body: []const u8, want_asked: []const u8, want_failed: ?anyerror) !void {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var f: Files = .{};
    defer f.asked.deinit(testing.allocator);
    const got = try abi.decide(arena.allocator(), sub, false, .GET, f.host());
    if (!std.mem.eql(u8, got.respond.body, want_body) or !std.mem.eql(u8, f.asked.items, want_asked) or !std.meta.eql(f.failed, want_failed)) {
        std.debug.print("{s}: answered \"{s}\" asking \"{s}\" failing {any}, want \"{s}\" asking \"{s}\" failing {any}\n", .{ sub, got.respond.body, f.asked.items, f.failed, want_body, want_asked, want_failed });
        return error.TestUnexpectedResult;
    }
}

test "a path that would leave the chat root fails the request at the seam, the host never asked; a path under it is the host's, and missing and failed are two answers" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    roc.use(arena.allocator());
    defer roc.deinit();
    // Outside the root, by every way out: the request fails, nothing asked.
    for ([_][]const u8{ "/read/../x", "/read//etc/passwd", "/read/", "/read/users/../../x", "/write/../x", "/write//etc/passwd", "/write/", "/remove/users/../../x", "/remove/" }) |sub|
        try probe(sub, "failed", "", error.PathOutsideChatRoot);
    // Under it: the host's, each answer as it gave it.
    try probe("/read/users/1/ok", "found hi", "read users/1/ok;", null);
    try probe("/read/users/1/gone", "missing", "read users/1/gone;", null);
    try probe("/read/users/1/broken", "failed", "read users/1/broken;", error.IsDir);
    try probe("/write/users/1/pinned-sessions/1_2", "done", "write users/1/pinned-sessions/1_2;", null);
    try probe("/remove/users/1/last-conv", "done", "remove users/1/last-conv;", null);
}

test "a Roc crash is error.RocCrashed, its message kept, and the next call is served; a crash after a hosted call too" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    roc.use(arena.allocator());
    var asker: Asker = .{};

    try testing.expectError(error.RocCrashed, abi.decide(arena.allocator(), "/crash", false, .GET, asker.member_()));
    try testing.expectEqualStrings("a planted crash", abi.last_crash[0..abi.last_crash_len]);
    try testing.expect(!roc.inCall());

    const ok = try abi.decide(arena.allocator(), "/ok", false, .GET, asker.member_());
    try testing.expectEqual(abi.Route.eql(ok.serve.route, .{ .family = .default }), true);

    try testing.expectError(error.RocCrashed, abi.decide(arena.allocator(), "/crash-after-asking", false, .GET, asker.member_()));
    try testing.expectEqualStrings("a planted crash, after asking", abi.last_crash[0..abi.last_crash_len]);
    _ = try abi.decide(arena.allocator(), "/ok", false, .GET, asker.member_());
}

test "a Roc call inside another is refused, error.RocReentered, and the outer call goes on" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    roc.use(arena.allocator());
    // The planted app asks who it is on `/crash-after-asking`; this asker
    // tries a Roc call of its own while asked, inside the outer one.
    var asking: Asker = .{ .nest = true };
    try testing.expectError(error.RocCrashed, abi.decide(arena.allocator(), "/crash-after-asking", false, .GET, asking.member_()));
    try testing.expectEqual(@as(?anyerror, error.RocReentered), asking.nested);
    try testing.expect(!roc.inCall());
}

test "memory that runs out inside a Roc call is error.RocCrashed for that request, at every allocation it could fail on, and the next call is served (metal-vmm FEEDBACK 2026-10-26: it panicked the machine)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    defer roc.deinit();
    var asker: Asker = .{};
    var failed: usize = 0;
    var k: usize = 0;
    while (k < 64) : (k += 1) {
        // The request's own allocator (useRequest, as angry-gopher's router
        // hands it), failing at its k-th allocation.
        var failing = std.testing.FailingAllocator.init(arena.allocator(), .{ .fail_index = k });
        roc.useRequest(failing.allocator());
        if (abi.decide(arena.allocator(), "/crash-after-asking-big", false, .GET, asker.member_())) |_| {
            unreachable;
        } else |e| {
            try testing.expectEqual(error.RocCrashed, e);
            if (std.mem.eql(u8, abi.last_crash[0..abi.last_crash_len], "roc_alloc: out of memory")) {
                failed += 1;
            } else {
                // Past every allocation the call makes: its own planted crash.
                try testing.expectEqualStrings("a planted crash, after a big list", abi.last_crash[0..abi.last_crash_len]);
                break;
            }
        }
        try testing.expect(!roc.inCall());
        roc.useRequest(arena.allocator());
        _ = try abi.decide(arena.allocator(), "/ok", false, .GET, asker.member_());
    }
    try testing.expect(failed >= 2 and k < 64);
}
