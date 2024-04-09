const std = @import("std");
const builtin = @import("builtin");
const mem = std.mem;
const math = std.math;

pub fn ungorn(rdr: anytype, wtr: anytype) !void {
    var br = std.io.bufferedReaderSize(4096 * 8, rdr);
    const input = br.reader();
    var bw = std.io.bufferedWriter(wtr);
    const stdout = bw.writer();
    var jws = std.json.writeStream(stdout, .{});

    // tracks nesting levels of array and object
    // PathInfo happens to hold last_field_str, but may point to garbage
    // as it's only used immediately after parsing.
    // Currently uses difference in nesting level between two paths to know
    // how far back to pop.
    var stack = try std.BoundedArray(LastField, 1024).init(0);
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

        // flushing more often helps with debugging
        if (builtin.mode == .Debug) {
            try bw.flush();
        }

        // write fields and values
        switch (last_field) {
            .object => try jws.objectField(path_info.last_field_str),
            .object_in_brackets => try jws.objectFieldRaw(path_info.last_field_str),
            else => {},
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
        // flushing more often helps with debugging
        if (builtin.mode == .Debug) {
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
    var last_field_start: usize = 0;
    var path_end: usize = 0;
    var i: usize = 4;
    while (i < line.len) {
        const c = line[i];
        switch (c) {
            ' ' => {
                path_end = i;
                break;
            },
            '.' => {
                last_field = .object;
                last_field_start = i;
                nest += 1;
            },
            '[' => {
                if (line[i + 1] == '"') {
                    last_field = .object_in_brackets;
                    last_field_start = i + 1;
                    i = endOfBracketedField(line, i + 1);
                } else {
                    last_field = .array;
                    last_field_start = i;
                }
                nest += 1;
            },
            else => {},
        }
        i += 1;
    }
    const last_field_str = switch (last_field) {
        .root => &.{},
        .array => &.{},
        .object => line[last_field_start + 1 .. path_end],
        // remove ]
        .object_in_brackets => line[last_field_start .. path_end - 1],
    };
    return PathInfo{
        .nest = nest,
        .last_field = last_field,
        .last_field_str = last_field_str,
        .value = line[path_end + 3 .. line.len - 1], // removes leading `=` and semicolon
    };
}

// returns index of last bracket of field-in-bracket syntax
fn endOfBracketedField(line: []const u8, start_idx: usize) usize {
    var i: usize = start_idx;
    while (i < line.len) {
        switch (line[i]) {
            '\\' => i += 1,
            ']' => break,
            else => {},
        }
        i += 1;
    }
    std.debug.assert(line[i] == ']');
    return i;
}
