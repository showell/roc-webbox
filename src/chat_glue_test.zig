//! **ROC GLUE, TEST-DRIVEN ON ONE SEAM RECORD** (metal-vmm QUEUE 280): the
//! listing's entry (Host.list!'s `{ kind : [Dir, File, Other], name :
//! List(U8) }`) as `roc glue` lays it out, held at compile time to the one
//! chat_abi.zig lays out by hand (`EntryRec`, `route.EntryKind`). Nothing is
//! replaced: the hand-laid records stay the seam, and this says whether glue
//! agrees with them.
//!
//! src/glue/chat_platform_abi.zig is glue's output, then `zig fmt` (glue's
//! is not formatted as the gate checks):
//!
//!     roc glue <roc-src>/src/glue/src/ZigGlue.roc src/glue chat/platform/main.roc
//!
//! (the pinned compiler, roc-version; the spec from roc's source, which the
//! compiler does not ship), then renamed from roc_platform_abi.zig.

const std = @import("std");
const abi = @import("chat_abi.zig");
const route = @import("chat_route.zig");
const glue = @import("glue/chat_platform_abi.zig");

/// Glue's answer of Host.list!, found by the hosted symbol's signature:
/// the record has no name of its own (glue calls it by a hash).
const GlueListing = @typeInfo(@TypeOf(glue.roc_chat_list)).@"fn".return_type.?;

/// Glue's entry: the element of the answer's `entries`.
const GlueEntry = @typeInfo(@typeInfo(@FieldType(
    @FieldType(GlueListing, "entries"),
    "elements_ptr",
)).optional.child).pointer.child;

/// `Want` and `Got` lay out alike: one size, one alignment, the same fields
/// by name at the same offsets, each field of one size.
fn sameLayout(comptime Want: type, comptime Got: type) bool {
    if (@sizeOf(Want) != @sizeOf(Got) or @alignOf(Want) != @alignOf(Got)) return false;
    const want = @typeInfo(Want).@"struct";
    if (want.field_names.len != @typeInfo(Got).@"struct".field_names.len) return false;
    inline for (want.field_names, want.field_types) |name, T| {
        if (!@hasField(Got, name)) return false;
        if (@offsetOf(Want, name) != @offsetOf(Got, name)) return false;
        if (@sizeOf(T) != @sizeOf(@FieldType(Got, name))) return false;
    }
    return true;
}

/// `Want` and `Got` lay out alike field by field in order, whatever their
/// fields are called.
fn sameShape(comptime Want: type, comptime Got: type) bool {
    if (@sizeOf(Want) != @sizeOf(Got) or @alignOf(Want) != @alignOf(Got)) return false;
    const want = @typeInfo(Want).@"struct";
    const got = @typeInfo(Got).@"struct";
    if (want.field_names.len != got.field_names.len) return false;
    inline for (want.field_names, got.field_names, want.field_types, got.field_types) |wn, gn, W, G| {
        if (@offsetOf(Want, wn) != @offsetOf(Got, gn) or @sizeOf(W) != @sizeOf(G)) return false;
    }
    return true;
}

/// Two enums that number the same names alike.
fn sameTags(comptime Want: type, comptime Got: type) bool {
    const want = @typeInfo(Want).@"enum";
    if (want.field_names.len != @typeInfo(Got).@"enum".field_names.len or @sizeOf(Want) != @sizeOf(Got)) return false;
    inline for (want.field_names, want.field_values) |name, value| {
        if (!@hasField(Got, name) or @backingInt(@field(Got, name)) != value) return false;
    }
    return true;
}

comptime {
    if (!sameLayout(
        abi.EntryRec,
        GlueEntry,
    )) @compileError("roc glue lays the listing's entry out unlike chat_abi.zig's EntryRec");
    if (!sameTags(
        route.EntryKind,
        @FieldType(GlueEntry, "kind"),
    )) @compileError("roc glue numbers the entry's kind unlike route.EntryKind");
    // And the answer that carries them, its status numbered alike.
    if (!sameShape(
        abi.ListRec,
        GlueListing,
    )) @compileError("roc glue lays the listing out unlike chat_abi.zig's ListRec");
    if (!sameTags(
        route.ReadStatus,
        @FieldType(GlueListing, "status"),
    )) @compileError("roc glue numbers the listing's status unlike route.ReadStatus");
    // The bytes: three words, as RocBytes's, though glue calls the first
    // `elements_ptr` where RocBytes says `ptr`.
    if (!sameShape(
        abi.RocBytes,
        @FieldType(GlueEntry, "name"),
    )) @compileError("roc glue lays List(U8) out unlike RocBytes");
}

test "roc glue's listing entry is chat_abi.zig's, field by field (metal-vmm QUEUE 280)" {
    try std.testing.expect(sameLayout(abi.EntryRec, GlueEntry));
    // The check has teeth: a record of the same fields in the other order is
    // not the entry.
    const Swapped = extern struct { kind: route.EntryKind, name: abi.RocBytes };
    try std.testing.expect(!sameLayout(Swapped, GlueEntry));
}
