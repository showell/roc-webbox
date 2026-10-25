const std = @import("std");
const rt = @import("rt.zig");
const Msg = struct { id: u64, from: []const u8, date: []const u8, body: []const u8 };
pub fn main(init: std.process.Init) !void {
    const a = init.arena.allocator();
    const input = try std.Io.Dir.cwd().readFileAlloc(init.io, "transcript.md", a, .unlimited);
    var best: u64 = std.math.maxInt(u64);
    var n: usize = 0; var total: usize = 0; var ids: u64 = 0; var hb: usize = 0;
    for (0..5) |_| {
        var gpa_arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
        defer gpa_arena.deinit();
        const t0 = rt.nowNs();
        if (!std.unicode.utf8ValidateSlice(input)) return error.Bad;
        var list: std.ArrayList(Msg) = .empty;
        var it = std.mem.splitSequence(u8, input, "\n\n-------------\n");
        while (it.next()) |block| {
            const k = std.mem.indexOf(u8, block, "\n\n") orelse continue;
            var lines = std.mem.splitScalar(u8, block[0..k], '\n');
            const first = lines.next().?;
            const id = std.fmt.parseInt(u64, if (std.mem.startsWith(u8, first, "MSG_")) first[4..] else first, 10) catch 0;
            var m: Msg = .{ .id = id, .from = "", .date = "", .body = try gpa_arena.allocator().dupe(u8, block[k + 2 ..]) };
            while (lines.next()) |line| {
                if (std.mem.startsWith(u8, line, "from: ")) m.from = line[6..] else if (std.mem.startsWith(u8, line, "date: ")) m.date = line[6..];
            }
            try list.append(gpa_arena.allocator(), m);
        }
        const t1 = rt.nowNs();
        best = @min(best, t1 - t0);
        n = list.items.len; total = 0; ids = 0; hb = 0;
        for (list.items) |m| { total += m.body.len; ids += m.id; hb += m.from.len + m.date.len; }
    }
    std.debug.print("zig: msgs={d} body_bytes={d} id_sum={d} hdr_bytes={d}; best of 5: {d} us (validate+split+parse+dupe body)\n", .{ n, total, ids, hb, best / 1000 });
}
