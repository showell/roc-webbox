//! **A ROC CRASH IS A 500, AND THE NEXT REQUEST IS SERVED** (docs/ROC-CHAT.md
//! R3, P9), and **ONE ROC CALL AT A TIME** (R1, P7): chat_abi.zig's `decide`
//! over the planted crash (chat/test/crash.roc, linked here in place of the
//! router; never into a server).

const std = @import("std");
const testing = std.testing;
const abi = @import("chat_abi.zig");
const roc = @import("roc_abi.zig");
const route = @import("chat_route.zig");

const Asker = struct {
    member: bool = true,
    /// When set, the asker starts a Roc call of its own, inside this one.
    nest: bool = false,
    nested: ?anyerror = null,

    fn ask(ctx: *anyopaque) abi.Asking {
        const self: *Asker = @ptrCast(@alignCast(ctx));
        if (self.nest) {
            var inner: Asker = .{};
            if (abi.decide(
                testing.allocator,
                "/ok",
                false,
                .GET,
                inner.member_(),
            )) |_| {} else |e| self.nested = e;
        }
        return if (self.member) .{ .known = "1" } else .stranger;
    }

    fn member_(self: *Asker) abi.Host {
        return abi.askingOnly(self, ask);
    }
};

/// A host whose files are one, `users/1/ok` ("hi"), and one that will not
/// read, `users/1/broken`; whose folders are `channels` (three entries, one
/// of each kind) and `empty`, and one that will not list, `1_2/sessions`;
/// it records what it was asked and how it failed.
const Files = struct {
    asked: std.ArrayList(u8) = .empty,
    failed: ?anyerror = null,
    /// Inside Host.aside!, and the aside's first failure.
    aside: bool = false,
    aside_failed: ?anyerror = null,

    fn host(f: *Files) abi.Host {
        var h = abi.askingOnly(f, yes);
        h.read = read;
        h.stat = stat;
        h.read_at = readAt;
        h.write = write;
        h.remove = remove;
        h.serve_file = raw;
        h.serve_rendered = links;
        h.list = list;
        h.fail = fail;
        h.fail_account = failAccount;
        h.count = counted;
        h.append = append;
        h.publish = publish;
        h.render = render;
        h.serve_upload = serveUpload;
        h.read_upload = readUpload;
        h.reserve_upload = reserveUpload;
        h.store_upload = storeUpload;
        h.refuse_upload = refuseUpload;
        h.retire_asked = retireAsked;
        h.retire_note = retireNote;
        h.retire_remove = retireRemove;
        h.retire_replace = retireReplace;
        h.retire_user = retireUser;
        h.bundle_add = bundleAdd;
        h.serve_bundle = serveBundle;
        h.index_message = indexMessage;
        h.write_cache = writeCache;
        h.aside = asideOf;
        h.check_online = online;
        return h;
    }
    /// Members 2 and 12 were seen lately; anyone else not.
    fn online(ctx: *anyopaque, id: []const u8) @import("chat_route.zig").Presence {
        say(
            ctx,
            "online",
            id,
        );
        return if (std.mem.eql(
            u8,
            id,
            "2",
        ) or std.mem.eql(
            u8,
            id,
            "12",
        )) .online else .offline;
    }
    /// An aside: a failure inside it is its own, answered at its end.
    fn asideOf(ctx: *anyopaque, which: route.Aside) abi.AsideOutcome {
        const f = of(ctx);
        say(ctx, "aside", @tagName(which));
        switch (which) {
            .begin => f.aside = true,
            .end => {
                f.aside = false;
                const e = f.aside_failed orelse return .done;
                f.aside_failed = null;
                return .{ .failed = e };
            },
        }
        return .done;
    }
    fn counted(ctx: *anyopaque, kind: route.CountKind, text: []const u8) void {
        of(ctx).asked.print(testing.allocator, "count {t} {s};", .{ kind, text }) catch @panic("oom");
    }
    /// `boom` will not render; anything else is its own HTML, marked.
    fn render(ctx: *anyopaque, md: []const u8) abi.Rendered {
        of(ctx).asked.print(
            testing.allocator,
            "render {s};",
            .{md},
        ) catch @panic("oom");
        if (std.mem.eql(
            u8,
            md,
            "boom",
        )) {
            fail(ctx, error.OutOfMemory);
            return .failed;
        }
        return .{ .rendered = "<p>html</p>" };
    }
    /// Topic `Broken` will not take a block; any other's transcript is 42
    /// bytes after it.
    fn serveUpload(ctx: *anyopaque, u: abi.Upload) @import("chat_route.zig").UploadServed {
        of(ctx).asked.print(
            testing.allocator,
            "upload {d} {d} {d} {s} {s} {t};",
            .{ u.first, u.last, u.size, u.content_type, u.path, u.part },
        ) catch @panic("oom");
        return .served;
    }
    fn readUpload(ctx: *anyopaque) abi.UploadRead {
        say(ctx, "read upload", "");
        return .{ .read = .{ .size = 4242, .ext = "png", .filename = "cat \"1\".png" } };
    }
    fn reserveUpload(ctx: *anyopaque, size: u64) @import("chat_route.zig").Reservation {
        of(ctx).asked.print(testing.allocator, "reserve {d};", .{size}) catch @panic("oom");
        return .reserved;
    }
    fn storeUpload(ctx: *anyopaque, folder: []const u8, ext: []const u8) abi.Stored {
        of(ctx).asked.print(testing.allocator, "store {s} {s};", .{ folder, ext }) catch @panic("oom");
        return .{ .stored = "0123456789abcdef0123456789abcdef.png" };
    }
    fn retireAsked(ctx: *anyopaque) abi.RetireAsked {
        say(ctx, "retire asked", "");
        return .{ .days = 30, .keep = "Steve\napoorva", .now = -1_700_000_000 };
    }
    fn retireNote(ctx: *anyopaque, kind: @import("chat_route.zig").RetireKind, label: []const u8) void {
        of(ctx).asked.print(testing.allocator, "note {t} {s};", .{ kind, label }) catch @panic("oom");
    }
    fn retireRemove(ctx: *anyopaque, path: []const u8, what: @import("chat_route.zig").RetireRemoval) @import("chat_route.zig").Done {
        of(ctx).asked.print(testing.allocator, "remove {t} {s};", .{ what, path }) catch @panic("oom");
        return if (what == .tree) .ok else .failed;
    }
    fn retireReplace(ctx: *anyopaque, path: []const u8, bytes: []const u8) @import("chat_route.zig").Done {
        of(ctx).asked.print(testing.allocator, "replace {s} {f};", .{ path, std.zig.fmtString(bytes) }) catch @panic("oom");
        return .ok;
    }
    fn retireUser(ctx: *anyopaque, uid: []const u8) @import("chat_route.zig").Done {
        say(ctx, "retire user", uid);
        return .ok;
    }
    fn refuseUpload(ctx: *anyopaque, why: @import("chat_route.zig").UploadRefusal, message: []const u8) void {
        of(ctx).asked.print(testing.allocator, "refuse {t} {s};", .{ why, message }) catch @panic("oom");
    }
    fn bundleAdd(ctx: *anyopaque, name: []const u8, path: []const u8) @import("chat_route.zig").Done {
        of(ctx).asked.print(
            testing.allocator,
            "add {s} {s};",
            .{ name, path },
        ) catch @panic("oom");
        return .ok;
    }
    fn serveBundle(ctx: *anyopaque, name: []const u8) void {
        say(ctx, "bundle", name);
    }
    /// Every field of the message in Chat.Message's order.
    fn indexMessage(
        ctx: *anyopaque,
        dir: []const u8,
        sid: []const u8,
        m: abi.Message,
    ) void {
        of(ctx).asked.print(
            testing.allocator,
            "index {s} {s} id={s} from={s} at={s} uid={s} md={s};",
            .{
                dir,
                sid,
                m.id,
                m.from,
                m.at,
                m.uid,
                m.markdown,
            },
        ) catch @panic("oom");
    }
    fn writeCache(ctx: *anyopaque, path: []const u8, bytes: []const u8) void {
        of(ctx).asked.print(
            testing.allocator,
            "cache {s} {f};",
            .{ path, std.zig.fmtString(bytes) },
        ) catch @panic("oom");
    }
    /// `users/1/broken`, `users/2/images.md` and topic `Broken`'s
    /// transcript will not take bytes; any other file is 42 bytes after.
    fn append(
        ctx: *anyopaque,
        path: []const u8,
        bytes: []const u8,
    ) abi.Appended {
        of(ctx).asked.print(
            testing.allocator,
            "append {s} {f};",
            .{ path, std.zig.fmtString(bytes) },
        ) catch @panic("oom");
        for ([_][]const u8{ "users/1/broken", "users/2/images.md", "1_2/sessions/Broken.md" }) |broken| if (std.mem.eql(
            u8,
            path,
            broken,
        )) {
            fail(ctx, error.IsDir);
            return .failed;
        };
        return .{ .appended = 42 };
    }
    fn publish(
        ctx: *anyopaque,
        key: []const u8,
        bytes: []const u8,
    ) void {
        of(ctx).asked.print(
            testing.allocator,
            "publish {s} {f};",
            .{ key, std.zig.fmtString(bytes) },
        ) catch @panic("oom");
    }
    /// Topic `Plans` has 7 messages; `Broken` will not count.
    /// An account's kind kept as error.SymLinkLoop, its name as
    /// error.IsDir: which one the request fails with shows which read the
    /// seam asked for.
    fn failAccount(
        ctx: *anyopaque,
        which: abi.AccountRead,
        id: []const u8,
    ) void {
        of(ctx).asked.print(
            testing.allocator,
            "fail_account {t} {s};",
            .{ which, id },
        ) catch @panic("oom");
        fail(ctx, switch (which) {
            .kind => error.SymLinkLoop,
            .name => error.IsDir,
        });
    }
    fn list(ctx: *anyopaque, path: []const u8) abi.Listing {
        say(
            ctx,
            "list",
            path,
        );
        if (std.mem.eql(
            u8,
            path,
            "channels",
        )) return .{ .found = &.{
            .{ .name = "ops.channel", .kind = .file },
            .{ .name = "x.md", .kind = .dir },
            .{ .name = "\xffl", .kind = .other },
        } };
        if (std.mem.eql(
            u8,
            path,
            "empty",
        )) return .{ .found = &.{} };
        if (std.mem.eql(
            u8,
            path,
            "1_2/sessions",
        )) {
            fail(ctx, error.NotDir);
            return .failed;
        }
        return .missing;
    }
    fn of(ctx: *anyopaque) *Files {
        return @ptrCast(@alignCast(ctx));
    }
    fn yes(_: *anyopaque) abi.Asking {
        return .{ .known = "1" };
    }
    fn say(
        ctx: *anyopaque,
        what: []const u8,
        path: []const u8,
    ) void {
        of(ctx).asked.print(
            testing.allocator,
            "{s} {s};",
            .{ what, path },
        ) catch @panic("oom");
    }
    fn read(ctx: *anyopaque, path: []const u8) abi.Read {
        say(
            ctx,
            "read",
            path,
        );
        if (std.mem.eql(
            u8,
            path,
            "users/1/ok",
        )) return .{ .found = "hi" };
        if (std.mem.eql(
            u8,
            path,
            "users/1/broken",
        )) {
            fail(ctx, error.IsDir);
            return .failed;
        }
        return .missing;
    }
    /// `users/1/ok` is 2 bytes changed at 1790000001; `users/1/broken` a
    /// folder, whose stat fails; anything else is not there.
    fn stat(ctx: *anyopaque, path: []const u8) abi.Stat {
        say(
            ctx,
            "stat",
            path,
        );
        if (std.mem.eql(
            u8,
            path,
            "users/1/ok",
        )) return .{ .found = .{ .size = 2, .mtime = 1790000001 } };
        if (std.mem.eql(
            u8,
            path,
            "users/1/broken",
        )) {
            fail(ctx, error.IsDir);
            return .failed;
        }
        return .missing;
    }
    /// `users/1/ok` holds "hello"; `users/1/long` hands back more than it
    /// was asked for, which the seam cuts.
    fn readAt(
        ctx: *anyopaque,
        path: []const u8,
        offset: u64,
        max: u64,
    ) abi.Read {
        say(
            ctx,
            "read_at",
            path,
        );
        if (std.mem.eql(
            u8,
            path,
            "users/1/long",
        )) return .{ .found = "0123456789" };
        if (!std.mem.eql(
            u8,
            path,
            "users/1/ok",
        )) return .missing;
        const text = "hello";
        const from = @min(offset, text.len);
        return .{ .found = text[from..@min(text.len, from + max)] };
    }
    fn write(
        ctx: *anyopaque,
        path: []const u8,
        _: []const u8,
    ) route.Done {
        say(
            ctx,
            "write",
            path,
        );
        return .ok;
    }
    fn remove(ctx: *anyopaque, path: []const u8) route.Done {
        say(
            ctx,
            "remove",
            path,
        );
        return .ok;
    }
    fn raw(ctx: *anyopaque, path: []const u8) route.Serving {
        say(
            ctx,
            "raw",
            path,
        );
        return .serving;
    }
    fn links(ctx: *anyopaque, path: []const u8) route.Serving {
        say(
            ctx,
            "links",
            path,
        );
        return .serving;
    }
    fn fail(ctx: *anyopaque, e: anyerror) void {
        const f = of(ctx);
        if (f.aside) {
            if (f.aside_failed == null) f.aside_failed = e;
            return;
        }
        if (f.failed == null) f.failed = e;
    }
};

/// What `sub` answered, what the host was asked, and how it failed.
fn probe(
    sub: []const u8,
    want_body: []const u8,
    want_asked: []const u8,
    want_failed: ?anyerror,
) !void {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var f: Files = .{};
    defer f.asked.deinit(testing.allocator);
    const got = try abi.decide(
        arena.allocator(),
        sub,
        false,
        .GET,
        f.host(),
    );
    if (!std.mem.eql(
        u8,
        got.respond.body,
        want_body,
    ) or !std.mem.eql(
        u8,
        f.asked.items,
        want_asked,
    ) or !std.meta.eql(f.failed, want_failed)) {
        std.debug.print("{s}: answered \"{s}\" asking \"{s}\" failing {any}, want \"{s}\" asking \"{s}\" failing {any}\n", .{
            sub,
            got.respond.body,
            f.asked.items,
            f.failed,
            want_body,
            want_asked,
            want_failed,
        });
        return error.TestUnexpectedResult;
    }
}

test "a path that would leave the chat root fails the request at the seam, the host never asked; a path under it is the host's, and missing and failed are two answers" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    roc.use(arena.allocator());
    defer roc.deinit();
    // Outside the root, by every way out: the request fails, nothing asked.
    for ([_][]const u8{
        "/stat/../x",
        "/stat//etc/passwd",
        "/read_at/0/1/../x",
        "/read/../x",
        "/read//etc/passwd",
        "/read/",
        "/read/users/../../x",
        "/write/../x",
        "/write//etc/passwd",
        "/write/",
        "/remove/users/../../x",
        "/remove/",
        "/raw/../x",
        "/raw//etc/passwd",
        "/raw/",
        "/links/users/../../x",
        "/links//etc/passwd",
    }) |sub|
        try probe(
            sub,
            "failed",
            "",
            error.PathOutsideChatRoot,
        );
    try probe(
        "/raw/1_2/sessions/Plans.md",
        "done",
        "raw 1_2/sessions/Plans.md;",
        null,
    );
    try probe(
        "/links/users/1/links.md",
        "done",
        "links users/1/links.md;",
        null,
    );
    // Under it: the host's, each answer as it gave it.
    try probe(
        "/read/users/1/ok",
        "found hi",
        "read users/1/ok;",
        null,
    );
    try probe(
        "/read/users/1/gone",
        "missing",
        "read users/1/gone;",
        null,
    );
    try probe(
        "/read/users/1/broken",
        "failed",
        "read users/1/broken;",
        error.IsDir,
    );
    // stat! and read_at! (metal-vmm QUEUE 274): every field in its place.
    try probe(
        "/stat/users/1/ok",
        "found size=2 mtime=1790000001",
        "stat users/1/ok;",
        null,
    );
    try probe(
        "/stat/users/1/gone",
        "missing size=0 mtime=0",
        "stat users/1/gone;",
        null,
    );
    try probe(
        "/stat/users/1/broken",
        "failed",
        "stat users/1/broken;",
        error.IsDir,
    );
    try probe(
        "/read_at/1/3/users/1/ok",
        "found ell",
        "read_at users/1/ok;",
        null,
    );
    try probe(
        "/read_at/3/9/users/1/ok",
        "found lo",
        "read_at users/1/ok;",
        null,
    );
    try probe(
        "/read_at/7/2/users/1/ok",
        "found ",
        "read_at users/1/ok;",
        null,
    );
    try probe(
        "/read_at/0/4/users/1/long",
        "found 0123",
        "read_at users/1/long;",
        null,
    );
    try probe(
        "/read_at/0/4/users/1/gone",
        "missing",
        "read_at users/1/gone;",
        null,
    );
    try probe(
        "/write/users/1/pinned-sessions/1_2",
        "done",
        "write users/1/pinned-sessions/1_2;",
        null,
    );
    try probe(
        "/remove/users/1/last-conv",
        "done",
        "remove users/1/last-conv;",
        null,
    );
}

test "bytes appended: a path that would leave the root fails the request at the seam, the host never asked; under it, stored with the size after, or failed; a publish crosses key and bytes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    roc.use(arena.allocator());
    defer roc.deinit();
    for ([_][]const u8{
        "/append/../x",
        "/append//etc/passwd",
        "/append/",
        "/append/1_2/sessions/../../../x",
        "/append/..",
    }) |sub|
        try probe(
            sub,
            "failed",
            "",
            error.PathOutsideChatRoot,
        );
    try probe(
        "/append/1_2/sessions/Plans.reactions.jsonl",
        "appended 42",
        "append 1_2/sessions/Plans.reactions.jsonl {\\\"a\\\":1}\\n;",
        null,
    );
    try probe(
        "/append/users/1/broken",
        "failed",
        "append users/1/broken {\\\"a\\\":1}\\n;",
        error.IsDir,
    );
    try probe(
        "/publish/1_2/Plans",
        "published",
        "publish 1_2/Plans event: reaction\\ndata: x\\n\\n;",
        null,
    );
}

test "an append in an aside never fails the request: a feed's entry appended or failed, the failure the aside's, its fault crossing back at the aside's end to be named and counted; a feed's path outside the root the aside's failure, the host never asked" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    roc.use(arena.allocator());
    defer roc.deinit();
    try probe(
        "/entry/users/1/images.md",
        "appended",
        "aside begin;append users/1/images.md the entry;aside end;",
        null,
    );
    try probe(
        "/entry/users/2/images.md",
        "said",
        "aside begin;append users/2/images.md the entry;aside end;count fanout_failure images for member 2, IsDir, on 1_2/Plans;",
        null,
    );
    for ([_][]const u8{
        "/entry/../x",
        "/entry//etc/passwd",
        "/entry/users/../../x",
    }) |sub|
        try probe(
            sub,
            "said",
            "aside begin;aside end;count fanout_failure images for member 2, PathOutsideChatRoot, on 1_2/Plans;",
            null,
        );
}

test "a message's render and store cross the seam: the HTML or a render that failed, never empty; every field of the conversation and the message in its place, the index beside them; a store that failed is no store" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    roc.use(arena.allocator());
    defer roc.deinit();
    try probe(
        "/render/**hi**",
        "rendered <p>html</p>",
        "render **hi**;",
        null,
    );
    try probe(
        "/render/boom",
        "failed",
        "render boom;",
        error.OutOfMemory,
    );
    const fields = "id=Plans_9 from=Steve at=2026-10-26T00:00:00Z uid=1 md=**hi**";
    try probe(
        "/store/Plans",
        "appended 42",
        "append 1_2/sessions/Plans.md the block;index 1_2 Plans " ++ fields ++ ";",
        null,
    );
    try probe(
        "/store/Broken",
        "failed",
        "append 1_2/sessions/Broken.md the block;",
        error.IsDir,
    );
    // A cache under the root is written; one off it fails the request (the
    // seam's path check), never written.
    // An upload's record crosses whole, each field in its place, for
    // each part; a bundle's two effects in turn (metal-vmm QUEUE 291).
    inline for (.{ .{ "r", "range" }, .{ "u", "unsatisfiable" }, .{ "w", "whole" } }) |p| try probe(
        "/upload/" ++ p[0],
        "served",
        "upload 11 22 33 image/png 1_2/sessions/Plans.uploads/a.png " ++ p[1] ++ ";",
        null,
    );
    try probe(
        "/upload-form",
        "read 4242 png cat \"1\".png reserved 0123456789abcdef0123456789abcdef.png",
        "read upload ;reserve 4242;store 1_2/sessions/Plans.uploads png;refuse too_large too big;",
        null,
    );
    try probe(
        "/bundle/Plans",
        "bundled",
        "add Plans/Plans.md 1_2/sessions/Plans.md;bundle Plans;",
        null,
    );
    try probe(
        "/cache/1_2/sessions/Plans.count",
        "written",
        "cache 1_2/sessions/Plans.count 7 99\\n;",
        null,
    );
}

test "presence crosses one flag for each id, in its place, never short, long or shifted" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    roc.use(arena.allocator());
    defer roc.deinit();
    try probe(
        "/online/1,2,3,12",
        "flags 4 1:off 2:on 3:off 12:on",
        "online 1;online 2;online 3;online 12;",
        null,
    );
    try probe(
        "/online/2",
        "flags 1 2:on",
        "online 2;",
        null,
    );
    try probe(
        "/online/7",
        "flags 1 7:off",
        "online 7;",
        null,
    );
}

test "a folder's listing: a path that would leave the root fails the request at the seam; under it, its entries and their kinds, nothing there, and a listing that failed are three answers" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    roc.use(arena.allocator());
    defer roc.deinit();
    for ([_][]const u8{
        "/list/../x",
        "/list//etc",
        "/list/",
        "/list/channels/../../x",
        "/list/..",
    }) |sub|
        try probe(
            sub,
            "failed",
            "",
            error.PathOutsideChatRoot,
        );
    try probe(
        "/list/channels",
        "found f:ops.channel d:x.md o:\xffl",
        "list channels;",
        null,
    );
    try probe(
        "/list/empty",
        "found",
        "list empty;",
        null,
    );
    try probe(
        "/list/gone",
        "missing",
        "list gone;",
        null,
    );
    try probe(
        "/list/1_2/sessions",
        "failed",
        "list 1_2/sessions;",
        error.NotDir,
    );
}

test "the Roc fails a request by a reason, each reason its own byte across: a malformed channel as error.MalformedChannel, an account's kind or name as the error the host kept for that read of that account, a message with no author as error.NoAuthor; and a malformed channel is counted by the host" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    roc.use(arena.allocator());
    defer roc.deinit();
    try probe(
        "/fail/malformed/Abad",
        "failed",
        "",
        error.MalformedChannel,
    );
    try probe(
        "/fail/kind/7",
        "failed",
        "fail_account kind 7;",
        error.SymLinkLoop,
    );
    try probe(
        "/fail/name/12",
        "failed",
        "fail_account name 12;",
        error.IsDir,
    );
    try probe(
        "/fail/author/x",
        "failed",
        "",
        error.NoAuthor,
    );
    try probe(
        "/malformed/Abad",
        "counted",
        "count malformed_channel Abad;",
        null,
    );
}

test "every account crosses with its id, kind and name, in the host's order, one that will not read as unreadable (its kind, its name, or both); a listing that failed is `failed`, never no accounts" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    roc.use(arena.allocator());
    defer roc.deinit();
    const S = struct {
        var fails: bool = false;
        fn accounts(ctx: *anyopaque) abi.Accounts {
            Files.say(
                ctx,
                "accounts",
                "",
            );
            if (fails) {
                Files.fail(ctx, error.IsDir);
                return .failed;
            }
            return .{ .found = &.{
                .{
                    .id = "10",
                    .name = .{ .found = "Ten\r\n" },
                    .kind = .member,
                },
                .{
                    .id = "3",
                    .name = .{ .found = "Claude" },
                    .kind = .agent,
                },
                .{
                    .id = "9",
                    .name = .{ .found = "" },
                    .kind = .guest,
                },
                .{
                    .id = "7",
                    .name = .{ .found = "Sev" },
                    .kind = .unreadable,
                },
                .{
                    .id = "12",
                    .name = .unreadable,
                    .kind = .member,
                },
                .{
                    .id = "13",
                    .name = .unreadable,
                    .kind = .unreadable,
                },
            } };
        }
    };
    for ([_]bool{ false, true }) |fails| {
        S.fails = fails;
        var f: Files = .{};
        defer f.asked.deinit(testing.allocator);
        var h = f.host();
        h.list_accounts = S.accounts;
        const got = try abi.decide(
            arena.allocator(),
            "/accounts",
            false,
            .GET,
            h,
        );
        try testing.expectEqualStrings(
            if (fails) "failed" else "found m:10=Ten\r\n a:3=Claude g:9= u:7=Sev m:12=? u:13=?",
            got.respond.body,
        );
        try testing.expectEqualStrings("accounts ;", f.asked.items);
        try testing.expectEqual(if (fails) @as(?anyerror, error.IsDir) else null, f.failed);
    }
}

test "a Roc crash is error.RocCrashed, its message kept, and the next call is served; a crash after a hosted call too" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    roc.use(arena.allocator());
    var asker: Asker = .{};

    try testing.expectError(error.RocCrashed, abi.decide(
        arena.allocator(),
        "/crash",
        false,
        .GET,
        asker.member_(),
    ));
    try testing.expectEqualStrings("a planted crash", abi.last_crash[0..abi.last_crash_len]);
    try testing.expect(!roc.inCall());

    const ok = try abi.decide(
        arena.allocator(),
        "/ok",
        false,
        .GET,
        asker.member_(),
    );
    try testing.expectEqualStrings("/ok", ok.found);

    try testing.expectError(error.RocCrashed, abi.decide(
        arena.allocator(),
        "/crash-after-asking",
        false,
        .GET,
        asker.member_(),
    ));
    try testing.expectEqualStrings(
        "a planted crash, after asking",
        abi.last_crash[0..abi.last_crash_len],
    );
    _ = try abi.decide(
        arena.allocator(),
        "/ok",
        false,
        .GET,
        asker.member_(),
    );
}

test "a Roc call inside another is refused, error.RocReentered, and the outer call goes on" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    roc.use(arena.allocator());
    // The planted app asks who it is on `/crash-after-asking`; this asker
    // tries a Roc call of its own while asked, inside the outer one.
    var asking: Asker = .{ .nest = true };
    try testing.expectError(error.RocCrashed, abi.decide(
        arena.allocator(),
        "/crash-after-asking",
        false,
        .GET,
        asking.member_(),
    ));
    try testing.expectEqual(@as(?anyerror, error.RocReentered), asking.nested);
    try testing.expect(!roc.inCall());
}

test "memory that runs out inside a Roc call is error.RocCrashed for that request, at every allocation it could fail on, and the next call is served (metal-vmm FEEDBACK 2026-10-26: it panicked the machine)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    defer roc.deinit();
    var asker: Asker = .{};
    var failed: usize = 0;
    var k: usize = 0;
    while (k < 64) : (k += 1) {
        // The request's own allocator (useRequest, as angry-gopher's router
        // hands it), failing at its k-th allocation.
        var failing = std.testing.FailingAllocator.init(arena.allocator(), .{ .fail_index = k });
        roc.useRequest(failing.allocator());
        if (abi.decide(
            arena.allocator(),
            "/crash-after-asking-big",
            false,
            .GET,
            asker.member_(),
        )) |_| {
            unreachable;
        } else |e| {
            try testing.expectEqual(error.RocCrashed, e);
            if (std.mem.eql(
                u8,
                abi.last_crash[0..abi.last_crash_len],
                "roc_alloc: out of memory",
            )) {
                failed += 1;
            } else {
                // Past every allocation the call makes: its own planted crash.
                try testing.expectEqualStrings(
                    "a planted crash, after a big list",
                    abi.last_crash[0..abi.last_crash_len],
                );
                break;
            }
        }
        try testing.expect(!roc.inCall());
        roc.useRequest(arena.allocator());
        _ = try abi.decide(
            arena.allocator(),
            "/ok",
            false,
            .GET,
            asker.member_(),
        );
    }
    try testing.expect(failed >= 2 and k < 64);
}

test "the admin retire's area reaches the app with every field of its ask in its place, each step's call and answer too (metal-vmm QUEUE 293)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var f: Files = .{};
    defer f.asked.deinit(testing.allocator);
    roc.use(arena.allocator());
    const got = try abi.retire(arena.allocator(), f.host());
    try testing.expectEqualStrings("days 30 now -1700000000 keep Steve\napoorva done failed done done", got.respond.body);
    try testing.expectEqualStrings("retire asked ;note channel_member ops (1 dropped);note user Spammer (uid 9);remove tree 1_9;remove file users/1/last-conv;replace channels/ops.channel 1\\n;retire user 9;", f.asked.items);
    try testing.expectEqual(@as(?anyerror, null), f.failed);
}
