const std = @import("std");
const mem = std.mem;
const fs = std.fs;
const io = std.io;
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
            if (opts.filepath == null) {
                opts.filepath = arg;
            } else if (mem.eql(u8, arg[0..1], "-")) {
                return error.UnsupportedCliArg;
            } else {
                return error.TooManyCliArg;
            }
        }
    }

    const input = if (opts.filepath) |path| blk: {
        const f = try fs.cwd().openFile(path, .{});
        break :blk f.reader();
    } else io.getStdIn().reader();

    const stdout_file = std.io.getStdOut().writer();
    if (opts.ungorn) {
        try ungorn.ungorn(input, stdout_file);
    } else {
        try gorn.gorn(input, stdout_file);
    }
}

const Opts = struct {
    ungorn: bool = false,
    filepath: ?[]const u8 = null,
};
