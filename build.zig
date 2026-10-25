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
    const app_roc = rocArchive(b, roc, rocTarget(target.result));

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

    _ = demo(b, roc, optimize);

    // The host's tests, the Roc app linked: the strings across the seam, and
    // the site's routes against a store in a temporary folder.
    const tests = b.step("test", "The host's tests, through the Roc app");
    for ([_][]const u8{"src/todo_test.zig"}) |root| {
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

/// **THE CLIENT TEST BENCH, NOT THE SERVER** (demo/README.md): the page
/// with the Roc app built for wasm32 answering its /api/ requests in the
/// tab, into zig-out/demo/.
fn demo(b: *std.Build, roc: []const u8, optimize: std.lang.Optimize) *std.Build.Step {
    const step = b.step("demo", "The client test bench (NOT the server): the page, with the Roc app as wasm in the tab, into zig-out/demo/");
    const wasm = b.addExecutable(.{ .name = "todo", .root_module = b.createModule(.{
        .root_source_file = b.path("demo/wasm_host.zig"),
        .target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .freestanding }),
        .optimize = if (optimize == .debug) .small else optimize,
        .strip = true,
        .imports = &.{.{ .name = "roc_abi", .module = b.createModule(.{ .root_source_file = b.path("src/roc_abi.zig") }) }},
    }) });
    wasm.root_module.addObjectFile(rocArchive(b, roc, "wasm32"));
    wasm.entry = .disabled;
    wasm.rdynamic = true;
    step.dependOn(&b.addInstallFileWithDir(wasm.getEmittedBin(), .{ .custom = "demo" }, "todo.wasm").step);

    const make_page = b.addRunArtifact(b.addExecutable(.{ .name = "make_page", .root_module = b.createModule(.{
        .root_source_file = b.path("demo/make_page.zig"),
        .target = b.graph.host,
    }) }));
    make_page.addFileArg(b.path("web/index.html"));
    const index = make_page.addOutputFileArg("index.html");
    const artifact = make_page.addOutputFileArg("artifact.html");
    step.dependOn(&b.addInstallFileWithDir(index, .{ .custom = "demo" }, "index.html").step);
    step.dependOn(&b.addInstallFileWithDir(artifact, .{ .custom = "demo" }, "artifact.html").step);
    step.dependOn(&b.addInstallFileWithDir(b.path("demo/host.js"), .{ .custom = "demo" }, "host.js").step);
    return step;
}

/// The page at `/` and the Roc app, for the module `m` that serves them.
fn withApp(b: *std.Build, m: *std.Build.Module, app_roc: std.Build.LazyPath) void {
    m.addAnonymousImport("todo_page", .{ .root_source_file = b.path("web/index.html") });
    m.addObjectFile(app_roc);
}

/// Roc's target for a host built for `t`: x64musl for x86-64 Linux,
/// x64v1elf for a freestanding x86-64 host (webbox's bare-metal one).
fn rocTarget(t: std.Target) []const u8 {
    if (t.cpu.arch != .x86_64) std.process.fatal("the TODO app's Roc: no archive for {t} (the server is built for x86-64)", .{t.cpu.arch});
    return if (t.os.tag == .freestanding) "x64v1elf" else "x64musl";
}

/// app/todo.roc built for Roc's target `roc_target`.
fn rocArchive(b: *std.Build, roc: []const u8, roc_target: []const u8) std.Build.LazyPath {
    const run = b.addSystemCommand(&.{ roc, "build", "app/todo.roc", b.fmt("--target={s}", .{roc_target}) });
    run.setCwd(b.path("."));
    for ([_][]const u8{ "app/todo.roc", "platform/main.roc", "platform/File.roc", "platform/Http.roc" }) |f| run.addFileInput(b.path(f));
    return run.addPrefixedOutputFileArg("--output=", b.fmt("todo-{s}.a", .{roc_target}));
}
