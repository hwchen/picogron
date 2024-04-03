const std = @import("std");
const mem = std.mem;

pub fn ungorn(rdr: anytype, wtr: anytype) !void {
    var br = std.io.bufferedReader(rdr);
    const input = br.reader();
    var bw = std.io.bufferedWriter(wtr);
    const stdout = bw.writer();
    var jws = std.json.writeStream(stdout, .{});

    var prev_path_nest: u32 = 0;
    var prev_path_is_arr = false;
    var line_buf: [1024]u8 = undefined;
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
            if (prev_path_is_arr) {
                try jws.endArray();
            } else {
                try jws.endObject();
            }
        }
        prev_path_nest = path_info.nest;
        prev_path_is_arr = path_info.last_field == .array;

        try bw.flush();

        // write fields and values
        if (last_field == .object or last_field == .object_in_brackets) {
            try jws.objectField(path_info.last_field_str);
        }
        if (val_is_obj) {
            try jws.beginObject();
        } else if (val_is_arr) {
            try jws.beginArray();
        } else {
            const val_is_string = val[0] == '\"';
            const val_is_null = mem.eql(u8, val, "null");
            const val_is_true = mem.eql(u8, val, "true");
            const val_is_false = mem.eql(u8, val, "false");
            if (val_is_string) {
                // trim quotes on ends
                try jws.write(val[1 .. val.len - 1]);
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
                    try jws.write(x);
                } else |_| {
                    return error.NotJsonValue;
                }
            }
        }
        try bw.flush();
    }
}

const PathInfo = struct {
    nest: u32,
    last_field: LastField,
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
