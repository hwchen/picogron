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
        if (mem.eql(u8, arg, "--help") or mem.eql(u8, arg, "-h")) {
            std.debug.print("{s}\n", .{HELP});
            return std.process.exit(0);
        } else if (mem.eql(u8, arg, "--ungron") or mem.eql(u8, arg, "-u")) {
            opts.ungron = true;
        } else if (mem.eql(u8, arg, "--stream") or mem.eql(u8, arg, "-s")) {
            opts.stream = true;
        } else {
            if (mem.eql(u8, arg[0..1], "-")) {
                std.debug.print("Arg '{s}' not supported\n", .{arg});
                return std.process.exit(1);
            } else if (opts.filepath == null) {
                // add a filepath if there isn't already a filepath specified in args
                opts.filepath = arg;
            } else {
                std.debug.print("Multiple positional args not supported, supply only one filename\n", .{});
                return std.process.exit(1);
            }
        }
    }
    if (opts.ungron and opts.stream) {
        std.debug.print("--ungron and --stream flags are incompatible\n", .{});
        return std.process.exit(1);
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

const HELP =
    \\Transform JSON (from a file or stdin) into discrete assignments to make it greppable
    \\
    \\Usage:
    \\  picogron [OPTIONS] [FILE]
    \\
    \\positional arguments:
    \\  FILE           file name (stdin if no filename provided)
    \\
    \\options:
    \\  -h, --help     show this help message and exit
    \\  -s, --stream   enable stream mode for json input (line delimited)
    \\  -u, --ungron   ungron: convert gron output back to JSON
;
