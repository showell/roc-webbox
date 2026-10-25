const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // webbox is two modules: `webbox`, portable, what the site imports; and
    // `webbox_linux`, the Linux host, for the Linux `main` only.
    const webbox_dep = b.dependency("webbox", .{ .target = target, .optimize = optimize });
    const imports: []const std.Build.Module.Import = &.{
        .{ .name = "webbox", .module = webbox_dep.module("webbox") },
        .{ .name = "host_io", .module = webbox_dep.module("host_io") },
        .{ .name = "webbox_linux", .module = webbox_dep.module("webbox_linux") },
    };

    // **THE APP'S ROC, BUILT BY EVERY BUILD**: app/todo.roc for the
    // platform in platform/, an archive the host links (`roc_handle`, and
    // the hosted functions it calls back). `roc` on the PATH, or -Droc=<path>.
    const roc = b.option([]const u8, "roc", "the Roc compiler (default: `roc` on the PATH)") orelse "roc";
    const app_roc = rocArchive(b, roc, target.result);

    const exe = b.addExecutable(.{ .name = "roc-todo", .root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = imports,
    }) });
    withApp(b, exe.root_module, app_roc);
    b.installArtifact(exe);
    const serve = b.addRunArtifact(exe);
    serve.step.dependOn(b.getInstallStep());
    b.step("serve", "Serve the TODO list on http://localhost:9110 (TODO_PORT), its list in data/todo/todos.json (TODO_DATA)").dependOn(&serve.step);

    // The host's tests, the Roc app linked: the strings across the seam, and
    // the site's routes against a store in a temporary folder.
    const tests = b.step("test", "The host's tests, through the Roc app");
    for ([_][]const u8{ "src/roc_abi.zig", "src/todo_test.zig" }) |root| {
        const m = b.createModule(.{
            .root_source_file = b.path(root),
            .target = target,
            .optimize = optimize,
            .imports = imports,
        });
        withApp(b, m, app_roc);
        tests.dependOn(&b.addRunArtifact(b.addTest(.{ .root_module = m })).step);
    }
}

/// The page at `/` and the Roc app, for the module `m` that serves them.
fn withApp(b: *std.Build, m: *std.Build.Module, app_roc: std.Build.LazyPath) void {
    m.addAnonymousImport("todo_page", .{ .root_source_file = b.path("web/index.html") });
    m.addObjectFile(app_roc);
}

/// app/todo.roc built for `t` (Roc's x64musl for x86-64 Linux; x64v1elf
/// for a freestanding x86-64 host, webbox's bare-metal one).
fn rocArchive(b: *std.Build, roc: []const u8, t: std.Target) std.Build.LazyPath {
    if (t.cpu.arch != .x86_64) std.process.fatal("the TODO app's Roc: no archive for {t} (it is built for x86-64)", .{t.cpu.arch});
    const roc_target = if (t.os.tag == .freestanding) "x64v1elf" else "x64musl";
    const run = b.addSystemCommand(&.{ roc, "build", "app/todo.roc", b.fmt("--target={s}", .{roc_target}) });
    run.setCwd(b.path("."));
    for ([_][]const u8{ "app/todo.roc", "platform/main.roc", "platform/File.roc", "platform/Http.roc" }) |f| run.addFileInput(b.path(f));
    return run.addPrefixedOutputFileArg("--output=", b.fmt("todo-{s}.a", .{roc_target}));
}
