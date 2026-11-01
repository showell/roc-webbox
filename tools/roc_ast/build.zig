//! `roc-ast` (main.zig), built against roc-lang/roc's own `parse` module at
//! the commit its own roc-version pins (beside this file): roc-chat's, the
//! Roc the linted code is built with, not this repo's frozen chat's.

const std = @import("std");

// **BUILT WITH THE ZIG THE PINNED ROC BUILDS WITH** (its build.zig.zon's
// minimum_zig_version), not this repo's: Roc's own build.zig runs as the
// dependency's, and another Zig refuses it. The box's patched 0.17.0.
comptime {
    const want = std.SemanticVersion{ .major = 0, .minor = 17, .patch = 0 };
    if (@import("builtin").zig_version.order(want) != .eq)
        @compileError("roc-ast builds with Zig 0.17.0, the pinned Roc's");
}

pub fn build(b: *std.Build) void {
    checkPin(b);
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const roc = b.dependency("roc", .{ .target = target, .optimize = optimize });
    const exe = b.addExecutable(.{
        .name = "roc-ast",
        .root_module = b.createModule(.{
            .root_source_file = b.path("main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "base", .module = roc.module("base") },
                .{ .name = "parse", .module = roc.module("parse") },
            },
        }),
    });
    b.installArtifact(exe);
}

/// **THE PARSER IS THE COMPILER'S**: build.zig.zon's roc must be the commit
/// the roc-version beside it names, or the tree is of a language our compiler may
/// not speak. A roc-version bump fails here until the dependency moves too.
fn checkPin(b: *std.Build) void {
    const io = b.graph.io;
    const dir = b.root.root_dir.handle;
    const here = b.root.subPathOrDot();
    const version = std.mem.trim(u8, dir.readFileAlloc(io, b.pathJoin(&.{ here, "roc-version" }), b.allocator, .limited(256)) catch |e| std.process.fatal("roc-ast: cannot read its roc-version ({t})", .{e}), " \n");
    const commit = version[(std.mem.lastIndexOfScalar(u8, version, '-') orelse std.process.fatal("roc-ast: roc-version `{s}` names no commit", .{version})) + 1 ..];
    const zon = dir.readFileAlloc(io, b.pathJoin(&.{ here, "build.zig.zon" }), b.allocator, .limited(64 * 1024)) catch |e| std.process.fatal("roc-ast: cannot read build.zig.zon ({t})", .{e});
    if (std.mem.indexOf(u8, zon, b.fmt("/archive/{s}", .{commit})) == null)
        std.process.fatal("roc-ast: roc-version pins Roc {s}, and build.zig.zon's roc is another commit: `zig fetch --save=roc https://github.com/roc-lang/roc/archive/<that commit, in full>.tar.gz`", .{commit});
}
