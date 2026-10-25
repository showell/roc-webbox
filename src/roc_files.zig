//! **THE FILE EFFECTS, ON WEBBOX** (platform/File.roc's hosted functions):
//! each runs when the app calls it, during the request, over webbox.store
//! and the `Io` the host hands that request, under the site's data root.
//! Nothing here calls the operating system, so the same file serves on
//! webbox's Linux host and its bare-metal one.

const std = @import("std");
const webbox = @import("webbox");
const Io = @import("host_io").Io;
const store = webbox.store;
const roc = @import("roc_abi.zig");
const RocStr = roc.RocStr;

/// The request's `Io`, while the app answers it (one handler at a time).
var call_io: ?Io = null;
var data_root: []const u8 = "data";

/// Where the app's files go, once, as the site starts.
pub fn use(root: []const u8) void {
    data_root = root;
}

/// The app's answer to one request, its effects done by `io`. Good until
/// `roc.end`.
pub fn handle(io: Io, method: []const u8, path: []const u8, body: []const u8) roc.Response {
    call_io = io;
    defer call_io = null;
    return roc.call(method, path, body);
}

/// The most of a file `File.read!` answers.
pub const read_most = 1 << 20;

/// `path` under the data root, or null when it would leave it.
fn under(path: []const u8) ?[]const u8 {
    if (!roc.inRoot(path)) return null;
    return std.fs.path.join(roc.alloc(), &.{ data_root, path }) catch null;
}

const outside = "a path outside the data root";

export fn roc_file_read(path: RocStr) callconv(.c) roc.Read {
    const p = under(path.slice()) orelse return .{ .text = .from(outside), .status = roc.read_failed };
    const got = store.readOrNull(call_io.?, roc.alloc(), p, .limited(read_most)) catch |e| return .{ .text = .from(@errorName(e)), .status = roc.read_failed };
    const text = got orelse return .{ .text = .from(""), .status = roc.read_absent };
    return .{ .text = .from(text), .status = roc.read_found };
}

export fn roc_file_write(path: RocStr, text: RocStr) callconv(.c) RocStr {
    const p = under(path.slice()) orelse return .from(outside);
    store.replace(call_io.?, roc.alloc(), p, text.slice(), .{}) catch |e| return .from(@errorName(e));
    return .from("");
}

export fn roc_file_delete(path: RocStr) callconv(.c) RocStr {
    const p = under(path.slice()) orelse return .from(outside);
    store.remove(call_io.?, roc.alloc(), p) catch |e| return .from(@errorName(e));
    return .from("");
}

test "a path under the data root" {
    roc.use(std.testing.allocator);
    defer roc.deinit();
    use("data");
    try std.testing.expectEqualStrings("data/todos.json", under("todos.json").?);
    try std.testing.expect(under("../x") == null);
}
