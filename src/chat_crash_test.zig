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
            if (abi.decide(testing.allocator, "/ok", false, inner.member_())) |_| {} else |e| self.nested = e;
        }
        return self.member;
    }

    fn member_(self: *Asker) abi.Member {
        return .{ .ctx = self, .ask = ask };
    }
};

test "a Roc crash is error.RocCrashed, its message kept, and the next call is served; a crash after a hosted call too" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    roc.use(arena.allocator());
    var asker: Asker = .{};

    try testing.expectError(error.RocCrashed, abi.decide(arena.allocator(), "/crash", false, asker.member_()));
    try testing.expectEqualStrings("a planted crash", abi.last_crash[0..abi.last_crash_len]);
    try testing.expect(!roc.inCall());

    const ok = try abi.decide(arena.allocator(), "/ok", false, asker.member_());
    try testing.expectEqual(abi.Route.eql(ok.serve.route, .{ .family = .default }), true);

    try testing.expectError(error.RocCrashed, abi.decide(arena.allocator(), "/crash-after-asking", false, asker.member_()));
    try testing.expectEqualStrings("a planted crash, after asking", abi.last_crash[0..abi.last_crash_len]);
    _ = try abi.decide(arena.allocator(), "/ok", false, asker.member_());
}

test "a Roc call inside another is refused, error.RocReentered, and the outer call goes on" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    roc.use(arena.allocator());
    // The planted app asks who it is on `/crash-after-asking`; this asker
    // tries a Roc call of its own while asked, inside the outer one.
    var asking: Asker = .{ .nest = true };
    try testing.expectError(error.RocCrashed, abi.decide(arena.allocator(), "/crash-after-asking", false, asking.member_()));
    try testing.expectEqual(@as(?anyerror, error.RocReentered), asking.nested);
    try testing.expect(!roc.inCall());
}
