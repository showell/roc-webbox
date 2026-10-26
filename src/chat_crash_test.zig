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
/// read, `users/1/broken`; whose folders are `channels` (three entries, one
/// of each kind) and `empty`, and one that will not list, `1_2/sessions`;
/// it records what it was asked and how it failed.
const Files = struct {
    asked: std.ArrayList(u8) = .empty,
    failed: ?anyerror = null,

    fn host(f: *Files) abi.Host {
        var h = abi.askingOnly(f, yes);
        h.read = read;
        h.write = write;
        h.remove = remove;
        h.list = list;
        h.fail = fail;
        h.fail_account = failAccount;
        h.malformed_channel = malformed;
        return h;
    }
    /// An account's kind kept as error.SymLinkLoop, its name as
    /// error.IsDir: which one the request fails with shows which read the
    /// seam asked for.
    fn failAccount(ctx: *anyopaque, which: abi.AccountRead, id: []const u8) void {
        of(ctx).asked.print(testing.allocator, "fail_account {t} {s};", .{ which, id }) catch @panic("oom");
        fail(ctx, switch (which) {
            .kind => error.SymLinkLoop,
            .name => error.IsDir,
        });
    }
    fn list(ctx: *anyopaque, path: []const u8) abi.Listing {
        say(ctx, "list", path);
        if (std.mem.eql(u8, path, "channels")) return .{ .found = &.{ .{ .name = "ops.channel", .kind = .file }, .{ .name = "x.md", .kind = .dir }, .{ .name = "\xffl", .kind = .other } } };
        if (std.mem.eql(u8, path, "empty")) return .{ .found = &.{} };
        if (std.mem.eql(u8, path, "1_2/sessions")) {
            fail(ctx, error.NotDir);
            return .failed;
        }
        return .missing;
    }
    fn malformed(ctx: *anyopaque, name: []const u8) void {
        say(ctx, "malformed", name);
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

test "a folder's listing: a path that would leave the root fails the request at the seam; under it, its entries and their kinds, nothing there, and a listing that failed are three answers" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    roc.use(arena.allocator());
    defer roc.deinit();
    for ([_][]const u8{ "/list/../x", "/list//etc", "/list/", "/list/channels/../../x", "/list/.." }) |sub|
        try probe(sub, "failed", "", error.PathOutsideChatRoot);
    try probe("/list/channels", "found f:ops.channel d:x.md o:\xffl", "list channels;", null);
    try probe("/list/empty", "found", "list empty;", null);
    try probe("/list/gone", "missing", "list gone;", null);
    try probe("/list/1_2/sessions", "failed", "list 1_2/sessions;", error.NotDir);
}

test "the Roc fails a request by a reason, each reason its own byte across: a malformed channel as error.MalformedChannel, an account's kind or name as the error the host kept for that read of that account; and a malformed channel is counted by the host" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    roc.use(arena.allocator());
    defer roc.deinit();
    try probe("/fail/malformed/Abad", "failed", "", error.MalformedChannel);
    try probe("/fail/kind/7", "failed", "fail_account kind 7;", error.SymLinkLoop);
    try probe("/fail/name/12", "failed", "fail_account name 12;", error.IsDir);
    try probe("/malformed/Abad", "counted", "malformed Abad;", null);
}

test "every account crosses with its id, kind and name, in the host's order, one that will not read as unreadable (its kind, its name, or both); a listing that failed is `failed`, never no accounts" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    roc.use(arena.allocator());
    defer roc.deinit();
    const S = struct {
        var fails: bool = false;
        fn accounts(ctx: *anyopaque) abi.Accounts {
            Files.say(ctx, "accounts", "");
            if (fails) {
                Files.fail(ctx, error.IsDir);
                return .failed;
            }
            return .{ .found = &.{
                .{ .id = "10", .name = .{ .found = "Ten\r\n" }, .kind = .member },
                .{ .id = "3", .name = .{ .found = "Claude" }, .kind = .agent },
                .{ .id = "9", .name = .{ .found = "" }, .kind = .guest },
                .{ .id = "7", .name = .{ .found = "Sev" }, .kind = .unreadable },
                .{ .id = "12", .name = .unreadable, .kind = .member },
                .{ .id = "13", .name = .unreadable, .kind = .unreadable },
            } };
        }
    };
    for ([_]bool{ false, true }) |fails| {
        S.fails = fails;
        var f: Files = .{};
        defer f.asked.deinit(testing.allocator);
        var h = f.host();
        h.accounts = S.accounts;
        const got = try abi.decide(arena.allocator(), "/accounts", false, .GET, h);
        try testing.expectEqualStrings(if (fails) "failed" else "found m:10=Ten\r\n a:3=Claude g:9= u:7=Sev m:12=? u:13=?", got.respond.body);
        try testing.expectEqualStrings("accounts ;", f.asked.items);
        try testing.expectEqual(if (fails) @as(?anyerror, error.IsDir) else null, f.failed);
    }
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
