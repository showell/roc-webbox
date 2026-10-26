//! **SEVERAL ROC APPS IN ONE BINARY** (webbox's combo, Dog Park beside the
//! TODO list): Roc's code calls `roc_alloc`, `roc_realloc`, `roc_dealloc`
//! and `roc_crashed` by name, one symbol each per binary, and each app's
//! host means its own by them (Dog Park's panics on a stray allocation, the
//! TODO list's allocates from a request's arena).
//!
//! So a binary with more than one declares this module in its root, as
//! `pub const roc_hooks = @import("roc_hooks");` (and a host whose root is
//! its own forwards the application's: zig-metal-unikernel's declares
//! `struct {}` for an application with none). These are then the only
//! four exports, and each hands a call to the app inside its Roc call. An
//! app sees the declaration (a `roc_hooks` in the root with `enter`, and
//! reaches this module only through the root, so the file is in one module),
//! exports nothing itself, and brackets each call into its Roc with
//! `enter`/`leave`. Alone in a binary it exports its own and calls neither:
//! no cost and no change.
//!
//! webbox runs one handler at a time, and its between-requests work in the
//! same turn, so one app is inside Roc at a time. A hook called with none
//! inside is a call from Roc nobody bracketed, and panics.

const std = @import("std");

const Hooks = struct {
    alloc: *const fn (len: usize, alignment: usize) callconv(.c) *anyopaque,
    realloc: *const fn (ptr: *anyopaque, len: usize, alignment: usize) callconv(.c) *anyopaque,
    dealloc: *const fn (ptr: *anyopaque, alignment: usize) callconv(.c) void,
    crashed: *const fn (bytes: [*]const u8, len: usize) callconv(.c) void,
};

var inside: ?*const Hooks = null;

/// `App`'s four (functions of those names, not exported) take Roc's calls
/// until `leave(was)`.
pub fn enter(comptime App: type) ?*const Hooks {
    const was = inside;
    inside = &struct {
        const hooks: Hooks = .{ .alloc = App.roc_alloc, .realloc = App.roc_realloc, .dealloc = App.roc_dealloc, .crashed = App.roc_crashed };
    }.hooks;
    return was;
}

pub fn leave(was: ?*const Hooks) void {
    inside = was;
}

fn now() *const Hooks {
    return inside orelse @panic("roc_hooks: Roc called the runtime outside any app's bracketed call (an app's glue misses an `enter`)");
}

export fn roc_alloc(len: usize, alignment: usize) callconv(.c) *anyopaque {
    return now().alloc(len, alignment);
}

export fn roc_realloc(ptr: *anyopaque, len: usize, alignment: usize) callconv(.c) *anyopaque {
    return now().realloc(ptr, len, alignment);
}

export fn roc_dealloc(ptr: *anyopaque, alignment: usize) callconv(.c) void {
    now().dealloc(ptr, alignment);
}

export fn roc_crashed(bytes: [*]const u8, len: usize) callconv(.c) void {
    now().crashed(bytes, len);
}

// A `dbg` or a failed `expect` is the calling app's crash (roc_abi.zig
// `roc_dbg`, `roc_expect_failed` say why).
export fn roc_dbg() callconv(.c) void {
    const m = "a `dbg` was reached in a served build";
    now().crashed(m.ptr, m.len);
}

export fn roc_expect_failed() callconv(.c) void {
    const m = "an inline `expect` failed in a served build";
    now().crashed(m.ptr, m.len);
}
