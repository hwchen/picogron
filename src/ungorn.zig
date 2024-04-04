const std = @import("std");
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
    while (try input.readUntilDelimiterOrEofAlloc(line_alloc, '\n', math.maxInt(u32))) |line_raw| {
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

        try bw.flush();

        // write fields and values
        if (last_field == .object or last_field == .object_in_brackets) {
            try jws.objectField(path_info.last_field_str);
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
        try bw.flush();
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
    _ = try stdout.write("\n");
    try bw.flush();
}

const PathInfo = struct {
    nest: u32,
    last_field: LastField,
    // Only needed immediately after parsing. May return
    // garbage once this struct is put on a stack.
    last_field_str: []const u8,
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
    for (path[4..]) |c| {
        switch (c) {
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
    }
    const last_field_str = switch (last_field) {
        .root => &.{},
        .array => &.{},
        .object => blk: {
            var it = mem.splitBackwardsSequence(u8, path, ".");
            break :blk it.next().?;
        },
        .object_in_brackets => blk: {
            var it = mem.splitBackwardsSequence(u8, path, "[");
            const name_raw = it.next().?;
            const name_trim_l = mem.trimLeft(u8, name_raw, "\"");
            break :blk mem.trimRight(u8, name_trim_l, "\"]");
        },
    };
    return PathInfo{
        .nest = nest,
        .last_field = last_field,
        .last_field_str = last_field_str,
    };
}
