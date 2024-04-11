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

// simple parsing
pub fn parseLine(line: []const u8) LineInfo {
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
