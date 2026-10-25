//! **THE TODO LIST AS A WEBBOX SITE**: the page at `/` (web/index.html,
//! compiled in), and every request under `/api/` handed to the Roc app
//! (app/todo.roc), which answers it, reading and writing its files as it
//! runs (roc_files.zig). Each visitor has their own list: who is asking is
//! a signed cookie (webbox's `signed_cookie.visitor`), handed to Roc as
//! `Request.user`; no names, no passwords. Portable: no host call reaches it, so webbox's Linux
//! host serves it (main.zig) and its bare-metal host can.

const std = @import("std");
const webbox = @import("webbox");
const http = webbox.http;
const Io = @import("host_io").Io;
const roc = @import("roc_abi.zig");
const files = @import("roc_files.zig");

/// The data root when the host names none: data/ where the server runs.
pub var data_dir: []const u8 = "data";
/// The secrets' folder when the host names none: auth/ where it runs.
pub var auth_dir: []const u8 = "auth";
/// How the visitor's cookie travels: Secure behind HTTPS, unless a Linux
/// main says plain http (TODO_INSECURE_COOKIE=yes, development only).
pub var transport: signed_cookie.Transport = .https;

const signed_cookie = webbox.signed_cookie;
const site_secret = webbox.site_secret;
var secret_dir: []const u8 = "";

pub const StartReport = struct {
    data_dir: []const u8,
    secret: enum { found, made },
    transport: signed_cookie.Transport,
};

pub fn setup(io: Io, base: std.mem.Allocator, roots: ?webbox.site.Roots) !StartReport {
    const root = if (roots) |r| r.data_dir else data_dir;
    secret_dir = if (roots) |r| r.auth_dir else auth_dir;
    roc.use(base);
    files.use(root);
    const made = if (try site_secret.load(io, base, secret_dir) != null) false else blk: {
        site_secret.create(io, base, secret_dir) catch |e| if (e != error.SecretExists) return e;
        break :blk true;
    };
    return .{ .data_dir = root, .secret = if (made) .made else .found, .transport = transport };
}

/// The visitor's cookie: `__Host-roc-todo` behind HTTPS, a year long,
/// renewed when used past half of it.
fn visitorCookie() signed_cookie.Cookie {
    return .{
        .name = signed_cookie.named("roc-todo", transport),
        .transport = transport,
        .kind = .{ .label = "roc-todo visitor\n", .lifetime_secs = 365 * 24 * 60 * 60, .skew_secs = 300, .validId = signed_cookie.isVisitorId },
    };
}

fn nowUnix(io: Io) i64 {
    return @intCast(@divFloor(Io.Clock.now(.real, io).nanoseconds, std.time.ns_per_s));
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
    // Who is asking, from the head, before a body read invalidates it.
    const method = @tagName(req.head.method);
    const who = try signed_cookie.visitor(visitorCookie(), io, alloc, req, secret_dir, nowUnix(io));
    const body = (try http.readLimitedBody(req, alloc, bodyLimit(path))) orelse "";
    const r = files.handle(io, method, path, body, who.id);
    defer roc.end();
    const status: std.http.Status = @fromBackingInt(@intCast(r.status));
    const content_type: std.http.Header = .{ .name = "content-type", .value = r.content_type.slice() };
    return req.respond(r.body.slice(), .{ .status = status, .extra_headers = if (who.set_cookie) |set| &.{ content_type, .{ .name = "set-cookie", .value = set } } else &.{content_type} });
}
