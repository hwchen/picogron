const std = @import("std");
const builtin = @import("builtin");
const mem = std.mem;
const math = std.math;
const parse_gron = @import("parse_gron.zig");

pub fn ungron(rdr: anytype, wtr: anytype) !void {
    var br = std.io.bufferedReaderSize(4096 * 8, rdr);
    const input = br.reader();
    var bw = std.io.bufferedWriter(wtr);
    const stdout = bw.writer();
    var jws = std.json.writeStream(stdout, .{});

    // tracks nesting levels of array and object
    // Currently uses difference in nesting level between two paths to know
    // how far back to pop.
    var stack = try std.BoundedArray(parse_gron.LastField, 1024).init(0);
    try stack.append(.root);

    var prev_path_nest: u32 = 0;
    var line_buf: [4096 * 1000]u8 = undefined;
    while (try input.readUntilDelimiterOrEof(&line_buf, '\n')) |line| {
        const path_info = parse_gron.parseLine(line);
        const val = path_info.value;
        const val_is_obj = val[0] == '{';
        const val_is_arr = val[0] == '[';
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
