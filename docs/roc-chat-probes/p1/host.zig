const std = @import("std");
const rt = @import("rt.zig");
const g = @import("glue/roc_platform_abi.zig");
const RocStr = rt.RocStr;
const Bytes = rt.Bytes;

const Header = extern struct { name: RocStr, value: RocStr };
const Headers = rt.RocList(Header, true);
const Member = extern struct { id: RocStr, name: RocStr };
const User = extern struct { payload: extern union { member: Member, nobody: [0]u8 }, tag: u8 }; // Member=0 Nobody=1
const Request = extern struct { at_unix_ms: i64, body: Bytes, headers: Headers, method: RocStr, peer: RocStr, target: RocStr, user: User };
const Response = extern struct { body: Bytes, headers: Headers, status: u16, kind: u8 };
const Echo = extern struct { body: Bytes, headers: Headers, tag: u8 };
const Maybe = extern struct { payload: extern union { some: Bytes, none: [0]u8 }, tag: u8 }; // None=0 Some=1
const Hostile = extern struct { payload: extern union { hostile: RocStr, ok: [0]u8 }, tag: u8 }; // Hostile=0 Ok=1

comptime {
    const G = g.Handle_for_hostArg0;
    if (@sizeOf(Request) != @sizeOf(G)) @compileError("req size");
    for (.{ "at_unix_ms", "body", "headers", "method", "peer", "target", "user" }) |f| if (@offsetOf(Request, f) != @offsetOf(G, f)) @compileError("req " ++ f);
    if (@sizeOf(Response) != @sizeOf(g.Handle_for_host) or @offsetOf(Response, "kind") != @offsetOf(g.Handle_for_host, "kind") or @offsetOf(Response, "status") != @offsetOf(g.Handle_for_host, "status")) @compileError("resp");
    if (@sizeOf(Maybe) != @sizeOf(g.NoneOrSome) or @sizeOf(Hostile) != @sizeOf(g.HostileOrOk) or @sizeOf(User) != @sizeOf(g.MemberOrNobody)) @compileError("unions");
    if (@offsetOf(Bytes, "length") != 8) @compileError("list");
}

extern fn roc_handle(req: Request) callconv(.c) Response;

export fn roc_memo_get(key: RocStr) callconv(.c) Maybe {
    if (std.mem.eql(u8, key.slice(), "/hit")) return .{ .payload = .{ .some = Bytes.from("|MEMO-BYTES") }, .tag = 1 };
    return .{ .payload = .{ .none = .{} }, .tag = 0 };
}
export fn roc_md_hostile(s: RocStr) callconv(.c) Hostile {
    if (std.mem.eql(u8, s.slice(), "EVIL")) return .{ .payload = .{ .hostile = RocStr.from("a reason longer than twenty-three bytes") }, .tag = 0 };
    return .{ .payload = .{ .ok = .{} }, .tag = 1 };
}
export fn roc_md_render(s: RocStr) callconv(.c) RocStr {
    var buf: [256]u8 = undefined;
    return RocStr.from(std.fmt.bufPrint(&buf, "<p>{s}</p>", .{s.slice()}) catch unreachable);
}
export fn roc_host_echo(e: Echo) callconv(.c) Echo {
    var hs: [8]Header = undefined;
    for (e.headers.items(), 0..) |h, i| hs[i] = .{ .name = h.value, .value = h.name }; // swap
    hs[e.headers.length] = .{ .name = RocStr.from("echo-added"), .value = RocStr.from("v") };
    return .{ .body = Bytes.from("|ECHOBODY:"), .headers = Headers.from(hs[0 .. e.headers.length + 1]), .tag = e.tag + 1 };
}
export fn roc_host_now_ns() callconv(.c) u64 { return rt.nowNs(); }
export fn roc_host_log(s: RocStr) callconv(.c) void { std.debug.print("log: {s}\n", .{s.slice()}); }

fn run(method: []const u8, target: []const u8, user: User) void {
    const hs = [_]Header{ .{ .name = RocStr.from("host"), .value = RocStr.from("example.com") }, .{ .name = RocStr.from("x-long-header-name-over-23"), .value = RocStr.from("value-also-long-enough-to-be-heap") } };
    const body = [_]u8{ 'B', 0xff, 0xfe, 'Z' };
    const r = roc_handle(.{ .at_unix_ms = -1234567890123, .body = Bytes.from(&body), .headers = Headers.from(&hs), .method = RocStr.from(method), .peer = RocStr.from("10.0.0.1"), .target = RocStr.from(target), .user = user });
    std.debug.print("kind={d} status={d} body={any}\n  body-as-text={s}\n", .{ r.kind, r.status, r.body.items(), r.body.items() });
    for (r.headers.items()) |h| std.debug.print("  hdr {s}: {s}\n", .{ h.name.slice(), h.value.slice() });
    rt.reset();
}

pub fn main() void {
    run("GET", "/hit", .{ .payload = .{ .member = .{ .id = RocStr.from("1"), .name = RocStr.from("Steve") } }, .tag = 0 });
    run("EVIL", "/miss", .{ .payload = .{ .nobody = .{} }, .tag = 1 });
}
