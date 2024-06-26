const std = @import("std");
const builtin = @import("builtin");
const json = std.json;
const mem = std.mem;
const fmt = std.fmt;
const GenCatData = @import("GenCatData");
const json_ident = @import("json_ident.zig");

pub fn gron(rdr: anytype, wtr: anytype, stream_info: StreamInfo) !void {
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

    // tracks statement stack (but not the associate names, to ensure that the
    // fba frees the names properly). Deinit not required.
    var stack_buf: [1024]u8 = undefined;
    var stack_fba = std.heap.FixedBufferAllocator.init(&stack_buf);
    const stack_alloc = stack_fba.allocator();
    var stack = std.ArrayList(StackItem).init(stack_alloc);
    try stack.append(.{ .root = .{ .line_idx = stream_info.line_idx } });

    // Note that fba will only free if the item is at the end of the stack
    // (like a bump allocator). That's why this is kept separate from the stack_fba,
    // so I don't have to make sure that e.g. a resizing of the stack will make it
    // impossible to free the stack names.
    //
    // Assumes that key names are generally not that big, and nesting is not that
    // deep. Could probably increase buffer size even more without penalty.
    //
    // Should free a name after stack is popped. Because these names are pushed and
    // popped stack-like, free should always succeed.
    var stack_names_buf: [4096]u8 = undefined;
    var stack_names_fba = std.heap.FixedBufferAllocator.init(&stack_names_buf);
    const stack_names_alloc = stack_names_fba.allocator();

    var bw = std.io.bufferedWriter(wtr);
    const stdout = bw.writer();

    var jr = std.json.reader(j_alloc, rdr);

    while (true) {
        const token = try jr.nextAlloc(val_alloc, .alloc_if_needed);

        // write stack
        if (shouldWriteLine(token)) {
            try writeStack(stack.items, &stdout);
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
                switch (stack.getLast()) {
                    .object_begin => {
                        // it's a kv

                        // since the scanner buffer may be evicted during the nextAlloc call
                        // to make way for new data, we need to alloc the key before the
                        // json nextAlloc call. Even though we can also write the key first
                        // for certain lines, if the key = {} or [], we'll need to save the key
                        // to the stack. But we won't know until nextAlloc is called.
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
                                const name = try stack_names_alloc.dupe(u8, key);
                                try stack.append(.{ .object_begin = .{ .name = name, .bracket = shouldBracketField(key, &gcd) } });
                            },
                            .array_begin => {
                                try stdout.print(" = [];\n", .{});
                                const name = try stack_names_alloc.dupe(u8, key);
                                try stack.append(.{ .array_begin = .{ .name = name, .bracket = shouldBracketField(key, &gcd) } });
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
                try stack.append(.{ .object_begin = .{} });
            },
            .array_begin => {
                try stdout.print(" = [];\n", .{});
                try stack.append(.{ .array_begin = .{} });
            },
            .object_end => {
                // unwind stack to previous bracket
                const last = stack.pop();
                switch (last) {
                    .object_begin => |o| if (o.name) |name| {
                        stack_names_alloc.free(name);
                    },
                    else => unreachable,
                }
            },
            .array_end => {
                // unwind stack to previous bracket
                const last = stack.pop();
                switch (last) {
                    .array_begin => |a| if (a.name) |name| {
                        stack_names_alloc.free(name);
                    },
                    else => unreachable,
                }
            },
            else => return error.PartialValue,
        }
        // flushing more often helps with debugging
        //try bw.flush();
        // Assumes that if we need to have space for large values once, we'll need it again
        _ = val_arena.reset(.retain_capacity);

        // increase index if stack inside array
        switch (stack.items[stack.items.len - 1]) {
            .array_begin => |*a| {
                if (a.curr_idx) |*curr_idx| {
                    curr_idx.* += 1;
                } else {
                    a.curr_idx = 0;
                }
            },
            else => {},
        }
    }
    try bw.flush();
}

fn writeStack(stack: []StackItem, wtr: anytype) !void {
    for (stack) |item| {
        switch (item) {
            .root => |r| if (r.line_idx) |idx| {
                try wtr.print("json[{d}]", .{idx});
            } else {
                try wtr.print("json", .{});
            },
            .object_begin => |o| if (o.name) |n| {
                if (o.bracket) {
                    // may contain escaped characters
                    _ = try wtr.write("[");
                    try json.encodeJsonString(n, .{}, wtr);
                    _ = try wtr.write("]");
                } else {
                    try wtr.print(".{s}", .{n});
                }
            },
            .array_begin => |a| if (a.name) |n| {
                if (a.bracket) {
                    // may contain escaped characters
                    _ = try wtr.write("[");
                    try json.encodeJsonString(n, .{}, wtr);
                    try wtr.print("][{d}]", .{a.curr_idx.?});
                } else {
                    try wtr.print(".{s}[{d}]", .{ n, a.curr_idx.? });
                }
            } else {
                try wtr.print("[{d}]", .{a.curr_idx.?});
            },
        }
    }
}

const StackItem = union(enum) {
    root: struct {
        line_idx: ?usize = null,
    },
    object_begin: struct {
        name: ?[]const u8 = null,
        bracket: bool = false,
    },
    array_begin: struct {
        name: ?[]const u8 = null,
        bracket: bool = false,
        curr_idx: ?u64 = null,
    },
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
