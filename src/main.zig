const std = @import("std");
const mem = std.mem;
const fs = std.fs;
const io = std.io;
const gron = @import("gron.zig");
const gron_stream = @import("gron_stream.zig");
const ungron = @import("ungron.zig");

pub fn main() !void {
    var arg_buf: [512]u8 = undefined;
    var arg_fba = std.heap.FixedBufferAllocator.init(&arg_buf);
    const arg_alloc = arg_fba.allocator();
    var args = try std.process.argsWithAllocator(arg_alloc);

    var opts = Opts{};
    _ = args.next(); // skip args[0]
    while (args.next()) |arg| {
        if (mem.eql(u8, arg, "--ungron") or mem.eql(u8, arg, "-u")) {
            opts.ungron = true;
        } else if (mem.eql(u8, arg, "--stream") or mem.eql(u8, arg, "-s")) {
            opts.stream = true;
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
    if (opts.ungron) {
        try ungron.ungron(input, stdout_file);
    } else if (opts.stream) {
        try gron_stream.gronStream(input, stdout_file);
    } else {
        try gron.gron(input, stdout_file, .{});
    }
}

const Opts = struct {
    ungron: bool = false,
    stream: bool = false,
    filepath: ?[]const u8 = null,
};
