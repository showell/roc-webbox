//! **THE ROC CHAT, AS A HOST TAKES IT** (webbox's Phase B contract): the
//! site's `site` and `hosting`. angry-gopher mounts it (webbox's combo), on
//! Linux and in gopher.elf; nothing hosts it alone yet.

const std = @import("std");
const webbox = @import("webbox");
const app = @import("chat_app.zig");

pub const site = webbox.site.Site(app);

pub const hosting = struct {
    /// What the application is called, where a host names it.
    pub const name = "Roc chat";
    /// What its data is called, where a host names it.
    pub const data_name = "the Roc chat";
    /// The largest file a plain read takes whole (roc_files.zig's cap).
    pub const whole_read_max = 1024 * 1024;
    /// The largest file worth keeping whole in a host's page cache.
    pub const cache_largest_most = 1024 * 1024;
    /// Its setup's report, a line each, for the host's log.
    pub fn describeStart(r: app.StartReport, w: *std.Io.Writer) std.Io.Writer.Error!void {
        try w.print("the Roc chat (T1: GET /ping), its files under {s}\n", .{r.data_dir});
    }
};

test "ping is Roc's answer, and anything else a 404" {
    const roc = @import("roc_abi.zig");
    const files = @import("roc_files.zig");
    roc.use(std.testing.allocator);
    defer roc.deinit();
    files.use("data");
    {
        const r = files.handle(std.testing.io, "GET", "/ping", "", "");
        defer roc.end();
        try std.testing.expectEqual(@as(u16, 200), r.status);
        try std.testing.expectEqualStrings("roc chat: ok\n", r.body.slice());
    }
    {
        const r = files.handle(std.testing.io, "POST", "/ping", "", "");
        defer roc.end();
        try std.testing.expectEqual(@as(u16, 405), r.status);
    }
    {
        const r = files.handle(std.testing.io, "GET", "/c/1_2/general", "", "");
        defer roc.end();
        try std.testing.expectEqual(@as(u16, 404), r.status);
    }
}
