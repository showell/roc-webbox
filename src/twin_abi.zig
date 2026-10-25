//! **THE PURE MODULES' TEST-ONLY SEAM** (docs/ROC-CHAT.md C1): `call` runs
//! the Roc function `which` names (chat/twin.roc) on `args` and answers its
//! results, copied out, the call ended. angry-gopher's chat_twin_test.zig
//! calls it beside the Zig each Roc function replaces. Never in a server:
//! only a test binary links the twin archive.

const std = @import("std");
const roc = @import("roc_abi.zig");

const Request = extern struct { args: roc.RocBytesList, which: u8 };

comptime {
    std.debug.assert(@sizeOf(Request) == 4 * @sizeOf(usize));
}

extern fn roc_twin_call(req: Request) callconv(.c) roc.RocBytesList;

/// roc_abi.zig's arena, from `base` (a test's allocator).
pub fn use(base: std.mem.Allocator) void {
    roc.use(base);
}

pub fn deinit() void {
    roc.deinit();
}

/// Roc's results for function `which` on `args`, each copied into `alloc`.
pub fn call(alloc: std.mem.Allocator, which: u8, args: []const []const u8) ![][]u8 {
    try roc.enter();
    defer roc.leave();
    defer roc.end();
    const got = roc_twin_call(.{ .args = .from(args), .which = which });
    const items = got.slice();
    const out = try alloc.alloc([]u8, items.len);
    for (items, 0..) |*it, k| out[k] = try alloc.dupe(u8, it.slice());
    return out;
}

test "the seam: a list of byte lists there and back" {
    use(std.testing.allocator);
    defer deinit();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const got = try call(arena.allocator(), 1, &.{"1761400000"});
    try std.testing.expectEqual(@as(usize, 1), got.len);
    try std.testing.expectEqualStrings("2025-10-25T13:46:40Z", got[0]);
}
