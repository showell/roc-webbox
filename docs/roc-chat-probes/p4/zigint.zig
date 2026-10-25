const std = @import("std");
pub fn main() void {
    const cases = [_][]const u8{ "1", "+1", "-0", "-1", "1_0", "_1", "1_", "1__0", " 1", "1 ", "", "0x10", "007", "18446744073709551615", "18446744073709551616", "1e3", "١", "0b11", "0o17", "0X10", "1.0", "1.5e1", "1e-1", "1.", "0x", "0x_1", "1E3", "10e18", "1_0e1", "+-1", "--1", "-0x0", "00x1", "0xff_ff", "1e19", "1e20" };
    for (cases) |c| {
        const r10 = std.fmt.parseInt(u64, c, 10);
        const r0 = std.fmt.parseInt(u64, c, 0);
        std.debug.print("zig parseInt(u64,\"{s}\",10) = {any}   base0: {any}\n", .{ c, r10, r0 });
    }
}
