//! **WHERE A CHAT REQUEST GOES** (docs/ROC-CHAT.md §5.2's `ZigRoute`): the
//! route the Roc router (chat/Route.roc) parses a /chat or /channel path
//! into, as angry-gopher's Zig serves it. Plain data, the same type the Roc
//! decision is read into (chat_abi.zig) and angry-gopher's own Zig parse,
//! the router's twin, answers (A3), so the two compare with `eql`.
//!
//! The numbers are chat/platform/Chat.roc's, and only these two files say
//! them.

const std = @import("std");

pub const Family = enum(u8) {
    not_found = 0,
    /// A static script, `rest` its name; served before the gate.
    asset = 1,
    /// `/chat`, `/chat/`, `/chat/default`: the last conversation resumed.
    default = 2,
    /// `rest` the path under `/docs` (and the four below likewise).
    docs = 3,
    recent = 4,
    images = 5,
    code = 6,
    links = 7,
    /// `rest` the path after `/search`, with no boundary (`/searchX` is "X").
    search = 8,
    conversations = 9,
    /// `rest` the message id after `/msg/`.
    msg = 10,
    /// A DM, `key` its pair as written (Zig checks the viewer is in it).
    dm = 11,
    /// A channel, `key` its name (already a valid one).
    channel = 12,
    notifications = 13,
    sidebar_stream = 14,
};

/// Which part of a conversation.
pub const Part = enum(u8) {
    /// No topic named: its first topic, or the page offering one.
    landing = 0,
    /// `.../new`: a topic made.
    new = 1,
    /// A topic id that is not one: refused after the conversation's own
    /// checks, as Zig always refused it.
    invalid = 2,
    /// `sid` a valid topic id, `tail` what of it.
    topic = 3,
};

pub const Tail = enum(u8) {
    page = 0,
    /// `rest` the file.
    uploads = 1,
    stream = 2,
    send = 3,
    upload = 4,
    pin = 5,
    unpin = 6,
    raw = 7,
    download = 8,
    saved = 9,
    reactions = 10,
    react = 11,
    /// No tail Zig serves: refused once the topic is known to exist.
    invalid = 12,
    /// The same, but under `send`, which skips that check (a send makes
    /// its topic).
    invalid_send = 13,
};

pub const Route = struct {
    family: Family,
    key: []const u8 = "",
    rest: []const u8 = "",
    sid: []const u8 = "",
    part: Part = .landing,
    tail: Tail = .page,

    pub fn eql(a: Route, b: Route) bool {
        return a.family == b.family and a.part == b.part and a.tail == b.tail and
            std.mem.eql(u8, a.key, b.key) and std.mem.eql(u8, a.rest, b.rest) and std.mem.eql(u8, a.sid, b.sid);
    }

    pub fn format(r: Route, w: *std.Io.Writer) std.Io.Writer.Error!void {
        try w.print("{t} key=\"{s}\" rest=\"{s}\" sid=\"{s}\" {t} {t}", .{ r.family, r.key, r.rest, r.sid, r.part, r.tail });
    }
};

/// What the router decided: a 303 (the gate's), or a route for Zig, with
/// whether the request counts as presence (it is not a stream); or, for a
/// route the Roc served itself, what to send.
pub const Decision = union(enum) {
    redirect: []const u8,
    serve: struct { route: Route, presence: bool },
    /// A status and its body, typed `content_type` when it is not empty.
    respond: struct { status: u16, content_type: []const u8 = "", body: []const u8 = "", nosniff: bool = false },
    /// A 405 naming the one method the route takes.
    not_allowed: std.http.Method,
    /// Answered already by the host, inside the call (a body too big), or
    /// failed there: the host has its error.
    answered,
    /// A malformed form: the site's 400, as every form's.
    malformed_form,
    /// webbox's plain 404.
    not_found,
    /// A 302 to the location (a lookup, then go).
    found: []const u8,
    /// As `respond`, its body `before`, the bytes the host holds (read or
    /// rendered by a hosted function: a transcript, a links page), `after`.
    held: struct { status: u16, content_type: []const u8 = "", nosniff: bool = false, before: []const u8 = "", after: []const u8 = "" },

    pub fn eql(a: Decision, b: Decision) bool {
        if (std.meta.activeTag(a) != std.meta.activeTag(b)) return false;
        return switch (a) {
            .redirect => |l| std.mem.eql(u8, l, b.redirect),
            .serve => |s| s.presence == b.serve.presence and s.route.eql(b.serve.route),
            .respond => |r| r.status == b.respond.status and r.nosniff == b.respond.nosniff and std.mem.eql(u8, r.content_type, b.respond.content_type) and std.mem.eql(u8, r.body, b.respond.body),
            .not_allowed => |m| m == b.not_allowed,
            .answered, .malformed_form, .not_found => true,
            .found => |l| std.mem.eql(u8, l, b.found),
            .held => |h| h.status == b.held.status and h.nosniff == b.held.nosniff and std.mem.eql(u8, h.content_type, b.held.content_type) and std.mem.eql(u8, h.before, b.held.before) and std.mem.eql(u8, h.after, b.held.after),
        };
    }

    pub fn format(d: Decision, w: *std.Io.Writer) std.Io.Writer.Error!void {
        switch (d) {
            .redirect => |l| try w.print("303 {s}", .{l}),
            .serve => |s| try w.print("{f}{s}", .{ s.route, if (s.presence) " +presence" else "" }),
            .respond => |r| try w.print("{d} \"{s}\"{s} {d} bytes", .{ r.status, r.content_type, if (r.nosniff) " nosniff" else "", r.body.len }),
            .not_allowed => |m| try w.print("405 allow {t}", .{m}),
            .answered => try w.writeAll("answered by the host"),
            .malformed_form => try w.writeAll("malformed form"),
            .not_found => try w.writeAll("404"),
            .found => |l| try w.print("302 {s}", .{l}),
            .held => |h| try w.print("{d} \"{s}\"{s} {d} bytes, the host's, {d} bytes", .{ h.status, h.content_type, if (h.nosniff) " nosniff" else "", h.before.len, h.after.len }),
        }
    }
};
