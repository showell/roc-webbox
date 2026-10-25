const std = @import("std");
const rt = @import("rt.zig");
const Bytes = rt.Bytes;
extern fn roc_run(mode: u8, input: Bytes) callconv(.c) Bytes;
export fn roc_host_now_ns() callconv(.c) u64 { return rt.nowNs(); }
export fn roc_host_log(s: rt.RocStr) callconv(.c) void { std.debug.print("{s}\n", .{s.slice()}); }
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const mode = try std.fmt.parseInt(u8, args[1], 10);
    var input: []const u8 = "";
    if (args.len > 2) input = try std.Io.Dir.cwd().readFileAlloc(init.io, args[2], init.arena.allocator(), .unlimited);
    const t0 = rt.nowNs();
    const out = roc_run(mode, Bytes.from(input));
    const t1 = rt.nowNs();
    std.debug.print("out({d} bytes): {s}\nroc_run took {d} us, roc allocated {d} bytes in {d} allocs\n", .{ out.length, out.items()[0..@min(out.length, 2000)], (t1 - t0) / 1000, rt.bytes_allocated, rt.allocs });
}
