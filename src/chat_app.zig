//! **THE ROC CHAT AS A WEBBOX SITE, ITS FIRST ROUTE** (docs/ROC-CHAT.md,
//! T1): every request handed to the Roc app (chat/main.roc), which answers
//! `GET /ping` and nothing else yet. The point is a Roc archive linked into
//! angry-gopher and gopher.elf, booted, answering. No cookie, no body, no
//! file read; the platform's file effects are linked (roc_files.zig) only
//! because the platform declares them.
//! Portable: no host call reaches it, so webbox's Linux host serves it and
//! its bare-metal host can.

const std = @import("std");
const webbox = @import("webbox");
const http = webbox.http;
const Io = @import("host_io").Io;
const roc = @import("roc_abi.zig");
const files = @import("roc_files.zig");

pub const StartReport = struct {
    data_dir: []const u8,
};

pub fn setup(io: Io, base: std.mem.Allocator, roots: ?webbox.site.Roots) !StartReport {
    _ = io;
    const root = if (roots) |r| r.data_dir else "data";
    roc.use(base);
    files.use(root);
    return .{ .data_dir = root };
}

/// No route reads a body.
pub fn bodyLimit(path: []const u8) u64 {
    _ = path;
    return 0;
}

pub fn routes(req: *std.http.Server.Request, io: Io, alloc: std.mem.Allocator, bus: *webbox.bus.Bus) !void {
    _ = bus;
    const path = http.pathOf(try http.target(req, alloc));
    const r = files.handle(io, @tagName(req.head.method), path, "", "");
    defer roc.end();
    const status: std.http.Status = @fromBackingInt(@intCast(r.status));
    return req.respond(r.body.slice(), .{ .status = status, .extra_headers = &.{.{ .name = "content-type", .value = r.content_type.slice() }} });
}
