const std = @import("std");
const builtin = @import("builtin");
const mem = std.mem;
const math = std.math;

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
    while (true) {
        const c = input.readByte() catch break;
        switch (c) {
            ' ' => { // value start, processes to semicolon eol
                // Try to end objects and arrays
                if (curr_path_nest < prev_path_nest) {
                    for (0..prev_path_nest - curr_path_nest) |_| {
                        const last_nest = stack.pop();
                        switch (last_nest) {
                            .array => try stdout.writeByte(']'),
                            .object => try stdout.writeByte('}'),
                            .root => unreachable,
                        }
                    }
                }
                prev_path_nest = curr_path_nest;
                curr_path_nest = 0;

                // insert comma if needed
                switch (stack.slice()[stack.len - 1]) {
                    .root => {},
                    inline else => |*is_first| {
                        if (!is_first.*) {
                            try stdout.writeByte(',');
                        } else {
                            is_first.* = false;
                        }
                    },
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

                // write value
                std.debug.assert(try input.readByte() == '=');
                std.debug.assert(try input.readByte() == ' ');
                const val_start = try input.readByte();
                switch (val_start) {
                    '{' => {
                        try stdout.writeByte('{');
                        try stack.append(.{ .object = true });
                    },
                    '[' => {
                        try stdout.writeByte('[');
                        try stack.append(.{ .array = true });
                    },
                    else => {
                        try stdout.writeByte(val_start);
                        while (true) {
                            const val_c = try input.readByte();
                            switch (val_c) {
                                ';' => {
                                    break;
                                },
                                else => try stdout.writeByte(val_c),
                            }
                        }
                    },
                }
                // flushing more often helps with debugging
                if (builtin.mode == .Debug) {
                    try bw.flush();
                }
            },
            '\n' => continue,
            '.' => {
                last_field = .object;
                try last_field_str.resize(0);
                curr_path_nest += 1;
            },
            '[' => { // need to handle object in brackets here, as it may contain chars we switch in the main loop.
                if (try input.readByte() == '"') {
                    last_field = .object;
                    try last_field_str.resize(0);
                    while (true) {
                        const c_in_quotes = try input.readByte();
                        switch (c_in_quotes) {
                            '\\' => {
                                try last_field_str.append('\\');
                                try last_field_str.append(try input.readByte());
                            },
                            '"' => break,
                            else => try last_field_str.append(c_in_quotes),
                        }
                    }
                    std.debug.assert(try input.readByte() == ']');
                } else {
                    last_field = .array;
                    try last_field_str.resize(0); // not needed?
                }
                curr_path_nest += 1;
            },
            ']' => {},
            else => try last_field_str.append(c),
        }
    }
    // Close any remaining objects or arrays
    while (stack.popOrNull()) |item| {
        switch (item) {
            .array => try stdout.writeByte(']'),
            .object => try stdout.writeByte('}'),
            .root => {},
        }
    }
    _ = try bw.write("\n");
    try bw.flush();
}

const StackItem = union(LastField) {
    root,
    array: bool, // whether we're iterating through the first item, to know whether to comma.
    object: bool, // whether we're iterating through the first item, to know whether to comma
};

const LastField = enum {
    root,
    array,
    object,
};
