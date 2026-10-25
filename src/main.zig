//! The TODO list, served: webbox's Linux host with the Roc app
//! (todo_app.zig).
//!
//! Run:  zig build serve       (on http://localhost:9110)

const std = @import("std");
const webbox = @import("webbox");
const app = @import("todo_app.zig");

pub const site = webbox.site.Site(app);

pub fn main(init: std.process.Init.Minimal) !void {
    var env = try std.process.Environ.createMap(init.environ, std.heap.page_allocator);
    defer env.deinit();
    // The data root the list goes in (todos.json) when no config names
    // one: TODO_DATA, else data/ under where the server runs.
    if (env.get("TODO_DATA")) |p| app.data_dir = try std.heap.page_allocator.dupe(u8, p);
    try @import("webbox_linux").linux_host.Server(site).run(init, .{
        .name = "roc-todo",
        .env = .{
            .port = "TODO_PORT",
            .bind = "TODO_BIND",
            .config = "TODO_CONFIG",
            .trusted_proxy = "TODO_TRUSTED_PROXY",
            .keepalive_ms = "TODO_KEEPALIVE_MS",
        },
        .default_port = 9110,
        .default_trusted_proxy = "127.0.0.1",
        // The host opens a second root at the start; the list keeps no
        // secret in it.
        .default_auth_dir = "auth",
        .routes_hint = "(/, /api/todos)",
        .free_space = unread,
    }, report);
}

/// Not read: no page here shows the data volume's free space.
fn unread(_: *const std.process.Environ.Map) webbox.free_space.FreeSpace {
    return .unknown;
}

fn report(started: *const site.Started) void {
    std.debug.print("roc-todo: the list in {s}/todos.json\n", .{started.app.data_dir});
}
