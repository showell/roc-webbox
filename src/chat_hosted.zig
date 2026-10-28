//! **THE ROC CHAT, AS ANGRY-GOPHER TAKES IT** (docs/ROC-CHAT.md §3,
//! milestone 1): `decide`, the Roc's answer to a /chat or /channel request
//! (chat/main.roc), read into chat_route.zig's `Decision`, which angry-gopher
//! sends; the hosted functions' types. Nothing else here touches a request.

const std = @import("std");
const abi = @import("chat_abi.zig");
const route = @import("chat_route.zig");

pub const decide = abi.decide;
pub const retire = abi.retire;
pub const Host = abi.Host;
pub const askingOnly = abi.askingOnly;
pub const Routing = abi.Routing;
pub const Decision = route.Decision;
pub const Form = route.Form;
pub const Count = abi.Count;
pub const CountStatus = route.CountStatus;
pub const Rendered = abi.Rendered;
pub const RenderStatus = route.RenderStatus;
pub const Message = abi.Message;
pub const Appended = abi.Appended;
pub const AsideOutcome = abi.AsideOutcome;
pub const AppendStatus = route.AppendStatus;
pub const Surface = route.Surface;
pub const Hostility = route.Hostility;
pub const ReadStatus = route.ReadStatus;
pub const Read = abi.Read;
pub const Listing = abi.Listing;
pub const Stat = abi.Stat;
pub const Entry = abi.Entry;
pub const Src = abi.Src;
pub const EntryKind = route.EntryKind;
pub const Account = abi.Account;
pub const Accounts = abi.Accounts;
pub const AccountKind = route.AccountKind;
pub const AccountRead = abi.AccountRead;
pub const Presence = route.Presence;
pub const PresenceEdge = route.PresenceEdge;
pub const Admission = route.Admission;
pub const Word = abi.Word;
pub const Words = abi.Words;
pub const Hit = abi.Hit;
pub const Messages = abi.Messages;
pub const Asking = abi.Asking;
pub const Identity = route.Identity;
pub const Done = route.Done;
pub const Upload = abi.Upload;
pub const UploadRead = abi.UploadRead;
pub const Stored = abi.Stored;
pub const UploadRefusal = route.UploadRefusal;
pub const Reservation = route.Reservation;
pub const RetireAsked = abi.RetireAsked;
pub const RetireKind = route.RetireKind;
pub const RetireRemoval = route.RetireRemoval;
pub const UploadServed = route.UploadServed;
pub const ScriptServed = route.ScriptServed;
pub const Welcome = route.Welcome;
pub const Serving = route.Serving;
pub const Dropped = route.Dropped;
pub const Aside = route.Aside;
pub const AsideEnd = route.AsideEnd;

/// roc_abi.zig's arena, from `base`, once, as the host starts.
pub fn use(base: std.mem.Allocator) void {
    @import("roc_abi.zig").use(base);
}

/// Or the request's own allocator, freed with the request, before each
/// call (roc_abi.zig `useRequest`): no arena over it.
pub fn useRequest(request: std.mem.Allocator) void {
    @import("roc_abi.zig").useRequest(request);
}

// ── tests: a few decisions through the Roc (angry-gopher's tests hold the
// router to Zig's own parse over a corpus) ────────────────────────────────

const testing = std.testing;

/// A host to which no one is asking.
fn stranger() Host {
    const S = struct {
        fn no(_: *anyopaque) abi.Asking {
            return .stranger;
        }
        var dummy: u8 = 0;
    };
    return askingOnly(&S.dummy, S.no);
}

/// A path that names nothing is the Roc's own 404 (metal-vmm QUEUE 286),
/// its presence counted as the Zig's was.
fn expectNotFound(sub: []const u8, channel: bool) !void {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var routing: Routing = .{};
    const got = try decide(
        arena.allocator(),
        sub,
        channel,
        .GET,
        routing.host(),
    );
    if (got == .not_found and routing.marked) return;
    std.debug.print("{s}: got {f} (presence {}), want the Roc's 404\n", .{ sub, got, routing.marked });
    return error.TestUnexpectedResult;
}

test "the router: a topic's tails, a channel, a script before the gate, the gate" {
    use(testing.allocator);
    defer @import("roc_abi.zig").deinit();
    // **THE ROC DECIDES A CONVERSATION'S ROUTES** (metal-vmm QUEUE 271): to
    // one who is in none, every tail is its 404, presence counted but for
    // a stream's; a DM's is webbox's plain one, a channel's the page that
    // says why.
    for ([_]struct {
        []const u8,
        bool,
        std.meta.Tag(Decision),
        bool,
    }{
        .{
            "/c/1_2/general/send",
            false,
            .not_found,
            true,
        },
        .{
            "/c/1_2/general/uploads/a.png",
            false,
            .not_found,
            true,
        },
        .{
            "/c/1_2/general/stream",
            false,
            .not_found,
            false,
        },
        .{
            "/c/1_2/general/send/x",
            false,
            .not_found,
            true,
        },
        .{
            "/c/1_2/bad_id",
            false,
            .not_found,
            true,
        },
        .{
            "/ops/new",
            true,
            .respond,
            true,
        },
        // Search is the Roc's (metal-vmm QUEUE 281, 282): past its two
        // routes, its 404.
        .{
            "/searchX",
            false,
            .not_found,
            true,
        },
    }) |c| {
        var ar = std.heap.ArenaAllocator.init(testing.allocator);
        defer ar.deinit();
        var routing: Routing = .{};
        const d = try decide(
            ar.allocator(),
            c[0],
            c[1],
            .GET,
            routing.host(),
        );
        if (d != c[2] or routing.marked != c[3] or (d == .respond and d.respond.status != 404)) {
            std.debug.print("{s}: got {f} (presence {}), want {t} (presence {})\n", .{
                c[0],
                d,
                routing.marked,
                c[2],
                c[3],
            });
            return error.TestUnexpectedResult;
        }
    }
    try expectNotFound("/9ops/x", true);
    try expectNotFound("/docsX", false);
    // A docs path of two segments is the Roc's 404 (metal-vmm QUEUE 289),
    // its text whole.
    try expectNotFound("/docs/caf\xc3\xa9/\xf0\x9f\x91\x8d", false);

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    // **A PATH THAT IS NOT UTF-8 IS REFUSED AT THE DOOR**: the site's 400,
    // before anyone is asked anything.
    for ([_]bool{ false, true }) |channel| {
        var routing: Routing = .{};
        const bad = try decide(
            arena.allocator(),
            "/docs/\xff\xfe",
            channel,
            .GET,
            routing.host(),
        );
        try testing.expect(bad == .malformed_form and !routing.marked);
    }
    const away = try decide(
        arena.allocator(),
        "/c/1_2/general",
        false,
        .GET,
        stranger(),
    );
    try testing.expectEqualStrings("/chat/c/1_2/general", away.to_login);
    // **A SCRIPT BEFORE THE GATE**: served by the host to anyone, by any
    // method, nobody asked and no presence counted; a name the host's table
    // has not is webbox's 404, the same.
    for ([_]bool{ false, true }) |member| for ([_]std.http.Method{ .GET, .POST }) |method| {
        var routing: Routing = .{ .member = member };
        const script = try decide(arena.allocator(), "/chat.js", false, method, routing.host());
        try testing.expect(script == .answered and !routing.asked and !routing.marked);
        try testing.expectEqualStrings("chat.js", routing.script.?);
        var none: Routing = .{ .member = member };
        const missing = try decide(arena.allocator(), "/nope.js", false, method, none.host());
        try testing.expect(missing == .not_found and !none.asked and !none.marked and none.script == null);
    };
}

/// A host whose answers a test sets, and which records what it was asked:
/// the member is 1, Steve, in channel ops with 3; account 2 is Debbie.
const Scripted = struct {
    /// Who is asking, as Host.identify! answers.
    asking: abi.Asking = .{ .known = "1" },
    /// Every account, as Host.list_accounts! hands them; null when the read
    /// failed.
    accounts: ?[]const abi.Account = &.{ steve, .{
        .id = "2",
        .name = .{ .found = "Debbie" },
        .kind = .member,
    } },
    /// Every channel, in the listing's order: `channels/` lists each as
    /// `<name>.channel`, and that file reads as `read`.
    channels: []const Channel = &.{.{ .name = "ops", .read = .{ .found = "1\n3\n" } }},
    /// The conversation's topics: every `.../sessions` folder lists each as
    /// `<topic>.md`, a file.
    topics: []const []const u8 = &.{"Plans"},
    /// The member's docs, in the folder's order: `.../docs` lists each as
    /// `<slug>.md`, a file, each changed at the one time stat answers.
    docs: []const []const u8 = &.{},
    body: ?[]const u8 = "",
    /// A topic's message count, or a count that failed.
    count: abi.Count = .{ .counted = 3 },
    /// Whether a line appended to a topic's reactions is stored.
    append_line_ok: bool = true,
    /// A topic's reactions as stored (null: none), and whether a read of
    /// them fails (Host.read_at!'s miss).
    sidecar: ?[]const u8 = null,
    sidecar_unread: bool = false,
    /// The files under the chat root, each as read; any other is missing.
    files: []const File = &.{},
    /// Whether a write or a remove succeeds.
    write_ok: bool = true,
    /// What counting the member online says: the edge (they came online) or not.
    edge: route.PresenceEdge = .steady,
    /// The members seen within the presence window; any other is offline.
    online_ids: []const []const u8 = &.{},
    is_async: bool = false,
    hostile_answer: route.Hostility = .fine,
    /// What the last hostile check would say on a refusal.
    refusal: []const u8 = "",
    /// Whether markdown renders (as `<p>` around it), and whether a
    /// message's block is stored.
    render_ok: bool = true,
    store_ok: bool = true,
    /// A topic whose message will not store, alone (an announcement's).
    store_fails_for: ?[]const u8 = null,
    /// The transcript's size before an append (Host.append!).
    transcript_before: u64 = 100,
    /// An aside whose every end fails with this error, whatever was in it.
    aside_fails: ?anyerror = null,
    /// Inside an aside, and the error an append in it failed with.
    in_aside: bool = false,
    aside_failed: ?anyerror = null,
    /// What Host.welcome_pending! answers (metal-vmm QUEUE 283); `welcome_done!`
    /// makes it `.none`.
    welcome: route.Welcome = .none,
    /// A feed's path whose entry will not append, and its error.
    entry_fails: ?struct { path: []const u8, e: anyerror } = null,
    transcript: bool = true,
    linked: bool = false,
    /// What Host.read_upload! reads of the form, and what reserving its
    /// bytes against the member's allowance says (metal-vmm QUEUE 292).
    upload: abi.UploadRead = .no_file,
    reservation: route.Reservation = .reserved,
    asked: std.ArrayList(u8) = .empty,
    alloc: std.mem.Allocator,

    const File = struct { path: []const u8, read: abi.Read };
    const Channel = struct { name: []const u8, read: abi.Read };

    fn host(self: *Scripted) Host {
        return .{
            .ctx = self,
            .identify = identify,
            .count_presence = presence,
            .presence_unspent = presenceUnspent,
            .list_accounts = accountsOf,
            .me = meId,
            .now = nowOf,
            .read_body = bodyOf,
            .publish = publish,
            .append = appendOf,
            .stat = statOf,
            .read_at = readAtOf,
            .read = readOf,
            .write = writeOf,
            .remove = removeOf,
            .list = listOf,
            .fail = failOf,
            .fail_text = failTextOf,
            .fail_account = failAccountOf,
            .count_malformed_channel = malformed,
            .count_refused_block = refusedBlock,
            .count_dropped = dropped,
            .aside = asideOf,
            .check_online = onlineOf,
            .read_header = header,
            .read_query = query,
            .check_hostile = hostile,
            .render = render,
            .render_preview = renderPreview,
            .index_message = indexMessage,
            .write_cache = writeCache,
            .report_fanout_failure = fanoutFailed,
            .serve_file = raw,
            .serve_rendered = links,
            .srcs = srcs,
            .welcome_pending = welcomeOf,
            .welcome_done = welcomeDone,
            .read_upload = readUpload,
            .refuse_upload = refuseUpload,
            .reserve_upload = reserveUpload,
            .store_upload = storeUpload,
        };
    }
    fn readUpload(ctx: *anyopaque) abi.UploadRead {
        say(ctx, "read_upload", .{});
        return me(ctx).upload;
    }
    fn refuseUpload(ctx: *anyopaque, why: route.UploadRefusal, message: []const u8) void {
        say(ctx, "refuse_upload {t} {s}", .{ why, message });
    }
    fn reserveUpload(ctx: *anyopaque, size: u64) route.Reservation {
        say(ctx, "reserve_upload {d}", .{size});
        return me(ctx).reservation;
    }
    fn storeUpload(ctx: *anyopaque, folder: []const u8, ext: []const u8) abi.Stored {
        say(ctx, "store_upload {s} {s}", .{ folder, ext });
        return .{ .stored = "0123.png" };
    }
    fn welcomeOf(ctx: *anyopaque) route.Welcome {
        say(
            ctx,
            "welcome?",
            .{},
        );
        return me(ctx).welcome;
    }
    fn welcomeDone(ctx: *anyopaque) route.Done {
        say(
            ctx,
            "welcome done",
            .{},
        );
        me(ctx).welcome = .none;
        return .ok;
    }
    fn me(ctx: *anyopaque) *Scripted {
        return @ptrCast(@alignCast(ctx));
    }
    fn say(
        ctx: *anyopaque,
        comptime fmt: []const u8,
        args: anytype,
    ) void {
        const s = me(ctx);
        s.asked.print(
            s.alloc,
            fmt ++ ";",
            args,
        ) catch @panic("oom");
    }
    fn identify(ctx: *anyopaque) abi.Asking {
        say(
            ctx,
            "identify",
            .{},
        );
        return me(ctx).asking;
    }
    fn presence(ctx: *anyopaque) route.PresenceEdge {
        say(
            ctx,
            "presence",
            .{},
        );
        return me(ctx).edge;
    }
    fn presenceUnspent(ctx: *anyopaque) void {
        say(
            ctx,
            "presence unspent",
            .{},
        );
    }
    fn meId(_: *anyopaque) []const u8 {
        return "1";
    }
    fn accountsOf(ctx: *anyopaque) abi.Accounts {
        say(
            ctx,
            "accounts",
            .{},
        );
        return .{ .found = me(ctx).accounts orelse return .failed };
    }
    fn bodyOf(ctx: *anyopaque, _: route.Form) ?[]const u8 {
        say(
            ctx,
            "body",
            .{},
        );
        return me(ctx).body;
    }
    /// The key and the bytes exactly, escaped, so a frame's every byte shows.
    fn publish(
        ctx: *anyopaque,
        key: []const u8,
        bytes: []const u8,
    ) void {
        say(
            ctx,
            "publish {s} {f}",
            .{ key, std.zig.fmtString(bytes) },
        );
    }
    /// The bytes escaped, so their every byte shows. A topic's reactions
    /// take a line but where `append_line_ok` is not; a transcript takes a
    /// block but where `store_ok` is not or its topic is `store_fails_for`,
    /// and is `transcript_before` bytes before it; a feed takes an entry
    /// but at `entry_fails`'s path, whose error is its aside's.
    fn appendOf(
        ctx: *anyopaque,
        path: []const u8,
        bytes: []const u8,
    ) abi.Appended {
        say(
            ctx,
            "append {s} {f}",
            .{ path, std.zig.fmtString(bytes) },
        );
        const s = me(ctx);
        if (std.mem.endsWith(u8, path, ".reactions.jsonl")) {
            return if (s.append_line_ok) .{ .appended = 7 + bytes.len } else .failed;
        }
        if (std.mem.indexOf(u8, path, "/sessions/") != null) {
            if (s.store_fails_for) |t| if (std.mem.endsWith(u8, path, std.fmt.allocPrint(
                s.alloc,
                "/sessions/{s}.md",
                .{t},
            ) catch @panic("oom"))) return .failed;
            if (!s.store_ok) return .failed;
            return .{ .appended = s.transcript_before + bytes.len };
        }
        if (s.entry_fails) |fails| if (std.mem.eql(
            u8,
            fails.path,
            path,
        )) {
            if (s.in_aside and s.aside_failed == null) s.aside_failed = fails.e;
            return .failed;
        };
        return .{ .appended = 7 + bytes.len };
    }
    /// A transcript (`<dir>/sessions/<topic>.md`) is 7 bytes, but where
    /// `count` failed (its stat fails); its sidecar says
    /// `count` at 7, so it is believed. A topic's reactions are `sidecar`.
    /// Any other path is not there.
    fn statOf(ctx: *anyopaque, path: []const u8) abi.Stat {
        say(
            ctx,
            "stat {s}",
            .{path},
        );
        if (std.mem.endsWith(u8, path, ".reactions.jsonl")) {
            const bytes = me(ctx).sidecar orelse return .missing;
            return .{ .found = .{ .size = bytes.len, .mtime = 1761400000 } };
        }
        if (!std.mem.endsWith(
            u8,
            path,
            ".md",
        )) return .missing;
        return switch (me(ctx).count) {
            .counted => .{ .found = .{ .size = 7, .mtime = 1761400000 } },
            .failed => .failed,
        };
    }
    fn readAtOf(
        ctx: *anyopaque,
        path: []const u8,
        offset: u64,
        max: u64,
    ) abi.Read {
        say(
            ctx,
            "read_at {s}",
            .{path},
        );
        if (std.mem.endsWith(u8, path, ".reactions.jsonl")) {
            const s = me(ctx);
            const bytes = s.sidecar orelse return .missing;
            if (s.sidecar_unread) return .failed;
            const from: usize = @intCast(@min(offset, bytes.len));
            return .{ .found = bytes[from..@min(bytes.len, from + @as(usize, @intCast(max)))] };
        }
        if (!std.mem.endsWith(
            u8,
            path,
            ".count",
        )) return .missing;
        return switch (me(ctx).count) {
            .counted => |n| .{ .found = std.fmt.allocPrint(
                me(ctx).alloc,
                "{d} 7\n",
                .{n},
            ) catch @panic("oom") },
            .failed => .missing,
        };
    }
    fn nowOf(_: *anyopaque) i64 {
        return 1761400000;
    }
    fn readOf(ctx: *anyopaque, path: []const u8) abi.Read {
        say(
            ctx,
            "read {s}",
            .{path},
        );
        const s = me(ctx);
        for (s.files) |f| if (std.mem.eql(
            u8,
            f.path,
            path,
        )) return f.read;
        for (s.channels) |c| {
            const file = std.fmt.allocPrint(
                s.alloc,
                "channels/{s}.channel",
                .{c.name},
            ) catch @panic("oom");
            if (std.mem.eql(
                u8,
                file,
                path,
            )) return c.read;
        }
        return .missing;
    }
    fn listOf(ctx: *anyopaque, path: []const u8) abi.Listing {
        say(
            ctx,
            "list {s}",
            .{path},
        );
        const s = me(ctx);
        var out: std.ArrayList(abi.Entry) = .empty;
        if (std.mem.eql(
            u8,
            path,
            "channels",
        )) {
            for (s.channels) |c| out.append(s.alloc, .{ .name = std.fmt.allocPrint(
                s.alloc,
                "{s}.channel",
                .{c.name},
            ) catch @panic("oom"), .kind = .file }) catch @panic("oom");
        } else if (std.mem.endsWith(
            u8,
            path,
            "/sessions",
        )) {
            for (s.topics) |t| out.append(s.alloc, .{ .name = std.fmt.allocPrint(
                s.alloc,
                "{s}.md",
                .{t},
            ) catch @panic("oom"), .kind = .file }) catch @panic("oom");
        } else if (std.mem.endsWith(
            u8,
            path,
            "/docs",
        )) {
            for (s.docs) |d| out.append(s.alloc, .{ .name = std.fmt.allocPrint(
                s.alloc,
                "{s}.md",
                .{d},
            ) catch @panic("oom"), .kind = .file }) catch @panic("oom");
        } else return .missing;
        return .{ .found = out.items };
    }
    fn malformed(ctx: *anyopaque, channel: []const u8) void {
        say(
            ctx,
            "malformed {s}",
            .{channel},
        );
    }
    fn refusedBlock(ctx: *anyopaque, first: []const u8) void {
        say(ctx, "refused {s}", .{first});
    }
    fn query(ctx: *anyopaque, name: []const u8) []const []const u8 {
        say(ctx, "query {s}", .{name});
        return &.{};
    }
    fn dropped(
        ctx: *anyopaque,
        what: route.Dropped,
        whose: []const u8,
    ) void {
        say(
            ctx,
            "dropped {t} {s}",
            .{ what, whose },
        );
    }
    fn asideOf(ctx: *anyopaque, which: route.Aside) abi.AsideOutcome {
        say(
            ctx,
            "aside {t}",
            .{which},
        );
        const s = me(ctx);
        switch (which) {
            .begin => s.in_aside = true,
            .end => {
                s.in_aside = false;
                const e = s.aside_failed orelse (s.aside_fails orelse return .done);
                s.aside_failed = null;
                return .{ .failed = e };
            },
        }
        return .done;
    }
    fn writeOf(
        ctx: *anyopaque,
        path: []const u8,
        bytes: []const u8,
    ) route.Done {
        say(
            ctx,
            "write {s} {s}",
            .{ path, bytes },
        );
        return if (me(ctx).write_ok) .ok else .failed;
    }
    fn removeOf(ctx: *anyopaque, path: []const u8) route.Done {
        say(
            ctx,
            "remove {s}",
            .{path},
        );
        return if (me(ctx).write_ok) .ok else .failed;
    }
    fn failOf(ctx: *anyopaque, e: anyerror) void {
        say(
            ctx,
            "fail {t}",
            .{e},
        );
    }
    fn failTextOf(ctx: *anyopaque, path: []const u8) void {
        say(
            ctx,
            "fail not_utf8 {s}",
            .{path},
        );
    }
    fn failAccountOf(
        ctx: *anyopaque,
        which: abi.AccountRead,
        id: []const u8,
    ) void {
        say(
            ctx,
            "fail {t} {s}",
            .{ which, id },
        );
    }
    /// Asked id by id by the seam, for the Roc's one asking.
    fn onlineOf(ctx: *anyopaque, id: []const u8) route.Presence {
        say(
            ctx,
            "online {s}",
            .{id},
        );
        for (me(ctx).online_ids) |o| if (std.mem.eql(
            u8,
            o,
            id,
        )) return .online;
        return .offline;
    }
    fn header(ctx: *anyopaque, header_name: []const u8) []const []const u8 {
        say(
            ctx,
            "header {s}",
            .{header_name},
        );
        return if (me(ctx).is_async) &.{"1"} else &.{};
    }
    fn hostile(
        ctx: *anyopaque,
        markdown: []const u8,
        refusal: []const u8,
    ) route.Hostility {
        say(
            ctx,
            "hostile {s}",
            .{markdown},
        );
        me(ctx).refusal = refusal;
        return me(ctx).hostile_answer;
    }
    fn raw(ctx: *anyopaque, path: []const u8) route.Serving {
        say(
            ctx,
            "raw {s}",
            .{path},
        );
        return if (me(ctx).transcript) .serving else .not_serving;
    }
    fn links(ctx: *anyopaque, path: []const u8) route.Serving {
        say(
            ctx,
            "links {s}",
            .{path},
        );
        return if (me(ctx).linked) .serving else .not_serving;
    }
    fn srcs(ctx: *anyopaque) []const abi.Src {
        say(
            ctx,
            "srcs",
            .{},
        );
        return &abi.test_srcs;
    }
    fn renderPreview(ctx: *anyopaque, markdown: []const u8) abi.Rendered {
        say(
            ctx,
            "preview {s}",
            .{markdown},
        );
        const s = me(ctx);
        if (!s.render_ok) return .failed;
        return .{ .rendered = std.fmt.allocPrint(
            s.alloc,
            "<p>{s}</p>",
            .{markdown},
        ) catch @panic("oom") };
    }
    fn render(ctx: *anyopaque, markdown: []const u8) abi.Rendered {
        say(
            ctx,
            "render {s}",
            .{markdown},
        );
        const s = me(ctx);
        if (!s.render_ok) return .failed;
        return .{ .rendered = std.fmt.allocPrint(
            s.alloc,
            "<p>{s}</p>",
            .{markdown},
        ) catch @panic("oom") };
    }
    /// Every field of the message in Chat.Message's order, so a record laid
    /// out wrong across the seam shows.
    fn indexMessage(
        ctx: *anyopaque,
        dir: []const u8,
        sid: []const u8,
        m: abi.Message,
    ) void {
        say(
            ctx,
            "index {s} {s} {s}|{s}|{s}|{s}|{s}",
            .{
                dir,
                sid,
                m.id,
                m.from,
                m.at,
                m.uid,
                m.markdown,
            },
        );
    }
    fn writeCache(ctx: *anyopaque, path: []const u8, bytes: []const u8) void {
        say(
            ctx,
            "cache {s} {f}",
            .{
                path,
                std.zig.fmtString(bytes),
            },
        );
    }
    fn fanoutFailed(
        ctx: *anyopaque,
        surface: route.Surface,
        member_: []const u8,
        key: []const u8,
        sid: []const u8,
        e: anyerror,
    ) void {
        say(
            ctx,
            "fanout_failed {t} {s} {s} {s} {t}",
            .{
                surface,
                member_,
                key,
                sid,
                e,
            },
        );
    }
};

const steve: abi.Account = .{
    .id = "1",
    .name = .{ .found = "Steve" },
    .kind = .member,
};

/// As expectAct, for an answer whose page is the test's only by its status.
fn expectStatus(
    sub: []const u8,
    channel: bool,
    method: std.http.Method,
    script: Scripted,
    status: u16,
    asked: []const u8,
) !void {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var s = script;
    s.alloc = arena.allocator();
    const got = try decide(
        arena.allocator(),
        sub,
        channel,
        method,
        s.host(),
    );
    if (got != .respond or got.respond.status != status or !std.mem.eql(
        u8,
        s.asked.items,
        asked,
    )) {
        std.debug.print("{s}: got {f} asking \"{s}\", want {d} asking \"{s}\"\n", .{
            sub,
            got,
            s.asked.items,
            status,
            asked,
        });
        return error.TestUnexpectedResult;
    }
}

fn expectAct(
    sub: []const u8,
    channel: bool,
    method: std.http.Method,
    script: Scripted,
    want: Decision,
    asked: []const u8,
) !void {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var s = script;
    s.alloc = arena.allocator();
    const got = try decide(
        arena.allocator(),
        sub,
        channel,
        method,
        s.host(),
    );
    if (!got.eql(want) or !std.mem.eql(
        u8,
        s.asked.items,
        asked,
    )) {
        std.debug.print("{s}: got {f} asking \"{s}\", want {f} asking \"{s}\"\n", .{
            sub,
            got,
            s.asked.items,
            want,
            asked,
        });
        return error.TestUnexpectedResult;
    }
}

/// What /chat asks first: the welcome's aside (metal-vmm QUEUE 279), which
/// finds no welcome pending (QUEUE 283), so reads nothing more.
const welcome_checked = "identify;accounts;aside begin;welcome?;aside end;";

/// What finding DM 1_2's topic Plans asks: the accounts (whether 2 is one,
/// and its name, the title, before the topics, as findTopic read them),
/// the topics (the DM's sessions folder, listed).
const dm_topic = "identify;accounts;presence;list 1_2/sessions;";
/// And channel ops's: its member file, its topics.
const ops_topic = "identify;accounts;presence;read channels/ops.channel;list channels/ops/sessions;";

/// What recording topic `sid` as where the member resumes DM 1_2 asks, both
/// bookmarks missing: the topic last viewed there, then the DM last in,
/// each read and written as a line.
inline fn bookmarked(comptime sid: []const u8) []const u8 {
    return comptime "read users/1/last-sessions/1_2;write users/1/last-sessions/1_2 " ++ sid ++ "\n;read users/1/last-conv;write users/1/last-conv 1_2\n;";
}

/// A frame as the scripted host says a publish of it: Frame.reaction's
/// bytes around the sidecar's `line`, escaped.
fn frameSaid(comptime line: []const u8) []const u8 {
    return std.fmt.comptimePrint(
        "{f}",
        .{std.zig.fmtString("event: reaction\ndata: " ++ line ++ "\n\n")},
    );
}

/// Steve's 👍 on message 3 taken back, at the scripted host's time.
const thumbs_line = "{\"msg\":3,\"uid\":\"1\",\"from\":\"Steve\",\"emoji\":\"\u{1F44D}\",\"on\":false,\"at\":\"2025-10-25T13:46:40Z\"}";
/// A line appended to the sidecar at `path` as the scripted host says it:
/// the sidecar's stat (none there, so no newline first), then the line and
/// its newline, escaped.
fn lineSaid(comptime path: []const u8, comptime line: []const u8) []const u8 {
    @setEvalBranchQuota(200_000);
    return comptime std.fmt.comptimePrint("stat {s};append {s} {f};", .{ path, path, std.zig.fmtString(line ++ "\n") });
}

/// What storing it in DM 1_2's topic Plans asks: the count, the line
/// appended to the sidecar, then its frame on the topic's key.
const stored_thumbs = "stat 1_2/sessions/Plans.md;read_at 1_2/sessions/Plans.count;" ++ lineSaid("1_2/sessions/Plans.reactions.jsonl", thumbs_line) ++ "publish 1_2/Plans " ++ frameSaid(thumbs_line) ++ ";";

test "a topic's reactions, react, pin and unpin are the Roc's: presence, the conversation and topic found, the method, then the work" {
    use(testing.allocator);
    defer @import("roc_abi.zig").deinit();
    const a: Scripted = .{ .alloc = undefined };
    const thumbs = "msg=3&emoji=%F0%9F%91%8D&on=0";
    // Stored: the reactor's name from the accounts the DM was found by, the
    // count, the line appended to the sidecar, then its frame published on
    // the topic's key.
    try expectAct("/c/1_2/Plans/react", false, .POST, blk: {
        var s = a;
        s.body = thumbs;
        break :blk s;
    }, .{ .respond = .{ .status = 204 } }, dm_topic ++ "body;" ++ stored_thumbs);
    // A channel's reactor is asked for by name; message 4 of 3 is none.
    try expectAct("/ops/Plans/react", true, .POST, blk: {
        var s = a;
        s.body = "msg=4&emoji=%F0%9F%91%8D";
        break :blk s;
    }, .{ .respond = .{
        .status = 400,
        .body = "react: no such message\n",
    } }, ops_topic ++ "body;stat channels/ops/sessions/Plans.md;read_at channels/ops/sessions/Plans.count;");
    try expectAct("/ops/Plans/react", true, .POST, blk: {
        var s = a;
        s.body = "msg=0&emoji=%F0%9F%91%8D";
        break :blk s;
    }, .{ .respond = .{
        .status = 400,
        .body = "react: no such message\n",
    } }, ops_topic ++ "body;stat channels/ops/sessions/Plans.md;read_at channels/ops/sessions/Plans.count;");
    // Message 1 is the first; a topic with none has no message 1.
    try expectAct("/ops/Plans/react", true, .POST, blk: {
        var s = a;
        s.body = "msg=1&emoji=%F0%9F%91%8D";
        break :blk s;
    }, .{ .respond = .{ .status = 204 } }, ops_topic ++ "body;stat channels/ops/sessions/Plans.md;read_at channels/ops/sessions/Plans.count;" ++ comptime lineSaid("channels/ops/sessions/Plans.reactions.jsonl", "{\"msg\":1,\"uid\":\"1\",\"from\":\"Steve\",\"emoji\":\"\u{1F44D}\",\"on\":true,\"at\":\"2025-10-25T13:46:40Z\"}") ++ "publish ops/Plans " ++ frameSaid("{\"msg\":1,\"uid\":\"1\",\"from\":\"Steve\",\"emoji\":\"\u{1F44D}\",\"on\":true,\"at\":\"2025-10-25T13:46:40Z\"}") ++ ";");
    try expectAct("/ops/Plans/react", true, .POST, blk: {
        var s = a;
        s.body = "msg=1&emoji=%F0%9F%91%8D";
        s.count = .{ .counted = 0 };
        break :blk s;
    }, .{ .respond = .{
        .status = 400,
        .body = "react: no such message\n",
    } }, ops_topic ++ "body;stat channels/ops/sessions/Plans.md;read_at channels/ops/sessions/Plans.count;");
    // **A COUNT THAT FAILED IS NO ANSWER**: nothing stored, nothing sent.
    try expectAct("/c/1_2/Plans/react", false, .POST, blk: {
        var s = a;
        s.body = thumbs;
        s.count = .failed;
        break :blk s;
    }, .answered, dm_topic ++ "body;stat 1_2/sessions/Plans.md;");
    // **A TORN LINE STAYS ITS OWN LINE**: a sidecar whose last byte is no
    // newline (a stop cut its append short) gets one before the line; one
    // that ends in a newline, or is empty, does not; a last byte that will
    // not read fails the request (ShortRead), nothing stored or sent.
    const reactions = "1_2/sessions/Plans.reactions.jsonl";
    const counted = "body;stat 1_2/sessions/Plans.md;read_at 1_2/sessions/Plans.count;stat " ++ reactions ++ ";";
    const thumbs_frame = comptime "publish 1_2/Plans " ++ frameSaid(thumbs_line) ++ ";";
    try expectAct("/c/1_2/Plans/react", false, .POST, blk: {
        var s = a;
        s.body = thumbs;
        s.sidecar = "{\"msg\":1,\"fr";
        break :blk s;
    }, .{ .respond = .{ .status = 204 } }, dm_topic ++ counted ++ "read_at " ++ reactions ++ ";" ++ comptime std.fmt.comptimePrint("append {s} {f};", .{ reactions, std.zig.fmtString("\n" ++ thumbs_line ++ "\n") }) ++ thumbs_frame);
    try expectAct("/c/1_2/Plans/react", false, .POST, blk: {
        var s = a;
        s.body = thumbs;
        s.sidecar = "{\"msg\":1}\n";
        break :blk s;
    }, .{ .respond = .{ .status = 204 } }, dm_topic ++ counted ++ "read_at " ++ reactions ++ ";" ++ comptime std.fmt.comptimePrint("append {s} {f};", .{ reactions, std.zig.fmtString(thumbs_line ++ "\n") }) ++ thumbs_frame);
    try expectAct("/c/1_2/Plans/react", false, .POST, blk: {
        var s = a;
        s.body = thumbs;
        s.sidecar = "";
        break :blk s;
    }, .{ .respond = .{ .status = 204 } }, dm_topic ++ counted ++ comptime std.fmt.comptimePrint("append {s} {f};", .{ reactions, std.zig.fmtString(thumbs_line ++ "\n") }) ++ thumbs_frame);
    try expectAct("/c/1_2/Plans/react", false, .POST, blk: {
        var s = a;
        s.body = thumbs;
        s.sidecar = "{\"msg\":1}\n";
        s.sidecar_unread = true;
        break :blk s;
    }, .answered, dm_topic ++ counted ++ "read_at " ++ reactions ++ ";fail ShortRead;");
    // **A LINE NOT STORED IS NEVER SENT**: no publish after a failed append.
    try expectAct("/c/1_2/Plans/react", false, .POST, blk: {
        var s = a;
        s.body = thumbs;
        s.append_line_ok = false;
        break :blk s;
    }, .answered, dm_topic ++ "body;stat 1_2/sessions/Plans.md;read_at 1_2/sessions/Plans.count;" ++ comptime lineSaid("1_2/sessions/Plans.reactions.jsonl", thumbs_line));
    // The reactor's name that will not read: the request fails with it, and
    // nothing is counted, stored or sent.
    try expectAct("/ops/Plans/react", true, .POST, blk: {
        var s = a;
        s.body = thumbs;
        s.accounts = &.{ .{
            .id = "1",
            .name = .unreadable,
            .kind = .member,
        }, .{
            .id = "2",
            .name = .{ .found = "Debbie" },
            .kind = .member,
        } };
        break :blk s;
    }, .answered, ops_topic ++ "body;fail name 1;");
    try expectAct("/ops/Plans/react", true, .POST, blk: {
        var s = a;
        s.body = thumbs;
        s.accounts = null;
        break :blk s;
    }, .answered, "identify;accounts;");
    // The form judged before the store is asked.
    try expectAct("/c/1_2/Plans/react", false, .POST, blk: {
        var s = a;
        s.body = "msg=x&emoji=%F0%9F%91%8D";
        break :blk s;
    }, .{ .respond = .{
        .status = 400,
        .body = "react: msg must be a message number\n",
    } }, dm_topic ++ "body;");
    try expectAct("/c/1_2/Plans/react", false, .POST, blk: {
        var s = a;
        s.body = "msg=1&emoji=a";
        break :blk s;
    }, .{ .respond = .{
        .status = 400,
        .body = "react: emoji must be one glyph\n",
    } }, dm_topic ++ "body;");
    // A field that is not UTF-8 (a torn emoji) is a malformed form at the door.
    try expectAct("/c/1_2/Plans/react", false, .POST, blk: {
        var s = a;
        s.body = "msg=1&emoji=%F0";
        break :blk s;
    }, .malformed_form, dm_topic ++ "body;");
    try expectAct("/c/1_2/Plans/react", false, .POST, blk: {
        var s = a;
        s.body = "msg=1&msg=2&emoji=%F0%9F%91%8D";
        break :blk s;
    }, .malformed_form, dm_topic ++ "body;");
    // The host answered (too big) or failed: nothing more.
    try expectAct("/c/1_2/Plans/react", false, .POST, blk: {
        var s = a;
        s.body = null;
        break :blk s;
    }, .answered, dm_topic ++ "body;");
    // The method after the topic, before the body.
    try expectAct(
        "/c/1_2/Plans/react",
        false,
        .GET,
        a,
        .{ .not_allowed = .POST },
        dm_topic,
    );
    try expectAct(
        "/c/1_2/Plans/reactions",
        false,
        .HEAD,
        a,
        .{ .not_allowed = .GET },
        dm_topic,
    );
    // The sidecar is the Roc's file: as stored, none yet (readReactions's
    // "": no events), or a read that failed (the host's 500).
    const sidecar = "1_2/sessions/Plans.reactions.jsonl";
    const ndjson = "application/x-ndjson; charset=utf-8";
    try expectAct("/c/1_2/Plans/reactions", false, .GET, blk: {
        var s = a;
        s.files = &.{.{ .path = sidecar, .read = .{ .found = "{\"msg\":1}\n" } }};
        break :blk s;
    }, .{ .respond = .{
        .status = 200,
        .content_type = ndjson,
        .body = "{\"msg\":1}\n",
    } }, dm_topic ++ "read " ++ sidecar ++ ";");
    try expectAct(
        "/c/1_2/Plans/reactions",
        false,
        .GET,
        a,
        .{ .respond = .{
            .status = 200,
            .content_type = ndjson,
            .body = "",
        } },
        dm_topic ++ "read " ++ sidecar ++ ";",
    );
    try expectAct("/c/1_2/Plans/reactions", false, .GET, blk: {
        var s = a;
        s.files = &.{.{ .path = sidecar, .read = .failed }};
        break :blk s;
    }, .answered, dm_topic ++ "read " ++ sidecar ++ ";");
    // Text with `é` and an emoji is served as stored; **SO ARE BYTES THAT
    // ARE NOT UTF-8** (metal-vmm QUEUE 267): a line torn mid-emoji is the
    // client's to drop, as the Zig's was, never a 500 for good.
    try expectAct("/c/1_2/Plans/reactions", false, .GET, blk: {
        var s = a;
        s.files = &.{.{
            .path = sidecar,
            .read = .{ .found = "{\"emoji\":\"caf\xc3\xa9 \xf0\x9f\x91\x8d\"}\n" },
        }};
        break :blk s;
    }, .{ .respond = .{
        .status = 200,
        .content_type = ndjson,
        .body = "{\"emoji\":\"caf\xc3\xa9 \xf0\x9f\x91\x8d\"}\n",
    } }, dm_topic ++ "read " ++ sidecar ++ ";");
    try expectAct("/c/1_2/Plans/reactions", false, .GET, blk: {
        var s = a;
        s.files = &.{.{ .path = sidecar, .read = .{ .found = "{\"msg\":1}\xff\n" } }};
        break :blk s;
    }, .{ .respond = .{
        .status = 200,
        .content_type = ndjson,
        .body = "{\"msg\":1}\xff\n",
    } }, dm_topic ++ "read " ++ sidecar ++ ";");
    try expectAct(
        "/ops/Plans/reactions",
        true,
        .GET,
        a,
        .{ .respond = .{
            .status = 200,
            .content_type = ndjson,
            .body = "",
        } },
        ops_topic ++ "read channels/ops/sessions/Plans.reactions.jsonl;",
    );
    // The set is the Roc's (ChatState.pinned), and its file's name: read,
    // changed, written back sorted by bytes, or removed when emptied. A
    // missing file is no pins.
    const pins = "users/1/pinned-sessions/1_2";
    try expectAct(
        "/c/1_2/Plans/pin",
        false,
        .POST,
        a,
        .{ .respond = .{ .status = 204 } },
        dm_topic ++ "read " ++ pins ++ ";write " ++ pins ++ " Plans\n;",
    );
    try expectAct("/c/1_2/Plans/pin", false, .POST, blk: {
        var s = a;
        s.files = &.{.{ .path = pins, .read = .{ .found = "b\r\n  a\n\nPlans\n" } }};
        break :blk s;
    }, .{ .respond = .{ .status = 204 } }, dm_topic ++ "read " ++ pins ++ ";write " ++ pins ++ " Plans\na\nb\n;");
    try expectAct(
        "/ops/Plans/unpin",
        true,
        .POST,
        a,
        .{ .respond = .{ .status = 204 } },
        ops_topic ++ "read users/1/pinned-sessions/ops;remove users/1/pinned-sessions/ops;",
    );
    try expectAct("/c/1_2/Plans/unpin", false, .POST, blk: {
        var s = a;
        s.files = &.{.{ .path = pins, .read = .{ .found = "Other\nPlans\n" } }};
        s.write_ok = false;
        break :blk s;
    }, .answered, dm_topic ++ "read " ++ pins ++ ";write " ++ pins ++ " Other\n;");
    // **A SET THAT WILL NOT READ IS NOT AN EMPTY SET**: a failed read (a
    // pins file that is a folder) writes nothing, where a missing one
    // would have written the pin alone.
    try expectAct("/c/1_2/Plans/pin", false, .POST, blk: {
        var s = a;
        s.files = &.{.{ .path = pins, .read = .failed }};
        break :blk s;
    }, .answered, dm_topic ++ "read " ++ pins ++ ";");
    try expectAct("/ops/Plans/unpin", true, .POST, blk: {
        var s = a;
        s.files = &.{.{ .path = "users/1/pinned-sessions/ops", .read = .failed }};
        break :blk s;
    }, .answered, ops_topic ++ "read users/1/pinned-sessions/ops;");
    try expectAct(
        "/c/1_2/Plans/pin",
        false,
        .PUT,
        a,
        .{ .not_allowed = .POST },
        dm_topic,
    );
    // A topic found without case.
    try expectAct(
        "/c/1_2/plans/pin",
        false,
        .PUT,
        a,
        .{ .not_allowed = .POST },
        dm_topic,
    );
    // A topic that is not there: the Roc's 404 that says so (metal-vmm
    // QUEUE 271), the viewer's name and the scripts read for the page. A
    // DM that is not the member's: webbox's plain 404.
    try expectStatus(
        "/c/1_2/Gone/react",
        false,
        .POST,
        a,
        404,
        dm_topic ++ "srcs;",
    );
    try expectAct("/c/1_2/Gone/react", false, .POST, blk: {
        var s = a;
        s.accounts = &.{steve};
        break :blk s;
    }, .not_found, "identify;accounts;presence;");
    // An upload's POST (metal-vmm QUEUE 292): the form read, then the
    // Roc's every decision; a name no upload has is the Roc's own 404
    // (QUEUE 291); a stream counts no presence.
    try expectAct(
        "/c/1_2/Plans/upload",
        false,
        .POST,
        a,
        .answered,
        dm_topic ++ "read_upload;refuse_upload malformed no file\n;",
    );
    try expectAct("/c/1_2/Plans/upload", false, .GET, a, .{ .not_allowed = .POST }, dm_topic);
    try expectAct("/c/1_2/Plans/upload", false, .POST, blk: {
        var s = a;
        s.upload = .unsupported;
        break :blk s;
    }, .{ .respond = .{
        .status = 415,
        .body = "unsupported file type (images: png, jpeg, gif, webp; video: mp4, webm, mov)\n",
    } }, dm_topic ++ "read_upload;");
    const png: abi.UploadRead = .{ .read = .{ .size = 62, .ext = "png", .filename = "a.png" } };
    try expectAct("/c/1_2/Plans/upload", false, .POST, blk: {
        var s = a;
        s.upload = .{ .read = .{ .size = 10 * 1024 * 1024 + 1, .ext = "png", .filename = "a.png" } };
        break :blk s;
    }, .answered, dm_topic ++ "read_upload;refuse_upload too_large Image too large — the limit is 10 MB.\n;");
    try expectAct("/c/1_2/Plans/upload", false, .POST, blk: {
        var s = a;
        s.upload = png;
        s.reservation = .refused;
        break :blk s;
    }, .{ .respond = .{
        .status = 403,
        .body = "Upload limit reached — you've used your 1 GB upload allowance.\n",
    } }, dm_topic ++ "read_upload;reserve_upload 62;");
    try expectAct(
        "/c/1_2/Plans/uploads/a.png",
        false,
        .GET,
        a,
        .not_found,
        dm_topic,
    );
    try expectAct(
        "/c/1_2/Plans/stream",
        false,
        .GET,
        a,
        .{ .stream = .{
            .key = "1_2/Plans",
            .backlog = "event: backlog-size\ndata: 0\n\n",
        } },
        "identify;accounts;list 1_2/sessions;header last-event-id;query since;read 1_2/sessions/Plans.md;",
    );
    // Its backlog the Roc's: a refused block counted, a message's number
    // from its id, its markdown rendered, its frame laid out.
    try expectAct("/c/1_2/Plans/stream", false, .GET, blk: {
        var s = a;
        s.files = &.{.{ .path = "1_2/sessions/Plans.md", .read = .{ .found = "from: x\n\nrefused\n\n-------------\nMSG_Plans_2\nfrom: S\ndate: d\n\nhi" } }};
        break :blk s;
    }, .{ .stream = .{
        .key = "1_2/Plans",
        .backlog = "event: backlog-size\ndata: 1\n\nid: 1\ndata: {\"index\":1,\"from\":\"S\",\"at\":\"d\",\"html\":\"<p>hi</p>\",\"markdown\":\"hi\",\"id\":\"Plans_2\"}\n\n",
    } }, "identify;accounts;list 1_2/sessions;header last-event-id;query since;read 1_2/sessions/Plans.md;refused from: x;render hi;");
    try expectAct("/ops/Plans/upload", true, .POST, blk: {
        var s = a;
        s.upload = .{ .read = .{ .size = 62, .ext = "png", .filename = "a.png" } };
        break :blk s;
    }, .{ .respond = .{
        .status = 200,
        .content_type = "application/json; charset=utf-8",
        .body = "{\"url\":\"/channel/ops/Plans/uploads/0123.png\",\"name\":\"a.png\",\"kind\":\"image\",\"width\":0,\"height\":0}",
    } }, ops_topic ++ "read_upload;reserve_upload 62;store_upload channels/ops/sessions/Plans.uploads png;");
    try expectAct(
        "/ops/Plans/nope",
        true,
        .GET,
        a,
        .not_found,
        ops_topic,
    );
    // Not one of the pair, a pair not canonical: no account asked.
    try expectAct(
        "/c/2_3/Plans/react",
        false,
        .POST,
        a,
        .not_found,
        "identify;accounts;presence;",
    );
    try expectAct(
        "/c/2_1/Plans/react",
        false,
        .POST,
        a,
        .not_found,
        "identify;accounts;presence;",
    );
    try expectStatus(
        "/dev/Plans/pin",
        true,
        .POST,
        a,
        404,
        "identify;accounts;presence;read channels/dev.channel;srcs;",
    );
}

/// What DM 1_2's page asks once its bookmark is recorded (its accounts known
/// since the DM was found), Debbie the only other member: the roster's
/// presence, the member's channels, their pins there, the scripts.
const dm_page = "online 2;list channels;read channels/ops.channel;read users/1/pinned-sessions/1_2;srcs;";

/// The page `sub` served from `script`: what it asked, and its body. One
/// not served (a 200) fails the test.
fn served(
    arena: std.mem.Allocator,
    sub: []const u8,
    channel: bool,
    script: Scripted,
) !struct { asked: []const u8, body: []const u8 } {
    var s = script;
    s.alloc = arena;
    const got = try decide(
        arena,
        sub,
        channel,
        .GET,
        s.host(),
    );
    if (got != .respond or got.respond.status != 200) {
        std.debug.print("{s}: got {f} asking \"{s}\", want a page\n", .{
            sub,
            got,
            s.asked.items,
        });
        return error.TestUnexpectedResult;
    }
    return .{ .asked = s.asked.items, .body = got.respond.body };
}

test "a DM's page and landing, and the DM with yourself: the title the Roc's, a page's bookmark before its sidebar" {
    use(testing.allocator);
    defer @import("roc_abi.zig").deinit();
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a: Scripted = .{ .alloc = undefined };
    // A page: the bookmark first, then the sidebar as sidebarOf read it.
    try testing.expectEqualStrings(dm_topic ++ bookmarked("Plans") ++ dm_page, (try served(
        arena.allocator(),
        "/c/1_2/Plans",
        false,
        a,
    )).asked);
    try expectAct("/c/1_2/Plans", false, .GET, blk: {
        var s = a;
        s.write_ok = false;
        break :blk s;
    }, .answered, dm_topic ++ "read users/1/last-sessions/1_2;write users/1/last-sessions/1_2 Plans\n;");
    // A channel's page moves no bookmark; its accounts are asked for the
    // viewer and the roster.
    try testing.expectEqualStrings(ops_topic ++ "online 2;list channels;read channels/ops.channel;read users/1/pinned-sessions/ops;srcs;", (try served(
        arena.allocator(),
        "/ops/Plans",
        true,
        a,
    )).asked);
    // The landing: the first topic, or the page offering one, titled by the
    // partner's id when the account has no name.
    try expectAct(
        "/c/1_2",
        false,
        .GET,
        a,
        .{ .redirect = "/chat/c/1_2/Plans" },
        "identify;accounts;presence;list 1_2/sessions;",
    );
    var s: Scripted = .{
        .alloc = arena.allocator(),
        .topics = &.{},
        .accounts = &.{ steve, .{
            .id = "2",
            .name = .{ .found = "" },
            .kind = .guest,
        } },
    };
    const got = try decide(
        arena.allocator(),
        "/c/1_2",
        false,
        .GET,
        s.host(),
    );
    try testing.expectEqualStrings(
        "identify;accounts;presence;list 1_2/sessions;srcs;",
        s.asked.items,
    );
    try testing.expect(std.mem.indexOf(
        u8,
        got.respond.body,
        "Chat w/2",
    ) != null);
    // The DM with yourself: one member, its partner yourself.
    try expectAct(
        "/c/1_1/Plans/reactions",
        false,
        .GET,
        a,
        .{ .respond = .{
            .status = 200,
            .content_type = "application/x-ndjson; charset=utf-8",
            .body = "",
        } },
        "identify;accounts;presence;list 1_1/sessions;read 1_1/sessions/Plans.reactions.jsonl;",
    );
}

test "a page's sidebar is the Roc's (sidebarOf): the roster but the viewer, each beside its own presence; the channels; the pins, stale ones dropped; the limits the Roc's; and a read that fails serves no page" {
    use(testing.allocator);
    defer @import("roc_abi.zig").deinit();
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    // Steve views; Debbie, Ann and the agent Claude are the roster (by
    // numeric id, never the guest), only Ann seen lately.
    const all = [_]abi.Account{
        .{
            .id = "5",
            .name = .{ .found = "Claude" },
            .kind = .agent,
        },
        steve,
        .{
            .id = "3",
            .name = .{ .found = "Ann" },
            .kind = .member,
        },
        .{
            .id = "2",
            .name = .{ .found = "Debbie" },
            .kind = .member,
        },
        .{
            .id = "4",
            .name = .{ .found = "Guest" },
            .kind = .guest,
        },
    };
    const pins = "users/1/pinned-sessions/1_2";
    const a: Scripted = .{
        .alloc = undefined,
        .accounts = &all,
        .online_ids = &.{"3"},
        .topics = &.{ "Plans", "Other" },
        .files = &.{.{ .path = pins, .read = .{ .found = "Stale\nPlans\n" } }},
    };
    const p = try served(
        arena.allocator(),
        "/c/1_2/Plans",
        false,
        a,
    );
    // **ONE ASKING FOR THE WHOLE ROSTER**, its ids in the roster's order.
    try testing.expectEqualStrings(
        dm_topic ++ bookmarked("Plans") ++ "online 2;online 3;online 5;list channels;read channels/ops.channel;read " ++ pins ++ ";srcs;",
        p.asked,
    );
    const conversations =
        "{\"conversations\":[{\"id\":\"uid:2\",\"label\":\"Debbie\",\"url\":\"/chat/c/1_2\",\"active\":true}," ++
        "{\"id\":\"uid:3\",\"label\":\"Ann\",\"url\":\"/chat/c/1_3\",\"active\":false,\"online\":true}," ++
        "{\"id\":\"uid:5\",\"label\":\"Claude\",\"url\":\"/chat/c/1_5\",\"active\":false}," ++
        "{\"id\":\"ch:ops\",\"label\":\"# ops\",\"url\":\"/channel/ops\",\"active\":false}]," ++
        "\"pinned_sessions\":[{\"id\":\"Plans\",\"label\":\"Plans\",\"url\":\"/chat/c/1_2/Plans\",\"active\":true}]," ++
        "\"topics\":[{\"id\":\"Other\",\"label\":\"Other\",\"url\":\"/chat/c/1_2/Other\",\"active\":false}]}";
    for ([_][]const u8{
        conversations,
        "data-upload-image-max=\"10485760\" data-upload-video-max=\"104857600\" data-upload-accept=\"image/png,image/jpeg,image/gif,image/webp,video/mp4,video/webm,video/quicktime\" data-search-min=\"2\"",
    }) |want| if (std.mem.indexOf(
        u8,
        p.body,
        want,
    ) == null) {
        std.debug.print("not in the page: {s}\nin: {s}\n", .{ want, p.body });
        return error.TestUnexpectedResult;
    };
    // A malformed channel is skipped and counted; the page is served.
    const m = try served(arena.allocator(), "/c/1_2/Plans", false, blk: {
        var s = a;
        s.channels = &.{
            .{ .name = "bad", .read = .{ .found = "x\n" } },
            .{ .name = "ops", .read = .{ .found = "1\n" } },
        };
        break :blk s;
    });
    try testing.expect(std.mem.indexOf(
        u8,
        m.asked,
        "list channels;read channels/bad.channel;malformed bad;read channels/ops.channel;",
    ) != null);
    // **A READ THAT FAILED SERVES NO PAGE**, and nothing after it is asked:
    // the pins (a folder: never no pins), a member file, the roster's
    // account, the viewer's own name (a channel's, asked for the page).
    try expectAct("/c/1_2/Plans", false, .GET, blk: {
        var s = a;
        s.files = &.{.{ .path = pins, .read = .failed }};
        break :blk s;
    }, .answered, dm_topic ++ bookmarked("Plans") ++ "online 2;online 3;online 5;list channels;read channels/ops.channel;read " ++ pins ++ ";");
    try expectAct("/c/1_2/Plans", false, .GET, blk: {
        var s = a;
        s.channels = &.{.{ .name = "ops", .read = .failed }};
        break :blk s;
    }, .answered, dm_topic ++ bookmarked("Plans") ++ "online 2;online 3;online 5;list channels;read channels/ops.channel;");
    const ann_unnamed = [_]abi.Account{
        steve,
        .{
            .id = "2",
            .name = .{ .found = "Debbie" },
            .kind = .member,
        },
        .{
            .id = "3",
            .name = .unreadable,
            .kind = .member,
        },
    };
    try expectAct("/c/1_2/Plans", false, .GET, blk: {
        var s = a;
        s.accounts = &ann_unnamed;
        break :blk s;
    }, .answered, dm_topic ++ bookmarked("Plans") ++ "fail name 3;");
    const me_unnamed = [_]abi.Account{ .{
        .id = "1",
        .name = .unreadable,
        .kind = .member,
    }, .{
        .id = "3",
        .name = .unreadable,
        .kind = .member,
    } };
    try expectAct("/ops/Plans", true, .GET, blk: {
        var s = a;
        s.accounts = &me_unnamed;
        break :blk s;
    }, .answered, ops_topic ++ "fail name 1;");
}

/// What storing a message asks, step by step: message 4 (index 3, the
/// scripted count) of topic `sid` in `conv` (`dm ...` for a DM, else a
/// channel), the conversation's key `key`, by member 1 named `name`, at the scripted
/// time. The count, the render, the parts, the store (the block escaped, then
/// the message's fields), the frame on the topic's key, then the fan-out
/// (`fanned`: DM 1_2's or channel ops's members).
const Sent = struct {
    count: []const u8,
    render: []const u8,
    /// The append alone: what a send whose append fails asks.
    append: []const u8,
    /// The append, the count and the index (metal-vmm QUEUE 287).
    store: []const u8,
    publish: []const u8,
    fan_out: []const u8,
};

fn sent(
    comptime conv: []const u8,
    comptime key: []const u8,
    comptime sid: []const u8,
    comptime name: []const u8,
    comptime md: []const u8,
    comptime cid: []const u8,
) Sent {
    const at = "2025-10-25T13:46:40Z";
    const id = sid ++ "_4";
    const block = "\n\n-------------\nMSG_" ++ id ++ "\nfrom: " ++ name ++ "\ndate: " ++ at ++ "\nuid: 1\n\n" ++ md;
    const frame = "id: 3\ndata: {\"index\":3,\"from\":\"" ++ name ++ "\",\"from_uid\":\"1\",\"at\":\"" ++ at ++ "\",\"html\":\"<p>" ++ md ++ "</p>\",\"markdown\":\"" ++ md ++ "\",\"id\":\"" ++ id ++ "\"" ++ (if (cid.len == 0) "" else ",\"cid\":\"" ++ cid ++ "\"") ++ "}\n\n";
    const message = id ++ "|" ++ name ++ "|" ++ at ++ "|1|" ++ md;
    // The conversation's folder: a DM's key, a channel's channels/<key>.
    const dir = if (std.mem.startsWith(
        u8,
        conv,
        "dm ",
    )) key else "channels/" ++ key;
    const appended = std.fmt.comptimePrint("append {s}/sessions/{s}.md {f};", .{
        dir,
        sid,
        std.zig.fmtString(block),
    });
    return comptime .{
        .append = appended,
        .count = "stat " ++ dir ++ "/sessions/" ++ sid ++ ".md;read_at " ++ dir ++ "/sessions/" ++ sid ++ ".count;",
        .render = "render " ++ md ++ ";",
        // The append, then the count the Roc writes (metal-vmm QUEUE 287:
        // 4 messages, the transcript's 100 bytes and the block, the block
        // at 100 by member 1), then the index, told the folder.
        .store = std.fmt.comptimePrint("{s}cache {s}/sessions/{s}.count 4 {d}\\n100 1\\n;index {s} {s} {s};", .{
            appended,
            dir,
            sid,
            100 + block.len,
            dir,
            sid,
            message,
        }),
        .publish = std.fmt.comptimePrint("publish {s}/{s} {f};", .{
            key,
            sid,
            std.zig.fmtString(frame),
        }),
        // A plain word is its own excerpt.
        .fan_out = fanned(
            key,
            sid,
            name,
            md,
        ),
    };
}

/// The whole of a message stored and sent.
fn sentAll(comptime s: Sent) []const u8 {
    return comptime s.count ++ s.render ++ s.store ++ s.publish ++ s.fan_out;
}

const at_said = "2025-10-25T13:46:40Z";

/// A publish as the scripted host says it: the key, the bytes escaped.
fn published(comptime key: []const u8, comptime bytes: []const u8) []const u8 {
    @setEvalBranchQuota(200_000);
    return comptime std.fmt.comptimePrint("publish {s} {f};", .{ key, std.zig.fmtString(bytes) });
}

/// Member `uid`'s Recent row of topic `sid` (its page `url`), by `who`,
/// labelled `where`, its excerpt `ex` (the Roc's, of the message).
fn recentSaid(
    comptime uid: []const u8,
    comptime url: []const u8,
    comptime who: []const u8,
    comptime where: []const u8,
    comptime sid: []const u8,
    comptime dm: bool,
    comptime ex: []const u8,
) []const u8 {
    return published(
        "rec:" ++ uid,
        "{\"kind\":\"chat\",\"at\":\"" ++ at_said ++ "\",\"url\":\"" ++ url ++ "\",\"who\":\"" ++ who ++ "\"" ++ (if (where.len == 0) "" else ",\"where\":\"" ++ where ++ "\"") ++ ",\"topic\":\"" ++ sid ++ "\",\"excerpt\":\"" ++ ex ++ "\"" ++ (if (dm) ",\"dm\":true" else "") ++ "}",
    );
}

/// The fan-out in DM `key` of member 1 and `partner`, by member 1 named
/// `name`: 1's row labelled `to_partner`, then the partner's notify and row,
/// each row's excerpt `ex`.
fn dmFanned(
    comptime key: []const u8,
    comptime partner: []const u8,
    comptime sid: []const u8,
    comptime name: []const u8,
    comptime to_partner: []const u8,
    comptime ex: []const u8,
) []const u8 {
    const url = "/chat/c/" ++ key ++ "/" ++ sid;
    return comptime recentSaid(
        "1",
        url,
        "You",
        to_partner,
        sid,
        true,
        ex,
    ) ++ notifySaid(
        partner,
        key,
        sid,
        name ++ " sent you a message on " ++ sid ++ ".",
        url,
    ) ++ recentSaid(
        partner,
        url,
        name,
        "to Steve",
        sid,
        true,
        ex,
    );
}

/// Member `uid`'s notify of topic `sid` in `key`.
fn notifySaid(
    comptime uid: []const u8,
    comptime key: []const u8,
    comptime sid: []const u8,
    comptime text: []const u8,
    comptime url: []const u8,
) []const u8 {
    return published(
        "ntf:" ++ uid,
        "{\"conv\":\"" ++ key ++ "\",\"session\":\"" ++ sid ++ "\",\"text\":\"" ++ text ++ "\",\"link_url\":\"" ++ url ++ "\"}",
    );
}

/// Member `uid`'s sidebar told of topic `sid` in `key`, its first message.
fn addedSaid(
    comptime uid: []const u8,
    comptime key: []const u8,
    comptime sid: []const u8,
    comptime url: []const u8,
) []const u8 {
    return published(
        "sb:" ++ uid,
        "{\"kind\":\"topic-added\",\"conv\":\"" ++ key ++ "\",\"sid\":\"" ++ sid ++ "\",\"url\":\"" ++ url ++ "\"}",
    );
}

/// The fan-out of a message (not a topic's first, no feed parts) by member
/// 1 named `name`: DM 1_2's members (1, then 2, each named for the other:
/// "to Debbie", "to Steve") or channel ops's (1, then 3, "in ops"). Each
/// member's notify (never the author's), then their Recent row (the
/// author's "You"), each row's excerpt `ex`.
fn fanned(
    comptime key: []const u8,
    comptime sid: []const u8,
    comptime name: []const u8,
    comptime ex: []const u8,
) []const u8 {
    comptime {
        if (std.mem.eql(
            u8,
            key,
            "1_2",
        )) return dmFanned(
            key,
            "2",
            sid,
            name,
            "to Debbie",
            ex,
        );
        // The scripted guest 4, named Guest.
        if (std.mem.eql(
            u8,
            key,
            "1_4",
        )) return dmFanned(
            key,
            "4",
            sid,
            name,
            "to Guest",
            ex,
        );
        const url = "/channel/ops/" ++ sid;
        return recentSaid(
            "1",
            url,
            "You",
            "in ops",
            sid,
            false,
            ex,
        ) ++ notifySaid(
            "3",
            key,
            sid,
            name ++ " posted to ops > " ++ sid ++ ".",
            url,
        ) ++ recentSaid(
            "3",
            url,
            name,
            "in ops",
            sid,
            false,
            ex,
        );
    }
}

const dm_said = "dm 1_2 /chat/c/1_2 [1,2]";

test "a message is the Roc's: no author, no message; the count, the id, the stamp, the block and the frame made before the store; then the store, the publish and the fan-out, in that order; nothing after a step that failed" {
    use(testing.allocator);
    defer @import("roc_abi.zig").deinit();
    const a: Scripted = .{ .alloc = undefined, .body = "markdown=hi&cid=c-1" };
    const before = "identify;accounts;presence;header x-chat-async;body;hostile hi;" ++ bookmarked("Plans");
    const plans = comptime sent(
        dm_said,
        "1_2",
        "Plans",
        "Steve",
        "hi",
        "c-1",
    );
    try expectAct(
        "/c/1_2/Plans/send",
        false,
        .POST,
        a,
        .{ .redirect = "/chat/c/1_2/Plans" },
        before ++ comptime sentAll(plans),
    );
    // **NO AUTHOR, NO MESSAGE**: the member's name empty fails the request
    // with appendMessage's error, nothing counted, stored or sent.
    try expectAct("/c/1_2/Plans/send", false, .POST, blk: {
        var s = a;
        s.accounts = &.{ .{
            .id = "1",
            .name = .{ .found = "" },
            .kind = .member,
        }, .{
            .id = "2",
            .name = .{ .found = "Debbie" },
            .kind = .member,
        } };
        break :blk s;
    }, .answered, before ++ "fail NoAuthor;");
    // A count that failed: nothing rendered, stored or sent.
    try expectAct("/c/1_2/Plans/send", false, .POST, blk: {
        var s = a;
        s.count = .failed;
        break :blk s;
    }, .answered, before ++ "stat 1_2/sessions/Plans.md;");
    // **THE FRAME IS MADE BEFORE THE STORE**: a render that failed stores nothing.
    try expectAct("/c/1_2/Plans/send", false, .POST, blk: {
        var s = a;
        s.render_ok = false;
        break :blk s;
    }, .answered, before ++ plans.count ++ plans.render);
    // **A MESSAGE NOT STORED IS NEVER SENT**: no publish, no fan-out.
    try expectAct("/c/1_2/Plans/send", false, .POST, blk: {
        var s = a;
        s.store_ok = false;
        break :blk s;
    }, .answered, before ++ plans.count ++ plans.render ++ plans.append);
    // A topic's first message is index 0: its id `_1`, its block with no
    // separator before it, its frame `id: 0`.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var first = a;
    first.alloc = arena.allocator();
    first.count = .{ .counted = 0 };
    first.body = "markdown=one";
    _ = try decide(
        arena.allocator(),
        "/c/1_2/Plans/send",
        false,
        .POST,
        first.host(),
    );
    const at = "2025-10-25T13:46:40Z";
    for ([_][]const u8{
        "append 1_2/sessions/Plans.md MSG_Plans_1\\nfrom: Steve\\ndate: " ++ at ++ "\\nuid: 1\\n\\none;",
        "index 1_2 Plans Plans_1|Steve|" ++ at ++ "|1|one;",
        "publish 1_2/Plans id: 0\\ndata: {\\\"index\\\":0,",
    }) |want| if (std.mem.indexOf(
        u8,
        first.asked.items,
        want,
    ) == null) {
        std.debug.print("not asked: {s}\nin: {s}\n", .{ want, first.asked.items });
        return error.TestUnexpectedResult;
    };
}

test "the fan-out is the Roc's: every member in order, each member's notify (never the author's), sidebar (a first message alone), recent (\"You\" for the author), images and code; a feed's entry before its event; a surface that fails is counted and said, and nothing else is lost, nor the send" {
    use(testing.allocator);
    defer @import("roc_abi.zig").deinit();
    const url = "/chat/c/1_2/Plans";
    const head = "Sent by Steve at " ++ at_said ++ ", source MSG_Plans_1 in 1_2:";
    // Each feed's entry in an aside of its own: the feed's stat (7 bytes,
    // so the separator first), then the separator and the entry, escaped.
    const img_entry = comptime std.fmt.comptimePrint(
        "{f}",
        .{std.zig.fmtString("\n\n-------------\n\n" ++ head ++ "\n<img a b>\n<IMG\tsrc=/x.png onerror=c>")},
    );
    const code_entry = comptime std.fmt.comptimePrint(
        "{f}",
        .{std.zig.fmtString("\n\n-------------\n\n" ++ head ++ "\n```zig\nx\n```\n\n```\ny\n```")},
    );
    const head_json = "{\"source_id\":\"Plans_1\",\"from\":\"Steve\",\"conv\":\"1_2\",\"at\":\"" ++ at_said ++ "\",";
    const src = ",\"source_url\":\"/chat/c/1_2/Plans#msg-Plans_1\"}";
    // The entry's tag one line, as found; its event's rebuilt by the
    // renderer's rule (SafeImg, metal-vmm QUEUE 266): the one with no
    // same-origin src dropped, the other's onerror gone.
    const img_event = head_json ++ "\"images\":[\"<img src=\\\"/x.png\\\">\"]" ++ src;
    const code_event = head_json ++ "\"blocks\":[{\"lang\":\"zig\",\"body\":\"x\"},{\"lang\":\"\",\"body\":\"y\"}]" ++ src;
    // A topic's first message, with two image tags (one spanning a line)
    // and two code blocks, as the Roc finds them: member 2's images.md will
    // not take its entry.
    const ex = "[image] [image] ```zig x ``` ``` y ```";
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var s: Scripted = .{
        .alloc = arena.allocator(),
        .body = "markdown=<img%20a%0Ab>%20<IMG%09src=/x.png%20onerror=c>%0A```zig%0Ax%0A```%0A```%0Ay%0A```",
        .count = .{ .counted = 0 },
    };
    s.entry_fails = .{ .path = "users/2/images.md", .e = error.IsDir };
    const got = try decide(
        arena.allocator(),
        "/c/1_2/Plans/send",
        false,
        .POST,
        s.host(),
    );
    try testing.expectEqualStrings("/chat/c/1_2/Plans", got.redirect);
    const member1 = comptime addedSaid(
        "1",
        "1_2",
        "Plans",
        url,
    ) ++ recentSaid(
        "1",
        url,
        "You",
        "to Debbie",
        "Plans",
        true,
        ex,
    ) ++
        "aside begin;stat users/1/images.md;append users/1/images.md " ++ img_entry ++ ";aside end;" ++ published("img:1", img_event) ++
        "aside begin;stat users/1/code.md;append users/1/code.md " ++ code_entry ++ ";aside end;" ++ published("code:1", code_event);
    const member2 = comptime notifySaid(
        "2",
        "1_2",
        "Plans",
        "Steve sent you a message on Plans.",
        url,
    ) ++ addedSaid(
        "2",
        "1_2",
        "Plans",
        url,
    ) ++ recentSaid(
        "2",
        url,
        "Steve",
        "to Steve",
        "Plans",
        true,
        ex,
    ) ++
        "aside begin;stat users/2/images.md;append users/2/images.md " ++ img_entry ++ ";aside end;fanout_failed images 2 1_2 Plans IsDir;" ++
        "aside begin;stat users/2/code.md;append users/2/code.md " ++ code_entry ++ ";aside end;" ++ published("code:2", code_event);
    const tail = s.asked.items[std.mem.indexOf(
        u8,
        s.asked.items,
        "publish 1_2/Plans ",
    ).?..];
    const fan = tail[std.mem.indexOfScalar(
        u8,
        tail,
        ';',
    ).? + 1 ..];
    if (!std.mem.eql(
        u8,
        fan,
        member1 ++ member2,
    )) {
        std.debug.print("fan-out:\n  got  {s}\n  want {s}\n", .{ fan, member1 ++ member2 });
        return error.TestUnexpectedResult;
    }

    // The DM with yourself: one member, the author, never notified; the row
    // "to " and no one's name (the old Zig's getUserName of "").
    var arena3 = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena3.deinit();
    var self: Scripted = .{ .alloc = arena3.allocator(), .body = "markdown=one" };
    _ = try decide(
        arena3.allocator(),
        "/c/1_1/Plans/send",
        false,
        .POST,
        self.host(),
    );
    try testing.expect(std.mem.endsWith(
        u8,
        self.asked.items,
        comptime recentSaid(
            "1",
            "/chat/c/1_1/Plans",
            "You",
            "to ",
            "Plans",
            true,
            "one",
        ),
    ));
    try testing.expectEqual(@as(usize, 0), std.mem.count(
        u8,
        self.asked.items,
        "publish ntf:",
    ));
}

test "a send is the Roc's: the conversation, the method, the header, the body, the message judged, the bookmark, then the store" {
    use(testing.allocator);
    defer @import("roc_abi.zig").deinit();
    const a: Scripted = .{ .alloc = undefined, .body = "markdown=hi&cid=c-1" };
    // The accounts are read (the partner's name with them, as the Zig read
    // the title before a send), once.
    const found = "identify;accounts;presence;";
    const asked = found ++ "header x-chat-async;body;";
    try expectAct(
        "/c/1_2/Plans/send",
        false,
        .POST,
        a,
        .{ .redirect = "/chat/c/1_2/Plans" },
        asked ++ "hostile hi;" ++ bookmarked("Plans") ++ comptime sentAll(sent(
            dm_said,
            "1_2",
            "Plans",
            "Steve",
            "hi",
            "c-1",
        )),
    );
    // A channel's send moves no bookmark; an async sender is answered 204.
    try expectAct("/ops/Plans/send", true, .POST, blk: {
        var s = a;
        s.is_async = true;
        break :blk s;
    }, .{ .respond = .{ .status = 204 } }, "identify;accounts;presence;read channels/ops.channel;header x-chat-async;body;hostile hi;" ++ comptime sentAll(sent(
        "channel ops /channel/ops [1,3]",
        "ops",
        "Plans",
        "Steve",
        "hi",
        "c-1",
    )));
    // Hostile, a bookmark or a store that failed: the host answered, and
    // nothing after it is asked.
    try expectAct("/c/1_2/Plans/send", false, .POST, blk: {
        var s = a;
        s.hostile_answer = .refused;
        break :blk s;
    }, .answered, asked ++ "hostile hi;");
    try expectAct("/c/1_2/Plans/send", false, .POST, blk: {
        var s = a;
        s.hostile_answer = .failed;
        break :blk s;
    }, .answered, asked ++ "hostile hi;");
    try expectAct("/c/1_2/Plans/send", false, .POST, blk: {
        var s = a;
        s.write_ok = false;
        break :blk s;
    }, .answered, asked ++ "hostile hi;read users/1/last-sessions/1_2;write users/1/last-sessions/1_2 Plans\n;");
    try expectAct("/c/1_2/Plans/send", false, .POST, blk: {
        var s = a;
        s.store_ok = false;
        break :blk s;
    }, .answered, asked ++ "hostile hi;" ++ bookmarked("Plans") ++ comptime blk: {
        const s = sent(
            dm_said,
            "1_2",
            "Plans",
            "Steve",
            "hi",
            "c-1",
        );
        break :blk s.count ++ s.render ++ s.append;
    });
    // Judged by the Roc before the host is asked to: empty; not UTF-8, which
    // the form's door refuses as malformed.
    try expectAct("/c/1_2/Plans/send", false, .POST, blk: {
        var s = a;
        s.body = "markdown=%20%0A";
        break :blk s;
    }, .{ .respond = .{ .status = 400, .body = "not sent: the message is empty\n" } }, asked);
    try expectAct("/c/1_2/Plans/send", false, .POST, blk: {
        var s = a;
        s.body = "markdown=%FF";
        break :blk s;
    }, .malformed_form, asked);
    // No conversation to send to: the Roc's 404.
    try expectAct("/c/1_2/Plans/send", false, .POST, blk: {
        var s = a;
        s.accounts = &.{steve};
        break :blk s;
    }, .not_found, "identify;accounts;presence;");
    try expectAct(
        "/c/1_2/Plans/send",
        false,
        .GET,
        a,
        .{ .not_allowed = .POST },
        found,
    );
    // A new topic in a DM: the bookmark, the first message, the announcement
    // in its highest general<N>, each with the conversation.
    try expectAct("/c/1_2/new", false, .POST, blk: {
        var s = a;
        s.body = "topic=Ideas";
        s.topics = &.{ "general2", "Plans" };
        break :blk s;
    }, .{ .respond = .{
        .status = 200,
        .content_type = "application/json; charset=utf-8",
        .body = "{\"conv\":\"1_2\",\"sid\":\"Ideas\"}",
    } }, "identify;accounts;presence;body;list 1_2/sessions;" ++ bookmarked("Ideas") ++ comptime sentAll(sent(
        dm_said,
        "1_2",
        "Ideas",
        "Steve",
        "hi",
        "",
    )) ++ "aside begin;list 1_2/sessions;" ++ sentAll(sent(
        dm_said,
        "1_2",
        "general2",
        "Steve",
        "New topic: [Ideas](/chat/c/1_2/Ideas)",
        "",
    )) ++ "aside end;");
    // **STORED IS DONE** (metal-vmm QUEUE 267): the topic is made once its
    // "hi" is stored, so an announcement that fails is the aside's, counted,
    // and the create still its 200, never a 500 whose retry is a 409.
    try expectAct("/c/1_2/new", false, .POST, blk: {
        var s = a;
        s.body = "topic=Ideas";
        s.topics = &.{ "general2", "Plans" };
        s.store_fails_for = "general2";
        s.aside_fails = error.IsDir;
        break :blk s;
    }, .{ .respond = .{
        .status = 200,
        .content_type = "application/json; charset=utf-8",
        .body = "{\"conv\":\"1_2\",\"sid\":\"Ideas\"}",
    } }, "identify;accounts;presence;body;list 1_2/sessions;" ++ bookmarked("Ideas") ++ comptime sentAll(sent(
        dm_said,
        "1_2",
        "Ideas",
        "Steve",
        "hi",
        "",
    )) ++ "aside begin;list 1_2/sessions;" ++ blk: {
        const g = sent(
            dm_said,
            "1_2",
            "general2",
            "Steve",
            "New topic: [Ideas](/chat/c/1_2/Ideas)",
            "",
        );
        break :blk g.count ++ g.render ++ g.append;
    } ++ "aside end;dropped announcement Ideas;");
}

test "a topic's raw transcript and /chat/links are the Roc's: a transcript the host has not is a plain 404, never handed back" {
    use(testing.allocator);
    defer @import("roc_abi.zig").deinit();
    const a: Scripted = .{ .alloc = undefined };
    try expectAct(
        "/c/1_2/Plans/raw",
        false,
        .GET,
        a,
        .{ .held = .{
            .status = 200,
            .content_type = "text/plain; charset=utf-8",
            .nosniff = true,
        } },
        dm_topic ++ "raw 1_2/sessions/Plans.md;",
    );
    // Found as a topic, but the host read no transcript (gone since).
    try expectAct("/c/1_2/Plans/raw", false, .HEAD, blk: {
        var s = a;
        s.transcript = false;
        break :blk s;
    }, .not_found, dm_topic ++ "raw 1_2/sessions/Plans.md;");
    try expectAct(
        "/c/1_2/Plans/raw",
        false,
        .POST,
        a,
        .{ .not_allowed = .GET },
        dm_topic,
    );
    // /chat/links asks the viewer, the scripts, then the page; below it, nothing.
    try expectAct(
        "/links/x",
        false,
        .GET,
        a,
        .not_found,
        "identify;accounts;presence;",
    );
}

test "the member's bookmarks are the Roc's files: the topic last viewed first, then the DM last in, each written only when it changed, and read back to resume" {
    use(testing.allocator);
    defer @import("roc_abi.zig").deinit();
    const a: Scripted = .{ .alloc = undefined };
    const page = dm_page;
    const ls = "users/1/last-sessions/1_2";
    const lc = "users/1/last-conv";
    var pages = std.heap.ArenaAllocator.init(testing.allocator);
    defer pages.deinit();
    // Both already say so, whitespace around them: nothing written.
    try testing.expectEqualStrings(dm_topic ++ "read " ++ ls ++ ";read " ++ lc ++ ";" ++ page, (try served(pages.allocator(), "/c/1_2/Plans", false, blk: {
        var s = a;
        s.files = &.{
            .{ .path = ls, .read = .{ .found = "Plans\r\n" } },
            .{ .path = lc, .read = .{ .found = " \t1_2 \n" } },
        };
        break :blk s;
    })).asked);
    // Only the topic changed; only the DM changed.
    try testing.expectEqualStrings(dm_topic ++ "read " ++ ls ++ ";write " ++ ls ++ " Plans\n;read " ++ lc ++ ";" ++ page, (try served(pages.allocator(), "/c/1_2/Plans", false, blk: {
        var s = a;
        s.files = &.{
            .{ .path = ls, .read = .{ .found = "Other\n" } },
            .{ .path = lc, .read = .{ .found = "1_2" } },
        };
        break :blk s;
    })).asked);
    try testing.expectEqualStrings(dm_topic ++ "read " ++ ls ++ ";read " ++ lc ++ ";write " ++ lc ++ " 1_2\n;" ++ page, (try served(pages.allocator(), "/c/1_2/Plans", false, blk: {
        var s = a;
        s.files = &.{
            .{ .path = ls, .read = .{ .found = "Plans" } },
            .{ .path = lc, .read = .{ .found = "1_3\n" } },
        };
        break :blk s;
    })).asked);
    // A bookmark that will not read is written again (the write says
    // whether it can be: a real host has failed the request already, and
    // answers its "failed" values after: a scripted one goes on).
    try testing.expectEqualStrings(dm_topic ++ "read " ++ ls ++ ";write " ++ ls ++ " Plans\n;read " ++ lc ++ ";" ++ page, (try served(pages.allocator(), "/c/1_2/Plans", false, blk: {
        var s = a;
        s.files = &.{
            .{ .path = ls, .read = .failed },
            .{ .path = lc, .read = .{ .found = "1_2\n" } },
        };
        break :blk s;
    })).asked);
    // /chat reads them back: the DM last in, then where it resumes.
    try expectAct("", false, .GET, blk: {
        var s = a;
        s.topics = &.{ "Other", "Plans" };
        s.files = &.{
            .{ .path = ls, .read = .{ .found = "\tPlans \r\n" } },
            .{ .path = lc, .read = .{ .found = " 1_2\r\n" } },
        };
        break :blk s;
    }, .{ .redirect = "/chat/c/1_2/Plans" }, welcome_checked ++ "presence;read " ++ lc ++ ";list 1_2/sessions;read " ++ ls ++ ";");
    // The feeds are the member's files too, named by the Roc.
    for ([_][2][]const u8{
        .{ "/images", "users/1/images.md" },
        .{ "/code", "users/1/code.md" },
    }) |feed| {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        var s: Scripted = .{ .alloc = arena.allocator() };
        _ = try decide(
            arena.allocator(),
            feed[0],
            false,
            .GET,
            s.host(),
        );
        try testing.expectEqualStrings(try std.fmt.allocPrint(
            arena.allocator(),
            "identify;accounts;presence;read {s};srcs;",
            .{feed[1]},
        ), s.asked.items);
    }
    // **ONE DAMAGED ENTRY IS ITS OWN** (metal-vmm QUEUE 267): an entry torn
    // mid-character is skipped and the feed counted, and the page served
    // with the others; never a 500 for that member for good.
    const head = "Sent by Steve at 2025-10-25T13:46:40Z, source MSG_Plans_{d} in 1_2:\n";
    for ([_][3][]const u8{
        .{
            "/images",
            "users/1/images.md",
            std.fmt.comptimePrint(
                head,
                .{1},
            ) ++ "<img src=\"/a.png\">\n\n-------------\n\n" ++ std.fmt.comptimePrint(
                head,
                .{2},
            ) ++ "<img src=\"/\xf0\x9f.png\">",
        },
        .{
            "/code",
            "users/1/code.md",
            std.fmt.comptimePrint(
                head,
                .{1},
            ) ++ "```\nok\n```\n\n-------------\n\n" ++ std.fmt.comptimePrint(
                head,
                .{2},
            ) ++ "```\n\xff\n```",
        },
    }) |feed| {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        var s: Scripted = .{
            .alloc = arena.allocator(),
            .files = &.{.{ .path = feed[1], .read = .{ .found = feed[2] } }},
        };
        const d = try decide(
            arena.allocator(),
            feed[0],
            false,
            .GET,
            s.host(),
        );
        try testing.expectEqual(@as(u16, 200), d.respond.status);
        try testing.expect(std.mem.indexOf(
            u8,
            d.respond.body,
            "Plans_1",
        ) != null and std.mem.indexOf(
            u8,
            d.respond.body,
            "Plans_2",
        ) == null);
        try testing.expectEqualStrings(try std.fmt.allocPrint(
            arena.allocator(),
            "identify;accounts;presence;read {s};srcs;dropped feed_entry {s};",
            .{ feed[1], feed[1] },
        ), s.asked.items);
    }
}

test "/chat/msg: every channel's roster, which are the member's, and their order, are the Roc's; a malformed one skipped and counted" {
    use(testing.allocator);
    defer @import("roc_abi.zig").deinit();
    // Only the member: no DM to search.
    const a: Scripted = .{ .alloc = undefined, .accounts = &.{steve} };
    // **A MEMBER FILE THAT IS NOT UTF-8 IS MALFORMED** (metal-vmm QUEUE
    // 267): skipped and counted like one, never every member's chat down.
    try expectAct("/msg/Plans_1", false, .GET, blk: {
        var s = a;
        s.channels = &.{
            .{ .name = "bad", .read = .{ .found = "1\n\xff\n" } },
            .{ .name = "ops", .read = .{ .found = "1\n" } },
        };
        break :blk s;
    }, .{ .found = "/channel/ops/Plans#msg-Plans_1" }, "identify;accounts;presence;list channels;read channels/bad.channel;malformed bad;read channels/ops.channel;list channels/ops/sessions;");
    // channels/ listed, each member file read in the listing's order, not
    // sorted: the member is in ops, Zed and a name that sorts high, not in
    // zeta. Every topic list has Plans, so the first of the member's by
    // bytes (`Z` before `o`) is the one.
    const four = "identify;accounts;presence;list channels;read channels/ops.channel;read channels/zeta.channel;read channels/zzhigh.channel;read channels/Zed.channel;";
    try expectAct("/msg/Plans_1", false, .GET, blk: {
        var s = a;
        s.channels = &.{
            .{ .name = "ops", .read = .{ .found = "1\n3\n" } },
            .{ .name = "zeta", .read = .{ .found = "2" } },
            .{ .name = "zzhigh", .read = .{ .found = "1" } },
            .{ .name = "Zed", .read = .{ .found = "# us\r\n 1\t\n" } },
        };
        break :blk s;
    }, .{ .found = "/channel/Zed/Plans#msg-Plans_1" }, four ++ "list channels/Zed/sessions;");
    // In none: nothing to search.
    try expectAct("/msg/Plans_1", false, .GET, blk: {
        var s = a;
        s.channels = &.{
            .{ .name = "zeta", .read = .{ .found = "2" } },
            .{ .name = "ops", .read = .{ .found = "" } },
        };
        break :blk s;
    }, .not_found, "identify;accounts;presence;list channels;read channels/zeta.channel;read channels/ops.channel;");
    // **A MALFORMED CHANNEL IS SKIPPED AND COUNTED** as it is met (Abad
    // would be first by bytes), and so is one whose name is no channel
    // name, never read; one gone since the listing is skipped, uncounted.
    // A name that is not UTF-8 (`\xffhigh`) is counted at the listing's
    // door, before any member file is read: Files.list! refuses it there.
    try expectAct("/msg/Plans_1", false, .GET, blk: {
        var s = a;
        s.channels = &.{
            .{ .name = "Abad", .read = .{ .found = "1\nnot a uid\n" } },
            .{ .name = "Agone", .read = .missing },
            .{ .name = "\xffhigh", .read = .{ .found = "1\n" } },
            .{ .name = "ops", .read = .{ .found = "1\n" } },
            .{ .name = "Adup", .read = .{ .found = "1\n1\n" } },
        };
        break :blk s;
    }, .{ .found = "/channel/ops/Plans#msg-Plans_1" }, "identify;accounts;presence;list channels;malformed \xffhigh;read channels/Abad.channel;malformed Abad;read channels/Agone.channel;read channels/ops.channel;read channels/Adup.channel;malformed Adup;list channels/ops/sessions;");
    // A member file that will not read: nothing past it is read, and no
    // channel searched (the host has failed the request), never "no such
    // topic"; one malformed before it was counted already, as the Zig
    // counted it.
    try expectAct("/msg/Plans_1", false, .GET, blk: {
        var s = a;
        s.channels = &.{
            .{ .name = "Abad", .read = .{ .found = "x\n" } },
            .{ .name = "ops", .read = .failed },
            .{ .name = "Zed", .read = .{ .found = "1\n" } },
        };
        break :blk s;
    }, .answered, "identify;accounts;presence;list channels;read channels/Abad.channel;malformed Abad;read channels/ops.channel;");
}

test "a channel's member file is the Roc's: a malformed one fails its own route by its reason (never the 404 of a channel not the member's); a missing one is no channel" {
    use(testing.allocator);
    defer @import("roc_abi.zig").deinit();
    const a: Scripted = .{ .alloc = undefined };
    for ([_][]const u8{
        "1\n../../x\n",
        "1\n3 # Claude\n",
        "1\n2\n1\n",
        "007\n",
        "+7\n",
    }) |bad| {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        var s = a;
        s.alloc = arena.allocator();
        s.channels = &.{.{ .name = "ops", .read = .{ .found = bad } }};
        _ = try decide(
            arena.allocator(),
            "/ops/Plans",
            true,
            .GET,
            s.host(),
        );
        try testing.expectEqualStrings(
            "identify;accounts;presence;read channels/ops.channel;fail MalformedChannel;",
            s.asked.items,
        );
    }
    try expectStatus(
        "/dev",
        true,
        .GET,
        a,
        404,
        "identify;accounts;presence;read channels/dev.channel;srcs;",
    );
}

test "a conversation's topics are the Roc's: its sessions folder listed, a folder named x.md no topic, and sorted by bytes" {
    use(testing.allocator);
    defer @import("roc_abi.zig").deinit();
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const S = struct {
        fn list(ctx: *anyopaque, path: []const u8) abi.Listing {
            Scripted.say(
                ctx,
                "list {s}",
                .{path},
            );
            return .{ .found = &.{
                .{ .name = "b.md", .kind = .file },
                .{ .name = "x.md", .kind = .dir },
                .{ .name = "a.md", .kind = .other },
                .{ .name = "notes.txt", .kind = .file },
            } };
        }
    };
    var s: Scripted = .{ .alloc = arena.allocator() };
    var h = s.host();
    h.list = S.list;
    // The landing goes to the first by bytes: a link counts, a folder not.
    const got = try decide(
        arena.allocator(),
        "/c/1_2",
        false,
        .GET,
        h,
    );
    try testing.expectEqualStrings("/chat/c/1_2/a", got.redirect);
    try testing.expectEqualStrings("identify;accounts;presence;list 1_2/sessions;", s.asked.items);
}

/// What `sub` asked of a scripted host, `script` as given.
fn askedOf(
    arena: std.mem.Allocator,
    sub: []const u8,
    channel: bool,
    method: std.http.Method,
    script: Scripted,
) ![]const u8 {
    var s = script;
    s.alloc = arena;
    _ = try decide(
        arena,
        sub,
        channel,
        method,
        s.host(),
    );
    return s.asked.items;
}

test "the accounts are asked of the host once a request, at the door: every route looks up in that one listing, and none asks again" {
    use(testing.allocator);
    defer @import("roc_abi.zig").deinit();
    const send: Scripted = .{ .alloc = undefined, .body = "markdown=hi" };
    const Case = struct {
        sub: []const u8,
        channel: bool = false,
        method: std.http.Method = .GET,
        script: Scripted = .{ .alloc = undefined },
        times: usize,
    };
    const cases = [_]Case{
        // A DM: found, titled, its viewer named, all from one asking.
        .{ .sub = "/c/1_2/Plans", .times = 1 },
        .{
            .sub = "/c/1_2",
            .script = .{ .alloc = undefined, .topics = &.{} },
            .times = 1,
        },
        .{
            .sub = "/c/1_2/Plans/send",
            .method = .POST,
            .script = send,
            .times = 1,
        },
        .{
            .sub = "/c/1_2/new",
            .method = .POST,
            .script = .{ .alloc = undefined, .body = "topic=Ideas" },
            .times = 1,
        },
        // A channel: its page (the viewer named, the roster in its sidebar),
        // and a pin, which names no one: the door's one listing.
        .{
            .sub = "/ops/Plans",
            .channel = true,
            .times = 1,
        },
        .{
            .sub = "/ops/Plans/pin",
            .channel = true,
            .method = .POST,
            .times = 1,
        },
        // A reaction names its reactor: a DM's from the accounts it was
        // found by, a channel's asked for it.
        .{
            .sub = "/c/1_2/Plans/react",
            .method = .POST,
            .script = .{ .alloc = undefined, .body = "msg=1&emoji=%F0%9F%91%8D" },
            .times = 1,
        },
        .{
            .sub = "/ops/Plans/react",
            .channel = true,
            .method = .POST,
            .script = .{ .alloc = undefined, .body = "msg=1&emoji=%F0%9F%91%8D" },
            .times = 1,
        },
        .{
            .sub = "/ops",
            .channel = true,
            .script = .{ .alloc = undefined, .topics = &.{} },
            .times = 1,
        },
        .{
            .sub = "/ops/Plans/send",
            .channel = true,
            .method = .POST,
            .script = send,
            .times = 1,
        },
        .{
            .sub = "/ops/new",
            .channel = true,
            .method = .POST,
            .script = .{ .alloc = undefined, .body = "topic=Ideas" },
            .times = 1,
        },
        // The member's own pages, the conversations, a message's topic.
        .{ .sub = "", .times = 1 },
        .{ .sub = "/links", .times = 1 },
        .{ .sub = "/images", .times = 1 },
        .{ .sub = "/conversations", .times = 1 },
        .{ .sub = "/msg/Plans_1", .times = 1 },
    };
    for (cases) |c| {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const asked = try askedOf(
            arena.allocator(),
            c.sub,
            c.channel,
            c.method,
            c.script,
        );
        if (std.mem.count(
            u8,
            asked,
            "accounts;",
        ) != c.times) {
            std.debug.print("{s}: asked \"{s}\", want accounts {d} times\n", .{
                c.sub,
                asked,
                c.times,
            });
            return error.TestUnexpectedResult;
        }
    }
}

test "accounts that will not list fail the request at the door, whatever the route: never a stranger, never \"no such account\" handed back to the Zig, never a viewer named \"\"" {
    use(testing.allocator);
    defer @import("roc_abi.zig").deinit();
    const a: Scripted = .{
        .alloc = undefined,
        .accounts = null,
        .body = "markdown=hi",
    };
    for ([_]struct { []const u8, bool, std.http.Method }{
        .{ "/c/1_2/Plans", false, .GET },
        .{ "/c/1_2/Plans/send", false, .POST },
        .{ "/c/1_2", false, .GET },
        .{ "/ops/Plans/send", true, .POST },
        .{ "/ops/Plans/pin", true, .POST },
        .{ "/links", false, .GET },
        .{ "", false, .GET },
        .{ "/conversations", false, .GET },
        .{ "/msg/Plans_1", false, .GET },
    }) |c| try expectAct(c[0], c[1], c[2], a, .answered, "identify;accounts;");
}

test "the door is the Roc's (Members.admit!): a member or the agent is let in, a guest, an id no account has, one no uid and a stranger are sent to sign in, and a look or a kind that failed fails the request" {
    use(testing.allocator);
    defer @import("roc_abi.zig").deinit();
    const sub = "/ops/Plans/reactions";
    const away: Decision = .{ .to_login = "/channel/ops/Plans/reactions" };
    const in: Decision = .{ .respond = .{
        .status = 200,
        .content_type = "application/x-ndjson; charset=utf-8",
        .body = "",
    } };
    const as = struct {
        fn one(kind: route.AccountKind) [1]abi.Account {
            return .{.{ .id = "1", .name = .{ .found = "Steve" }, .kind = kind }};
        }
    };
    const member = as.one(.member);
    const agent = as.one(.agent);
    const guest = as.one(.guest);
    const unkind = as.one(.unreadable);
    const let_in = "identify;accounts;presence;read channels/ops.channel;list channels/ops/sessions;read channels/ops/sessions/Plans.reactions.jsonl;";
    try expectAct(sub, true, .GET, .{ .alloc = undefined, .accounts = &member }, in, let_in);
    try expectAct(sub, true, .GET, .{ .alloc = undefined, .accounts = &agent }, in, let_in);
    try expectAct(sub, true, .GET, .{ .alloc = undefined, .accounts = &guest }, away, "identify;accounts;");
    try expectAct(sub, true, .GET, .{ .alloc = undefined, .asking = .{ .known = "9" } }, away, "identify;accounts;");
    try expectAct(sub, true, .GET, .{ .alloc = undefined, .asking = .{ .known = "01" } }, away, "identify;accounts;");
    try expectAct(sub, true, .GET, .{ .alloc = undefined, .asking = .stranger }, away, "identify;");
    try expectAct(sub, true, .GET, .{ .alloc = undefined, .asking = .failed }, .answered, "identify;");
    try expectAct(sub, true, .GET, .{ .alloc = undefined, .accounts = &unkind }, .answered, "identify;accounts;fail kind 1;");
}

test "an account that will not read fails only what reads it, with its own read's error: its name the DM it titles, the viewer's own name the pages that name them, the roster on the first in the disk's order; never no account, never a name of \"\"" {
    use(testing.allocator);
    defer @import("roc_abi.zig").deinit();
    const debbie_unnamed: abi.Account = .{
        .id = "2",
        .name = .unreadable,
        .kind = .member,
    };
    const named = [_]abi.Account{ steve, debbie_unnamed };
    const a: Scripted = .{
        .alloc = undefined,
        .accounts = &named,
        .body = "markdown=hi",
    };
    // The partner's name: every topic route and a send (the title, read
    // before the topics and before a send's tail) fail with it, nothing
    // after asked; never handed to the Zig as not the member's.
    try expectAct(
        "/c/1_2/Plans",
        false,
        .GET,
        a,
        .answered,
        "identify;accounts;presence;fail name 2;",
    );
    try expectAct(
        "/c/1_2/Plans/reactions",
        false,
        .GET,
        a,
        .answered,
        "identify;accounts;presence;fail name 2;",
    );
    try expectAct(
        "/c/1_2/Plans/send",
        false,
        .POST,
        a,
        .answered,
        "identify;accounts;presence;fail name 2;",
    );
    // The roster reads a member's name: the conversations and a message's
    // topic fail with it.
    try expectAct(
        "/conversations",
        false,
        .GET,
        a,
        .answered,
        "identify;accounts;presence;fail name 2;",
    );
    try expectAct(
        "/msg/Plans_1",
        false,
        .GET,
        a,
        .answered,
        "identify;accounts;presence;fail name 2;",
    );
    // **WHAT NEVER READ IT IS SERVED**: a landing with a topic, the
    // member's own pages, a new topic (the viewer's name only).
    try expectAct(
        "/c/1_2",
        false,
        .GET,
        a,
        .{ .redirect = "/chat/c/1_2/Plans" },
        "identify;accounts;presence;list 1_2/sessions;",
    );
    try expectAct("/c/1_2/new", false, .POST, blk: {
        var s = a;
        s.body = "topic=Ideas";
        s.topics = &.{"Plans"};
        break :blk s;
    }, .{ .respond = .{
        .status = 200,
        .content_type = "application/json; charset=utf-8",
        .body = "{\"conv\":\"1_2\",\"sid\":\"Ideas\"}",
    } }, "identify;accounts;presence;body;list 1_2/sessions;" ++ bookmarked("Ideas") ++ comptime blk: {
        // **A NAME THAT WILL NOT READ LABELS NO ROW** (recentWhere's
        // absent-ok): member 1's row of the new topic has no `where`, and
        // is sent all the same.
        const s = sent(
            dm_said,
            "1_2",
            "Ideas",
            "Steve",
            "hi",
            "",
        );
        break :blk s.count ++ s.render ++ s.store ++ s.publish ++ dmFanned(
            "1_2",
            "2",
            "Ideas",
            "Steve",
            "",
            "hi",
        );
    } ++ "aside begin;list 1_2/sessions;aside end;");
    for ([_][]const u8{
        "/links",
        "/images",
        "",
    }) |sub| {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const asked = try askedOf(
            arena.allocator(),
            sub,
            false,
            .GET,
            a,
        );
        if (std.mem.indexOf(
            u8,
            asked,
            "fail",
        ) != null) {
            std.debug.print("{s}: asked \"{s}\", read no other account\n", .{ sub, asked });
            return error.TestUnexpectedResult;
        }
    }
    // The landing with no topic reads the title, then fails with it.
    try expectAct("/c/1_2", false, .GET, blk: {
        var s = a;
        s.topics = &.{};
        break :blk s;
    }, .answered, "identify;accounts;presence;list 1_2/sessions;fail name 2;");
    // The viewer's own name: every page that names them, and a send.
    const me_unnamed = [_]abi.Account{ .{
        .id = "1",
        .name = .unreadable,
        .kind = .member,
    }, .{
        .id = "2",
        .name = .{ .found = "Debbie" },
        .kind = .member,
    } };
    const m: Scripted = .{
        .alloc = undefined,
        .accounts = &me_unnamed,
        .body = "markdown=hi",
    };
    try expectAct(
        "/links",
        false,
        .GET,
        m,
        .answered,
        "identify;accounts;presence;fail name 1;",
    );
    try expectAct(
        "/images",
        false,
        .GET,
        m,
        .answered,
        "identify;accounts;presence;fail name 1;",
    );
    try expectAct(
        "/ops/Plans/send",
        true,
        .POST,
        m,
        .answered,
        "identify;accounts;presence;read channels/ops.channel;header x-chat-async;body;hostile hi;fail name 1;",
    );
    // A guest's name: never read by the roster, read by its DM's title.
    const guest_unnamed = [_]abi.Account{ steve, .{
        .id = "2",
        .name = .unreadable,
        .kind = .guest,
    } };
    const g: Scripted = .{ .alloc = undefined, .accounts = &guest_unnamed };
    {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        var s = g;
        s.alloc = arena.allocator();
        const got = try decide(
            arena.allocator(),
            "/conversations",
            false,
            .GET,
            s.host(),
        );
        try testing.expectEqual(@as(u16, 200), got.respond.status);
        try testing.expectEqualStrings("identify;accounts;presence;", s.asked.items);
    }
    try expectAct(
        "/c/1_2/Plans",
        false,
        .GET,
        g,
        .answered,
        "identify;accounts;presence;fail name 2;",
    );
    // A password whose stat failed: the roster fails with it, the agent's
    // too; the DM it is half of is found and titled all the same.
    const unkind = [_]abi.Account{ steve, .{
        .id = "2",
        .name = .{ .found = "Debbie" },
        .kind = .unreadable,
    } };
    const k: Scripted = .{ .alloc = undefined, .accounts = &unkind };
    try expectAct(
        "/conversations",
        false,
        .GET,
        k,
        .answered,
        "identify;accounts;presence;fail kind 2;",
    );
    try expectAct(
        "/c/1_2/Plans/reactions",
        false,
        .GET,
        k,
        .{ .respond = .{
            .status = 200,
            .content_type = "application/x-ndjson; charset=utf-8",
            .body = "",
        } },
        "identify;accounts;presence;list 1_2/sessions;read 1_2/sessions/Plans.reactions.jsonl;",
    );
    // **THE ROSTER FAILS ON THE FIRST, IN THE DISK'S ORDER**, as
    // listAuthorized read them: a name before a kind after it; one account
    // with both, its kind (the password is read first).
    const order = [_]abi.Account{
        steve,
        .{
            .id = "5",
            .name = .unreadable,
            .kind = .agent,
        },
        .{
            .id = "2",
            .name = .{ .found = "Debbie" },
            .kind = .unreadable,
        },
    };
    try expectAct(
        "/conversations",
        false,
        .GET,
        .{ .alloc = undefined, .accounts = &order },
        .answered,
        "identify;accounts;presence;fail name 5;",
    );
    const both = [_]abi.Account{ steve, .{
        .id = "2",
        .name = .unreadable,
        .kind = .unreadable,
    } };
    try expectAct(
        "/conversations",
        false,
        .GET,
        .{ .alloc = undefined, .accounts = &both },
        .answered,
        "identify;accounts;presence;fail kind 2;",
    );
}

test "the accounts are the Roc's to read: a guest's DM is opened, the roster is members and the agent by numeric id, and a name is cut of its line end" {
    use(testing.allocator);
    defer @import("roc_abi.zig").deinit();
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const huge = "99999999999999999999";
    const all = [_]abi.Account{
        .{
            .id = "1",
            .name = .{ .found = "Steve\r\n" },
            .kind = .member,
        },
        .{
            .id = "10",
            .name = .{ .found = "Ten\r\n" },
            .kind = .member,
        },
        .{
            .id = "9",
            .name = .{ .found = " Nine  x" },
            .kind = .member,
        },
        .{
            .id = "4",
            .name = .{ .found = "Guest" },
            .kind = .guest,
        },
        .{
            .id = huge,
            .name = .{ .found = "Big" },
            .kind = .member,
        },
        .{
            .id = "3",
            .name = .{ .found = "Claude" },
            .kind = .agent,
        },
    };
    var s: Scripted = .{ .alloc = arena.allocator(), .accounts = &all };
    const got = try decide(
        arena.allocator(),
        "/conversations",
        false,
        .GET,
        s.host(),
    );
    const body = got.respond.body;
    // One too big for an i64 counts as 0, first; then 3, 9, 10 (by bytes 10
    // would come before 9); never the guest, never the member.
    var at: usize = 0;
    for ([_][]const u8{
        "{\"id\":\"" ++ huge ++ "\",\"name\":\"Big\"}",
        "{\"id\":\"3\",\"name\":\"Claude\"}",
        "{\"id\":\"9\",\"name\":\" Nine  x\"}",
        "{\"id\":\"10\",\"name\":\"Ten\"}",
    }) |want| {
        const i = std.mem.indexOfPos(
            u8,
            body,
            at,
            want,
        ) orelse {
            std.debug.print("{s} not after {d} in {s}\n", .{
                want,
                at,
                body,
            });
            return error.TestUnexpectedResult;
        };
        at = i + want.len;
    }
    try testing.expect(std.mem.indexOf(
        u8,
        body,
        "Guest",
    ) == null and std.mem.indexOf(
        u8,
        body,
        "\"id\":\"1\"",
    ) == null);
    // A guest is an account: its DM is the member's, titled by its name;
    // the viewer's name cut of its CR LF as it is stored.
    const guest: Scripted = .{
        .alloc = undefined,
        .accounts = &all,
        .body = "markdown=hi",
    };
    try expectAct(
        "/c/1_4/Plans/send",
        false,
        .POST,
        guest,
        .{ .redirect = "/chat/c/1_4/Plans" },
        "identify;accounts;presence;header x-chat-async;body;hostile hi;read users/1/last-sessions/1_4;write users/1/last-sessions/1_4 Plans\n;read users/1/last-conv;write users/1/last-conv 1_4\n;" ++ comptime sentAll(sent(
            "dm 1_4 /chat/c/1_4 [1,4]",
            "1_4",
            "Plans",
            "Steve",
            "hi",
            "",
        )),
    );
    // Not an account: the Zig's to answer.
    try expectAct(
        "/c/1_5/Plans/send",
        false,
        .POST,
        guest,
        .not_found,
        "identify;accounts;presence;",
    );
}

test "a doc too formatted to post is refused in the docs' own words, and nothing after the check is asked (metal-vmm QUEUE 278)" {
    use(testing.allocator);
    defer @import("roc_abi.zig").deinit();
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var s: Scripted = .{
        .alloc = arena.allocator(),
        .body = "slug=notes",
        .hostile_answer = .refused,
        .files = &.{.{ .path = "users/1/docs/notes.md", .read = .{ .found = "hi" } }},
    };
    const got = try decide(
        arena.allocator(),
        "/docs/post",
        false,
        .POST,
        s.host(),
    );
    try testing.expect(got.eql(.answered));
    try testing.expectEqualStrings(
        "identify;accounts;presence;body;read users/1/docs/notes.md;hostile hi;",
        s.asked.items,
    );
    try testing.expectEqualStrings(
        "not posted: too much markdown formatting; break the doc up\n",
        s.refusal,
    );
}
test "the docs landing's tie in mtime goes to the first doc by name, whatever the folder's order (the box, 2026-10-28)" {
    use(testing.allocator);
    var s: Scripted = .{ .alloc = undefined };
    s.docs = &.{ "zeta", "alpha", "mid" };
    try expectAct("/docs", false, .GET, s, .{ .redirect = "/chat/docs/alpha" }, "identify;accounts;presence;list users/1/docs;stat users/1/docs/alpha.md;stat users/1/docs/mid.md;stat users/1/docs/zeta.md;");
}
