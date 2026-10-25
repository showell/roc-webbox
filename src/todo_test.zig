//! The Roc app through the host's seam (roc_abi.zig), its files in a
//! temporary data root: each request as the site hands it over, and what
//! the list's file holds after.

const std = @import("std");
const testing = std.testing;
const webbox = @import("webbox");
const roc = @import("roc_abi.zig");
const files = @import("roc_files.zig");

/// A data root of its own, for one test.
const Root = struct {
    tmp: testing.TmpDir,
    path: []const u8,

    fn init() !Root {
        var tmp = testing.tmpDir(.{});
        const path = try std.fs.path.join(testing.allocator, &.{ ".zig-cache", "tmp", &tmp.sub_path });
        roc.use(testing.allocator);
        files.use(path);
        return .{ .tmp = tmp, .path = path };
    }

    fn deinit(r: *Root) void {
        roc.deinit();
        testing.allocator.free(r.path);
        r.tmp.cleanup();
    }

    /// The list's file, as the app last wrote it.
    fn file(r: *Root) ![]u8 {
        return r.tmp.dir.readFileAlloc(testing.io, "todos.json", testing.allocator, .limited(1 << 16));
    }
};

/// One request: its status and body, which the test frees.
fn ask(method: []const u8, path: []const u8, body: []const u8) !struct { status: u16, body: []u8 } {
    const r = files.handle(testing.io, method, path, body);
    defer roc.end();
    return .{ .status = r.status, .body = try testing.allocator.dupe(u8, r.body.slice()) };
}

fn expectAnswer(status: u16, body: []const u8, method: []const u8, path: []const u8, sent: []const u8) !void {
    const got = try ask(method, path, sent);
    defer testing.allocator.free(got.body);
    try testing.expectEqualStrings(body, got.body);
    try testing.expectEqual(status, got.status);
}

test "no file yet is an empty list, and nothing is written" {
    var root = try Root.init();
    defer root.deinit();
    try expectAnswer(200, "[]", "GET", "/api/todos", "");
    try testing.expectError(error.FileNotFound, root.file());
}

test "add, toggle and remove, each answered with the list and written" {
    var root = try Root.init();
    defer root.deinit();
    try expectAnswer(200, "[{\"done\":false,\"id\":1,\"text\":\"milk\"}]", "POST", "/api/todos", "  milk \n");
    try expectAnswer(200, "[{\"done\":false,\"id\":1,\"text\":\"milk\"},{\"done\":false,\"id\":2,\"text\":\"a line \\\"quoted\\\" past twenty-three bytes\"}]", "POST", "/api/todos", "a line \"quoted\" past twenty-three bytes");
    try expectAnswer(200, "[{\"done\":true,\"id\":1,\"text\":\"milk\"},{\"done\":false,\"id\":2,\"text\":\"a line \\\"quoted\\\" past twenty-three bytes\"}]", "POST", "/api/todos/1/toggle", "");
    try expectAnswer(200, "[{\"done\":false,\"id\":2,\"text\":\"a line \\\"quoted\\\" past twenty-three bytes\"}]", "DELETE", "/api/todos/1", "");
    // An id is never given twice, even after the last one is removed.
    try expectAnswer(200, "[{\"done\":false,\"id\":2,\"text\":\"a line \\\"quoted\\\" past twenty-three bytes\"},{\"done\":false,\"id\":3,\"text\":\"eggs\"}]", "POST", "/api/todos", "eggs");
    const f = try root.file();
    defer testing.allocator.free(f);
    try testing.expectEqualStrings("{\"items\":[{\"done\":false,\"id\":2,\"text\":\"a line \\\"quoted\\\" past twenty-three bytes\"},{\"done\":false,\"id\":3,\"text\":\"eggs\"}],\"next_id\":4}", f);
}

test "what cannot be done is said, and the file is left alone" {
    var root = try Root.init();
    defer root.deinit();
    try expectAnswer(200, "[{\"done\":false,\"id\":1,\"text\":\"milk\"}]", "POST", "/api/todos", "milk");
    try expectAnswer(400, "an item needs some text", "POST", "/api/todos", " \t");
    try expectAnswer(404, "no item 7", "POST", "/api/todos/7/toggle", "");
    try expectAnswer(404, "no item x", "DELETE", "/api/todos/x", "");
    try expectAnswer(405, "GET or POST", "PUT", "/api/todos", "");
    try expectAnswer(404, "no such route: GET /api/other", "GET", "/api/other", "");
    const f = try root.file();
    defer testing.allocator.free(f);
    try testing.expectEqualStrings("{\"items\":[{\"done\":false,\"id\":1,\"text\":\"milk\"}],\"next_id\":2}", f);
}

test "a file that is not a list is an error, never an empty list written over it" {
    var root = try Root.init();
    defer root.deinit();
    try root.tmp.dir.writeFile(testing.io, .{ .sub_path = "todos.json", .data = "garbage" });
    try expectAnswer(500, "todos.json is not a list of todos", "GET", "/api/todos", "");
    try expectAnswer(500, "todos.json is not a list of todos", "POST", "/api/todos", "milk");
    const f = try root.file();
    defer testing.allocator.free(f);
    try testing.expectEqualStrings("garbage", f);
}

test "a file that cannot be read is an error, not an absent file" {
    var root = try Root.init();
    defer root.deinit();
    // A folder where the file should be: a read that fails, not one that
    // finds nothing.
    try root.tmp.dir.createDirPath(testing.io, "todos.json");
    const got = try ask("POST", "/api/todos", "milk");
    defer testing.allocator.free(got.body);
    try testing.expectEqual(500, got.status);
    try testing.expect(std.mem.startsWith(u8, got.body, "todos.json: "));
}

test {
    _ = webbox;
    _ = files;
}
