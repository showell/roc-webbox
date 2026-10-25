//! **THE TODO LIST AS A WEBBOX SITE**: the page at `/` (web/index.html,
//! compiled in), and every request under `/api/` handed to the Roc app
//! (app/todo.roc), which answers it, reading and writing its files as it
//! runs (roc_abi.zig). Portable: no host call reaches it, so webbox's Linux
//! host serves it (main.zig) and its bare-metal host can.

const std = @import("std");
const webbox = @import("webbox");
const http = webbox.http;
const Io = std.Io;
const roc = @import("roc_abi.zig");

/// The data root when the host names none: data/ where the server runs.
pub var data_dir: []const u8 = "data";

pub const StartReport = struct { data_dir: []const u8 };

pub fn setup(_: Io, base: std.mem.Allocator, roots: ?webbox.site.Roots) !StartReport {
    const root = if (roots) |r| r.data_dir else data_dir;
    roc.use(base, root);
    return .{ .data_dir = root };
}

/// An item's text is the only body any route reads.
pub fn bodyLimit(path: []const u8) u64 {
    _ = path;
    return 16 * 1024;
}

pub fn routes(req: *std.http.Server.Request, io: Io, alloc: std.mem.Allocator, bus: *webbox.bus.Bus) !void {
    _ = bus;
    const whole = try http.target(req, alloc);
    const path = http.pathOf(whole);
    if (std.mem.eql(u8, path, "/") or std.mem.eql(u8, path, "/index.html")) {
        if (req.head.method != .GET) return http.methodNotAllowed(req, .GET);
        return req.respond(@embedFile("todo_page"), .{ .extra_headers = &.{http.html_ct} });
    }
    if (!std.mem.startsWith(u8, path, "/api/")) return http.notFound(req);
    const body = (try http.readLimitedBody(req, alloc, bodyLimit(path))) orelse "";
    const r = roc.handle(io, @tagName(req.head.method), path, body);
    defer roc.end();
    const status: std.http.Status = @fromBackingInt(@intCast(r.status));
    return req.respond(r.body.slice(), .{ .status = status, .extra_headers = &.{.{ .name = "content-type", .value = r.content_type.slice() }} });
}
