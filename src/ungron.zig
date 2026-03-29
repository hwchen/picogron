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
// TODO:
// - fix bracket closing
// - fix commas
// - fix missing object/array when it's empty and not in path
// - fix nulls in array skips
// - fix perf

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
                    // Write obj open when comparing path stack
                    const cs_2 = try input.readBytesNoEof(2);
                    assert(mem.eql(u8, &cs_2, "};"));
                    continue :state .endline;
                },
                '[' => {
                    // Write arr open when comparing path stack
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
    name: []const u8,
    array_idx: u64,
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
        .name => |n| mem.eql(u8, name, n),
        .array_idx => unreachable("this fn only compares path"),
    };
    if (!eq_path_at_depth) {
        // pop and write close object/array
        while (path_stack.len - 1 > depth) {
            switch (path_stack.pop().?) {
                .root => unreachable("logic bug"),
                .name => |n| {
                    path_names_alloc.free(n);
                    try stdout.writeByte('}');
                },
                .array_idx => try stdout.writeByte(']'),
            }
        }
        // Last pop should not write a close bracket
        // TODO is this true for arrays?
        _ = path_stack.pop().?;

        _ = try stdout.writeByte('"');
        _ = try stdout.write(name);
        _ = try stdout.write("\":");
        try path_stack.append(.{ .name = try path_names_alloc.dupe(u8, name) });
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
        try path_stack.append(.{ .array_idx = idx });
        return;
    }

    const eq_path_at_depth = switch (path_stack.slice()[depth]) {
        .root => false,
        .array_idx => |i| idx == i,
        .name => unreachable("this fn only compares array idx"),
    };
    if (!eq_path_at_depth) {
        // pop and write close object/array
        while (path_stack.len - 1 > depth) {
            switch (path_stack.pop().?) {
                .root => unreachable("logic bug"),
                .name => |n| {
                    path_names_alloc.free(n);
                    try stdout.writeByte('}');
                },
                .array_idx => try stdout.writeByte(']'),
            }
        }
        // Last pop should not write a close bracket
        // TODO is this true for arrays?
        _ = path_stack.pop().?;

        try path_stack.append(.{ .array_idx = idx });
    }
}

// path_end logic
//            std.log.debug(".path_end::stack_end {any}", .{stack.slice()[stack.len - 1]});
//            // Need to pop one more if prev line was empty objarr.
//            const follows_empty_objarr = switch (stack.slice()[stack.len - 1]) {
//                .array_first, .object_first => true,
//                else => false,
//            };
//
//            // Try to end objects and arrays
//            if (curr_path_nest == prev_path_nest and follows_empty_objarr) {
//                // There's a significant perf slowdown if this `if` is merged into the
//                // following `else if` as (curr_path_nest <= prev_path_nest) because all
//                // diffs == 0 have to be checked, where this allows many fewer diffs to
//                // be checked. And adding an additional `if` to this block doesn't appear
//                // to impact perf.
//                //
//                // TODO unwrap on null, is that ok?
//                switch (stack.pop().?) {
//                    .array, .array_first => try stdout.writeByte(']'),
//                    .object, .object_first => try stdout.writeByte('}'),
//                    .root => unreachable,
//                }
//            } else if (curr_path_nest < prev_path_nest) {
//                var i = stack.len;
//                var diff = prev_path_nest - curr_path_nest;
//                diff += @as(u32, @intFromBool(follows_empty_objarr));
//                std.log.debug(".path_end::updated_diff {d}", .{diff});
//                while (i > stack.len - diff) {
//                    std.log.debug(".path_end::pop_stack", .{});
//                    i -= 1;
//                    switch (stack.slice()[i]) {
//                        .array, .array_first => try stdout.writeByte(']'),
//                        .object, .object_first => try stdout.writeByte('}'),
//                        .root => unreachable,
//                    }
//                }
//                try stack.resize(stack.len - diff);
//            }
//            prev_path_nest = curr_path_nest;
//            curr_path_nest = 0;
//
//            // insert comma if needed
//            switch (stack.slice()[stack.len - 1]) {
//                .root => {},
//                .array_first => stack.slice()[stack.len - 1] = .array,
//                .object_first => stack.slice()[stack.len - 1] = .object,
//                else => try stdout.writeByte(','),
//            }
//
//            // flushing more often helps with debugging
//            if (builtin.mode == .Debug) {
//                try bw.flush();
//            }
//
//            // write fields and values
//            switch (last_field) {
//                .object => {
//                    // expects field name without quotes
//                    try stdout.writeByte('"');
//                    _ = try stdout.write(last_field_str.slice());
//                    _ = try stdout.write("\":");
//                },
//                else => {},
//            }
//            switch (c) {
//                '{' => {
//                    const cs_2 = try input.readBytesNoEof(2);
//                    assert(mem.eql(u8, &cs_2, "};"));
//                    try stdout.writeByte('{');
//                    try stack.append(.object_first);
//                    continue :state .endline;
//                },
//                '[' => {
//                    const cs_2 = try input.readBytesNoEof(2);
//                    assert(mem.eql(u8, &cs_2, "];"));
//                    try stdout.writeByte('[');
//                    try stack.append(.array_first);
//                    continue :state .endline;
//                },
//                '"' => {
//                    try stdout.writeByte('"');
//                    continue :state .value_string;
//                },
//                else => {
//                    try stdout.writeByte(c);
//                    continue :state .value_non_string;
//                },
//            }
//
//

// .end
//
