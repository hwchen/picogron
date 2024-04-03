const std = @import("std");
const mem = std.mem;

pub fn ungorn(rdr: anytype, wtr: anytype) !void {
    var br = std.io.bufferedReader(rdr);
    const input = br.reader();
    var bw = std.io.bufferedWriter(wtr);
    const stdout = bw.writer();
    var jws = std.json.writeStream(stdout, .{});

    var prev_path_buf: [1024]u8 = undefined;
    var prev_path = try std.fmt.bufPrint(&prev_path_buf, "json", .{});
    var line_buf: [1024]u8 = undefined;
    while (try input.readUntilDelimiterOrEof(&line_buf, '\n')) |line_raw| {
        const line = mem.trimRight(u8, line_raw, ";");
        var path_val_it = mem.splitBackwardsSequence(u8, line, " = ");
        const val = path_val_it.next().?;
        const path = path_val_it.next().?;
        const val_is_obj = mem.eql(u8, val, "{}");
        const val_is_arr = mem.eql(u8, val, "[]");
        const path_is_arr = path[path.len - 1] == ']';
        const path_is_nonroot = !mem.eql(u8, path, "json");
        const path_nest = pathNest(path);
        const prev_path_nest = pathNest(prev_path);

        // Try to end objects and arrays
        if (path_nest < prev_path_nest) {
            if (prev_path[prev_path.len - 1] == ']') {
                try jws.endArray();
            } else {
                try jws.endObject();
            }
        }
        // TODO memcopy
        prev_path = try std.fmt.bufPrint(&prev_path_buf, "{s}", .{path});
        try bw.flush();

        // write fields and values
        if (path_is_nonroot and !path_is_arr) {
            // assumes that fields do not contain periods
            var path_it = mem.splitBackwardsSequence(u8, path, ".");
            const key = path_it.next().?;
            std.debug.print("path: {s}, key: {s}, is_arr{any}\n", .{ path, key, path_is_arr });
            try jws.objectField(key);
        }
        if (val_is_obj) {
            try jws.beginObject();
        } else if (val_is_arr) {
            try jws.beginArray();
        } else {
            try jws.write(val);
        }
        try bw.flush();
    }
}

fn pathNest(path: []const u8) usize {
    var sum: usize = 0;
    for (path) |c| {
        if (c == '.' or c == '[') {
            sum += 1;
        }
    }
    return sum;
}
