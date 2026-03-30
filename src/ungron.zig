const std = @import("std");
const builtin = @import("builtin");
const mem = std.mem;
const Allocator = mem.Allocator;
const math = std.math;
const assert = std.debug.assert;

const PathStack = std.BoundedArray(PathItem, 1024);

// Nested arrays and objects are derived from entirely from path, not from
// declarations of array/obj. This is because when grepping, it's easy to
// remove those declarations when e.g. searching for name.
//
// We'll keep a stack for global obj/arr.
//
// Then if there's a diff while parsing the name, we'll pop back to the diff
// before adding a new item to the stack.
//
// We need to keep name segments in a stack to do the diffing.
//
// # Handling obj/arr which do not appear in path, are only declared as value.
//
// ```
// json = {};
// json.a = {};
// json.a.b = [];
// json.c = "";
// ```
// Notice that the array is never used in the path, and it's empty.
//
// Because of this, just writing the segments that appear in the path
// is insufficient.
//
// The solution is to have `name` and `array_idx` be able to carry null values.
//
// When we see an obj/arr declared on the rhs, we'll
// - set a null stack item, ready to be filled if there's a path segment
//     on the next line.
// - write an "open" bracket.
//
// On parsing the next line, if there's a path segment at the right depth
// it will "fill" the null stack item.
//
// When popping, close will happen correctly whether the stack item is null
// or not, as close does not depend on the value of the stack item.

pub fn ungron(rdr: anytype, wtr: anytype) !void {
    var br = std.io.bufferedReaderSize(4096 * 8, rdr);
    const input = br.reader();
    var bw = std.io.bufferedWriter(wtr);
    const stdout = bw.writer();

    // tracks nesting levels of array and object
    // Currently uses difference in nesting level between two paths to know
    // how far back to pop.
    var path_stack = try PathStack.init(0);
    try path_stack.append(.root);

    // Tracks depth in current line.
    var depth: usize = 0;

    // Should free a name after stack is popped. Because these names
    // are pushed and popped stack-like, free should always succeed.
    var path_names_buf: [4096]u8 = undefined;
    var path_names_fba = std.heap.FixedBufferAllocator.init(&path_names_buf);
    const path_names_alloc = path_names_fba.allocator();

    // Holds the name while it's being built
    // TODO maybe use a string builder
    var name_builder = try std.BoundedArray(u8, 256).init(0);

    state: switch (ParseState.startline) {
        .startline => {
            depth = 0;
            const root = input.readBytesNoEof(4) catch {
                continue :state .end;
            };
            assert(mem.eql(u8, &root, "json"));
            const c = try input.readByte();
            std.log.debug(".startline: {c}", .{c});
            switch (c) {
                '.' => continue :state .dot,
                '[' => continue :state .bracket,
                ' ' => continue :state .path_end,
                else => unreachable,
            }
        },
        .dot => {
            std.log.debug(".dot", .{});
            continue :state .name;
        },
        .bracket => {
            const c = try input.readByte();
            std.log.debug(".bracket: {c}", .{c});
            switch (c) {
                '"' => {
                    continue :state .bracketed_name;
                },
                else => {
                    try name_builder.append(c);
                    continue :state .array_idx;
                },
            }
        },
        .name => {
            const c = try input.readByte();
            std.log.debug(".name: {c}", .{c});
            switch (c) {
                '.', '[', ' ' => {
                    // End of name, check against path_stack
                    depth += 1;
                    const name = name_builder.slice();
                    try comparePathName(name, depth, &path_stack, path_names_alloc, stdout);
                    try name_builder.resize(0);

                    switch (c) {
                        '.' => continue :state .dot,
                        ' ' => continue :state .path_end,
                        '[' => {
                            // next may be object or array.
                            continue :state .bracket;
                        },
                        else => unreachable,
                    }
                },
                else => {
                    try name_builder.append(c);
                    continue :state .name;
                },
            }
        },
        .bracketed_name => {
            const c_1 = try input.readByte();
            std.log.debug(".bracketed_name: {c}", .{c_1});
            switch (c_1) {
                '\\' => {
                    // this will skip over escaped double quotes
                    // in the switch expr.
                    try name_builder.append('\\');
                    try name_builder.append(try input.readByte());
                    continue :state .bracketed_name;
                },
                '"' => {
                    const c_2 = try input.readByte();
                    assert(c_2 == ']');

                    // End of name, check against path_stack
                    depth += 1;
                    const name = name_builder.slice();
                    try comparePathName(name, depth, &path_stack, path_names_alloc, stdout);
                    try name_builder.resize(0);

                    switch (try input.readByte()) {
                        '.' => continue :state .dot,
                        '[' => continue :state .bracket,
                        ' ' => continue :state .path_end,
                        else => unreachable,
                    }
                },
                else => {
                    try name_builder.append(c_1);
                    continue :state .bracketed_name;
                },
            }
        },
        .array_idx => {
            const c = try input.readByte();
            std.log.debug(".array_idx: {c}", .{c});
            switch (c) {
                ']' => {
                    // end of array_idx, read in number to stack
                    depth += 1;
                    std.log.debug(".array_idx end: {s}", .{name_builder.slice()});
                    const idx = try std.fmt.parseInt(u64, name_builder.slice(), 10);
                    try comparePathIdx(idx, depth, &path_stack, path_names_alloc, stdout);
                    try name_builder.resize(0);

                    // check which state to advance to
                    const c_2 = try input.readByte();
                    switch (c_2) {
                        '.' => continue :state .dot,
                        '[' => continue :state .bracket,
                        ' ' => continue :state .path_end,
                        else => unreachable(),
                    }
                },
                else => {
                    try name_builder.append(c);
                    continue :state .array_idx;
                },
            }
        },
        .path_end => {
            const cs_1 = try input.readBytesNoEof(2);
            assert(mem.eql(u8, &cs_1, "= "));
            const c = try input.readByte();
            std.log.debug(".path_end::value start {c}", .{c});

            switch (c) {
                '{' => {
                    // Write name placeholder to stack
                    try path_stack.append(.{ .name = null });
                    try stdout.writeByte('{');
                    const cs_2 = try input.readBytesNoEof(2);
                    assert(mem.eql(u8, &cs_2, "};"));
                    continue :state .endline;
                },
                '[' => {
                    // Write arr idx placeholder to stack
                    try path_stack.append(.{ .array_idx = null });
                    try stdout.writeByte('[');
                    const cs_2 = try input.readBytesNoEof(2);
                    assert(mem.eql(u8, &cs_2, "];"));
                    continue :state .endline;
                },
                '"' => {
                    try stdout.writeByte('"');
                    continue :state .value_string;
                },
                else => {
                    try stdout.writeByte(c);
                    continue :state .value_non_string;
                },
            }
        },
        .value_string => {
            const c = try input.readByte();
            std.log.debug(".value_string: {c}", .{c});
            switch (c) {
                '\\' => {
                    // this will skip over escaped double quotes
                    // in the switch expr.
                    try stdout.writeByte('\\');
                    try stdout.writeByte(try input.readByte());
                    continue :state .value_string;
                },
                '"' => {
                    try stdout.writeByte('"');
                    const c_2 = try input.readByte();
                    assert(c_2 == ';');
                    continue :state .endline;
                },
                else => {
                    try stdout.writeByte(c);
                    continue :state .value_string;
                },
            }
        },
        .value_non_string => {
            const c = try input.readByte();
            std.log.debug(".value_non_string: {c}", .{c});
            switch (c) {
                ';' => {
                    continue :state .endline;
                },
                else => {
                    try stdout.writeByte(c);
                    continue :state .value_non_string;
                },
            }
        },
        .endline => {
            const c = try input.readByte();
            std.log.debug(".endline: {c}", .{c});
            std.log.debug(".endline stack {any}\n", .{path_stack.slice()});

            assert(c == '\n');
            // flushing more often helps with debugging
            if (builtin.mode == .Debug) {
                try bw.flush();
            }
            continue :state .startline;
        },
        .end => {
            std.log.debug(".end", .{});
            // Close any remaining objects or arrays
            while (path_stack.pop()) |item| {
                switch (item) {
                    .array_idx => try stdout.writeByte(']'),
                    .name => try stdout.writeByte('}'),
                    .root => {},
                }
            }
            _ = try bw.write("\n");
            try bw.flush();
            return;
        },
    }
}

const PathItem = union(enum) {
    root,
    name: ?[]const u8,
    array_idx: ?u64,
};

const ParseState = enum {
    startline,
    name,
    dot,
    bracket,
    bracketed_name,
    array_idx,
    path_end,
    value_string,
    value_non_string,
    endline,
    end,
};

fn comparePathName(
    name: []const u8,
    depth: usize,
    path_stack: *PathStack,
    path_names_alloc: Allocator,
    stdout: anytype,
) !void {
    std.log.debug("comparePathName: {d} {any}", .{ depth, path_stack.slice() });
    if (depth >= path_stack.len) {
        _ = try stdout.writeByte('{');
        _ = try stdout.writeByte('"');
        _ = try stdout.write(name);
        _ = try stdout.write("\":");
        try path_stack.append(.{ .name = try path_names_alloc.dupe(u8, name) });
        return;
    }

    const eq_path_at_depth = switch (path_stack.slice()[depth]) {
        .root => false,
        .name => |*n_opt| if (n_opt.*) |n| mem.eql(u8, name, n) else {
            // Hack; fill null and early return
            n_opt.* = try path_names_alloc.dupe(u8, name);
            _ = try stdout.writeByte('"');
            _ = try stdout.write(name);
            _ = try stdout.write("\":");
            return;
        },
        .array_idx => unreachable("this fn only compares path"),
    };
    if (!eq_path_at_depth) {
        // pop and write close object/array for tail
        var stack_idx = path_stack.len - 1;
        while (stack_idx > depth) {
            switch (path_stack.slice()[stack_idx]) {
                .root => unreachable("logic bug"),
                .name => |n_opt| {
                    if (n_opt) |n| path_names_alloc.free(n);
                    try stdout.writeByte('}');
                },
                .array_idx => try stdout.writeByte(']'),
            }
            stack_idx -= 1;
        }
        try path_stack.resize(depth + 1);

        // Replace curr segment
        switch (path_stack.slice()[depth]) {
            .root, .array_idx => unreachable("logic bug"),
            .name => |*n_opt| if (n_opt.*) |n| {
                path_names_alloc.free(n);
                n_opt.* = try path_names_alloc.dupe(u8, name);
            },
        }

        // Since we're replacing at the same level, there should
        // be a comma between children
        _ = try stdout.writeByte(',');

        _ = try stdout.writeByte('"');
        _ = try stdout.write(name);
        _ = try stdout.write("\":");
    }
}

fn comparePathIdx(
    idx: u64,
    depth: usize,
    path_stack: *PathStack,
    path_names_alloc: Allocator,
    stdout: anytype,
) !void {
    std.log.debug("comparePathIdx: {d} {any}", .{ depth, path_stack.slice() });
    if (depth >= path_stack.len) {
        _ = try stdout.writeByte('[');
        for (0..idx) |_| {
            _ = try stdout.write("null,");
        }
        try path_stack.append(.{ .array_idx = idx });
        return;
    }

    const eq_idx_at_depth = blk: switch (path_stack.slice()[depth]) {
        .root => false,
        .array_idx => |*i_opt| if (i_opt.*) |i| {
            if (idx != i) {
                for (i..idx - 1) |_| {
                    _ = try stdout.write(",null");
                }
            }
            break :blk idx == i;
        } else {
            // Hack; early return when filling null
            i_opt.* = idx;
            for (0..idx) |_| {
                _ = try stdout.write("null,");
            }
            return;
        },
        .name => unreachable("this fn only compares array idx"),
    };
    if (!eq_idx_at_depth) {
        // pop and write close object/array tail
        var stack_idx = path_stack.len - 1;
        while (stack_idx > depth) {
            switch (path_stack.slice()[stack_idx]) {
                .root => unreachable("logic bug"),
                .name => |n_opt| {
                    if (n_opt) |n| path_names_alloc.free(n);
                    try stdout.writeByte('}');
                },
                .array_idx => try stdout.writeByte(']'),
            }
            stack_idx -= 1;
        }
        try path_stack.resize(depth + 1);

        // Replace curr segment
        switch (path_stack.slice()[depth]) {
            .root, .name => unreachable("logic bug"),
            .array_idx => |*n_opt| {
                n_opt.* = idx;
            },
        }

        // Since we're replacing at the same level, there should
        // be a comma between children
        _ = try stdout.writeByte(',');
    }
}
