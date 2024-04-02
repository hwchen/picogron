const std = @import("std");
const json = std.json;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();
    defer arena.deinit();

    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    const stdin_file = std.io.getStdIn().reader();
    var jr = std.json.reader(alloc, stdin_file);
    while (true) {
        const token = try jr.next();
        try stdout.print("{}\n", .{token});
        try bw.flush();
    }
}
