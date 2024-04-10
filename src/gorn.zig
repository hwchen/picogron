const std = @import("std");
const builtin = @import("builtin");
const json = std.json;
const mem = std.mem;
const fmt = std.fmt;
const GenCatData = @import("GenCatData");
const json_ident = @import("json_ident.zig");

pub fn gorn(rdr: anytype, wtr: anytype, stream_info: StreamInfo) !void {
    // Used to hold data for unicode processing (checking if string is
    // javascript ident).
    var gcd_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const gcd_alloc = gcd_arena.allocator();
    var gcd = try GenCatData.init(gcd_alloc);

    // Used to track nesting levels for json parser
    var j_buf: [512]u8 = undefined;
    var j_fba = std.heap.FixedBufferAllocator.init(&j_buf);
    const j_alloc = j_fba.allocator();

    // Used to temporarily allocate (and immediately free) parsed values.
    // Reset on each iteration of loop, as we don't need past parse values.
    var val_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const val_alloc = val_arena.allocator();

    // track the path to be written before the value
    var path = try Path.init(stream_info.line_idx);

    var bw = std.io.bufferedWriter(wtr);
    const stdout = bw.writer();

    var jr = std.json.reader(j_alloc, rdr);

    while (true) {
        const token = try jr.nextAlloc(val_alloc, .alloc_if_needed);

        // write stack
        if (shouldWriteLine(token)) {
            _ = try path.write(&stdout);
        }

        // write value
        switch (token) {
            .end_of_document => break,
            .true => try stdout.print(" = true;\n", .{}),
            .false => try stdout.print(" = false;\n", .{}),
            .null => try stdout.print(" = null;\n", .{}),
            .number, .allocated_number => |n| try stdout.print(" = {s};\n", .{n}),
            // Could be just a string, or a kv
            .string, .allocated_string => |s| {
                switch (path.getLastTag()) {
                    .object => {
                        // it's a kv

                        // since the scanner buffer may be evicted during the nextAlloc call
                        // to make way for new data, we need to alloc the key before the
                        // json nextAlloc call. Even though we can also write the key first
                        // for certain lines, if the key = {} or [], we'll need to save the key
                        // to the path. But we won't know until nextAlloc is called.
                        const key = try val_alloc.dupe(u8, s);

                        // We can assume that since we received an .object_begin,
                        // we must write the key, otherwise the json is malformed.
                        if (shouldBracketField(key, &gcd)) {
                            // may contain escaped characters
                            _ = try stdout.write("[");
                            try json.encodeJsonString(key, .{}, &stdout);
                            _ = try stdout.write("]");
                        } else {
                            try stdout.print(".{s}", .{key});
                        }

                        const val = try jr.nextAlloc(val_alloc, .alloc_if_needed);
                        switch (val) {
                            .end_of_document => break,
                            .true => try stdout.print(" = true;\n", .{}),
                            .false => try stdout.print(" = false;\n", .{}),
                            .null => try stdout.print(" = null;\n", .{}),
                            .number, .allocated_number => |v| {
                                try stdout.print(" = {s};\n", .{v});
                            },
                            .string, .allocated_string => |v| {
                                // Value may contain escaped sequences, so encode as json string
                                _ = try stdout.write(" = ");
                                try json.encodeJsonString(v, .{}, &stdout);
                                _ = try stdout.write(";\n");
                            },
                            .object_begin => {
                                try stdout.print(" = {{}};\n", .{});
                                try path.pushTagName(.object, key, shouldBracketField(key, &gcd));
                            },
                            .array_begin => {
                                try stdout.print(" = [];\n", .{});
                                try path.pushTagName(.array, key, shouldBracketField(key, &gcd));
                            },
                            .object_end, .array_end => {
                                return error.malformedJson;
                            },
                            else => return error.PartialValue,
                        }
                    },
                    else => {
                        // just a string. Value may contain escaped sequences, so encode as json string
                        _ = try stdout.write(" = ");
                        try json.encodeJsonString(s, .{}, &stdout);
                        _ = try stdout.write(";\n");
                    },
                }
            },
            .object_begin => {
                try stdout.print(" = {{}};\n", .{});
                try path.pushTag(.object);
            },
            .array_begin => {
                try stdout.print(" = [];\n", .{});
                try path.pushTag(.array);
            },
            .object_end, .array_end => {
                _ = path.pop();
            },
            else => return error.PartialValue,
        }
        // flushing more often helps with debugging
        //try bw.flush();
        // Assumes that if we need to have space for large values once, we'll need it again
        _ = val_arena.reset(.retain_capacity);

        // increase index if stack inside array
        try path.incrementIfInArray();
    }
    try bw.flush();
}

// Assumes that key names are generally not that big, and nesting is not that
// deep. Could probably increase buffer size even more without penalty.
const Path = struct {
    // tracks the nodes of the path in a stack
    buf: [1024]u8,
    fba: std.heap.FixedBufferAllocator,
    alloc: std.mem.Allocator,
    stack: std.ArrayList(Node),

    // Stores the line to write
    line_buf: [4096]u8,
    line_end: usize,

    fn init(stream_idx: ?usize) !Path {
        var buf: [1024]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buf);
        const alloc = fba.allocator();
        const stack = std.ArrayList(Node).init(alloc);
        var line_buf: [4096]u8 = undefined;
        const line = if (stream_idx) |i|
            try fmt.bufPrint(&line_buf, "json[{d}]", .{i})
        else
            try fmt.bufPrint(&line_buf, "json", .{});
        return Path{
            .buf = buf,
            .fba = fba,
            .alloc = alloc,
            .stack = stack,
            .line_buf = line_buf,
            .line_end = line.len,
        };
    }

    fn write(self: Path, wtr: anytype) !usize {
        return try wtr.write(self.line_buf[0..self.line_end]);
    }

    fn pushTag(self: *Path, tag: NodeTag) !void {
        const write_idx = self.line_end;
        const target = self.line_buf[write_idx..];
        const written = switch (tag) {
            .object => &.{},
            .array => try fmt.bufPrint(target, "[0]", .{}),
        };
        self.line_end = write_idx + written.len;
        // TODO streamline this?
        switch (tag) {
            .object => try self.stack.append(.{ .object = .{ .line_idx = write_idx } }),
            .array => try self.stack.append(.{ .array = .{ .line_idx = write_idx } }),
        }
    }

    fn pushTagName(self: *Path, tag: NodeTag, name: []const u8, is_bracketed: bool) !void {
        const write_idx = self.line_end;
        const target = self.line_buf[write_idx..];
        const written = if (is_bracketed) switch (tag) {
            .object => blk: {
                var fbs = std.io.fixedBufferStream(target);
                var wtr = fbs.writer();
                _ = try wtr.write("[");
                try json.encodeJsonString(name, .{}, wtr);
                _ = try wtr.write("]");
                break :blk fbs.getWritten();
            },
            .array => blk: {
                var fbs = std.io.fixedBufferStream(target);
                var wtr = fbs.writer();
                _ = try wtr.write("[");
                try json.encodeJsonString(name, .{}, wtr);
                try wtr.print("][0]", .{});
                break :blk fbs.getWritten();
            },
        } else switch (tag) {
            .object => try fmt.bufPrint(target, ".{s}", .{name}),
            .array => try fmt.bufPrint(target, ".{s}[0]", .{name}),
        };
        self.line_end = write_idx + written.len;
        switch (tag) {
            .object => try self.stack.append(.{ .object = .{ .line_idx = write_idx } }),
            .array => try self.stack.append(.{ .array = .{ .line_idx = write_idx } }),
        }
    }

    fn pop(self: *Path) void {
        const node = self.stack.pop();
        switch (node) {
            inline else => |n| self.line_end = n.line_idx,
        }
    }

    fn getLastTag(self: Path) NodeTag {
        return self.stack.getLast();
    }

    fn incrementIfInArray(self: *Path) !void {
        const nodes = self.stack.items;
        if (nodes.len > 0) switch (nodes[nodes.len - 1]) {
            .array => |*a| {
                a.curr_idx += 1;
                // rewrite line for the new idx
                const write_idx = std.mem.lastIndexOf(u8, self.line_buf[0..self.line_end], "[").?;
                const written = try fmt.bufPrint(self.line_buf[write_idx..], "[{d}]", .{a.curr_idx});
                self.line_end = write_idx + written.len;
            },
            else => {},
        };
    }

    const NodeTag = enum {
        object,
        array,
    };

    const Node = union(NodeTag) { object: struct {
        line_idx: usize,
    }, array: struct {
        line_idx: usize,
        curr_idx: usize = 0,
    } };
};

// Should write line on most tokens, but not on e.g. array end and object end
fn shouldWriteLine(token: json.Token) bool {
    return switch (token) {
        .true, .false, .null, .number, .allocated_number, .string, .allocated_string, .object_begin, .array_begin => true,
        else => false,
    };
}

// Javascript identifiers do not need to be bracketed. Field names do not need to conform to
// javascript ident standards; non-js-idents are bracketed, while js-idents are written using
// dot notation.
//
// https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Lexical_grammar#identifiers
fn shouldBracketField(s: []const u8, gcd: *GenCatData) bool {
    const out = !json_ident.isJsIdent(s, gcd);
    return out;
}

pub const StreamInfo = struct {
    line_idx: ?usize = null,
};
