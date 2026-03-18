const std = @import("std");
const builtin = @import("builtin");
const mem = std.mem;
const math = std.math;
const assert = std.debug.assert;

// Nested arrays and objects are derived from entirely from path, not from
// declarations of array/obj. This is because when grepping, it's easy to
// remove those declarations when e.g. searching for name.

pub fn ungron(rdr: anytype, wtr: anytype) !void {
    var br = std.io.bufferedReaderSize(4096 * 8, rdr);
    const input = br.reader();
    var bw = std.io.bufferedWriter(wtr);
    const stdout = bw.writer();

    // tracks nesting levels of array and object
    // Currently uses difference in nesting level between two paths to know
    // how far back to pop.
    var stack = try std.BoundedArray(StackItem, 1024).init(0);
    try stack.append(.root);

    var prev_path_nest: u32 = 0;
    var curr_path_nest: u32 = 0;
    var last_field: LastField = .root;
    var last_field_str = try std.BoundedArray(u8, 256).init(0);
    state: switch (ParseState.startline) {
        .startline => {
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
            last_field = .object;
            try last_field_str.resize(0);
            curr_path_nest += 1;
            continue :state .name;
        },
        .bracket => {
            const c = try input.readByte();
            std.log.debug(".bracket: {c}", .{c});
            try last_field_str.resize(0);
            curr_path_nest += 1;
            switch (c) {
                '"' => {
                    last_field = .object;
                    continue :state .bracketed_name;
                },
                else => {
                    last_field = .array;
                    continue :state .array_idx;
                },
            }
        },
        .name => {
            const c = try input.readByte();
            std.log.debug(".name: {c}", .{c});
            switch (c) {
                '.' => continue :state .dot,
                '[' => continue :state .bracket,
                ' ' => continue :state .path_end,
                else => {
                    try last_field_str.append(c);
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
                    try last_field_str.append('\\');
                    try last_field_str.append(try input.readByte());
                    continue :state .bracketed_name;
                },
                '"' => {
                    const c_2 = try input.readByte();
                    assert(c_2 == ']');
                    switch (try input.readByte()) {
                        '.' => continue :state .dot,
                        '[' => continue :state .bracket,
                        ' ' => continue :state .path_end,
                        else => unreachable,
                    }
                },
                else => {
                    try last_field_str.append(c_1);
                    continue :state .bracketed_name;
                },
            }
        },
        .array_idx => {
            const c = try input.readByte();
            std.log.debug(".array_idx: {c}", .{c});
            switch (c) {
                '.' => continue :state .dot,
                '[' => continue :state .bracket,
                ' ' => continue :state .path_end,
                else => {
                    // does not currently read the actual array idx,
                    // just continues until it hits next path segment.
                    continue :state .array_idx;
                },
            }
        },
        .path_end => {
            std.log.debug(".path_end: curr nest {d}, prev nest {d}", .{ curr_path_nest, prev_path_nest });
            const cs_1 = try input.readBytesNoEof(2);
            assert(mem.eql(u8, &cs_1, "= "));
            const c = try input.readByte();
            std.log.debug(".path_end::value start {c}", .{c});
            std.log.debug(".path_end::stack_end {any}", .{stack.slice()[stack.len - 1]});
            // Need to pop one more if prev line was empty objarr.
            const follows_empty_objarr = switch (stack.slice()[stack.len - 1]) {
                .array_first, .object_first => true,
                else => false,
            };

            // Try to end objects and arrays
            if (curr_path_nest == prev_path_nest and follows_empty_objarr) {
                // There's a significant perf slowdown if this `if` is merged into the
                // following `else if` as (curr_path_nest <= prev_path_nest) because all
                // diffs == 0 have to be checked, where this allows many fewer diffs to
                // be checked. And adding an additional `if` to this block doesn't appear
                // to impact perf.
                //
                // TODO unwrap on null, is that ok?
                switch (stack.pop().?) {
                    .array, .array_first => try stdout.writeByte(']'),
                    .object, .object_first => try stdout.writeByte('}'),
                    .root => unreachable,
                }
            } else if (curr_path_nest < prev_path_nest) {
                var i = stack.len;
                var diff = prev_path_nest - curr_path_nest;
                diff += @as(u32, @intFromBool(follows_empty_objarr));
                std.log.debug(".path_end::updated_diff {d}", .{diff});
                while (i > stack.len - diff) {
                    std.log.debug(".path_end::pop_stack", .{});
                    i -= 1;
                    switch (stack.slice()[i]) {
                        .array, .array_first => try stdout.writeByte(']'),
                        .object, .object_first => try stdout.writeByte('}'),
                        .root => unreachable,
                    }
                }
                try stack.resize(stack.len - diff);
            }
            prev_path_nest = curr_path_nest;
            curr_path_nest = 0;

            // insert comma if needed
            switch (stack.slice()[stack.len - 1]) {
                .root => {},
                .array_first => stack.slice()[stack.len - 1] = .array,
                .object_first => stack.slice()[stack.len - 1] = .object,
                else => try stdout.writeByte(','),
            }

            // flushing more often helps with debugging
            if (builtin.mode == .Debug) {
                try bw.flush();
            }

            // write fields and values
            switch (last_field) {
                .object => {
                    // expects field name without quotes
                    try stdout.writeByte('"');
                    _ = try stdout.write(last_field_str.slice());
                    _ = try stdout.write("\":");
                },
                else => {},
            }
            switch (c) {
                '{' => {
                    const cs_2 = try input.readBytesNoEof(2);
                    assert(mem.eql(u8, &cs_2, "};"));
                    try stdout.writeByte('{');
                    try stack.append(.object_first);
                    continue :state .endline;
                },
                '[' => {
                    const cs_2 = try input.readBytesNoEof(2);
                    assert(mem.eql(u8, &cs_2, "];"));
                    try stdout.writeByte('[');
                    try stack.append(.array_first);
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

            std.log.debug(".endline: curr nest {d}, prev nest {d}", .{ curr_path_nest, prev_path_nest });
            std.log.debug(".endline: stack {any}", .{stack.slice()});

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
            std.log.debug(".end: stack {any}", .{stack.slice()});
            while (stack.pop()) |item| {
                switch (item) {
                    .array, .array_first => try stdout.writeByte(']'),
                    .object, .object_first => try stdout.writeByte('}'),
                    .root => {},
                }
            }
            _ = try bw.write("\n");
            try bw.flush();
            return;
        },
    }
}

// *_first means that it's the first iteration through the array/object
const StackItem = enum {
    root,
    array_first,
    array,
    object,
    object_first,
};

const LastField = enum {
    root,
    array,
    object,
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
