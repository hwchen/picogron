const std = @import("std");
const math = std.math;
const gorn = @import("gorn.zig");

pub fn gornStream(rdr: anytype, wtr: anytype) !void {
    var br = std.io.bufferedReader(rdr);
    const input = br.reader();
    var line_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const line_alloc = line_arena.allocator();

    _ = try wtr.write("json = [];\n");

    var line_idx: usize = 0;
    while (try input.readUntilDelimiterOrEofAlloc(line_alloc, '\n', math.maxInt(u32))) |line| {
        var line_stream = std.io.fixedBufferStream(line);
        try gorn.gorn(line_stream.reader(), wtr, .{ .line_idx = line_idx });
        line_idx += 1;
    }
}
