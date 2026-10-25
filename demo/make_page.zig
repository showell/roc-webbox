//! The client test bench's page (NOT THE SERVER: demo/host.js says what
//! this is): web/index.html as it is, with demo/host.js loaded before its
//! own script, so its /api/ requests go to the Roc app in the tab.
//!
//!   make_page <web/index.html> <index.html> <artifact.html>
//!
//! `index.html` is the whole document, for any static file server;
//! `artifact.html` is its content without the document's own `<html>`,
//! `<head>` and `<body>` tags, which a claude.ai artifact supplies.

const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const a = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(a);
    if (args.len != 4) std.process.fatal("usage: make_page <web/index.html> <index.html> <artifact.html>", .{});
    const cwd = std.Io.Dir.cwd();
    const page = try cwd.readFileAlloc(io, args[1], a, .limited(1 << 20));
    const at = std.mem.indexOf(u8, page, "<script>") orelse std.process.fatal("{s}: no <script> to load host.js before", .{args[1]});
    const whole = try std.mem.concat(a, u8, &.{ page[0..at], "<script src=\"host.js\"></script>\n", page[at..] });
    try cwd.writeFile(io, .{ .sub_path = args[2], .data = whole });

    var out: std.ArrayList(u8) = .empty;
    var lines = std.mem.splitScalar(u8, whole, '\n');
    while (lines.next()) |line| {
        const t = std.mem.trim(u8, line, " \t\r");
        const document_tag = for ([_][]const u8{ "<!doctype", "<html", "</html", "<head", "</head", "<body", "</body" }) |tag| {
            if (std.ascii.startsWithIgnoreCase(t, tag)) break true;
        } else false;
        if (document_tag) continue;
        try out.appendSlice(a, line);
        try out.append(a, '\n');
    }
    try cwd.writeFile(io, .{ .sub_path = args[3], .data = out.items });
}
