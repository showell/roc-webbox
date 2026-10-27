//! **WHERE A CHAT REQUEST GOES** (docs/ROC-CHAT.md §5.2's `ZigRoute`): the
//! route the Roc router (chat/Route.roc) parses a /chat or /channel path
//! into, as angry-gopher's Zig serves it. Plain data, the same type the Roc
//! decision is read into (chat_abi.zig) and angry-gopher's own Zig parse,
//! the router's twin, answers (A3), so the two compare with `eql`.
//!
//! **EVERY ENUM HERE IS A ROC TAG UNION, IN ROC'S ORDER.** A tag union
//! whose tags carry nothing crosses the seam as one byte, its tags numbered
//! in the order of their names (Roc's layout; probed with the pinned
//! nightly). So each enum lists Chat.roc's tags, snake_case for PascalCase,
//! in that order, with no numbers written: `assertRocOrder` checks it at
//! compile time. A tag added in Chat.roc is added here, where it sorts.

const std = @import("std");

/// Chat.roc's `Family`: which part of the chat a path names.
pub const Family = enum(u8) {
    /// A static script, `rest` its name; served before the gate.
    asset,
    /// A channel, `key` its name (already a valid one).
    channel,
    code,
    conversations,
    /// `/chat`, `/chat/`, `/chat/default`: the last conversation resumed.
    default,
    /// A DM, `key` its pair as written (Zig checks the viewer is in it).
    dm,
    /// `rest` the path under `/docs` (and images, links, recent and code
    /// likewise).
    docs,
    images,
    links,
    /// `rest` the message id after `/msg/`.
    msg,
    not_found,
    notifications,
    recent,
    /// `rest` the path after `/search`, with no boundary (`/searchX` is "X").
    search,
    sidebar_stream,
};

/// Chat.roc's `Part`: which part of a conversation.
pub const Part = enum(u8) {
    /// A topic id that is not one: refused after the conversation's own
    /// checks, as Zig always refused it.
    invalid,
    /// No topic named: its first topic, or the page offering one.
    landing,
    /// `.../new`: a topic made.
    new,
    /// `sid` a valid topic id, `tail` what of it.
    topic,
};

/// Chat.roc's `Tail`: what of a topic.
pub const Tail = enum(u8) {
    download,
    /// No tail Zig serves: refused once the topic is known to exist.
    invalid,
    /// The same, but under `send`, which skips that check (a send makes
    /// its topic).
    invalid_send,
    page,
    pin,
    raw,
    react,
    reactions,
    saved,
    send,
    stream,
    unpin,
    upload,
    /// `rest` the file.
    uploads,
};

/// Chat.roc's `Method`: a request's method, as the router tells them apart.
pub const Method = enum(u8) {
    get,
    head,
    other,
    post,

    pub fn of(m: std.http.Method) Method {
        return switch (m) {
            .GET => .get,
            .HEAD => .head,
            .POST => .post,
            else => .other,
        };
    }
};

/// Chat.roc's `Kind`: what an answer is (Chat.roc says each).
pub const Kind = enum(u8) { answered, found, held, malformed, not_allowed, not_found, redirect, respond, serve };

/// Host.roc's `body!` argument: whose limit the body is read to.
pub const Form = enum(u8) { message, reaction };

/// Host.roc's `message_count!` answer's `status`: the topic's messages
/// counted (the count beside it), or a count that failed (the host has
/// failed the request). **NEVER 0 FOR A COUNT THAT FAILED**: a reaction
/// judged against it would be refused as no such message.
pub const CountStatus = enum(u8) { counted, failed };

/// Host.roc's `hostile!` answer: `refused` when the host has answered the
/// request (webbox's edge counter and its 400), `failed` when the check did.
pub const Hostility = enum(u8) { failed, fine, refused };

/// Host.roc's `read!` answer's `status`: the file found (its bytes beside
/// it), missing (nothing there), or failed (the host has failed the
/// request). **MISSING AND FAILED ARE NEVER ONE ANSWER.**
pub const ReadStatus = enum(u8) { failed, found, missing };

/// Host.roc's `list!` answer: each entry's `kind`, as webbox's store.list
/// tells them (`directory` is `dir`; a link, a device or the like `other`).
pub const EntryKind = enum(u8) { dir, file, other };

/// Host.roc's `accounts!`: each account's kind (the agent, which the host
/// alone decides; a member, who has a password; a guest, who has neither),
/// or `unreadable` when its password's stat failed (the host keeps the
/// error; the request fails only when a lookup needs the kind).
pub const AccountKind = enum(u8) { agent, guest, member, unreadable };

/// Host.roc's `accounts!`: whether each account's `name` file read (its
/// bytes beside it, "" when it has none) or failed (the host keeps the
/// error).
pub const NameRead = enum(u8) { found, unreadable };

/// Host.roc's `accounts!` answer's `status`: every account listed, or a
/// listing of the auth root that failed (the host has failed the request,
/// and the list is no answer). An auth root not there is no accounts, as
/// store.list holds it. One account that will not read is not this.
pub const AccountsStatus = enum(u8) { failed, found };

/// Host.roc's `fail!` argument: why the Roc fails the request. A malformed
/// channel is error.MalformedChannel, the error the Zig it replaced
/// returned; an account whose kind or name a lookup needed and which would
/// not read is that read's own error, as the host kept it; a message with no
/// author's name is error.NoAuthor, appendMessage's own.
pub const FailReason = enum(u8) { kind_unreadable, malformed_channel, name_unreadable, no_author };

/// Host.roc's `render!` answer's `status`: the markdown rendered (the HTML
/// beside it), or a render that failed (the host has failed the request):
/// never an empty page for one that failed.
pub const RenderStatus = enum(u8) { failed, rendered };

/// Host.roc's `message_parts!`: each part of a message (its excerpt, its
/// image tags, its code blocks) made, or failed on its own (its fault
/// beside it): **A PART THAT FAILED IS NEVER AN EMPTY ONE**, and never the
/// request's failure.
pub const PartStatus = enum(u8) { failed, made };

/// Host.roc's `append_entry!`: a feed's entry appended, or failed (its
/// fault beside it): the fan-out's failure, counted, never the request's.
pub const AppendStatus = enum(u8) { appended, failed };

/// Host.roc's `fanout_failed!`: the fan-out's surfaces that can fail, a
/// member at a time (chat_fanout's names for them, as /admin/host says
/// them). Notify and sidebar are made of the Roc's bytes alone, so never.
pub const Surface = enum(u8) { code, images, recent };

/// Host.roc's `online!` answer: each id seen within the presence window of
/// the request's time, or not (never seen is `offline`).
pub const Presence = enum(u8) { offline, online };

comptime {
    @setEvalBranchQuota(20_000);
    for (.{ Family, Part, Tail, Method, Kind, Form, CountStatus, Hostility, ReadStatus, EntryKind, AccountKind, NameRead, AccountsStatus, FailReason, RenderStatus, PartStatus, AppendStatus, Surface, Presence }) |E| assertRocOrder(E);
}

/// That `E`'s values are Roc's for the same tags: numbered from 0 in the
/// order of the tags' PascalCase names, compared byte by byte (`NotFound`
/// before `Notifications`, `Invalid` before `InvalidSend`).
pub fn assertRocOrder(comptime E: type) void {
    const info = @typeInfo(E).@"enum";
    for (info.field_names, info.field_values, 0..) |name, value, i| {
        if (value != i) @compileError(@typeName(E) ++ "." ++ name ++ " has a number written: Roc's are its place in name order");
        if (i > 0 and !std.mem.lessThan(u8, pascal(info.field_names[i - 1]), pascal(name)))
            @compileError(@typeName(E) ++ ": `" ++ name ++ "` must come before `" ++ info.field_names[i - 1] ++ "`, as Roc numbers its tags by name");
    }
}

/// `not_found` as Roc spells the tag: `NotFound`.
fn pascal(comptime snake: []const u8) []const u8 {
    comptime {
        var out: []const u8 = "";
        var up = true;
        for (snake) |c| {
            if (c == '_') {
                up = true;
                continue;
            }
            out = out ++ &[_]u8{if (up) std.ascii.toUpper(c) else c};
            up = false;
        }
        return out;
    }
}

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
