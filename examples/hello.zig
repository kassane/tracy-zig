const std = @import("std");
const tracy = @import("tracy");

pub fn main() !void {
    const trace = tracy.trace(@src());
    defer trace.end();

    // Prints to stderr (it's a shortcut based on `std.io.getStdErr()`)
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});

    // stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    try stdout.print("Run `zig build test` to run the tests.\n", .{});

    try bw.flush(); // don't forget to flush!
    _ = std.c.printf("C hello");

    var buf: [8]u8 = undefined;
    std.crypto.random.bytes(buf[0..]);
    const seed = std.mem.readIntLittle(u64, buf[0..8]);
    var r = std.rand.DefaultPrng.init(seed);
    const w = r.random().int(u32);

    std.time.sleep(1000_000_000 * (w % 5));
    try main();
}
