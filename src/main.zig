const std = @import("std");
const mem = std.mem;
const gorn = @import("gorn.zig");
const ungorn = @import("ungorn.zig");

pub fn main() !void {
    // Used to track nesting levels for json parser
    var arg_buf: [512]u8 = undefined;
    var arg_fba = std.heap.FixedBufferAllocator.init(&arg_buf);
    const arg_alloc = arg_fba.allocator();
    var args = try std.process.argsWithAllocator(arg_alloc);

    var opts = Opts{};
    _ = args.next(); // skip args[0]
    while (args.next()) |arg| {
        if (mem.eql(u8, arg, "--ungorn") or mem.eql(u8, arg, "-u")) {
            opts.ungorn = true;
        } else {
            // TODO clean errors
            return error.UnsupportedCliFlag;
        }
    }

    const stdin_file = std.io.getStdIn().reader();
    const stdout_file = std.io.getStdOut().writer();
    if (opts.ungorn) {
        try ungorn.ungorn(stdin_file, stdout_file);
    } else {
        try gorn.gorn(stdin_file, stdout_file);
    }
}

const Opts = struct {
    ungorn: bool = false,
};
