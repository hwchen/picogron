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
            try jws.objectField(key);
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
                try jws.write(val);
            } else if (val_is_null) {
                try jws.write(null);
            } else if (val_is_true) {
                try jws.write(true);
            } else if (val_is_false) {
                try jws.write(false);
            } else {
                std.debug.print("{s}", .{val});
                const n = try std.fmt.parseFloat(f64, val);
                try jws.write(n);
            }
        }
        try bw.flush();
    }
}

// TODO: don't count periods inside of quoted idents
fn pathNest(path: []const u8) usize {
    var sum: usize = 0;
    for (path) |c| {
        if (c == '.' or c == '[') {
            sum += 1;
        }
    }
    return sum;
}
