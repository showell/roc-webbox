//! **THE ROC CHAT'S SIDE OF THE SEAM** (chat/platform/): the records
//! `roc_chat_handle` takes and answers, laid out as Roc lays them (fields
//! by alignment, then by name; sizes asserted below), and the hosted
//! functions (chat/platform/Host.roc), each answered by the host's `Host`
//! for the call. The runtime and the call's arena are roc_abi.zig's, shared
//! with any other Roc app in the binary.
//!
//! **THE DECISION LEAVES THE CALL**: `decide` copies what Roc answered into
//! the caller's allocator and ends the call before it returns, so the Zig
//! that serves a delegated route runs with no Roc call open (docs/ROC-CHAT.md
//! R1): its writes, and on metal the network pumps inside them, nest
//! nothing. A route the Roc serves itself (C4) writes through the hosted
//! functions, inside the call, as §6.2's send will: a pump there runs the
//! kernel's turn and its fixed Zig render, never a handler, and the busy
//! word refuses any Roc call beside this one.

const std = @import("std");
const roc = @import("roc_abi.zig");
const route_mod = @import("chat_route.zig");
const sljmp = @import("sljmp.zig");
pub const Route = route_mod.Route;
pub const Decision = route_mod.Decision;

pub const RocBytes = roc.RocBytes;

const Family = route_mod.Family;
const Method = route_mod.Method;

/// Chat.roc's `Request`.
pub const Request = extern struct { sub: RocBytes, channel: bool, method: Method };
/// Chat.roc's `Route`.
pub const RouteRec = extern struct { key: RocBytes, rest: RocBytes, sid: RocBytes, family: Family, part: route_mod.Part, tail: route_mod.Tail };
/// Chat.roc's `Answer`.
pub const Answer = extern struct { body: RocBytes, content_type: RocBytes, location: RocBytes, route: RouteRec, status: u16, allow: Method, kind: route_mod.Kind, nosniff: bool, presence: bool };
/// Host.roc's `{ ok : Bool, bytes : List(U8) }`.
pub const Got = extern struct { bytes: RocBytes, ok: bool };
/// Chat.roc's `Conv`, as Roc hands it to a hosted function.
pub const ConvRec = extern struct { base: RocBytes, key: RocBytes, members: roc.RocBytesList, family: Family };
/// Host.roc's `read!` answer: `{ bytes : List(U8), status : [Failed, Found, Missing] }`.
pub const ReadRec = extern struct { bytes: RocBytes, status: route_mod.ReadStatus };
/// One of Host.roc's `list!` entries: `{ kind : [Dir, File, Other], name : List(U8) }`.
pub const EntryRec = extern struct { name: RocBytes, kind: route_mod.EntryKind };
/// Host.roc's `list!` answer: `{ entries : List(...), status : [Failed, Found, Missing] }`.
pub const ListRec = extern struct { entries: EntryList, status: route_mod.ReadStatus };
/// One of Host.roc's `accounts!` accounts: `{ id : List(U8), kind : [Agent, Guest, Member], name : List(U8) }`.
pub const AccountRec = extern struct { id: RocBytes, name: RocBytes, kind: route_mod.AccountKind };
/// Host.roc's `accounts!` answer: `{ accounts : List(...), status : [Failed, Found] }`.
pub const AccountsRec = extern struct { accounts: AccountList, status: route_mod.AccountsStatus };

/// A Roc list of `Rec`, each made of an `Item` by `rec`: its elements hold
/// a refcounted list, so it has the two-word header (count, refcount) a
/// `List(List(U8))` has.
fn RecList(comptime Rec: type, comptime Item: type, comptime rec: fn (Item) Rec) type {
    return extern struct {
        ptr: ?[*]Rec,
        length: usize,
        capacity_or_alloc_ptr: usize,

        fn from(items: []const Item) @This() {
            if (items.len == 0) return .{ .ptr = null, .length = 0, .capacity_or_alloc_ptr = 0 };
            const w = @sizeOf(usize);
            const base = roc.allocate(2 * w + items.len * @sizeOf(Rec), w);
            std.mem.writeInt(usize, base[0..w], items.len, .little);
            std.mem.writeInt(usize, base[w..][0..w], 1, .little);
            const elems: [*]Rec = @ptrCast(@alignCast(base + 2 * w));
            for (items, 0..) |it, k| elems[k] = rec(it);
            return .{ .ptr = elems, .length = items.len, .capacity_or_alloc_ptr = items.len << 1 };
        }
    };
}

pub const EntryList = RecList(EntryRec, Entry, struct {
    fn rec(it: Entry) EntryRec {
        return .{ .name = .from(it.name), .kind = it.kind };
    }
}.rec);

pub const AccountList = RecList(AccountRec, Account, struct {
    fn rec(it: Account) AccountRec {
        return .{ .id = .from(it.id), .name = .from(it.name), .kind = it.kind };
    }
}.rec);

comptime {
    const w = @sizeOf(usize);
    std.debug.assert(@sizeOf(RocBytes) == 3 * w and @sizeOf(Request) == 4 * w and @sizeOf(RouteRec) == 10 * w and @sizeOf(Answer) == 20 * w and @sizeOf(Got) == 4 * w and @sizeOf(ConvRec) == 10 * w and @sizeOf(ReadRec) == 4 * w and @sizeOf(EntryRec) == 4 * w and @sizeOf(ListRec) == 4 * w and @sizeOf(AccountRec) == 7 * w and @sizeOf(AccountsRec) == 4 * w);
}

/// **A FILE AS THE HOST READ IT**: its bytes, nothing there, or a read that
/// failed (the host has failed the request: `fail`). Missing and failed are
/// never one answer: a set read as empty because the disk failed would be
/// written back empty.
pub const Read = union(route_mod.ReadStatus) { failed, found: []const u8, missing };

/// A folder's entry: its name and its kind.
pub const Entry = struct { name: []const u8, kind: route_mod.EntryKind };

/// **A FOLDER AS THE HOST LISTED IT**: its entries, in the order the disk
/// gives them; nothing there; or a listing that failed (the host has failed
/// the request). Missing and failed are never one answer.
pub const Listing = union(route_mod.ReadStatus) { failed, found: []const Entry, missing };

/// An account as the host read it: its id (a canonical folder's name), its
/// `name` file's bytes as stored ("" when it has none), its kind.
pub const Account = struct { id: []const u8, name: []const u8, kind: route_mod.AccountKind };

/// **EVERY ACCOUNT, OR A READ THAT FAILED** (the host has failed the
/// request): never "no accounts" for a read that failed.
pub const Accounts = union(route_mod.AccountsStatus) { failed, found: []const Account };

/// **A CONVERSATION THE ROC FOUND TO BE THE MEMBER'S** (chat/main.roc
/// `find!`), handed to each hosted function that works on one: the host
/// holds no conversation between calls. `family` is `.dm` or `.channel`;
/// `members` each member once. Its bytes are the call's.
pub const Conv = struct {
    family: Family,
    key: []const u8,
    base: []const u8,
    members: []const []const u8,

    fn of(r: ConvRec) Conv {
        const items = r.members.slice();
        const members = roc.alloc().alloc([]const u8, items.len) catch @panic("roc_chat: out of memory for a conversation's members");
        for (items, members) |*it, *m| m.* = it.slice();
        return .{ .family = r.family, .key = r.key.slice(), .base = r.base.slice(), .members = members };
    }
};

extern fn roc_chat_handle(req: Request) callconv(.c) Answer;

/// **WHAT ANSWERS THE HOSTED FUNCTIONS** during a call: the host's, with its
/// own context (the request, its `Io`). Set by `decide` for the call alone.
/// Bytes handed in are the call's, good until it ends; bytes handed back
/// are the host's, copied into the call here.
pub const Host = struct {
    ctx: *anyopaque,
    /// Host.member!.
    member: *const fn (ctx: *anyopaque) bool,
    /// Host.presence!.
    presence: *const fn (ctx: *anyopaque) void,
    /// Host.accounts!: every account (canonical folders, in the disk's
    /// order), its kind and its name file's bytes; the Roc does every
    /// lookup. **NEVER A READ OF THE AUTH ROOT'S SECRETS**: the folders,
    /// whether each has a password, each name.
    accounts: *const fn (ctx: *anyopaque) Accounts = noAccounts,
    /// Host.body!: read to `which` form's limit; null
    /// when the host answered (too big) or failed.
    body: *const fn (ctx: *anyopaque, which: route_mod.Form) ?[]const u8,
    /// Host.react!.
    react: *const fn (ctx: *anyopaque, conv: Conv, sid: []const u8, msg: u64, emoji: []const u8, on: bool) route_mod.Reacted,
    /// **THE FILE PRIMITIVES** (Host.read!, Host.write!, Host.remove!): a
    /// file under the chat root, `path` relative to it, its bytes and its
    /// name the Roc's. Every path is checked here first (`inRoot`); the host
    /// sees only one that stays under the root. `write` makes the folders;
    /// `remove` of a file not there succeeds. False, or `.failed`, when it
    /// failed (the host has failed the request).
    read: *const fn (ctx: *anyopaque, path: []const u8) Read = noRead,
    write: *const fn (ctx: *anyopaque, path: []const u8, bytes: []const u8) bool = noWrite,
    remove: *const fn (ctx: *anyopaque, path: []const u8) bool = noRemove,
    /// Host.list!: a folder under the chat root, its entries in the disk's
    /// order (`.missing` when it is not there), its path checked as the
    /// others'.
    list: *const fn (ctx: *anyopaque, path: []const u8) Listing = noListing,
    /// Fail the request with `e` (a 500), as a hosted function's own failure
    /// does: the seam's, for a path the Roc should never have named, and the
    /// Roc's own (Host.fail!, its reason as the error). A host that has
    /// failed already keeps its first failure.
    fail: *const fn (ctx: *anyopaque, e: anyerror) void = noFail,
    /// Host.malformed_channel!: channel `name`'s member file skipped by a
    /// listing as malformed, counted for the operator.
    malformed_channel: *const fn (ctx: *anyopaque, name: []const u8) void = noMalformed,
    /// Host.page!: topic `sid`'s page's data in `conv` (Pages.roc reads
    /// it), or none when it failed.
    page: *const fn (ctx: *anyopaque, conv: Conv, sid: []const u8) []const []const u8 = noPage,
    /// Host.srcs!: where a page names each script, as `name, src` pairs.
    srcs: *const fn (ctx: *anyopaque) []const []const u8 = noSrcs,
    /// Host.me!: the member's id.
    me: *const fn (ctx: *anyopaque) []const u8 = noBytes,
    /// Host.now!: the request's time, Unix seconds.
    now: *const fn (ctx: *anyopaque) i64 = noNow,
    /// Host.append!: a message appended to topic `sid` of `conv`. False
    /// when it failed.
    append: *const fn (ctx: *anyopaque, conv: Conv, sid: []const u8, name: []const u8, markdown: []const u8, cid: []const u8) bool = noAppend,
    /// Host.header!: a request header's value, or none.
    header: *const fn (ctx: *anyopaque, name: []const u8) []const []const u8 = noHeader,
    /// Host.hostile!.
    hostile: *const fn (ctx: *anyopaque, markdown: []const u8) route_mod.Hostility = noHostile,
    /// Host.raw!: whether the host holds topic `sid`'s transcript in
    /// `conv`, for a `held` answer.
    raw: *const fn (ctx: *anyopaque, conv: Conv, sid: []const u8) bool = noRaw,
    /// Host.links!: whether the host holds the member's links page
    /// rendered, for a `held` answer.
    links: *const fn (ctx: *anyopaque) bool = noHeld,
    /// Host.recent!: the member's recent rows, nine fields each, or none.
    recent: *const fn (ctx: *anyopaque) []const []const u8 = noList,
};

fn noHeld(_: *anyopaque) bool {
    @panic("links asked of a host that does not answer it");
}
fn noRaw(_: *anyopaque, _: Conv, _: []const u8) bool {
    @panic("raw asked of a host that does not answer it");
}
fn noRead(_: *anyopaque, _: []const u8) Read {
    @panic("read asked of a host that does not answer it");
}
fn noWrite(_: *anyopaque, _: []const u8, _: []const u8) bool {
    @panic("write asked of a host that does not answer it");
}
fn noRemove(_: *anyopaque, _: []const u8) bool {
    @panic("remove asked of a host that does not answer it");
}
fn noListing(_: *anyopaque, _: []const u8) Listing {
    @panic("list asked of a host that does not answer it");
}
fn noFail(_: *anyopaque, e: anyerror) void {
    std.debug.panic("a host that cannot fail a request was asked to: {t}", .{e});
}
fn noMalformed(_: *anyopaque, _: []const u8) void {
    @panic("malformed_channel asked of a host that does not answer it");
}
fn noAccounts(_: *anyopaque) Accounts {
    @panic("accounts asked of a host that does not answer it");
}
fn noHeader(_: *anyopaque, _: []const u8) []const []const u8 {
    @panic("header asked of a host that does not answer it");
}
fn noHostile(_: *anyopaque, _: []const u8) route_mod.Hostility {
    @panic("hostile asked of a host that does not answer it");
}

fn noBytes(_: *anyopaque) []const u8 {
    @panic("a hosted read asked of a host that does not answer it");
}
fn noNow(_: *anyopaque) i64 {
    @panic("now asked of a host that does not answer it");
}
fn noAppend(_: *anyopaque, _: Conv, _: []const u8, _: []const u8, _: []const u8, _: []const u8) bool {
    @panic("append asked of a host that does not answer it");
}

fn noPage(_: *anyopaque, _: Conv, _: []const u8) []const []const u8 {
    @panic("page asked of a host that does not answer it");
}
fn noList(_: *anyopaque) []const []const u8 {
    @panic("a hosted list asked of a host that does not answer it");
}
fn noSrcs(_: *anyopaque) []const []const u8 {
    @panic("srcs asked of a host that does not answer it");
}
var host: ?Host = null;

/// **A HOST FOR THE ROUTER ALONE**, for a test of its decisions: it says
/// whether the one asking is a member, records whether the Roc counted
/// presence itself, and has no conversation for the member (no id, no
/// channel), so a route the Roc serves goes to Zig as every other does.
pub const Routing = struct {
    member: bool = true,
    asked: bool = false,
    /// The Roc counted the request as presence itself (a route it serves).
    marked: bool = false,

    pub fn host(r: *Routing) Host {
        var h = askingOnly(r, ask);
        h.presence = mark;
        // The routes the Roc serves outright meet a member with nothing: no
        // id (so no DM is theirs), no files (no last DM, no feed, no
        // channel), no folders (no topics, no channels), no other members.
        h.me = empty;
        h.accounts = noAccount;
        h.read = noFile;
        h.list = noFolder;
        h.srcs = nothing;
        h.links = holdsNone;
        h.recent = nothing;
        return h;
    }
    fn of(ctx: *anyopaque) *Routing {
        return @ptrCast(@alignCast(ctx));
    }
    fn ask(ctx: *anyopaque) bool {
        of(ctx).asked = true;
        return of(ctx).member;
    }
    fn mark(ctx: *anyopaque) void {
        of(ctx).marked = true;
    }
    fn empty(_: *anyopaque) []const u8 {
        return "";
    }
    fn nothing(_: *anyopaque) []const []const u8 {
        return &.{};
    }
    fn holdsNone(_: *anyopaque) bool {
        return false;
    }
    fn noFile(_: *anyopaque, _: []const u8) Read {
        return .missing;
    }
    fn noAccount(_: *anyopaque) Accounts {
        return .{ .found = &.{} };
    }
    fn noFolder(_: *anyopaque, _: []const u8) Listing {
        return .missing;
    }
};

/// A host that answers who is asking and nothing else, for a test of the
/// router alone: any other hosted call is a panic.
pub fn askingOnly(ctx: *anyopaque, ask: *const fn (ctx: *anyopaque) bool) Host {
    const No = struct {
        fn presence(_: *anyopaque) void {
            @panic("presence asked of a host that only answers who is asking");
        }
        fn body(_: *anyopaque, _: route_mod.Form) ?[]const u8 {
            @panic("body asked of a host that only answers who is asking");
        }
        fn react(_: *anyopaque, _: Conv, _: []const u8, _: u64, _: []const u8, _: bool) route_mod.Reacted {
            @panic("react asked of a host that only answers who is asking");
        }
    };
    return .{ .ctx = ctx, .member = ask, .presence = No.presence, .body = No.body, .react = No.react };
}

/// The call's host, or a panic for a hosted function Roc ran outside one.
fn current(comptime name: []const u8) Host {
    if (!roc.inCall()) @panic("roc_chat_" ++ name ++ ": Roc asked outside a call (docs/ROC-CHAT.md R1)");
    return host orelse @panic("roc_chat_" ++ name ++ ": Roc asked outside a call (chat_abi.decide sets it)");
}

fn got(bytes: ?[]const u8) Got {
    const b = bytes orelse return .{ .bytes = .from(""), .ok = false };
    return .{ .bytes = .from(b), .ok = true };
}

export fn roc_chat_member() callconv(.c) bool {
    const h = current("member");
    return h.member(h.ctx);
}

export fn roc_chat_presence() callconv(.c) void {
    const h = current("presence");
    h.presence(h.ctx);
}

export fn roc_chat_accounts() callconv(.c) AccountsRec {
    const h = current("accounts");
    return switch (h.accounts(h.ctx)) {
        .found => |all| .{ .accounts = .from(all), .status = .found },
        .failed => .{ .accounts = .from(&.{}), .status = .failed },
    };
}

export fn roc_chat_body(which: route_mod.Form) callconv(.c) Got {
    const h = current("body");
    return got(h.body(h.ctx, which));
}

export fn roc_chat_react(conv: ConvRec, sid: RocBytes, msg: u64, emoji: RocBytes, on: bool) callconv(.c) route_mod.Reacted {
    const h = current("react");
    return h.react(h.ctx, .of(conv), sid.slice(), msg, emoji.slice(), on);
}

/// **A PATH THAT WOULD LEAVE THE CHAT ROOT IS A ROC BUG, NEVER A MISSING
/// FILE**: empty, absolute, or through `..` (roc_abi.inRoot). The request
/// fails (`error.PathOutsideChatRoot`, a 500) and the host is never asked:
/// a read answered "missing" there would be taken for an empty file and
/// written over.
fn underRoot(h: Host, path: []const u8) bool {
    if (roc.inRoot(path)) return true;
    h.fail(h.ctx, error.PathOutsideChatRoot);
    return false;
}

export fn roc_chat_read(path: RocBytes) callconv(.c) ReadRec {
    const h = current("read");
    if (!underRoot(h, path.slice())) return .{ .bytes = .from(""), .status = .failed };
    return switch (h.read(h.ctx, path.slice())) {
        .found => |b| .{ .bytes = .from(b), .status = .found },
        .missing => .{ .bytes = .from(""), .status = .missing },
        .failed => .{ .bytes = .from(""), .status = .failed },
    };
}

export fn roc_chat_write(path: RocBytes, bytes: RocBytes) callconv(.c) bool {
    const h = current("write");
    if (!underRoot(h, path.slice())) return false;
    return h.write(h.ctx, path.slice(), bytes.slice());
}

export fn roc_chat_remove(path: RocBytes) callconv(.c) bool {
    const h = current("remove");
    if (!underRoot(h, path.slice())) return false;
    return h.remove(h.ctx, path.slice());
}

export fn roc_chat_list(path: RocBytes) callconv(.c) ListRec {
    const h = current("list");
    if (!underRoot(h, path.slice())) return .{ .entries = .from(&.{}), .status = .failed };
    return switch (h.list(h.ctx, path.slice())) {
        .found => |entries| .{ .entries = .from(entries), .status = .found },
        .missing => .{ .entries = .from(&.{}), .status = .missing },
        .failed => .{ .entries = .from(&.{}), .status = .failed },
    };
}

/// **THE ROC FAILS THE REQUEST BY A REASON, NEVER BY TEXT**: the reason's
/// error is the one the Zig it replaced returned (a malformed channel on its
/// own route: error.MalformedChannel), so the answer and the log are the
/// same. The first failure is kept, as every other.
///
/// **A TAG UNION OF ONE TAG CROSSES AS NOTHING**: it is zero-sized, so Roc
/// passes no argument (a byte read here was garbage: the crash test's
/// `/fail`). With one reason, the reason is that one; a second makes it a
/// byte, and this export must then take `FailReason`, which the check below
/// refuses to forget.
export fn roc_chat_fail() callconv(.c) void {
    comptime if (@typeInfo(route_mod.FailReason).@"enum".field_names.len != 1)
        @compileError("Host.fail!'s reason now crosses as a byte: roc_chat_fail takes `reason: route_mod.FailReason`");
    const h = current("fail");
    h.fail(h.ctx, route_mod.FailReason.malformed_channel.err());
}

export fn roc_chat_malformed_channel(name: RocBytes) callconv(.c) void {
    const h = current("malformed_channel");
    h.malformed_channel(h.ctx, name.slice());
}

export fn roc_chat_page(conv: ConvRec, sid: RocBytes) callconv(.c) roc.RocBytesList {
    const h = current("page");
    return .from(h.page(h.ctx, .of(conv), sid.slice()));
}

export fn roc_chat_me() callconv(.c) RocBytes {
    const h = current("me");
    return .from(h.me(h.ctx));
}

export fn roc_chat_now() callconv(.c) i64 {
    const h = current("now");
    return h.now(h.ctx);
}

export fn roc_chat_append(conv: ConvRec, sid: RocBytes, name: RocBytes, markdown: RocBytes, cid: RocBytes) callconv(.c) bool {
    const h = current("append");
    return h.append(h.ctx, .of(conv), sid.slice(), name.slice(), markdown.slice(), cid.slice());
}

export fn roc_chat_header(name: RocBytes) callconv(.c) roc.RocBytesList {
    const h = current("header");
    return .from(h.header(h.ctx, name.slice()));
}

export fn roc_chat_hostile(markdown: RocBytes) callconv(.c) route_mod.Hostility {
    const h = current("hostile");
    return h.hostile(h.ctx, markdown.slice());
}

export fn roc_chat_raw(conv: ConvRec, sid: RocBytes) callconv(.c) bool {
    const h = current("raw");
    return h.raw(h.ctx, .of(conv), sid.slice());
}

export fn roc_chat_recent() callconv(.c) roc.RocBytesList {
    const h = current("recent");
    return .from(h.recent(h.ctx));
}

export fn roc_chat_links() callconv(.c) bool {
    const h = current("links");
    return h.links(h.ctx);
}

export fn roc_chat_srcs() callconv(.c) roc.RocBytesList {
    const h = current("srcs");
    return .from(h.srcs(h.ctx));
}

// ── a crash is a 500 (docs/ROC-CHAT.md R3, P9) ─────────────────────────────

/// **A ROC CRASH ENDS THE CALL, NOT THE SERVER**: a Roc `crash`, an
/// overflow or a failed allocation calls `roc_crashed`, which, inside a
/// call, jumps back to where the call began (`guarded`), so `decide`
/// answers `error.RocCrashed` and the site a 500. On metal, a crash that
/// stopped the machine would restart it, and a crash a stored request
/// causes would do so on every request. What Roc held is the call's arena,
/// dropped with it; what the host did inside the call (only answering
/// `member`) holds nothing.
var jump: sljmp.JmpBuf = undefined;

/// The last crash's message, for a test or a log (cut to its size).
pub var last_crash: [256]u8 = undefined;
pub var last_crash_len: usize = 0;

fn crashed(message: []const u8) noreturn {
    last_crash_len = @min(message.len, last_crash.len);
    @memcpy(last_crash[0..last_crash_len], message[0..last_crash_len]);
    sljmp.longjmp(&jump, 1);
}

/// The call, or null when Roc crashed inside it. Nothing of this frame is
/// read after the jump back but what `setjmp` answers: the answer is
/// written through `out` only on the way that returns normally. The
/// request's strings are made here, after `setjmp`: they are the call's
/// first allocations, and one that fails must jump back to this frame,
/// not to one already gone.
noinline fn guarded(sub: []const u8, channel: bool, method: Method, out: *Answer) bool {
    if (sljmp.setjmp(&jump) != 0) return false;
    out.* = roc_chat_handle(.{ .sub = .from(sub), .channel = channel, .method = method });
    return true;
}

/// The router's decision for `sub` (under /chat, or /channel when
/// `channel`) asked with `method`, its bytes copied into `alloc`, the Roc
/// call ended. A Roc crash is `error.RocCrashed`; a call inside or beside
/// another, `error.RocReentered`.
pub fn decide(alloc: std.mem.Allocator, sub: []const u8, channel: bool, method: std.http.Method, with: Host) !Decision {
    try roc.enter();
    defer roc.leave();
    host = with;
    defer host = null;
    const was = roc.crashed;
    roc.crashed = crashed;
    defer roc.crashed = was;
    defer roc.end();
    var a: Answer = undefined;
    if (!guarded(sub, channel, .of(method), &a)) return error.RocCrashed;
    return switch (a.kind) {
        .serve => .{ .serve = .{ .presence = a.presence, .route = .{
            .family = a.route.family,
            .part = a.route.part,
            .tail = a.route.tail,
            .key = try alloc.dupe(u8, a.route.key.slice()),
            .rest = try alloc.dupe(u8, a.route.rest.slice()),
            .sid = try alloc.dupe(u8, a.route.sid.slice()),
        } } },
        .redirect => .{ .redirect = try alloc.dupe(u8, a.location.slice()) },
        .respond => .{ .respond = .{ .status = a.status, .content_type = try alloc.dupe(u8, a.content_type.slice()), .body = try alloc.dupe(u8, a.body.slice()), .nosniff = a.nosniff } },
        .not_allowed => .{ .not_allowed = switch (a.allow) {
            .get => .GET,
            .head => .HEAD,
            .post => .POST,
            .other => std.debug.panic("roc_chat_handle: a 405 allowing no method", .{}),
        } },
        .answered => .answered,
        .malformed => .malformed_form,
        .not_found => .not_found,
        .found => .{ .found = try alloc.dupe(u8, a.location.slice()) },
        .held => .{ .held = .{ .status = a.status, .content_type = try alloc.dupe(u8, a.content_type.slice()), .nosniff = a.nosniff, .before = try alloc.dupe(u8, a.body.slice()), .after = try alloc.dupe(u8, a.location.slice()) } },
    };
}
