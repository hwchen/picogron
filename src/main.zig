const std = @import("std");
const gorn = @import("gorn.zig");

pub fn main() !void {
    const stdin_file = std.io.getStdIn().reader();
    const stdout_file = std.io.getStdOut().writer();
    try gorn.gorn(stdin_file, stdout_file);
}

fn ungorn() !void {}
