//! **THE TODO LIST, AS A HOST TAKES IT** (webbox's Phase B contract): the
//! site's `site` (its webbox Site) and `hosting` (what only it can say about
//! itself). zig-metal-unikernel's kernel hosts this (`zig build metal`);
//! Linux's main (main.zig) hosts the same site.

const std = @import("std");
const webbox = @import("webbox");
const app = @import("todo_app.zig");

pub const site = webbox.site.Site(app);

pub const hosting = struct {
    /// What the application is called, where a host names it (metal's boot
    /// banner).
    pub const name = "Roc TODO list";
    /// What its data is called, where a host names it.
    pub const data_name = "the TODO list";
    /// The largest file a plain read takes whole: the list, which the app
    /// reads whole (roc_files.zig).
    pub const whole_read_max = 1024 * 1024;
    /// The largest file worth keeping whole in a host's page cache: the same.
    pub const cache_largest_most = 1024 * 1024;
    /// Its setup's report, a line each, for the host's log.
    pub fn describeStart(r: app.StartReport, w: *std.Io.Writer) std.Io.Writer.Error!void {
        try w.print("the list in {s}/todos.json\n", .{r.data_dir});
    }
};
