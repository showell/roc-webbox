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
/// whether the request counts as presence (it is not a stream).
pub const Decision = union(enum) {
    redirect: []const u8,
    serve: struct { route: Route, presence: bool },

    pub fn eql(a: Decision, b: Decision) bool {
        return switch (a) {
            .redirect => |l| b == .redirect and std.mem.eql(u8, l, b.redirect),
            .serve => |s| b == .serve and s.presence == b.serve.presence and s.route.eql(b.serve.route),
        };
    }

    pub fn format(d: Decision, w: *std.Io.Writer) std.Io.Writer.Error!void {
        switch (d) {
            .redirect => |l| try w.print("303 {s}", .{l}),
            .serve => |s| try w.print("{f}{s}", .{ s.route, if (s.presence) " +presence" else "" }),
        }
    }
};
