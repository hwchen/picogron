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
        if (!mem.eql(u8, path, "json")) {
            // assumes that fields do not contain periods
            var path_it = mem.splitBackwardsSequence(u8, path, ".");
            const key = path_it.next().?;
            try jws.objectField(key);
        }
        if (mem.eql(u8, val, "{}")) {
            try jws.beginObject();
        } else if (mem.eql(u8, val, "[]")) {
            try jws.beginArray();
        } else {
            try jws.write(val);
        }
        // TODO when to end object or array?
        // Can track previous path to see if something was popped
        if (path.len < prev_path.len) {
            if (path[path.len - 1] == ']') {
                try jws.endArray();
            } else {
                try jws.endObject();
            }
        }
        // TODO memcopy
        prev_path = try std.fmt.bufPrint(&prev_path_buf, "{s}", .{path});
    }
    try bw.flush();
}
