//! **THE ROC CHAT'S SIDE OF THE SEAM** (chat/platform/): the records
//! `roc_chat_handle` takes and answers, laid out as Roc lays them (Roc's
//! field order, as roc_abi.zig states it; sizes asserted below), and the hosted
//! functions (chat/platform/Host.roc), each answered by the host's `Host`
//! for the call. The runtime and the call's arena are roc_abi.zig's, shared
//! with any other Roc app in the binary.
//!
//! **THE DECISION LEAVES THE CALL**: `decide` copies what Roc answered into
//! the caller's allocator and ends the call before it returns, so the host
//! sends the answer with no Roc call open (docs/ROC-CHAT.md R1): its writes,
//! and on metal the network pumps inside them, nest nothing. What the Roc
//! has the host answer itself (an upload, a bundle, a script) is written
//! through the hosted functions, inside the call: a pump there runs the
//! kernel's turn and its fixed Zig render, never a handler, and the busy
//! word refuses any Roc call beside this one.
//!
//! **EVERY `roc_chat_` FUNCTION IS `pub`**: src/chat_glue_test.zig lists
//! them so, and holds each, record by record, to what `roc glue` makes of
//! Host.roc.

const std = @import("std");
const roc = @import("roc_abi.zig");
const route_mod = @import("chat_route.zig");
const sljmp = @import("sljmp.zig");
pub const Decision = route_mod.Decision;

pub const RocBytes = roc.RocBytes;

const Method = route_mod.Method;

/// Chat.roc's `Request`.
pub const Request = extern struct {
    sub: RocBytes,
    area: route_mod.Area,
    method: Method,
};
/// Chat.roc's `Answer`.
pub const Answer = extern struct {
    body: RocBytes,
    content_type: RocBytes,
    location: RocBytes,
    topic: RocBytes,
    status: u16,
    allow: Method,
    kind: route_mod.Kind,
    sniff: route_mod.Sniff,
};
/// Host.roc's `read_body!` answer: `{ bytes : List(U8), status : [Answered, Read] }`.
pub const Got = extern struct { bytes: RocBytes, status: route_mod.BodyStatus };
/// Host.roc's `read!` answer: `{ bytes : List(U8), status : [Failed, Found, Missing] }`.
pub const ReadRec = extern struct { bytes: RocBytes, status: route_mod.ReadStatus };
/// One of Host.roc's `list!` entries: `{ kind : [Dir, File, Other], name : List(U8) }`.
pub const EntryRec = extern struct { name: RocBytes, kind: route_mod.EntryKind };
/// Host.roc's `list!` answer: `{ entries : List(...), status : [Failed, Found, Missing] }`.
pub const ListRec = extern struct { entries: EntryList, status: route_mod.ReadStatus };
/// Host.roc's `stat!` answer: `{ mtime : I64, size : U64, status : [Failed,
/// Found, Missing] }`. **THE 8-BYTE FIELDS FIRST, BY NAME, THEN THE TAG**
/// (src/roc_abi.zig's rule): 24 bytes, the tag in the last word's first
/// byte. A missing or failed stat's size and mtime are 0.
pub const StatRec = extern struct {
    mtime: i64,
    size: u64,
    status: route_mod.ReadStatus,
};
/// One of Host.roc's `srcs!` scripts: `{ name : List(U8), src : List(U8) }`.
pub const SrcRec = extern struct { name: RocBytes, src: RocBytes };
/// One of Host.roc's `search_words!` words: `{ count : U64, word : List(U8)
/// }`. **THE 8-BYTE COUNT FIRST, THEN THE BYTES** (src/roc_abi.zig's rule).
pub const WordRec = extern struct { count: u64, word: RocBytes };
/// Host.roc's `search_words!` answer: `{ status : [NotReady, Ready],
/// unreadable : U64, words : List(...) }`: the count, the list, then the tag.
pub const WordsRec = extern struct {
    unreadable: u64,
    words: WordList,
    status: route_mod.WordsStatus,
};
/// One of Host.roc's `search_messages!` hits: `{ at, length, start : U64,
/// base, date, from, id, sid, window : List(U8), found, kind }`. **THE
/// 8-BYTE NUMBERS FIRST, BY NAME, THEN THE BYTES, BY NAME, THEN THE TAGS.**
/// `window` is the message's bytes from `start`, through the one past the
/// excerpt's end (its cut looks there), of a message `length` long; `at`
/// where the word is in the message, when `found`.
pub const HitRec = extern struct {
    at: u64,
    length: u64,
    start: u64,
    base: RocBytes,
    date: RocBytes,
    from: RocBytes,
    id: RocBytes,
    sid: RocBytes,
    window: RocBytes,
    found: route_mod.HitWord,
    kind: route_mod.HitConv,
};
/// Host.roc's `search_messages!` answer: `{ hits : List(...), matched,
/// unreadable : U64, status : [NotReady, Ready] }`: the numbers, the list,
/// the tag.
pub const MessagesRec = extern struct {
    matched: u64,
    unreadable: u64,
    hits: HitList,
    status: route_mod.WordsStatus,
};
/// One of Host.roc's `list_accounts!` accounts: `{ id : List(U8), kind : [Agent, Guest, Member, Unreadable], name : List(U8), name_read : [Found, Unreadable] }`.
pub const AccountRec = extern struct {
    id: RocBytes,
    name: RocBytes,
    kind: route_mod.AccountKind,
    name_read: route_mod.NameRead,
};
/// Host.roc's `list_accounts!` answer: `{ accounts : List(...), status : [Failed, Found] }`.
pub const AccountsRec = extern struct { accounts: AccountList, status: route_mod.AccountsStatus };
/// Host.roc's `render!` answer: `{ html : List(U8), status : [Failed, Rendered] }`.
pub const RenderRec = extern struct { html: RocBytes, status: route_mod.RenderStatus };
/// Chat.roc's `Message`: `{ id, from, at, uid, markdown }`, every field
/// `List(U8)`, so laid out by name alone.
pub const MessageRec = extern struct {
    at: RocBytes,
    from: RocBytes,
    id: RocBytes,
    markdown: RocBytes,
    uid: RocBytes,
};
/// Host.roc's `mark_aside!` answer: `{ fault : U16, status : [Done, Failed] }`.
pub const AsideRec = extern struct { fault: u16, status: route_mod.AsideEnd };
/// Host.roc's `append!` answer: `{ size : U64, status : [Appended,
/// Failed] }`, the file's size after the append.
pub const AppendedRec = extern struct { size: u64, status: route_mod.AppendStatus };
/// Host.roc's `index_message!` record (metal-vmm QUEUE 297): `{ sid :
/// List(U8), message : Chat.Message }`, by name.
pub const IndexMessageArgs = extern struct { message: MessageRec, sid: RocBytes };
/// Host.roc's `report_fanout_failure!` record (metal-vmm QUEUE 297):
/// `{ member, key, sid : List(U8), fault : U16 }`, the bytes by name, the
/// fault last.
pub const FanoutFailureArgs = extern struct { key: RocBytes, member: RocBytes, sid: RocBytes, fault: u16 };
/// Host.roc's `serve_upload!` record (metal-vmm QUEUE 291): `{ first, last,
/// size : U64, content_type, path : List(U8), part : [Range, Unsatisfiable,
/// Whole] }`, the numbers first, the bytes by name, the tag last.
/// Host.roc's `read_upload!` answer (metal-vmm QUEUE 292): `{ size : U64,
/// ext, filename : List(U8), status }`, the number first, the bytes by name,
/// the tag last.
pub const UploadReadRec = extern struct {
    size: u64,
    ext: RocBytes,
    filename: RocBytes,
    status: route_mod.UploadRead,
};
/// Host.roc's `store_upload!` answer: `{ name : List(U8), status : [Failed,
/// Stored] }`, a ReadRec's shape.
pub const StoredRec = extern struct { name: RocBytes, status: route_mod.UploadStored };
/// Host.roc's `retire_asked!` answer (metal-vmm QUEUE 293): `{ days : U64,
/// keep : List(U8), now : I64 }`, the numbers first by name, then the bytes.
pub const RetireAskedRec = extern struct { days: u64, now: i64, keep: RocBytes };
pub const UploadRec = extern struct {
    first: u64,
    last: u64,
    size: u64,
    content_type: RocBytes,
    path: RocBytes,
    part: route_mod.UploadPart,
};
/// Host.roc's `check_online!` answer, `List([Offline, Online])`: its elements one
/// byte each, so laid out as a `List(U8)` is.
pub const PresenceList = RocBytes;

/// A Roc list of `Rec`, each made of an `Item` by `rec`: its elements hold
/// a refcounted list, so it has the two-word header (count, refcount) a
/// `List(List(U8))` has.
fn RecList(
    comptime Rec: type,
    comptime Item: type,
    comptime rec: fn (Item) Rec,
) type {
    return extern struct {
        ptr: ?[*]Rec,
        length: usize,
        capacity_or_alloc_ptr: usize,

        fn from(items: []const Item) @This() {
            if (items.len == 0) return .{
                .ptr = null,
                .length = 0,
                .capacity_or_alloc_ptr = 0,
            };
            const w = @sizeOf(usize);
            const base = roc.allocate(2 * w + items.len * @sizeOf(Rec), w);
            std.mem.writeInt(
                usize,
                base[0..w],
                items.len,
                .little,
            );
            std.mem.writeInt(
                usize,
                base[w..][0..w],
                1,
                .little,
            );
            const elems: [*]Rec = @ptrCast(@alignCast(base + 2 * w));
            for (items, 0..) |it, k| elems[k] = rec(it);
            return .{
                .ptr = elems,
                .length = items.len,
                .capacity_or_alloc_ptr = items.len << 1,
            };
        }
    };
}

pub const EntryList = RecList(EntryRec, Entry, struct {
    fn rec(it: Entry) EntryRec {
        return .{ .name = .from(it.name), .kind = it.kind };
    }
}.rec);

pub const WordList = RecList(WordRec, Word, struct {
    fn rec(it: Word) WordRec {
        return .{ .count = it.count, .word = .from(it.word) };
    }
}.rec);

pub const HitList = RecList(HitRec, Hit, struct {
    fn rec(it: Hit) HitRec {
        return .{
            .at = it.at,
            .length = it.length,
            .start = it.start,
            .base = .from(it.base),
            .date = .from(it.date),
            .from = .from(it.from),
            .id = .from(it.id),
            .sid = .from(it.sid),
            .window = .from(it.window),
            .found = it.found,
            .kind = it.kind,
        };
    }
}.rec);

pub const SrcList = RecList(SrcRec, Src, struct {
    fn rec(it: Src) SrcRec {
        return .{ .name = .from(it.name), .src = .from(it.src) };
    }
}.rec);

pub const AccountList = RecList(AccountRec, Account, struct {
    fn rec(it: Account) AccountRec {
        return switch (it.name) {
            .found => |name| .{
                .id = .from(it.id),
                .name = .from(name),
                .kind = it.kind,
                .name_read = .found,
            },
            .unreadable => .{
                .id = .from(it.id),
                .name = .from(""),
                .kind = it.kind,
                .name_read = .unreadable,
            },
        };
    }
}.rec);

comptime {
    const w = @sizeOf(usize);
    std.debug.assert(@sizeOf(RocBytes) == 3 * w and @sizeOf(Request) == 4 * w and @sizeOf(Answer) == 13 * w and @sizeOf(Got) == 4 * w and @sizeOf(ReadRec) == 4 * w and @sizeOf(EntryRec) == 4 * w and @sizeOf(SrcRec) == 6 * w and @sizeOf(ListRec) == 4 * w and @sizeOf(AccountRec) == 7 * w and @sizeOf(AccountsRec) == 4 * w and @sizeOf(RenderRec) == 4 * w and @sizeOf(MessageRec) == 15 * w);
    std.debug.assert(@sizeOf(AsideRec) == 4 and @offsetOf(AsideRec, "fault") == 0 and @offsetOf(AsideRec, "status") == 2);
    std.debug.assert(@sizeOf(AppendedRec) == 16 and @offsetOf(AppendedRec, "size") == 0 and @offsetOf(AppendedRec, "status") == 8);
    // read_upload!'s and store_upload!'s (metal-vmm QUEUE 292).
    std.debug.assert(@offsetOf(UploadReadRec, "size") == 0 and
        @offsetOf(UploadReadRec, "ext") == 8 and
        @offsetOf(UploadReadRec, "filename") == 8 + 3 * w and
        @offsetOf(UploadReadRec, "status") == 8 + 6 * w and
        @sizeOf(UploadReadRec) == std.mem.alignForward(usize, 8 + 6 * w + 1, 8));
    std.debug.assert(@offsetOf(StoredRec, "name") == 0 and @offsetOf(StoredRec, "status") == 3 * w and @sizeOf(StoredRec) == 4 * w);
    // The hosted effects' argument records (metal-vmm QUEUE 297).
    std.debug.assert(@offsetOf(IndexMessageArgs, "message") == 0 and @offsetOf(IndexMessageArgs, "sid") == 15 * w and @sizeOf(IndexMessageArgs) == 18 * w);
    std.debug.assert(@offsetOf(FanoutFailureArgs, "key") == 0 and @offsetOf(FanoutFailureArgs, "member") == 3 * w and @offsetOf(FanoutFailureArgs, "sid") == 6 * w and @offsetOf(FanoutFailureArgs, "fault") == 9 * w and @sizeOf(FanoutFailureArgs) == 10 * w);
    // retire_asked!'s (metal-vmm QUEUE 293).
    std.debug.assert(@offsetOf(RetireAskedRec, "days") == 0 and @offsetOf(RetireAskedRec, "now") == 8 and @offsetOf(RetireAskedRec, "keep") == 16 and @sizeOf(RetireAskedRec) == 16 + 3 * w);
    // serve_upload!'s (metal-vmm QUEUE 291): three numbers, two lists, a tag.
    std.debug.assert(@offsetOf(UploadRec, "first") == 0 and
        @offsetOf(UploadRec, "last") == 8 and
        @offsetOf(UploadRec, "size") == 16 and
        @offsetOf(UploadRec, "content_type") == 24 and
        @offsetOf(UploadRec, "path") == 24 + 3 * w and
        @offsetOf(UploadRec, "part") == 24 + 6 * w and
        @sizeOf(UploadRec) == std.mem.alignForward(usize, 24 + 6 * w + 1, 8));
    // search_words!'s (metal-vmm QUEUE 281): the 8-byte numbers at 0, the
    // bytes and the list after, the tag last.
    std.debug.assert(@offsetOf(
        WordRec,
        "count",
    ) == 0 and @offsetOf(WordRec, "word") == 8 and @sizeOf(WordRec) == std.mem.alignForward(
        usize,
        8 + 3 * w,
        8,
    ));
    // search_messages!'s (metal-vmm QUEUE 282).
    std.debug.assert(@offsetOf(HitRec, "at") == 0 and @offsetOf(
        HitRec,
        "length",
    ) == 8 and @offsetOf(HitRec, "start") == 16 and @offsetOf(HitRec, "base") == 24 and @offsetOf(
        HitRec,
        "window",
    ) == 24 + 15 * w and @offsetOf(
        HitRec,
        "found",
    ) == 24 + 18 * w and @offsetOf(
        HitRec,
        "kind",
    ) == 25 + 18 * w and @sizeOf(HitRec) == std.mem.alignForward(
        usize,
        26 + 18 * w,
        8,
    ));
    std.debug.assert(@offsetOf(MessagesRec, "matched") == 0 and @offsetOf(
        MessagesRec,
        "unreadable",
    ) == 8 and @offsetOf(MessagesRec, "hits") == 16 and @offsetOf(
        MessagesRec,
        "status",
    ) == 16 + 3 * w and @sizeOf(MessagesRec) == std.mem.alignForward(
        usize,
        17 + 3 * w,
        8,
    ));
    std.debug.assert(@offsetOf(
        WordsRec,
        "unreadable",
    ) == 0 and @offsetOf(WordsRec, "words") == 8 and @offsetOf(
        WordsRec,
        "status",
    ) == 8 + 3 * w and @sizeOf(WordsRec) == std.mem.alignForward(
        usize,
        8 + 3 * w + 1,
        8,
    ));
    std.debug.assert(@sizeOf(StatRec) == 24 and @offsetOf(StatRec, "size") == 8 and @offsetOf(
        StatRec,
        "status",
    ) == 16);
    std.debug.assert(@sizeOf(route_mod.Presence) == 1);
    // **A FAULT IS THE HOST'S ERROR, CARRIED BY THE ROC AS A NUMBER** it
    // never reads (`@intFromError`), handed back to say it: it fits a U16.
    std.debug.assert(@bitSizeOf(anyerror) <= 16);
}

/// **A FILE AS THE HOST READ IT**: its bytes, nothing there, or a read that
/// failed (the host has failed the request: `fail`). Missing and failed are
/// never one answer: a set read as empty because the disk failed would be
/// written back empty.
pub const Read = union(route_mod.ReadStatus) {
    failed,
    found: []const u8,
    missing,
};

/// A folder's entry: its name and its kind.
pub const Entry = struct { name: []const u8, kind: route_mod.EntryKind };

/// **A FOLDER AS THE HOST LISTED IT**: its entries, in the order the disk
/// gives them; nothing there; or a listing that failed (the host has failed
/// the request). Missing and failed are never one answer.
pub const Listing = union(route_mod.ReadStatus) {
    failed,
    found: []const Entry,
    missing,
};
/// One word search_words! answers: the word, and how many messages hold it.
pub const Word = struct { word: []const u8, count: u64 };
/// One message search_messages! answers: its conversation's URL base and
/// kind, its topic, id, sender and date, and its excerpt's window (HitRec).
pub const Hit = struct {
    base: []const u8,
    kind: route_mod.HitConv,
    sid: []const u8,
    id: []const u8,
    from: []const u8,
    date: []const u8,
    window: []const u8,
    start: u64,
    length: u64,
    at: u64,
    found: route_mod.HitWord,
};
/// search_messages!'s answer, where there is an index.
pub const Messages = struct {
    hits: []const Hit,
    matched: u64,
    unreadable: u64,
};
/// search_words!'s answer, where there is an index.
pub const Words = struct { words: []const Word, unreadable: u64 };
/// A file's size in bytes and its last change in whole seconds since the
/// epoch, as stat! answers them.
pub const Stat = union(route_mod.ReadStatus) {
    failed,
    found: struct { size: u64, mtime: i64 },
    missing,
};

/// A script a page names: its name and its src.
pub const Src = struct { name: []const u8, src: []const u8 };

/// An account as the host read it: its id (a canonical folder's name), its
/// kind (`.unreadable` when its password's stat failed), its `name` file's
/// bytes as stored ("" when it has none) or a read of them that failed.
/// **AN ACCOUNT THAT WILL NOT READ IS STILL LISTED, ITS ERROR THE HOST'S**:
/// the request fails only when a lookup needs what failed (Host.fail!,
/// `fail_account`), as the Zig it replaced failed only the reads that
/// touched it.
pub const Account = struct {
    id: []const u8,
    kind: route_mod.AccountKind,
    name: Name,
};

/// An account's name file: its bytes ("" when there is none), or a read
/// that failed. Never "" for a read that failed.
pub const Name = union(route_mod.NameRead) { found: []const u8, unreadable };

/// **EVERY ACCOUNT, OR A LISTING OF THEM THAT FAILED** (the host has failed
/// the request): never "no accounts" for a listing that failed.
pub const Accounts = union(route_mod.AccountsStatus) { failed, found: []const Account };

/// **A TOPIC'S MESSAGES AS THE HOST COUNTED THEM**, or a count that failed
/// (the host has failed the request): never 0 for a count that failed.
pub const Count = union(route_mod.CountStatus) { counted: u64, failed };

/// **A MESSAGE'S MARKDOWN AS THE HOST RENDERED IT**, or a render that
/// failed (the host has failed the request): never "" for one that failed.
pub const Rendered = union(route_mod.RenderStatus) { failed, rendered: []const u8 };

/// Host.read_upload!'s answer, its bytes as slices: the file's size, the
/// extension its bytes say and the client's name for it.
pub const UploadRead = union(route_mod.UploadRead) {
    answered,
    no_file,
    read: struct { size: u64, ext: []const u8, filename: []const u8 },
    unsupported,
};

/// Host.retire_asked!'s answer: the admin's days, the names kept (one to a
/// line) and now.
pub const RetireAsked = struct { days: u64, keep: []const u8, now: i64 };

/// Host.store_upload!'s answer: the fresh name, or `.failed`.
pub const Stored = union(route_mod.UploadStored) { failed, stored: []const u8 };

/// An upload as Host.serve_upload! names it (UploadRec, its bytes as slices).
pub const Upload = struct {
    first: u64,
    last: u64,
    size: u64,
    content_type: []const u8,
    path: []const u8,
    part: route_mod.UploadPart,
};

/// A message as the Roc made it (Chat.Message): what the store's count and
/// search, and the fan-out, take. Its bytes are the call's.
pub const Message = struct {
    id: []const u8,
    from: []const u8,
    at: []const u8,
    uid: []const u8,
    markdown: []const u8,

    fn of(r: MessageRec) Message {
        return .{
            .id = r.id.slice(),
            .from = r.from.slice(),
            .at = r.at.slice(),
            .uid = r.uid.slice(),
            .markdown = r.markdown.slice(),
        };
    }
};

/// What Host.append! answers: the file's size after the append, or that it
/// failed (the host has failed the request, or the aside).
pub const Appended = union(route_mod.AppendStatus) { appended: u64, failed };

/// What Host.aside! answers: done, or the error something in it failed
/// with (at `end`; at `begin`, the request's own, which has failed).
pub const AsideOutcome = union(route_mod.AsideEnd) { done, failed: anyerror };

/// Which of an account's reads a lookup needed, and failed on: its kind
/// (the password's stat) or its name.
pub const AccountRead = enum { kind, name };

pub extern fn roc_chat_handle(req: Request) callconv(.c) Answer;

/// **WHAT ANSWERS THE HOSTED FUNCTIONS** during a call: the host's, with its
/// own context (the request, its `Io`). Set by `decide` for the call alone.
/// Bytes handed in are the call's, good until it ends; bytes handed back
/// are the host's, copied into the call here.
pub const Host = struct {
    ctx: *anyopaque,
    /// Host.check_member!.
    check_member: *const fn (ctx: *anyopaque) route_mod.Membership,
    /// Host.count_presence!: the member marked online now; whether this was
    /// the edge (metal-vmm QUEUE 288).
    count_presence: *const fn (ctx: *anyopaque) route_mod.PresenceEdge,
    /// Host.presence_unspent!: the edge's broadcast lost; due again later.
    presence_unspent: *const fn (ctx: *anyopaque) void = noUnspent,
    /// Host.list_accounts!: every account (canonical folders, in the disk's
    /// order), its kind and its name file's bytes; the Roc does every
    /// lookup. **NEVER A READ OF THE AUTH ROOT'S SECRETS**: the folders,
    /// whether each has a password, each name. An account whose own read
    /// failed is listed as unreadable there, and the host keeps the error
    /// for `fail_account`; only a listing of the auth root that failed is
    /// `.failed` (and fails the request).
    list_accounts: *const fn (ctx: *anyopaque) Accounts = noAccounts,
    /// Host.fail! for an account a lookup needed: fail the request with the
    /// error account `id`'s `read` failed with when `accounts` listed it,
    /// as the host kept it. An id whose read did not fail is the Roc's bug,
    /// and fails the request all the same.
    fail_account: *const fn (
        ctx: *anyopaque,
        read: AccountRead,
        id: []const u8,
    ) void = noFailAccount,
    /// Host.read_body!: read to `which` form's limit; null
    /// when the host answered (too big) or failed.
    read_body: *const fn (ctx: *anyopaque, which: route_mod.Form) ?[]const u8,
    /// Host.publish!: webbox's bus.publish, `bytes` to every subscriber on
    /// `key` (each its own copy, so the call's bytes may go with it). It
    /// cannot fail.
    publish: *const fn (
        ctx: *anyopaque,
        key: []const u8,
        bytes: []const u8,
    ) void = noPublish,
    /// Host.append!: `bytes` appended to the file at `path` under the chat
    /// root (checked here first, as the file primitives' are), its folders
    /// made; the file's size after, or `.failed` (the host has failed the
    /// request, or the aside; nothing stored).
    append: *const fn (
        ctx: *anyopaque,
        path: []const u8,
        bytes: []const u8,
    ) Appended = noAppend,
    /// **THE FILE PRIMITIVES** (Host.read!, Host.write!, Host.remove!): a
    /// file under the chat root, `path` relative to it, its bytes and its
    /// name the Roc's. Every path is checked here first (`inRoot`); the host
    /// sees only one that stays under the root. `write` makes the folders;
    /// `remove` of a file not there succeeds. `.failed` when it
    /// failed (the host has failed the request).
    read: *const fn (ctx: *anyopaque, path: []const u8) Read = noRead,
    /// Host.stat!: a file's size and mtime, under the chat root.
    stat: *const fn (ctx: *anyopaque, path: []const u8) Stat = noStat,
    /// Host.read_at!: at most `max` bytes of a file from `offset`.
    read_at: *const fn (
        ctx: *anyopaque,
        path: []const u8,
        offset: u64,
        max: u64,
    ) Read = noReadAt,
    write: *const fn (
        ctx: *anyopaque,
        path: []const u8,
        bytes: []const u8,
    ) route_mod.Done = noWrite,
    remove: *const fn (ctx: *anyopaque, path: []const u8) route_mod.Done = noRemove,
    /// Host.list!: a folder under the chat root, its entries in the disk's
    /// order (`.missing` when it is not there), its path checked as the
    /// others'.
    list: *const fn (ctx: *anyopaque, path: []const u8) Listing = noListing,
    /// Fail the request with `e` (a 500), as a hosted function's own failure
    /// does: the seam's, for a path the Roc should never have named, and the
    /// Roc's own for a malformed channel (Host.fail!). A host that has
    /// failed already keeps its first failure.
    fail: *const fn (ctx: *anyopaque, e: anyerror) void = noFail,
    /// Host.fail!'s `NotUtf8`: the file at `path` under the chat root read
    /// as bytes that are not UTF-8, which the Roc refuses at its door. The
    /// host fails the request (error.NotUtf8), saying the path.
    fail_text: *const fn (ctx: *anyopaque, path: []const u8) void = noFailText,
    /// Host.count_malformed_channel!: channel `name`'s member file skipped by a
    /// listing as malformed, counted for the operator.
    count_malformed_channel: *const fn (ctx: *anyopaque, name: []const u8) void = noMalformed,
    /// Host.count_dropped!: something the chat dropped rather than fail the
    /// request for (`what`, about `whose`: a topic, a feed's path, a recent
    /// row's key), counted for the operator.
    count_dropped: *const fn (
        ctx: *anyopaque,
        what: route_mod.Dropped,
        whose: []const u8,
    ) void = noDropped,
    /// Host.aside!: from `begin` to `end`, a failure is the aside's, kept
    /// apart and answered at `end` (its error, which the seam hands the Roc
    /// as a fault), never the request's; after one, the aside's later calls
    /// do nothing, as after a request's failure. Asides nest: one begun
    /// inside another ends first, its failure its own.
    aside: *const fn (ctx: *anyopaque, which: route_mod.Aside) AsideOutcome = noAside,
    /// Host.check_online!, asked by the seam once for each of the Roc's ids:
    /// whether `id` was seen within the presence window of the request's
    /// time. A read of process-lifetime state; it cannot fail.
    check_online: *const fn (ctx: *anyopaque, id: []const u8) route_mod.Presence = noOnline,
    /// Host.admit!: whether the member may search now.
    admit: *const fn (ctx: *anyopaque) route_mod.Admission = noAdmit,
    /// Host.read_query!: the query field's value, as written, or none.
    read_query: *const fn (ctx: *anyopaque, name: []const u8) []const []const u8 = noQuery,
    /// Host.search_words!: the words beginning `key`, at most `most`; null
    /// when there is no index.
    search_words: *const fn (
        ctx: *anyopaque,
        key: []const u8,
        most: u64,
    ) ?Words = noWords,
    /// Host.search_messages!: the messages holding `key`, at most `most`;
    /// null when there is no index.
    search_messages: *const fn (
        ctx: *anyopaque,
        key: []const u8,
        most: u64,
    ) ?Messages = noMessages,
    /// Host.welcome_pending!: whether the member's welcome is pending, a
    /// fact signup wrote (metal-vmm QUEUE 283).
    welcome_pending: *const fn (ctx: *anyopaque) route_mod.Welcome = noWelcome,
    /// Host.welcome_done!: the member's welcome given; the pending mark goes.
    welcome_done: *const fn (ctx: *anyopaque) route_mod.Done = noWelcomeDone,
    /// Host.srcs!: where a page names each script, by its name.
    srcs: *const fn (ctx: *anyopaque) []const Src = noSrcs,
    /// Host.me!: the member's id.
    me: *const fn (ctx: *anyopaque) []const u8 = noBytes,
    /// Host.now!: the request's time, Unix seconds.
    now: *const fn (ctx: *anyopaque) i64 = noNow,
    /// Host.render!: a message's markdown as its frame's HTML, or `.failed`
    /// (the host has failed the request).
    render: *const fn (ctx: *anyopaque, markdown: []const u8) Rendered = noRender,
    /// Host.render_preview!: as `render`, and hostile markdown counted.
    render_preview: *const fn (ctx: *anyopaque, markdown: []const u8) Rendered = noRenderPreview,
    /// Host.index_message!: the search index told of `message`, topic `sid`
    /// of the conversation whose folder is `dir` under the chat root (the
    /// seam has checked both). It cannot fail.
    index_message: *const fn (
        ctx: *anyopaque,
        dir: []const u8,
        sid: []const u8,
        message: Message,
    ) void = noIndexMessage,
    /// Host.write_cache!: a cache's whole file under the chat root (the seam
    /// has checked the path). A write that failed is the host's to log,
    /// never the request's failure.
    write_cache: *const fn (
        ctx: *anyopaque,
        path: []const u8,
        bytes: []const u8,
    ) void = noWriteCache,
    /// Host.report_fanout_failure!: `surface` failed for `member` with `e`, on
    /// topic `sid` of the conversation keyed `key`: counted and said, the
    /// operator's (/admin/host). **NEVER THE REQUEST'S FAILURE.**
    report_fanout_failure: *const fn (
        ctx: *anyopaque,
        surface: route_mod.Surface,
        member: []const u8,
        key: []const u8,
        sid: []const u8,
        e: anyerror,
    ) void = noFanoutFailed,
    /// Host.read_header!: a request header's value, or none.
    read_header: *const fn (ctx: *anyopaque, name: []const u8) []const []const u8 = noHeader,
    /// Host.check_hostile!: `refusal` what a refusal says.
    check_hostile: *const fn (
        ctx: *anyopaque,
        markdown: []const u8,
        refusal: []const u8,
    ) route_mod.Hostility = noHostile,
    /// Host.serve_file!: `.serving` when the host holds the bytes of the file at `path`
    /// under the chat root (the seam has checked it), for a `held` answer.
    serve_file: *const fn (ctx: *anyopaque, path: []const u8) route_mod.Serving = noServeFile,
    /// Host.serve_rendered!: `.serving` when the host holds the file at `path` under the
    /// chat root (the seam has checked it) rendered as the server's own
    /// markdown, for a `held` answer.
    serve_rendered: *const fn (
        ctx: *anyopaque,
        path: []const u8,
    ) route_mod.Serving = noServeRendered,
    /// Host.serve_upload!: the upload answered, or gone since the Roc's look.
    serve_upload: *const fn (ctx: *anyopaque, upload: Upload) route_mod.UploadServed = noServeUpload,
    /// Host.read_upload!: the form read and its file sniffed, its bytes held.
    read_upload: *const fn (ctx: *anyopaque) UploadRead = noReadUpload,
    /// Host.refuse_upload!: refused on the edge counter `why`, answered `message`.
    refuse_upload: *const fn (ctx: *anyopaque, why: route_mod.UploadRefusal, message: []const u8) void = noRefuseUpload,
    /// Host.reserve_upload!: the member's allowance spent by `size`, if it holds it.
    reserve_upload: *const fn (ctx: *anyopaque, size: u64) route_mod.Reservation = noReserveUpload,
    /// Host.store_upload!: the held bytes stored in `folder` as `<fresh>.<ext>`.
    store_upload: *const fn (ctx: *anyopaque, folder: []const u8, ext: []const u8) Stored = noStoreUpload,
    /// Host.bundle_add!: the file at `path` added to the bundle as `name`.
    bundle_add: *const fn (ctx: *anyopaque, name: []const u8, path: []const u8) route_mod.Done = noBundleAdd,
    /// Host.serve_bundle!: the bundle answered as `<name>.tar.gz`.
    serve_bundle: *const fn (ctx: *anyopaque, name: []const u8) void = noServeBundle,
    /// Host.serve_script!: the script `name` of the host's table answered,
    /// or `.missing` (nothing answered) when the table has none of the name.
    serve_script: *const fn (ctx: *anyopaque, name: []const u8) route_mod.ScriptServed = noServeScript,
    /// Host.retire_asked!: the admin retire's days, names kept and now.
    retire_asked: *const fn (ctx: *anyopaque) RetireAsked = noRetireAsked,
    /// Host.retire_note!: a step of the retire's plan said for its report.
    retire_note: *const fn (ctx: *anyopaque, kind: route_mod.RetireKind, label: []const u8) void = noRetireNote,
    /// Host.retire_remove!: the file or folder removed on a confirm.
    retire_remove: *const fn (ctx: *anyopaque, path: []const u8, what: route_mod.RetireRemoval) route_mod.Done = noRetireRemove,
    /// Host.retire_replace!: the file written whole on a confirm.
    retire_replace: *const fn (ctx: *anyopaque, path: []const u8, bytes: []const u8) route_mod.Done = noRetireReplace,
    /// Host.retire_user!: the member retired outside the chat on a confirm.
    retire_user: *const fn (ctx: *anyopaque, uid: []const u8) route_mod.Done = noRetireUser,
};

fn noPublish(
    _: *anyopaque,
    _: []const u8,
    _: []const u8,
) void {
    @panic("publish asked of a host that does not answer it");
}
fn noAppend(
    _: *anyopaque,
    _: []const u8,
    _: []const u8,
) Appended {
    @panic("append asked of a host that does not answer it");
}
fn noRetireAsked(_: *anyopaque) RetireAsked {
    @panic("retire_asked asked of a host that does not answer it");
}
fn noRetireNote(_: *anyopaque, _: route_mod.RetireKind, _: []const u8) void {
    @panic("retire_note asked of a host that does not answer it");
}
fn noRetireRemove(_: *anyopaque, _: []const u8, _: route_mod.RetireRemoval) route_mod.Done {
    @panic("retire_remove asked of a host that does not answer it");
}
fn noRetireReplace(_: *anyopaque, _: []const u8, _: []const u8) route_mod.Done {
    @panic("retire_replace asked of a host that does not answer it");
}
fn noRetireUser(_: *anyopaque, _: []const u8) route_mod.Done {
    @panic("retire_user asked of a host that does not answer it");
}
fn noReadUpload(_: *anyopaque) UploadRead {
    @panic("read_upload asked of a host that does not answer it");
}
fn noRefuseUpload(_: *anyopaque, _: route_mod.UploadRefusal, _: []const u8) void {
    @panic("refuse_upload asked of a host that does not answer it");
}
fn noReserveUpload(_: *anyopaque, _: u64) route_mod.Reservation {
    @panic("reserve_upload asked of a host that does not answer it");
}
fn noStoreUpload(_: *anyopaque, _: []const u8, _: []const u8) Stored {
    @panic("store_upload asked of a host that does not answer it");
}
fn noServeUpload(_: *anyopaque, _: Upload) route_mod.UploadServed {
    @panic("serve_upload asked of a host that does not answer it");
}
fn noBundleAdd(_: *anyopaque, _: []const u8, _: []const u8) route_mod.Done {
    @panic("bundle_add asked of a host that does not answer it");
}
fn noServeBundle(_: *anyopaque, _: []const u8) void {
    @panic("serve_bundle asked of a host that does not answer it");
}
fn noServeScript(_: *anyopaque, _: []const u8) route_mod.ScriptServed {
    @panic("serve_script asked of a host that does not answer it");
}
fn noServeRendered(_: *anyopaque, _: []const u8) route_mod.Serving {
    @panic("serve_rendered asked of a host that does not answer it");
}
fn noServeFile(_: *anyopaque, _: []const u8) route_mod.Serving {
    @panic("serve_file asked of a host that does not answer it");
}
fn noStat(_: *anyopaque, _: []const u8) Stat {
    @panic("stat asked of a host that does not answer it");
}
fn noReadAt(
    _: *anyopaque,
    _: []const u8,
    _: u64,
    _: u64,
) Read {
    @panic("read_at asked of a host that does not answer it");
}
fn noRead(_: *anyopaque, _: []const u8) Read {
    @panic("read asked of a host that does not answer it");
}
fn noWrite(
    _: *anyopaque,
    _: []const u8,
    _: []const u8,
) route_mod.Done {
    @panic("write asked of a host that does not answer it");
}
fn noRemove(_: *anyopaque, _: []const u8) route_mod.Done {
    @panic("remove asked of a host that does not answer it");
}
fn noListing(_: *anyopaque, _: []const u8) Listing {
    @panic("list asked of a host that does not answer it");
}
fn noFail(_: *anyopaque, e: anyerror) void {
    std.debug.panic("a host that cannot fail a request was asked to: {t}", .{e});
}
fn noFailText(_: *anyopaque, path: []const u8) void {
    std.debug.panic("a host that cannot fail a request was asked to, for {s}, not UTF-8", .{path});
}
fn noMalformed(_: *anyopaque, _: []const u8) void {
    @panic("count_malformed_channel asked of a host that does not answer it");
}
fn noDropped(
    _: *anyopaque,
    _: route_mod.Dropped,
    _: []const u8,
) void {
    @panic("count_dropped asked of a host that does not answer it");
}
fn noAside(_: *anyopaque, _: route_mod.Aside) AsideOutcome {
    @panic("aside asked of a host that does not answer it");
}
fn noAccounts(_: *anyopaque) Accounts {
    @panic("list_accounts asked of a host that does not answer it");
}
fn noFailAccount(
    _: *anyopaque,
    read: AccountRead,
    id: []const u8,
) void {
    std.debug.panic(
        "a host that listed no account was asked to fail on account {s}'s {t}",
        .{ id, read },
    );
}
fn noHeader(_: *anyopaque, _: []const u8) []const []const u8 {
    @panic("read_header asked of a host that does not answer it");
}
fn noHostile(
    _: *anyopaque,
    _: []const u8,
    _: []const u8,
) route_mod.Hostility {
    @panic("check_hostile asked of a host that does not answer it");
}

fn noBytes(_: *anyopaque) []const u8 {
    @panic("a hosted read asked of a host that does not answer it");
}
fn noNow(_: *anyopaque) i64 {
    @panic("now asked of a host that does not answer it");
}
fn noRender(_: *anyopaque, _: []const u8) Rendered {
    @panic("render asked of a host that does not answer it");
}
fn noRenderPreview(_: *anyopaque, _: []const u8) Rendered {
    @panic("render_preview asked of a host that does not answer it");
}
fn noUnspent(_: *anyopaque) void {
    @panic("presence_unspent asked of a host that does not answer it");
}
fn noIndexMessage(_: *anyopaque, _: []const u8, _: []const u8, _: Message) void {
    @panic("index_message asked of a host that does not answer it");
}
fn noWriteCache(_: *anyopaque, _: []const u8, _: []const u8) void {
    @panic("write_cache asked of a host that does not answer it");
}
fn noFanoutFailed(
    _: *anyopaque,
    _: route_mod.Surface,
    _: []const u8,
    _: []const u8,
    _: []const u8,
    _: anyerror,
) void {
    @panic("report_fanout_failure asked of a host that does not answer it");
}

fn noAdmit(_: *anyopaque) route_mod.Admission {
    @panic("admit asked of a host that does not answer it");
}
fn noQuery(_: *anyopaque, _: []const u8) []const []const u8 {
    @panic("read_query asked of a host that does not answer it");
}
fn noWords(
    _: *anyopaque,
    _: []const u8,
    _: u64,
) ?Words {
    @panic("search_words asked of a host that does not answer it");
}
fn noMessages(
    _: *anyopaque,
    _: []const u8,
    _: u64,
) ?Messages {
    @panic("search_messages asked of a host that does not answer it");
}
fn noWelcome(_: *anyopaque) route_mod.Welcome {
    @panic("welcome_pending asked of a host that does not answer it");
}
fn noWelcomeDone(_: *anyopaque) route_mod.Done {
    @panic("welcome_done asked of a host that does not answer it");
}
fn noOnline(_: *anyopaque, _: []const u8) route_mod.Presence {
    @panic("check_online asked of a host that does not answer it");
}
fn noSrcs(_: *anyopaque) []const Src {
    @panic("srcs asked of a host that does not answer it");
}
/// Every script a chat page names, each its own name as its src: a test
/// host's `srcs`, since a name the host does not answer crashes the page.
pub const test_srcs = blk: {
    const names = [_][]const u8{
        "colors.js",
        "viewport.js",
        "chat_theme.js",
        "chrome_drawer.js",
        "chat_add_topic.js",
        "chat_first_topic.js",
        "recent.js",
        "notify.js",
        "styles.js",
        "chat_image_popup.js",
        "images.js",
        "chat_code_popup.js",
        "code.js",
        "chat_time_popup.js",
        "chat_save_popup.js",
        "message.js",
        "message_view.js",
        "nav_stack.js",
        "middle_pane.js",
        "chat_search.js",
        "chat_drag_to_pin.js",
        "chat_left_sidebar.js",
        "chat_right_sidebar.js",
        "chat_emoji.js",
        "chat_reactions.js",
        "chat_compose.js",
        "chat_help.js",
        "chat_responsive.js",
        "chat.js",
    };
    var out: [names.len]Src = undefined;
    for (names, &out) |n, *o| o.* = .{ .name = n, .src = n };
    break :blk out;
};
pub fn everyScript(_: *anyopaque) []const Src {
    return &test_srcs;
}

var host: ?Host = null;

/// **A HOST FOR THE ROUTER ALONE**, for a test of its decisions: it says
/// whether the one asking is a member, records whether the Roc counted
/// presence and which script it had served, and has no conversation for the
/// member (no id, no channel), so a route meets nothing there.
pub const Routing = struct {
    member: bool = true,
    asked: bool = false,
    /// The Roc counted the request as presence.
    marked: bool = false,
    /// The script the Roc had served (Host.serve_script!), one of
    /// `test_srcs`; null when it served none.
    script: ?[]const u8 = null,

    pub fn host(r: *Routing) Host {
        var h = askingOnly(r, ask);
        h.count_presence = mark;
        // The routes the Roc serves outright meet a member with nothing: an
        // id in no route's DM (so no DM is theirs; an id is always a uid,
        // or the Roc fails the request), no files (no last DM, no feed, no
        // channel), no folders (no topics, no channels), no other members.
        h.me = noDmId;
        h.list_accounts = noAccount;
        h.read = noFile;
        h.list = noFolder;
        h.srcs = everyScript;
        h.serve_script = scriptOf;
        h.serve_rendered = holdsNone;
        // An aside (the welcome on /chat) that meets no host account does nothing.
        h.aside = asideDone;
        // Search's words (metal-vmm QUEUE 281) meet an index with none.
        h.admit = admitted;
        h.read_query = noQueryField;
        h.search_words = noWordsHeld;
        h.search_messages = noMessagesHeld;
        // No member's welcome is pending (metal-vmm QUEUE 283).
        h.welcome_pending = noneWelcome;
        return h;
    }
    fn of(ctx: *anyopaque) *Routing {
        return @ptrCast(@alignCast(ctx));
    }
    fn ask(ctx: *anyopaque) route_mod.Membership {
        of(ctx).asked = true;
        return if (of(ctx).member) .member else .outsider;
    }
    fn mark(ctx: *anyopaque) route_mod.PresenceEdge {
        of(ctx).marked = true;
        return .steady;
    }
    fn noDmId(_: *anyopaque) []const u8 {
        return "999";
    }
    fn holdsNone(_: *anyopaque, _: []const u8) route_mod.Serving {
        return .not_serving;
    }
    fn scriptOf(ctx: *anyopaque, name: []const u8) route_mod.ScriptServed {
        for (test_srcs) |s| if (std.mem.eql(u8, s.name, name)) {
            of(ctx).script = s.name;
            return .served;
        };
        return .missing;
    }
    fn noFile(_: *anyopaque, _: []const u8) Read {
        return .missing;
    }
    fn noAccount(_: *anyopaque) Accounts {
        return .{ .found = &.{} };
    }
    fn asideDone(_: *anyopaque, _: route_mod.Aside) AsideOutcome {
        return .done;
    }
    fn admitted(_: *anyopaque) route_mod.Admission {
        return .admitted;
    }
    fn noQueryField(_: *anyopaque, _: []const u8) []const []const u8 {
        return &.{};
    }
    fn noWordsHeld(
        _: *anyopaque,
        _: []const u8,
        _: u64,
    ) ?Words {
        return .{ .words = &.{}, .unreadable = 0 };
    }
    fn noMessagesHeld(
        _: *anyopaque,
        _: []const u8,
        _: u64,
    ) ?Messages {
        return .{
            .hits = &.{},
            .matched = 0,
            .unreadable = 0,
        };
    }
    fn noFolder(_: *anyopaque, _: []const u8) Listing {
        return .missing;
    }
    fn noneWelcome(_: *anyopaque) route_mod.Welcome {
        return .none;
    }
};

/// A host that answers who is asking and nothing else, for a test of the
/// router alone: any other hosted call is a panic.
pub fn askingOnly(ctx: *anyopaque, ask: *const fn (ctx: *anyopaque) route_mod.Membership) Host {
    const No = struct {
        fn presence(_: *anyopaque) route_mod.PresenceEdge {
            @panic("count_presence asked of a host that only answers who is asking");
        }
        fn body(_: *anyopaque, _: route_mod.Form) ?[]const u8 {
            @panic("read_body asked of a host that only answers who is asking");
        }
    };
    return .{
        .ctx = ctx,
        .check_member = ask,
        .count_presence = No.presence,
        .read_body = No.body,
    };
}

/// The call's host, or a panic for a hosted function Roc ran outside one.
fn current(comptime name: []const u8) Host {
    if (!roc.inCall()) @panic("roc_chat_" ++ name ++ ": Roc asked outside a call (docs/ROC-CHAT.md R1)");
    return host orelse @panic("roc_chat_" ++ name ++ ": Roc asked outside a call (chat_abi.decide sets it)");
}

fn got(bytes: ?[]const u8) Got {
    const b = bytes orelse return .{ .bytes = .from(""), .status = .answered };
    return .{ .bytes = .from(b), .status = .read };
}

pub export fn roc_chat_check_member() callconv(.c) route_mod.Membership {
    const h = current("check_member");
    return h.check_member(h.ctx);
}

pub export fn roc_chat_count_presence() callconv(.c) route_mod.PresenceEdge {
    const h = current("count_presence");
    return h.count_presence(h.ctx);
}

pub export fn roc_chat_presence_unspent() callconv(.c) void {
    const h = current("presence_unspent");
    h.presence_unspent(h.ctx);
}

pub export fn roc_chat_list_accounts() callconv(.c) AccountsRec {
    const h = current("list_accounts");
    return switch (h.list_accounts(h.ctx)) {
        .found => |all| .{ .accounts = .from(all), .status = .found },
        .failed => .{ .accounts = .from(&.{}), .status = .failed },
    };
}

pub export fn roc_chat_read_body(which: route_mod.Form) callconv(.c) Got {
    const h = current("read_body");
    return got(h.read_body(h.ctx, which));
}

pub export fn roc_chat_publish(key: RocBytes, bytes: RocBytes) callconv(.c) void {
    const h = current("publish");
    h.publish(
        h.ctx,
        key.slice(),
        bytes.slice(),
    );
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

pub export fn roc_chat_read(path: RocBytes) callconv(.c) ReadRec {
    const h = current("read");
    if (!underRoot(h, path.slice())) return .{ .bytes = .from(""), .status = .failed };
    return switch (h.read(h.ctx, path.slice())) {
        .found => |b| .{ .bytes = .from(b), .status = .found },
        .missing => .{ .bytes = .from(""), .status = .missing },
        .failed => .{ .bytes = .from(""), .status = .failed },
    };
}

pub export fn roc_chat_read_stat(path: RocBytes) callconv(.c) StatRec {
    const h = current("stat");
    if (!underRoot(h, path.slice())) return .{
        .mtime = 0,
        .size = 0,
        .status = .failed,
    };
    return switch (h.stat(h.ctx, path.slice())) {
        .found => |st| .{
            .mtime = st.mtime,
            .size = st.size,
            .status = .found,
        },
        .missing => .{
            .mtime = 0,
            .size = 0,
            .status = .missing,
        },
        .failed => .{
            .mtime = 0,
            .size = 0,
            .status = .failed,
        },
    };
}

/// **NEVER MORE THAN `max`**: a host that hands back more is cut to it
/// here, so the Roc's window is the window it asked for.
pub export fn roc_chat_read_at(
    path: RocBytes,
    offset: u64,
    max: u64,
) callconv(.c) ReadRec {
    const h = current("read_at");
    if (!underRoot(h, path.slice())) return .{ .bytes = .from(""), .status = .failed };
    return switch (h.read_at(
        h.ctx,
        path.slice(),
        offset,
        max,
    )) {
        .found => |b| .{ .bytes = .from(b[0..@min(b.len, max)]), .status = .found },
        .missing => .{ .bytes = .from(""), .status = .missing },
        .failed => .{ .bytes = .from(""), .status = .failed },
    };
}

pub export fn roc_chat_write(path: RocBytes, bytes: RocBytes) callconv(.c) route_mod.Done {
    const h = current("write");
    if (!underRoot(h, path.slice())) return .failed;
    return h.write(
        h.ctx,
        path.slice(),
        bytes.slice(),
    );
}

pub export fn roc_chat_remove(path: RocBytes) callconv(.c) route_mod.Done {
    const h = current("remove");
    if (!underRoot(h, path.slice())) return .failed;
    return h.remove(h.ctx, path.slice());
}

pub export fn roc_chat_append(path: RocBytes, bytes: RocBytes) callconv(.c) AppendedRec {
    const h = current("append");
    if (!underRoot(h, path.slice())) return .{ .size = 0, .status = .failed };
    return switch (h.append(
        h.ctx,
        path.slice(),
        bytes.slice(),
    )) {
        .appended => |size| .{ .size = size, .status = .appended },
        .failed => .{ .size = 0, .status = .failed },
    };
}

pub export fn roc_chat_list(path: RocBytes) callconv(.c) ListRec {
    const h = current("list");
    if (!underRoot(h, path.slice())) return .{ .entries = .from(&.{}), .status = .failed };
    return switch (h.list(h.ctx, path.slice())) {
        .found => |entries| .{ .entries = .from(entries), .status = .found },
        .missing => .{ .entries = .from(&.{}), .status = .missing },
        .failed => .{ .entries = .from(&.{}), .status = .failed },
    };
}

/// **THE ROC FAILS THE REQUEST BY A REASON, NEVER BY TEXT**, about `whose`
/// (the channel's name; the account's id): the error is the one the Zig it
/// replaced returned, so the answer and the log are the same. A malformed
/// channel on its own route is error.MalformedChannel; an account a lookup
/// needed and that would not read is the error its own read failed with,
/// which the host kept when it listed the accounts (`fail_account`). The
/// first failure is kept, as every other.
///
/// **A TAG UNION OF ONE TAG CROSSES AS NOTHING**: it is zero-sized, so Roc
/// passes no argument for it (a byte read here was garbage). The reason is
/// a byte only while FailReason has two tags or more, which the check below
/// holds.
pub export fn roc_chat_fail(reason: route_mod.FailReason, whose: RocBytes) callconv(.c) void {
    comptime if (@typeInfo(route_mod.FailReason).@"enum".field_names.len < 2)
        @compileError("Host.fail!'s reason of one tag crosses as nothing: roc_chat_fail must not take it");
    const h = current("fail");
    switch (reason) {
        .malformed_channel => h.fail(h.ctx, error.MalformedChannel),
        .kind_unreadable => h.fail_account(
            h.ctx,
            .kind,
            whose.slice(),
        ),
        .name_unreadable => h.fail_account(
            h.ctx,
            .name,
            whose.slice(),
        ),
        .no_author => h.fail(h.ctx, error.NoAuthor),
        .not_a_uid => h.fail(h.ctx, error.NotAUid),
        .not_utf8 => h.fail_text(h.ctx, whose.slice()),
        .short_read => h.fail(h.ctx, error.ShortRead),
    }
}

pub export fn roc_chat_count_malformed_channel(name: RocBytes) callconv(.c) void {
    const h = current("count_malformed_channel");
    h.count_malformed_channel(h.ctx, name.slice());
}

pub export fn roc_chat_count_dropped(what: route_mod.Dropped, whose: RocBytes) callconv(.c) void {
    const h = current("count_dropped");
    h.count_dropped(
        h.ctx,
        what,
        whose.slice(),
    );
}

pub export fn roc_chat_mark_aside(which: route_mod.Aside) callconv(.c) AsideRec {
    const h = current("aside");
    return switch (h.aside(h.ctx, which)) {
        .done => .{ .fault = 0, .status = .done },
        .failed => |e| .{ .fault = faultOf(e), .status = .failed },
    };
}

/// **ONE FLAG FOR EACH ID, IN ITS PLACE**: the Roc asks once for the whole
/// roster, and the seam asks the host id by id, so the answer is exactly as
/// long as the ids and never out of their order.
pub export fn roc_chat_check_welcome() callconv(.c) route_mod.Welcome {
    const h = current("welcome_pending");
    return h.welcome_pending(h.ctx);
}

pub export fn roc_chat_clear_welcome() callconv(.c) route_mod.Done {
    const h = current("welcome_done");
    return h.welcome_done(h.ctx);
}

pub export fn roc_chat_admit() callconv(.c) route_mod.Admission {
    const h = current("admit");
    return h.admit(h.ctx);
}

pub export fn roc_chat_read_query(name: RocBytes) callconv(.c) roc.RocBytesList {
    const h = current("read_query");
    return .from(h.read_query(h.ctx, name.slice()));
}

pub export fn roc_chat_search_words(key: RocBytes, most: u64) callconv(.c) WordsRec {
    const h = current("search_words");
    const found = h.search_words(
        h.ctx,
        key.slice(),
        most,
    ) orelse return .{
        .unreadable = 0,
        .words = .from(&.{}),
        .status = .not_ready,
    };
    return .{
        .unreadable = found.unreadable,
        .words = .from(found.words),
        .status = .ready,
    };
}

pub export fn roc_chat_search_messages(key: RocBytes, most: u64) callconv(.c) MessagesRec {
    const h = current("search_messages");
    const found = h.search_messages(
        h.ctx,
        key.slice(),
        most,
    ) orelse return .{
        .matched = 0,
        .unreadable = 0,
        .hits = .from(&.{}),
        .status = .not_ready,
    };
    return .{
        .matched = found.matched,
        .unreadable = found.unreadable,
        .hits = .from(found.hits),
        .status = .ready,
    };
}

pub export fn roc_chat_check_online(ids: roc.RocBytesList) callconv(.c) PresenceList {
    const h = current("check_online");
    const items = ids.slice();
    const flags = roc.alloc().alloc(
        u8,
        items.len,
    ) catch @panic("roc_chat: out of memory for the presence flags");
    for (items, flags) |*id, *f| f.* = @backingInt(h.check_online(h.ctx, id.slice()));
    return .from(flags);
}

pub export fn roc_chat_read_uid() callconv(.c) RocBytes {
    const h = current("me");
    return .from(h.me(h.ctx));
}

pub export fn roc_chat_read_time() callconv(.c) i64 {
    const h = current("now");
    return h.now(h.ctx);
}

pub export fn roc_chat_render(markdown: RocBytes) callconv(.c) RenderRec {
    const h = current("render");
    return renderRec(h.render(h.ctx, markdown.slice()));
}

pub export fn roc_chat_render_preview(markdown: RocBytes) callconv(.c) RenderRec {
    const h = current("render_preview");
    return renderRec(h.render_preview(h.ctx, markdown.slice()));
}

fn renderRec(r: Rendered) RenderRec {
    return switch (r) {
        .rendered => |html| .{ .html = .from(html), .status = .rendered },
        .failed => .{ .html = .from(""), .status = .failed },
    };
}

/// **THE INDEX IS TOLD ONLY OF A FOLDER AND A TOPIC THAT ARE ONE**: after
/// the store, nothing fails the send (STORED IS DONE), so a folder that
/// would leave the chat root, or a topic that is not one part, is told
/// nothing, never the request's failure.
pub export fn roc_chat_index_message(dir: RocBytes, args: IndexMessageArgs) callconv(.c) void {
    const sid = args.sid;
    const message = args.message;
    const h = current("index_message");
    if (!roc.inRoot(dir.slice()) or !onePart(sid.slice())) return;
    h.index_message(
        h.ctx,
        dir.slice(),
        sid.slice(),
        .of(message),
    );
}

pub export fn roc_chat_write_cache(path: RocBytes, bytes: RocBytes) callconv(.c) void {
    const h = current("write_cache");
    if (!underRoot(h, path.slice())) return;
    h.write_cache(h.ctx, path.slice(), bytes.slice());
}

/// An error as the Roc carries it: a number only the host reads. **EVERY
/// NUMBER HANDED OUT IS KEPT** (`issued`), so the one the Roc hands back is
/// checked before it is made an error again (`errorOf`): any other number
/// is no error at all, and `@errorFromInt` of it would be illegal behaviour.
fn faultOf(e: anyerror) u16 {
    const n = @intFromError(e);
    issued.set(n);
    return n;
}
var issued: std.StaticBitSet(1 << 16) = .empty;

/// The error a fault from `faultOf` names, or null for a number it never
/// handed out (0, or the Roc's garbage).
fn errorOf(fault: u16) ?anyerror {
    if (fault == 0 or !issued.isSet(fault)) return null;
    return @errorFromInt(fault);
}

/// **A NAME THE HOST JOINS INTO A PATH IS ONE PART OF IT** (metal-vmm QUEUE
/// 268, defense in depth): a topic as the index takes it is checked as
/// `underRoot` checks a path, and holds no `/`.
fn onePart(name: []const u8) bool {
    return roc.inRoot(name) and std.mem.indexOfScalar(
        u8,
        name,
        '/',
    ) == null;
}

pub export fn roc_chat_report_fanout_failure(surface: route_mod.Surface, args: FanoutFailureArgs) callconv(.c) void {
    const member = args.member;
    const key = args.key;
    const sid = args.sid;
    const fault = args.fault;
    comptime if (@typeInfo(route_mod.Surface).@"enum".field_names.len < 2)
        @compileError("Host.report_fanout_failure!'s surface of one tag crosses as nothing: roc_chat_report_fanout_failure must not take it");
    const h = current("report_fanout_failure");
    // A fault the seam never handed out is the Roc's bug: the request's
    // failure, never illegal behaviour here (metal-vmm QUEUE 268).
    const e = errorOf(fault) orelse return h.fail(h.ctx, error.FaultNotIssued);
    h.report_fanout_failure(
        h.ctx,
        surface,
        member.slice(),
        key.slice(),
        sid.slice(),
        e,
    );
}

pub export fn roc_chat_read_header(name: RocBytes) callconv(.c) roc.RocBytesList {
    const h = current("read_header");
    return .from(h.read_header(h.ctx, name.slice()));
}

pub export fn roc_chat_check_hostile(
    markdown: RocBytes,
    refusal: RocBytes,
) callconv(.c) route_mod.Hostility {
    const h = current("check_hostile");
    return h.check_hostile(
        h.ctx,
        markdown.slice(),
        refusal.slice(),
    );
}

pub export fn roc_chat_serve_file(path: RocBytes) callconv(.c) route_mod.Serving {
    const h = current("serve_file");
    if (!underRoot(h, path.slice())) return .not_serving;
    return h.serve_file(h.ctx, path.slice());
}

pub export fn roc_chat_read_upload() callconv(.c) UploadReadRec {
    const h = current("read_upload");
    return switch (h.read_upload(h.ctx)) {
        .read => |f| .{ .size = f.size, .ext = .from(f.ext), .filename = .from(f.filename), .status = .read },
        .answered => .{ .size = 0, .ext = .from(""), .filename = .from(""), .status = .answered },
        .no_file => .{ .size = 0, .ext = .from(""), .filename = .from(""), .status = .no_file },
        .unsupported => .{ .size = 0, .ext = .from(""), .filename = .from(""), .status = .unsupported },
    };
}

pub export fn roc_chat_refuse_upload(why: route_mod.UploadRefusal, message: RocBytes) callconv(.c) void {
    const h = current("refuse_upload");
    h.refuse_upload(h.ctx, why, message.slice());
}

pub export fn roc_chat_retire_asked() callconv(.c) RetireAskedRec {
    const h = current("retire_asked");
    const it = h.retire_asked(h.ctx);
    return .{ .days = it.days, .now = it.now, .keep = .from(it.keep) };
}

pub export fn roc_chat_retire_note(kind: route_mod.RetireKind, label: RocBytes) callconv(.c) void {
    const h = current("retire_note");
    h.retire_note(h.ctx, kind, label.slice());
}

pub export fn roc_chat_retire_remove(path: RocBytes, what: route_mod.RetireRemoval) callconv(.c) route_mod.Done {
    const h = current("retire_remove");
    if (!underRoot(h, path.slice())) return .failed;
    return h.retire_remove(h.ctx, path.slice(), what);
}

pub export fn roc_chat_retire_replace(path: RocBytes, bytes: RocBytes) callconv(.c) route_mod.Done {
    const h = current("retire_replace");
    if (!underRoot(h, path.slice())) return .failed;
    return h.retire_replace(h.ctx, path.slice(), bytes.slice());
}

/// **A UID THE HOST JOINS INTO EVERY ROOT IS ONE** (metal-vmm QUEUE 293):
/// digits with no leading zero, as an account is made, or the request's
/// failure, the host never asked.
pub export fn roc_chat_retire_user(uid: RocBytes) callconv(.c) route_mod.Done {
    const h = current("retire_user");
    if (!isUid(uid.slice())) {
        h.fail(h.ctx, error.NotAUid);
        return .failed;
    }
    return h.retire_user(h.ctx, uid.slice());
}

fn isUid(s: []const u8) bool {
    if (s.len == 0 or s[0] == '0') return false;
    for (s) |c| if (c < '0' or c > '9') return false;
    return true;
}

pub export fn roc_chat_reserve_upload(size: u64) callconv(.c) route_mod.Reservation {
    const h = current("reserve_upload");
    return h.reserve_upload(h.ctx, size);
}

pub export fn roc_chat_store_upload(folder: RocBytes, ext: RocBytes) callconv(.c) StoredRec {
    const h = current("store_upload");
    if (!underRoot(h, folder.slice())) return .{ .name = .from(""), .status = .failed };
    return switch (h.store_upload(h.ctx, folder.slice(), ext.slice())) {
        .stored => |name| .{ .name = .from(name), .status = .stored },
        .failed => .{ .name = .from(""), .status = .failed },
    };
}

pub export fn roc_chat_serve_upload(rec: UploadRec) callconv(.c) route_mod.UploadServed {
    const h = current("serve_upload");
    if (!underRoot(h, rec.path.slice())) return .gone;
    return h.serve_upload(h.ctx, .{
        .first = rec.first,
        .last = rec.last,
        .size = rec.size,
        .content_type = rec.content_type.slice(),
        .path = rec.path.slice(),
        .part = rec.part,
    });
}

pub export fn roc_chat_bundle_add(name: RocBytes, path: RocBytes) callconv(.c) route_mod.Done {
    const h = current("bundle_add");
    if (!underRoot(h, path.slice())) return .failed;
    return h.bundle_add(h.ctx, name.slice(), path.slice());
}

pub export fn roc_chat_serve_bundle(name: RocBytes) callconv(.c) void {
    const h = current("serve_bundle");
    h.serve_bundle(h.ctx, name.slice());
}

pub export fn roc_chat_serve_script(name: RocBytes) callconv(.c) route_mod.ScriptServed {
    const h = current("serve_script");
    return h.serve_script(h.ctx, name.slice());
}

pub export fn roc_chat_serve_rendered(path: RocBytes) callconv(.c) route_mod.Serving {
    const h = current("serve_rendered");
    if (!underRoot(h, path.slice())) return .not_serving;
    return h.serve_rendered(h.ctx, path.slice());
}

pub export fn roc_chat_list_srcs() callconv(.c) SrcList {
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
noinline fn guarded(
    sub: []const u8,
    area: route_mod.Area,
    method: Method,
    out: *Answer,
) bool {
    if (sljmp.setjmp(&jump) != 0) return false;
    out.* = roc_chat_handle(.{
        .sub = .from(sub),
        .area = area,
        .method = method,
    });
    return true;
}

/// The router's decision for `sub` (under /chat, or /channel when
/// `channel`) asked with `method`, its bytes copied into `alloc`, the Roc
/// call ended. A Roc crash is `error.RocCrashed`; a call inside or beside
/// another, `error.RocReentered`.
pub fn decide(
    alloc: std.mem.Allocator,
    sub: []const u8,
    channel: bool,
    method: std.http.Method,
    with: Host,
) !Decision {
    return call(alloc, sub, if (channel) .channel else .chat, method, with);
}

/// **THE ADMIN RETIRE** (metal-vmm QUEUE 293), asked of the one entry in
/// its own area, so it shares the chat's guard (the crash's jump, one call
/// at a time, the Roc's memory ended) and none of the chat's prelude: the
/// Roc reads its days and names (Host.retire_asked!), plans, and hands each
/// step to `with`. Its decision: a keep list refused (`respond` 400, the
/// reason), the plan handed over (`respond` 200), or `answered` when the
/// host failed it.
pub fn retire(alloc: std.mem.Allocator, with: Host) !Decision {
    return call(alloc, "", .retire, .POST, with);
}

fn call(
    alloc: std.mem.Allocator,
    sub: []const u8,
    area: route_mod.Area,
    method: std.http.Method,
    with: Host,
) !Decision {
    try roc.enter();
    defer roc.leave();
    host = with;
    defer host = null;
    const was = roc.crashed;
    roc.crashed = crashed;
    defer roc.crashed = was;
    defer roc.end();
    var a: Answer = undefined;
    if (!guarded(
        sub,
        area,
        .of(method),
        &a,
    )) return error.RocCrashed;
    return switch (a.kind) {
        .redirect => .{ .redirect = try alloc.dupe(u8, a.location.slice()) },
        .respond => .{ .respond = .{
            .status = a.status,
            .content_type = try alloc.dupe(u8, a.content_type.slice()),
            .body = try alloc.dupe(u8, a.body.slice()),
            .nosniff = a.sniff == .forbid,
        } },
        .not_allowed => .{
            .not_allowed = switch (a.allow) {
                .get => .GET,
                .head => .HEAD,
                .post => .POST,
                // The Roc's bug, the request's 500, never a panic (QUEUE 268).
                .other => return error.NotAllowedNoMethod,
            },
        },
        .answered => .answered,
        .malformed => .malformed_form,
        .not_found => .not_found,
        .found => .{ .found = try alloc.dupe(u8, a.location.slice()) },
        .to_login => .{ .to_login = try alloc.dupe(u8, a.location.slice()) },
        .stream => blk: {
            // A transcript the host replays is a file the Roc names, held
            // to the chat root as every file call is (QUEUE 268).
            if (a.body.slice().len > 0 and !roc.inRoot(a.body.slice())) return error.PathOutsideChatRoot;
            break :blk .{ .stream = .{
                .key = try alloc.dupe(u8, a.location.slice()),
                .transcript = try alloc.dupe(u8, a.body.slice()),
                .topic = try alloc.dupe(u8, a.topic.slice()),
            } };
        },
        .held => .{ .held = .{
            .status = a.status,
            .content_type = try alloc.dupe(u8, a.content_type.slice()),
            .nosniff = a.sniff == .forbid,
            .before = try alloc.dupe(u8, a.body.slice()),
            .after = try alloc.dupe(u8, a.location.slice()),
        } },
    };
}

test "a fault is an error again only if the seam handed it out: 0 and any other number are none (metal-vmm QUEUE 268)" {
    const n = faultOf(error.IsDir);
    try std.testing.expectEqual(@as(?anyerror, error.IsDir), errorOf(n));
    try std.testing.expectEqual(@as(?anyerror, null), errorOf(0));
    // A number past every error this binary has: never handed out.
    try std.testing.expectEqual(@as(?anyerror, null), errorOf(std.math.maxInt(u16)));
}

test "a key or a topic the host joins into a path is one part of it: never empty, absolute, `..` or holding a `/` (metal-vmm QUEUE 268)" {
    try std.testing.expect(onePart("1_2") and onePart("Plans") and onePart("ops"));
    for ([_][]const u8{
        "",
        "..",
        "/etc",
        "a/b",
        "1_2/../x",
    }) |bad| try std.testing.expect(!onePart(bad));
}
