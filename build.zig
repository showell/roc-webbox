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
    // the hosted functions it calls back), by the Roc roc-version pins.
    const roc = rocCompiler(b);
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
    b.step("serve", "Serve the TODO list on http://localhost:9110 (TODO_PORT), its list in data/todos.json (TODO_DATA)").dependOn(&serve.step);

    // **FOR A COMBINATION** (webbox's combo, beside another app): `roc_todo`,
    // the list as a host takes it (hosted.zig, its Roc linked); and
    // `roc_hooks`, which a binary holding more than one Roc app declares in
    // its root (src/roc_hooks.zig).
    const hosted = b.addModule("roc_todo", .{
        .root_source_file = b.path("src/hosted.zig"),
        .target = target,
        .optimize = optimize,
        .imports = imports[0..2],
    });
    withApp(b, hosted, app_roc);
    // The same for a combination on zig-metal-unikernel (its addAppKernel
    // `parts`): no target, mode or webbox (the kernel's), Roc for its target.
    const hosted_metal = b.addModule("roc_todo_metal", .{ .root_source_file = b.path("src/hosted.zig") });
    const metal_roc = rocArchive(b, roc, "x64v1elf");
    withApp(b, hosted_metal, metal_roc);
    _ = b.addModule("roc_hooks", .{ .root_source_file = b.path("src/roc_hooks.zig") });

    _ = demo(b, roc, optimize);

    // **THE LIST ON METAL**: zig-metal-unikernel's kernel, a sibling
    // checkout, hosting hosted.zig's `site` in place of main.zig's Linux
    // host. The module names no target or optimize mode (the kernel's) and
    // imports neither webbox nor host_io (the kernel supplies its own); its
    // Roc is built for the kernel's target, freestanding x86-64.
    const metal_step = b.step("metal", "Build the TODO list as a zig-metal-unikernel kernel, zig-out/bin/roc-todo.elf (ReleaseSafe; ../zig-metal-unikernel)");
    if (b.lazyDependency("zig_metal_unikernel", .{})) |kernel| {
        if (b.lazyImport(@This(), "zig_metal_unikernel")) |kernel_build| {
            // Its own module: the kernel makes a module its machine's in
            // place, and `roc_todo_metal` is a combination's to give.
            const metal_app = b.createModule(.{ .root_source_file = b.path("src/hosted.zig") });
            withApp(b, metal_app, metal_roc);
            const elf = kernel_build.addAppKernel(b, kernel, .{
                .name = "roc-todo.elf",
                .module = metal_app,
                .assets = b.path("assets.zon"),
                .optimize = .ReleaseSafe,
            });
            metal_step.dependOn(&b.addInstallArtifact(elf, .{}).step);
        }
    }

    // The host's tests, the Roc app linked: the strings across the seam, and
    // the site's routes against a store in a temporary folder.
    const tests = b.step("test", "The host's tests, through the Roc app, alone and with roc_hooks (src/shared_check.zig)");
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
    const shared = b.createModule(.{
        .root_source_file = b.path("src/shared_check.zig"),
        .target = target,
        .optimize = optimize,
        .imports = imports,
    });
    withApp(b, shared, app_roc);
    const shared_run = b.addRunArtifact(b.addExecutable(.{ .name = "shared-check", .root_module = shared }));
    shared_run.setCwd(b.path("."));
    shared_run.has_side_effects = true;
    tests.dependOn(&shared_run.step);
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

const roc_pin = std.mem.trim(u8, @embedFile("roc-version"), " \n");

/// **THE ROC IS PINNED** (roc-version): -Droc=<path>, or `roc` on the PATH,
/// and it must be the pinned one. A combination builds each of its Roc apps
/// with its primary's compiler, handed down as -Droc, so two apps that pin
/// different Roc versions fail here rather than link.
fn rocCompiler(b: *std.Build) []const u8 {
    const named = b.option([]const u8, "roc", "the Roc compiler (default: `roc` on the PATH); the version roc-version pins") orelse "roc";
    const none = "the TODO list is built from Roc, and there is no Roc compiler at `{s}`: put Roc {s} (roc-version) on the PATH (tools/get_roc.sh installs it), or name it with -Droc=<path>";
    const found = if (std.mem.indexOfScalar(u8, named, '/') == null)
        b.findProgram(.{ .names = &.{named} }) orelse std.process.fatal(none, .{ named, roc_pin })
    else
        b.root.root_dir.handle.realPathFileAlloc(b.graph.io, named, b.allocator) catch std.process.fatal(none, .{ named, roc_pin });
    const said = std.mem.trim(u8, b.run(&.{ found, "version" }), " \n");
    const version = if (std.mem.lastIndexOfScalar(u8, said, ' ')) |i| said[i + 1 ..] else said;
    if (!std.mem.eql(u8, version, roc_pin)) std.process.fatal("the TODO list is pinned to Roc {s} (roc-version), and `{s}` is {s}: put the pinned one on the PATH (tools/get_roc.sh) or name it with -Droc=<path>; in a combination, the primary's Roc builds every part, so their pins must agree", .{ roc_pin, found, version });
    return found;
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
    // The compiler too: a new Roc builds the archive again.
    run.addFileInput(.{ .cwd_relative = roc });
    return run.addPrefixedOutputFileArg("--output=", b.fmt("todo-{s}.a", .{roc_target}));
}
