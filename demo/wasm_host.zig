//! ╔════════════════════════════════════════════════════════════════════╗
//! ║ NOT THE SERVER. A TEST BENCH FOR THE CLIENT (web/index.html) ONLY.  ║
//! ╚════════════════════════════════════════════════════════════════════╝
//!
//! The Roc app (app/todo.roc) built for wasm32 and run in a browser tab,
//! so the page can be tried without a webbox host anywhere. host.js hands
//! it the page's /api/ requests; its file effects go to the page's storage
//! (host.js's `files`), not to webbox.store. Nothing here is the real host:
//! that is src/ (roc_files.zig, todo_app.zig), on webbox's Linux host or its
//! bare-metal one. What this shares with it is the Roc app and the runtime
//! (src/roc_abi.zig), so the client meets the same answers it will there.

const std = @import("std");
const roc = @import("roc_abi");
const RocStr = roc.RocStr;

// ── what host.js gives ──────────────────────────────────────────────────────

/// Each file call answers 0 (found, or done), 1 (no such file) or 2
/// (failed), and leaves text for `js_take`: the file's, or why it failed.
extern "env" fn js_file_read(path: [*]const u8, path_len: usize) u32;
extern "env" fn js_file_write(path: [*]const u8, path_len: usize, text: [*]const u8, text_len: usize) u32;
extern "env" fn js_file_delete(path: [*]const u8, path_len: usize) u32;
extern "env" fn js_pending_len() usize;
extern "env" fn js_take(dst: [*]u8) void;
/// A Roc crash: host.js throws, with Roc's message.
extern "env" fn js_crashed(message: [*]const u8, len: usize) noreturn;

fn pending() []const u8 {
    const buf = roc.alloc().alloc(u8, js_pending_len()) catch @panic("out of memory");
    js_take(buf.ptr);
    return buf;
}

fn crashed(message: []const u8) noreturn {
    js_crashed(message.ptr, message.len);
}

// ── the hosted functions (platform/File.roc), over host.js's storage ────────

export fn roc_file_read(path: RocStr) callconv(.c) roc.Read {
    const p = path.slice();
    if (!roc.inRoot(p)) return .{ .text = .from("a path outside the data root"), .status = roc.read_failed };
    const status: u8 = @intCast(js_file_read(p.ptr, p.len));
    return .{ .text = .from(pending()), .status = status };
}

export fn roc_file_write(path: RocStr, text: RocStr) callconv(.c) RocStr {
    const p = path.slice();
    if (!roc.inRoot(p)) return .from("a path outside the data root");
    const t = text.slice();
    if (js_file_write(p.ptr, p.len, t.ptr, t.len) == 0) return .from("");
    return .from(pending());
}

export fn roc_file_delete(path: RocStr) callconv(.c) RocStr {
    const p = path.slice();
    if (!roc.inRoot(p)) return .from("a path outside the data root");
    if (js_file_delete(p.ptr, p.len) == 0) return .from("");
    return .from(pending());
}

// ── what host.js calls ──────────────────────────────────────────────────────

export fn demo_init() void {
    roc.use(std.heap.wasm_allocator);
    roc.crashed = crashed;
}

/// Room for `n` bytes of a request, in the call's arena.
export fn demo_alloc(n: usize) [*]u8 {
    return (roc.alloc().alloc(u8, n) catch @panic("out of memory")).ptr;
}

/// The answer, as host.js reads it: five words.
const Answer = extern struct { status: u32, content_type: [*]const u8, content_type_len: usize, body: [*]const u8, body_len: usize };

/// Kept here, not on the stack: a small string's bytes are in it.
/// The bench's one visitor: the tab is one person, and its files are the
/// page's storage.
const demo_user = "0000000000000000";
var response: roc.Response = undefined;
var answer: Answer = undefined;

export fn demo_handle(method: [*]const u8, method_len: usize, path: [*]const u8, path_len: usize, body: [*]const u8, body_len: usize) *const Answer {
    response = roc.call(method[0..method_len], path[0..path_len], body[0..body_len], demo_user);
    const ct = response.content_type.slice();
    const b = response.body.slice();
    answer = .{ .status = response.status, .content_type = ct.ptr, .content_type_len = ct.len, .body = b.ptr, .body_len = b.len };
    return &answer;
}

/// The call's memory back (the answer with it).
export fn demo_end() void {
    roc.end();
}
