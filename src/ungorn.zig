const std = @import("std");
const builtin = @import("builtin");
const mem = std.mem;
const math = std.math;

pub fn ungorn(rdr: anytype, wtr: anytype) !void {
    var br = std.io.bufferedReader(rdr);
    const input = br.reader();
    var bw = std.io.bufferedWriter(wtr);
    const stdout = bw.writer();
    var jws = std.json.writeStream(stdout, .{});

    // tracks nesting levels of array and object
    // PathInfo happens to hold last_field_str, but may point to garbage
    // as it's only used immediately after parsing.
    // Currently uses difference in nesting level between two paths to know
    // how far back to pop.
    var stack_buf: [1024]u8 = undefined;
    var stack_fba = std.heap.FixedBufferAllocator.init(&stack_buf);
    const stack_alloc = stack_fba.allocator();
    var stack = std.ArrayList(LastField).init(stack_alloc);
    try stack.append(.root);

    var prev_path_nest: u32 = 0;
    var line_buf: [4096 * 1000]u8 = undefined;
    while (try input.readUntilDelimiterOrEof(&line_buf, '\n')) |line| {
        const path_info = parsePath(line);
        const val = path_info.value;
        const val_is_obj = mem.eql(u8, val, "{}");
        const val_is_arr = mem.eql(u8, val, "[]");
        const last_field = path_info.last_field;

        // Try to end objects and arrays
        if (path_info.nest < prev_path_nest) {
            for (0..prev_path_nest - path_info.nest) |_| {
                const last_nest = stack.pop();
                switch (last_nest) {
                    .array => try jws.endArray(),
                    .object, .object_in_brackets => try jws.endObject(),
                    .root => unreachable,
                }
            }
        }
        prev_path_nest = path_info.nest;

        if (builtin.mode == .Debug) {
            // flushing more often helps with debugging
            try bw.flush();
        }

        // write fields and values
        if (last_field == .object or last_field == .object_in_brackets) {
            if (path_info.last_field_contains_escapes) {
                try jws.objectFieldRaw(path_info.last_field_str);
            } else {
                try jws.objectField(path_info.last_field_str);
            }
        }
        if (val_is_obj) {
            try jws.beginObject();
            try stack.append(.object);
        } else if (val_is_arr) {
            try jws.beginArray();
            try stack.append(.array);
        } else {
            // if string, print exact, if using write will escape escape chars
            // this also prints numbers, null, bools exactly as they were read.
            try jws.print("{s}", .{val});
        }
        if (builtin.mode == .Debug) {
            // flushing more often helps with debugging
            try bw.flush();
        }
    }

    // Close any remaining objects or arrays
    while (stack.popOrNull()) |item| {
        switch (item) {
            .array => try jws.endArray(),
            .object, .object_in_brackets => try jws.endObject(),
            .root => {},
        }
    }
    _ = try bw.write("\n");
    try bw.flush();
}

const PathInfo = struct {
    nest: u32,
    last_field: LastField,
    // Only needed immediately after parsing. May return
    // garbage once this struct is put on a stack.
    last_field_str: []const u8,
    // was bracketed, so contains non-ident chars. Maybe doesn't
    // contain escapes, but it's a clearer naming than should_escape
    last_field_contains_escapes: bool = false,
    value: []const u8,
};

const LastField = enum {
    root,
    array,
    object,
    object_in_brackets,
};

// simple parsing
fn parsePath(line: []const u8) PathInfo {
    std.debug.assert(mem.eql(u8, line[0..4], "json"));
    var last_field: LastField = .root;
    var nest: u32 = 0;
    var is_in_quoted_string = false;
    var is_in_square_brackets = false;
    var path_end: usize = 0;
    var i: usize = 4;
    while (i < line.len) {
        const c = line[i];
        switch (c) {
            ' ' => {
                path_end = i;
                break;
            },
            '\\' => {
                // we only care about escaped double quotes, which
                // are important for nesting. For those, we want
                // to skip counting them for nesting, so do an
                // extra increment.
                if (i < line.len - 1 and line[i + 1] == '\"') {
                    i += 1;
                }
            },
            '\"' => {
                is_in_quoted_string = !is_in_quoted_string;
                if (is_in_quoted_string and is_in_square_brackets) {
                    last_field = .object_in_brackets;
                }
            },
            '.' => if (!is_in_quoted_string) {
                nest += 1;
            },
            '[' => if (!is_in_quoted_string) {
                is_in_square_brackets = true;
                last_field = .array;
                nest += 1;
            },
            ']' => if (!is_in_quoted_string) {
                is_in_square_brackets = false;
            },
            else => if (!is_in_quoted_string and !is_in_square_brackets) {
                last_field = .object;
            },
        }
        i += 1;
    }
    const path = line[0..path_end];
    var escapes = false;
    // Re-parse the last field string now that we know what type it is.
    const last_field_str = switch (last_field) {
        .root => &.{},
        .array => &.{},
        .object => blk: {
            var it = mem.splitBackwardsSequence(u8, path, ".");
            break :blk it.next().?;
        },
        .object_in_brackets => blk: {
            escapes = true;
            var it = mem.splitBackwardsSequence(u8, path, "[");
            const name_raw = it.next().?;
            // remove ] on right
            break :blk name_raw[0 .. name_raw.len - 1];
        },
    };
    return PathInfo{
        .nest = nest,
        .last_field = last_field,
        .last_field_str = last_field_str,
        .last_field_contains_escapes = escapes,
        .value = line[path_end + 3 .. line.len - 1], // removes leading `=` and semicolon
    };
}
