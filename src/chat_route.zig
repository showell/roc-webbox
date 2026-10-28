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
    /// `topic` a valid topic id, `tail` what of it.
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

/// Chat.roc's `Request`'s `area`: the path is under /channel or /chat.
pub const Area = enum(u8) { channel, chat, retire };

/// Chat.roc's `Sniff`: `forbid` when the answer says `nosniff`.
pub const Sniff = enum(u8) { allow, forbid };

/// Chat.roc's `Kind`: what an answer is (Chat.roc says each).
pub const Kind = enum(u8) {
    answered,
    found,
    held,
    malformed,
    not_allowed,
    not_found,
    redirect,
    respond,
    serve,
    stream,
    to_login,
};

/// Host.roc's `read_body!` argument: whose limit the body is read to.
pub const Form = enum(u8) {
    doc,
    message,
    reaction,
};

/// Host.roc's `read_body!` answer's `status`: the body read (its bytes beside
/// it), or answered by the host instead (too big) or failed.
pub const BodyStatus = enum(u8) { answered, read };

/// Host.roc's `message_count!` answer's `status`: the topic's messages
/// counted (the count beside it), or a count that failed (the host has
/// failed the request). **NEVER 0 FOR A COUNT THAT FAILED**: a reaction
/// judged against it would be refused as no such message.
pub const CountStatus = enum(u8) { counted, failed };

/// Host.roc's `check_hostile!` answer: `refused` when the host has answered the
/// request (webbox's edge counter and its 400), `failed` when the check did.
pub const Hostility = enum(u8) {
    failed,
    fine,
    refused,
};

/// Host.roc's `read!` answer's `status`: the file found (its bytes beside
/// it), missing (nothing there), or failed (the host has failed the
/// request). **MISSING AND FAILED ARE NEVER ONE ANSWER.**
pub const ReadStatus = enum(u8) {
    failed,
    found,
    missing,
};

/// Host.roc's `list!` answer: each entry's `kind`, as webbox's store.list
/// tells them (`directory` is `dir`; a link, a device or the like `other`).
pub const EntryKind = enum(u8) {
    dir,
    file,
    other,
};

/// Host.roc's `list_accounts!`: each account's kind (the agent, which the host
/// alone decides; a member, who has a password; a guest, who has neither),
/// or `unreadable` when its password's stat failed (the host keeps the
/// error; the request fails only when a lookup needs the kind).
pub const AccountKind = enum(u8) {
    agent,
    guest,
    member,
    unreadable,
};

/// Host.roc's `list_accounts!`: whether each account's `name` file read (its
/// bytes beside it, "" when it has none) or failed (the host keeps the
/// error).
pub const NameRead = enum(u8) { found, unreadable };

/// Host.roc's `list_accounts!` answer's `status`: every account listed, or a
/// listing of the auth root that failed (the host has failed the request,
/// and the list is no answer). An auth root not there is no accounts, as
/// store.list holds it. One account that will not read is not this.
pub const AccountsStatus = enum(u8) { failed, found };

/// Host.roc's `fail!` argument: why the Roc fails the request. A malformed
/// channel is error.MalformedChannel, the error the Zig it replaced
/// returned; an account whose kind or name a lookup needed and which would
/// not read is that read's own error, as the host kept it; a message with no
/// author's name is error.NoAuthor, appendMessage's own; a file whose bytes
/// are not UTF-8 is error.NotUtf8, about its path (Files.read!'s door).
pub const FailReason = enum(u8) {
    kind_unreadable,
    malformed_channel,
    name_unreadable,
    no_author,
    not_a_uid,
    not_utf8,
};

/// Host.roc's `render!` answer's `status`: the markdown rendered (the HTML
/// beside it), or a render that failed (the host has failed the request):
/// never an empty page for one that failed.
pub const RenderStatus = enum(u8) { failed, rendered };

/// Host.roc's `append_entry!`: a feed's entry appended, or failed (its
/// fault beside it): the fan-out's failure, counted, never the request's.
pub const AppendStatus = enum(u8) { appended, failed };

/// Host.roc's `report_fanout_failure!`: the fan-out's surfaces that can fail, a
/// member at a time (chat_fanout's names for them, as /admin/host says
/// them). Notify and sidebar are made of the Roc's bytes alone, so never.
pub const Surface = enum(u8) { code, images };

/// Host.roc's `admit!` answer: the member may search now, or has searched
/// too often this second (chat_search.zig `admit`).
pub const Admission = enum(u8) { admitted, refused };

/// Host.roc's `search_words!` answer's `status`: the index there to ask, or
/// not ready (it could not be built).
pub const WordsStatus = enum(u8) { not_ready, ready };

/// Host.roc's `search_messages!` hits: a DM's or a channel's.
pub const HitConv = enum(u8) { channel, dm };

/// Host.roc's `search_messages!` hits: whether the index found the word in
/// the message where the excerpt is cut (`search_index.wordAt`), or not.
pub const HitWord = enum(u8) { found, missing };

/// Host.roc's `check_online!` answer: each id seen within the presence window of
/// the request's time, or not (never seen is `offline`).
pub const Presence = enum(u8) { offline, online };

/// Host.roc's `count_presence!` answer (metal-vmm QUEUE 288): the member
/// came online with this request (the Roc broadcasts), or was online.
pub const PresenceEdge = enum(u8) { came_online, steady };

/// Host.roc's `identify!` answer's `status`: who is asking was verified
/// (`known`, the id beside it), no one is (`stranger`), or the look failed
/// (`failed`: the host has failed the request). Whether that one may use the
/// chat is the Roc's.
pub const Identity = enum(u8) { failed, known, stranger };

/// Host.roc's `Try({}, [Failed])` answer (`append_line!`, `write!`,
/// `remove!`, `store_message!`): `Err(Failed)` or `Ok({})`, both payloads
/// empty, so the tag alone crosses (`Err` first, as Roc sorts them).
/// `failed` means the host has failed the request.
pub const Done = enum(u8) { failed, ok };

/// Host.roc's `retire_note!` kind (metal-vmm QUEUE 293): what a step of the
/// admin retire's plan removes, as the report counts it.
pub const RetireKind = enum(u8) {
    channel_member,
    dm,
    ref_last_conv,
    ref_last_session,
    ref_pinned,
    topic,
    user,
};

/// Host.roc's `retire_remove!` what: one file, or a folder and all in it.
pub const RetireRemoval = enum(u8) { file, tree };

/// Host.roc's `welcome_pending!` answer (metal-vmm QUEUE 283): the member's
/// welcome is pending, is not, or the look failed (the host has failed the
/// request, or the aside).
pub const Welcome = enum(u8) {
    failed,
    none,
    pending,
};

/// Host.roc's `serve_file!` and `serve_rendered!` answer: the host holds
/// the file's bytes for a `held` answer, or it is not there (or its read
/// failed).
pub const Serving = enum(u8) { not_serving, serving };

/// Host.roc's `serve_upload!` record's `part` (metal-vmm QUEUE 291): the
/// whole file, the bytes `first` to `last`, or a range it cannot serve.
pub const UploadPart = enum(u8) { range, unsatisfiable, whole };

/// Host.roc's `serve_upload!` answer: the file gone since the Roc's look
/// (nothing answered), or served.
pub const UploadServed = enum(u8) { gone, served };

/// Host.roc's `read_upload!` answer's `status` (metal-vmm QUEUE 292).
pub const UploadRead = enum(u8) { answered, no_file, read, unsupported };

/// Host.roc's `refuse_upload!` argument: which edge counter refuses it.
pub const UploadRefusal = enum(u8) { malformed, too_large };

/// Host.roc's `reserve_upload!` answer.
pub const Reservation = enum(u8) { failed, refused, reserved };

/// Host.roc's `store_upload!` answer's `status`.
pub const UploadStored = enum(u8) { failed, stored };

/// Host.roc's `count_dropped!`: what the chat dropped, counted, rather than
/// fail the request for (metal-vmm QUEUE 267): a DM's new-topic announcement
/// that failed after the topic was made, a feed's entry or a recent row
/// whose bytes are not UTF-8.
pub const Dropped = enum(u8) {
    announcement,
    feed_entry,
    recent_row,
};

/// Host.roc's `aside!` argument: the start or the end of work whose failure
/// is its own, never the request's.
pub const Aside = enum(u8) { begin, end };

/// Host.roc's `aside!` answer: `End`'s, whether anything in the aside failed
/// (`Begin`'s is `failed` only for a request that has failed already).
pub const AsideEnd = enum(u8) { done, failed };

comptime {
    @setEvalBranchQuota(20_000);
    for (.{
        Family,
        Part,
        Tail,
        Method,
        Area,
        Sniff,
        Kind,
        Form,
        BodyStatus,
        CountStatus,
        Hostility,
        ReadStatus,
        EntryKind,
        AccountKind,
        NameRead,
        AccountsStatus,
        FailReason,
        RenderStatus,
        AppendStatus,
        Surface,
        Presence,
        PresenceEdge,
        Identity,
        Admission,
        WordsStatus,
        HitConv,
        HitWord,
        Done,
        Welcome,
        Serving,
        UploadPart,
        UploadServed,
        UploadRead,
        UploadRefusal,
        Reservation,
        UploadStored,
        RetireKind,
        RetireRemoval,
        Dropped,
        Aside,
        AsideEnd,
    }) |E| assertRocOrder(E);
}

/// That `E`'s values are Roc's for the same tags: numbered from 0 in the
/// order of the tags' PascalCase names, compared byte by byte (`NotFound`
/// before `Notifications`, `Invalid` before `InvalidSend`).
pub fn assertRocOrder(comptime E: type) void {
    const info = @typeInfo(E).@"enum";
    for (info.field_names, info.field_values, 0..) |name, value, i| {
        if (value != i) @compileError(@typeName(E) ++ "." ++ name ++ " has a number written: Roc's are its place in name order");
        if (i > 0 and !std.mem.lessThan(
            u8,
            pascal(info.field_names[i - 1]),
            pascal(name),
        ))
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
    topic: []const u8 = "",
    part: Part = .landing,
    tail: Tail = .page,

    pub fn eql(a: Route, b: Route) bool {
        return a.family == b.family and a.part == b.part and a.tail == b.tail and
            std.mem.eql(
                u8,
                a.key,
                b.key,
            ) and std.mem.eql(
            u8,
            a.rest,
            b.rest,
        ) and std.mem.eql(
            u8,
            a.topic,
            b.topic,
        );
    }

    pub fn format(r: Route, w: *std.Io.Writer) std.Io.Writer.Error!void {
        try w.print("{t} key=\"{s}\" rest=\"{s}\" topic=\"{s}\" {t} {t}", .{
            r.family,
            r.key,
            r.rest,
            r.topic,
            r.part,
            r.tail,
        });
    }
};

/// What the router decided: the gate's 303 to the login page, or a route for
/// Zig (the Roc counted its presence first, metal-vmm QUEUE 288); or,
/// for a route the Roc served itself, what to send.
pub const Decision = union(enum) {
    /// A 303 to a path the Roc built from a conversation's base and a
    /// topic, which the store's names keep on the site.
    redirect: []const u8,
    serve: struct { route: Route },
    /// A status and its body, typed `content_type` when it is not empty.
    respond: struct {
        status: u16,
        content_type: []const u8 = "",
        body: []const u8 = "",
        nosniff: bool = false,
    },
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
    held: struct {
        status: u16,
        content_type: []const u8 = "",
        nosniff: bool = false,
        before: []const u8 = "",
        after: []const u8 = "",
    },
    /// A 303 to the login page, to come back to this path after: the
    /// request's own, which the host checks is on the site (a 400 if not).
    to_login: []const u8,
    /// The live stream on bus key `key`, held by the host (metal-vmm QUEUE
    /// 286); a topic's replays its backlog first, from `transcript` (a path
    /// under the chat root, its messages numbered in `topic`). `transcript`
    /// empty: live only.
    stream: struct {
        key: []const u8,
        transcript: []const u8 = "",
        topic: []const u8 = "",
    },

    pub fn eql(a: Decision, b: Decision) bool {
        if (std.meta.activeTag(a) != std.meta.activeTag(b)) return false;
        return switch (a) {
            .redirect => |l| std.mem.eql(
                u8,
                l,
                b.redirect,
            ),
            .serve => |s| s.route.eql(b.serve.route),
            .respond => |r| r.status == b.respond.status and r.nosniff == b.respond.nosniff and std.mem.eql(
                u8,
                r.content_type,
                b.respond.content_type,
            ) and std.mem.eql(
                u8,
                r.body,
                b.respond.body,
            ),
            .not_allowed => |m| m == b.not_allowed,
            .answered, .malformed_form, .not_found => true,
            .found => |l| std.mem.eql(
                u8,
                l,
                b.found,
            ),
            .to_login => |l| std.mem.eql(
                u8,
                l,
                b.to_login,
            ),
            .stream => |s| std.mem.eql(
                u8,
                s.key,
                b.stream.key,
            ) and std.mem.eql(
                u8,
                s.transcript,
                b.stream.transcript,
            ) and std.mem.eql(
                u8,
                s.topic,
                b.stream.topic,
            ),
            .held => |h| h.status == b.held.status and h.nosniff == b.held.nosniff and std.mem.eql(
                u8,
                h.content_type,
                b.held.content_type,
            ) and std.mem.eql(
                u8,
                h.before,
                b.held.before,
            ) and std.mem.eql(
                u8,
                h.after,
                b.held.after,
            ),
        };
    }

    pub fn format(d: Decision, w: *std.Io.Writer) std.Io.Writer.Error!void {
        switch (d) {
            .redirect => |l| try w.print("303 {s}", .{l}),
            .serve => |s| try w.print("{f}", .{s.route}),
            .respond => |r| try w.print("{d} \"{s}\"{s} {d} bytes", .{
                r.status,
                r.content_type,
                if (r.nosniff) " nosniff" else "",
                r.body.len,
            }),
            .not_allowed => |m| try w.print("405 allow {t}", .{m}),
            .answered => try w.writeAll("answered by the host"),
            .malformed_form => try w.writeAll("malformed form"),
            .not_found => try w.writeAll("404"),
            .found => |l| try w.print("302 {s}", .{l}),
            .to_login => |l| try w.print("303 to login, then {s}", .{l}),
            .stream => |s| if (s.transcript.len == 0) try w.print(
                "stream {s}",
                .{s.key},
            ) else try w.print("stream {s}, its backlog from {s} in {s}", .{
                s.key,
                s.transcript,
                s.topic,
            }),
            .held => |h| try w.print("{d} \"{s}\"{s} {d} bytes, the host's, {d} bytes", .{
                h.status,
                h.content_type,
                if (h.nosniff) " nosniff" else "",
                h.before.len,
                h.after.len,
            }),
        }
    }
};
