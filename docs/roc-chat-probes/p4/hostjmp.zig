const std = @import("std");
const rt = @import("rt_jmp.zig");
const sj = @import("sljmp.zig");
const Bytes = rt.Bytes;
extern fn roc_run(mode: u8, input: Bytes) callconv(.c) Bytes;
export fn roc_host_now_ns() callconv(.c) u64 { return rt.nowNs(); }
export fn roc_host_log(s: rt.RocStr) callconv(.c) void { std.debug.print("{s}\n", .{s.slice()}); }
var jb: sj.JmpBuf = undefined;
var msg: [256]u8 = undefined;
var msg_len: usize = 0;
fn bail(m: []const u8) noreturn {
    msg_len = @min(m.len, msg.len);
    @memcpy(msg[0..msg_len], m[0..msg_len]);
    sj.longjmp(&jb, 1);
}
noinline fn guarded(mode: u8, input: []const u8) ?Bytes {
    if (sj.setjmp(&jb) != 0) {
        rt.reset(); // drop everything Roc allocated in the call
        return null;
    }
    return roc_run(mode, Bytes.from(input));
}
pub fn main() void {
    rt.on_crash = bail;
    for ([_]u8{ 1, 0, 2, 0, 3, 0 }) |mode| {
        // modes: 1 add overflow, 2 sub underflow, 3 div by zero, 0 ok
        if (guarded(mode, "abc")) |out| {
            std.debug.print("mode {d}: ok: {s}\n", .{ mode, out.items() });
        } else {
            std.debug.print("mode {d}: Roc crashed (\"{s}\"), answered 500, carried on\n", .{ mode, msg[0..msg_len] });
        }
        rt.reset();
    }
}
