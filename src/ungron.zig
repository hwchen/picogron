// TODO test value strings for semicolo]

const std = @import("std");
const builtin = @import("builtin");
const mem = std.mem;
const math = std.math;
const assert = std.debug.assert;

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

    var parse_state: ParseState = .startline;
    var prev_path_nest: u32 = 0;
    var curr_path_nest: u32 = 0;
    var last_field: LastField = .root;
    var last_field_str = try std.BoundedArray(u8, 256).init(0);
    while (true) {
        switch (parse_state) {
            .startline => {
                const root = input.readBytesNoEof(4) catch {
                    parse_state = .end;
                    continue;
                };
                assert(mem.eql(u8, &root, "json"));
                const c = try input.readByte();
                std.log.debug(".startline: {c}", .{c});
                switch (c) {
                    '.' => parse_state = .dot,
                    '[' => parse_state = .bracket,
                    ' ' => parse_state = .path_end,
                    else => unreachable,
                }
            },
            .dot => {
                std.log.debug(".dot", .{});
                last_field = .object;
                try last_field_str.resize(0);
                curr_path_nest += 1;
                parse_state = .name;
            },
            .bracket => {
                const c = try input.readByte();
                std.log.debug(".bracket: {c}", .{c});
                switch (c) {
                    '"' => {
                        last_field = .object;
                        parse_state = .bracketed_name;
                    },
                    else => {
                        last_field = .array;
                        parse_state = .array_idx;
                    },
                }
                try last_field_str.resize(0);
                curr_path_nest += 1;
            },
            .name => {
                const c = try input.readByte();
                std.log.debug(".name: {c}", .{c});
                switch (c) {
                    '.' => parse_state = .dot,
                    '[' => parse_state = .bracket,
                    ' ' => parse_state = .path_end,
                    else => try last_field_str.append(c),
                }
            },
            .bracketed_name => {
                const c = try input.readByte();
                std.log.debug(".bracketed_name: {c}", .{c});
                switch (c) {
                    '\\' => {
                        // this will skip over escaped double quotes
                        // in the switch expr.
                        try last_field_str.append('\\');
                        try last_field_str.append(try input.readByte());
                    },
                    '"' => {
                        assert(try input.readByte() == ']');
                        switch (try input.readByte()) {
                            '.' => parse_state = .dot,
                            '[' => parse_state = .bracket,
                            ' ' => parse_state = .path_end,
                            else => unreachable,
                        }
                    },
                    else => try last_field_str.append(c),
                }
            },
            .array_idx => {
                const c = try input.readByte();
                std.log.debug(".array_idx: {c}", .{c});
                switch (c) {
                    '.' => parse_state = .dot,
                    '[' => parse_state = .bracket,
                    ' ' => parse_state = .path_end,
                    else => {},
                }
            },
            .path_end => {
                std.log.debug(".path_end: curr nest {d}, prev nest {d}", .{ curr_path_nest, prev_path_nest });
                assert(mem.eql(u8, &(try input.readBytesNoEof(2)), "= "));

                // Try to end objects and arrays
                if (curr_path_nest < prev_path_nest) {
                    for (0..prev_path_nest - curr_path_nest) |_| {
                        const last_nest = stack.pop();
                        switch (last_nest) {
                            .array, .array_first => try stdout.writeByte(']'),
                            .object, .object_first => try stdout.writeByte('}'),
                            .root => unreachable,
                        }
                    }
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
                parse_state = .value_start;
            },
            // TODO could just be folded into .path_end?
            .value_start => {
                const c = try input.readByte();
                std.log.debug(".value_start: {c}", .{c});
                switch (c) {
                    '{' => {
                        assert(mem.eql(u8, &(try input.readBytesNoEof(2)), "};"));
                        try stdout.writeByte('{');
                        try stack.append(.object_first);
                        parse_state = .endline;
                    },
                    '[' => {
                        assert(mem.eql(u8, &(try input.readBytesNoEof(2)), "];"));
                        try stdout.writeByte('[');
                        try stack.append(.array_first);
                        parse_state = .endline;
                    },
                    '"' => {
                        try stdout.writeByte('"');
                        parse_state = .value_string;
                    },
                    else => {
                        try stdout.writeByte(c);
                        parse_state = .value_non_string;
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
                    },
                    '"' => {
                        try stdout.writeByte('"');
                        assert(try input.readByte() == ';');
                        parse_state = .endline;
                    },
                    else => try stdout.writeByte(c),
                }
            },
            .value_non_string => {
                const c = try input.readByte();
                std.log.debug(".value_non_string: {c}", .{c});
                switch (c) {
                    ';' => {
                        parse_state = .endline;
                    },
                    else => try stdout.writeByte(c),
                }
            },
            .endline => {
                const c = try input.readByte();
                std.log.debug(".endline: {c}", .{c});
                assert(c == '\n');
                parse_state = .startline;
                // flushing more often helps with debugging
                if (builtin.mode == .Debug) {
                    try bw.flush();
                }
            },
            .end => {
                std.log.debug(".end", .{});
                // Close any remaining objects or arrays
                while (stack.popOrNull()) |item| {
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
}

// *_first means that it's the first iteration through the array/object
const StackItem = union(enum) {
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
    value_start,
    value_string,
    value_non_string,
    endline,
    end,
};
