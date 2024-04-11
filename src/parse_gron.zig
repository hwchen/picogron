const std = @import("std");
const mem = std.mem;

pub const LineInfo = struct {
    nest: u32,
    last_field: LastField,
    // Only needed immediately after parsing. Lives as long
    // as a line
    last_field_str: []const u8,
    value: []const u8,
};

pub const LastField = enum {
    root,
    array,
    object,
    object_in_brackets,
};

pub fn parseLine(line: []const u8) LineInfo {
    return parseLineSimd(line) orelse parseLineSimple(line);
}

fn parseLineSimd(line: []const u8) ?LineInfo {
    var path_val_it = mem.splitBackwardsSequence(u8, line, " = ");
    const val = path_val_it.next().?;
    const path = path_val_it.next().?;

    const vector_len = 4;
    const needles_period: @Vector(vector_len, u8) = @splat(@as(u8, '.'));
    const needles_brcket: @Vector(vector_len, u8) = @splat(@as(u8, '['));
    const needles_dquote: @Vector(vector_len, u8) = @splat(@as(u8, '"'));

    var nest: u32 = 0;
    var idx: usize = 0;
    var remains = path.len;
    while (remains > 0) {
        if (remains < vector_len) {
            for (path[path.len - remains ..]) |c| {
                switch (c) {
                    '.', '[' => nest += 1,
                    '"' => return null,
                    else => {},
                }
            }
            break;
        } else {
            const haystack: @Vector(vector_len, u8) = path[idx..][0..vector_len].*;
            const matches_dquote = haystack == needles_dquote;
            if (@reduce(.Or, matches_dquote)) {
                // We want to exit and let simple parsing handle if there's any
                // double quotes in the path.
                return null;
            }

            const matches_period: @Vector(vector_len, u8) = @intCast(@intFromBool(haystack == needles_period));
            const matches_brcket: @Vector(vector_len, u8) = @intCast(@intFromBool(haystack == needles_brcket));
            nest += @reduce(.Add, matches_period);
            nest += @reduce(.Add, matches_brcket);
        }
        idx += vector_len;
        remains -= vector_len;
    }

    // At this point, we've exited if there's double quotes in the path,
    // so we know that a square bracket means array, otherwise object
    const last_field = switch (path[path.len - 1]) {
        ']' => LastField.array,
        else => if (nest == 0) LastField.root else LastField.object,
    };

    const last_field_str = switch (last_field) {
        .root => &.{},
        .array => &.{},
        .object => blk: {
            const last_dot = mem.lastIndexOfScalar(u8, path, '.').?;
            break :blk path[last_dot + 1 ..];
        },
        .object_in_brackets => unreachable,
    };

    return LineInfo{
        .nest = nest,
        .last_field = last_field,
        .last_field_str = last_field_str,
        .value = val[0 .. val.len - 1], // removes semicolon
    };
}

// simple parsing
fn parseLineSimple(line: []const u8) LineInfo {
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
    return LineInfo{
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

// Used to figure out that I needed to cast from bool to int (u1), then u1 to u8
test "parsing_simd" {
    const line =
        \\json.five.beta.hey = "How's tricks?";
    ;
    try std.testing.expectEqual(3, parseLineSimd(line).?.nest);
}
