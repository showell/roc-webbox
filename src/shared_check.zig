//! **THE LIST WITH roc_hooks IN THE ROOT**, as a binary holding two Roc apps
//! has it (src/roc_hooks.zig): a program, since a test's root is the test
//! runner's. That it links at all says roc_abi.zig exported none of the four
//! (they would clash with roc_hooks'); that the list answers says each of
//! Roc's runtime calls reached the list's runtime through `enter` (a call
//! from outside one panics).

const std = @import("std");
const roc = @import("roc_abi.zig");
const files = @import("roc_files.zig");

pub const roc_hooks = @import("roc_hooks.zig");

pub fn main(init: std.process.Init) !void {
    const dir = ".zig-cache/tmp/shared-check";
    std.Io.Dir.cwd().deleteTree(init.io, dir) catch {};
    roc.use(init.gpa);
    defer roc.deinit();
    files.use(dir);
    for ([_][3][]const u8{
        .{ "POST", "/api/todos", "a line past twenty-three bytes, so Roc allocates" },
        .{ "POST", "/api/todos/1/toggle", "" },
        .{ "GET", "/api/todos", "" },
    }) |r| {
        const got = files.handle(init.io, r[0], r[1], r[2]);
        defer roc.end();
        if (got.status != 200) return fail(r[1], got.body.slice());
        if (std.mem.eql(u8, r[0], "GET") and !std.mem.eql(u8, got.body.slice(), "[{\"done\":true,\"id\":1,\"text\":\"a line past twenty-three bytes, so Roc allocates\"}]")) return fail(r[1], got.body.slice());
    }
    std.debug.print("shared check: the list answered through roc_hooks\n", .{});
}

fn fail(path: []const u8, body: []const u8) error{SharedCheckFailed} {
    std.debug.print("shared check: {s} answered {s}\n", .{ path, body });
    return error.SharedCheckFailed;
}
