//! **A ROC FILE'S PARSE TREE, AS ROC'S OWN PARSER SEES IT**: for each path
//! on stdin (one a line), `== <path>` and then the file's tree as the
//! compiler's snapshot tests print it (`AST.toSExprStr`, with line and
//! column). The parser is roc-lang/roc's, at the commit roc-version pins, so
//! the tree is what our compiler accepts. Shale hunts over the output.
//!
//! A file that does not parse cleanly is a failure, named, never a tree.

const std = @import("std");
const base = @import("base");
const parse = @import("parse");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var in_buf: [4096]u8 = undefined;
    var stdin = std.Io.File.stdin().reader(io, &in_buf);
    const list = try stdin.interface.allocRemaining(arena, .unlimited);

    var out_buf: [64 * 1024]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(io, &out_buf);
    const out = &stdout.interface;

    var it = std.mem.splitScalar(u8, list, '\n');
    while (it.next()) |raw| {
        const path = std.mem.trim(u8, raw, " \t\r");
        if (path.len == 0) continue;
        const source = try std.Io.Dir.cwd().readFileAlloc(io, path, arena, .unlimited);

        var env = try base.CommonEnv.init(gpa, source);
        defer env.deinit(gpa);
        try env.calcLineStarts(gpa);
        const ast = try parse.file(gpa, &env);
        defer ast.deinit();

        const problems = ast.tokenize_diagnostics.items.len + ast.parse_diagnostics.items.len;
        if (problems != 0) {
            try out.flush();
            std.debug.print("{s}: {d} parse problem(s): a file that does not parse has no tree to hunt\n", .{ path, problems });
            std.process.exit(1);
        }

        try out.print("== {s}\n", .{path});
        try ast.toSExprStr(gpa, &env, out);
        try out.writeByte('\n');
    }
    try out.flush();
}
