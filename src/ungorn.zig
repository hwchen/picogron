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
    var line_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const line_alloc = line_arena.allocator();
    var line_buf: [4096 * 10]u8 = undefined;
    while (try input.readUntilDelimiterOrEof(&line_buf, '\n')) |line_raw| {
        const line = mem.trimRight(u8, line_raw, ";");
        var path_val_it = mem.splitBackwardsSequence(u8, line, " = ");
        const val = path_val_it.next().?;
        const path = path_val_it.next().?;
        const val_is_obj = mem.eql(u8, val, "{}");
        const val_is_arr = mem.eql(u8, val, "[]");
        const path_info = parsePath(path);
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
            const last_field_str = path_info.last_field_str;
            if (path_info.last_field_contains_escapes) {
                // This is a hack to allow objectField to write the escaped
                // chars w/out double escaping. Uses line arena as it's
                // reset every line anyways.
                const unescaped = try unescape(last_field_str, line_alloc);
                try jws.objectField(unescaped);
            } else {
                try jws.objectField(last_field_str);
            }
        }
        if (val_is_obj) {
            try jws.beginObject();
            try stack.append(.object);
        } else if (val_is_arr) {
            try jws.beginArray();
            try stack.append(.array);
        } else {
            const val_is_string = val[0] == '\"';
            const val_is_null = mem.eql(u8, val, "null");
            const val_is_true = mem.eql(u8, val, "true");
            const val_is_false = mem.eql(u8, val, "false");
            if (val_is_string) {
                // print exact, if using write will escape escape chars
                try jws.print("{s}", .{val});
            } else if (val_is_null) {
                try jws.write(null);
            } else if (val_is_true) {
                try jws.write(true);
            } else if (val_is_false) {
                try jws.write(false);
            } else {
                if (std.fmt.parseInt(i64, val, 10)) |n| {
                    try jws.write(n);
                } else |_| if (std.fmt.parseFloat(f64, val)) |x| {
                    try jws.print("{d}", .{x});
                } else |_| {
                    return error.NotJsonValue;
                }
            }
        }
        if (builtin.mode == .Debug) {
            // flushing more often helps with debugging
            try bw.flush();
        }
        // Assumes that if we need to have space for large values once, we'll need it again
        _ = line_arena.reset(.retain_capacity);
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
};

const LastField = enum {
    root,
    array,
    object,
    object_in_brackets,
};

// simple parsing
// TODO handle escaped quotes
fn parsePath(path: []const u8) PathInfo {
    std.debug.assert(mem.eql(u8, path[0..4], "json"));
    var last_field: LastField = .root;
    var nest: u32 = 0;
    var is_in_quoted_string = false;
    var is_in_square_brackets = false;
    var i: usize = 4;
    while (i < path.len) {
        const c = path[i];
        switch (c) {
            '\\' => {
                // we only care about escaped double quotes, which
                // are important for nesting. For those, we want
                // to skip counting them for nesting, so do an
                // extra increment.
                if (i < path.len - 1 and path[i + 1] == '\"') {
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
            // remove \" on left and right, and ] on right
            break :blk name_raw[1 .. name_raw.len - 2];
        },
    };
    return PathInfo{
        .nest = nest,
        .last_field = last_field,
        .last_field_str = last_field_str,
        .last_field_contains_escapes = escapes,
    };
}

// This is a hack to allow objectField to write the escaped
// chars w/out double escaping. Might be slow as it appends
// by char, but probably not that bad for this case. Plus should
// be removed once json API is improved.
fn unescape(s: []const u8, alloc: mem.Allocator) ![]const u8 {
    var unescaped = std.ArrayList(u8).init(alloc);
    var i: usize = 0;
    while (i < s.len) {
        const c = s[i];
        if (c == '\\' and i + 1 < s.len) {
            const escape_char = s[i + 1];
            try unescaped.append(switch (escape_char) {
                '"', '\\', '/' => escape_char,
                'b' => 0x08,
                'f' => 0x0c,
                'n' => '\n',
                'r' => '\r',
                't' => '\t',
                else => return error.UnsupportedEscapeCode,
            });
            i += 1;
        } else {
            try unescaped.append(c);
        }
        i += 1;
    }
    return unescaped.toOwnedSlice();
}
