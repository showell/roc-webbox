const std = @import("std");
const rt = @import("rt.zig");
const Bytes = rt.Bytes;
const Ret = extern struct { model: ?*anyopaque, out: Bytes };
const Resp = extern struct { body: Bytes, a: u16, z: u8 };
extern fn roc_init() callconv(.c) ?*anyopaque;
extern fn roc_handle(m: ?*anyopaque, input: Bytes) callconv(.c) Ret;
extern fn roc_nominal(b: Bytes) callconv(.c) Resp;
// A host buffer with a static refcount word (0) in front: Roc treats it as constant data.
var buf: [8 + 32]u8 align(8) = undefined;
pub fn main() void {
    var model = roc_init();
    for ([_][]const u8{ "alpha", "beta", "gamma" }) |w| {
        // Zero-copy: refcount 0 = static, Roc must never free or mutate it.
        @memset(buf[0..8], 0);
        @memcpy(buf[8 .. 8 + w.len], w);
        const input: Bytes = .{ .ptr = buf[8..].ptr, .length = w.len, .capacity_or_alloc_ptr = w.len << 1 };
        const r = roc_handle(model, input);
        model = r.model;
        std.debug.print("{s}  (input refcount word after: {d})\n", .{ r.out.items(), std.mem.readInt(usize, buf[0..8], .little) });
    }
    const n = roc_nominal(Bytes.from("xy"));
    std.debug.print("nominal: a={d} z={d} body={s}\n", .{ n.a, n.z, n.body.items() });
}
