const std = @import("std");
const json = std.json;
const mem = std.mem;
const fmt = std.fmt;

pub fn gorn(rdr: anytype, wtr: anytype) !void {
    // Used to track nesting levels for json parser
    var j_buf: [512]u8 = undefined;
    var j_fba = std.heap.FixedBufferAllocator.init(&j_buf);
    const j_alloc = j_fba.allocator();

    // Used to temporarily allocate (and immediately free) parsed values
    var val_buf: [2048]u8 = undefined;
    var val_fba = std.heap.FixedBufferAllocator.init(&val_buf);
    const val_alloc = val_fba.allocator();

    // tracks statement stack (nested levels, with object key)
    // TODO use gpa so we can free field name strings as needed?
    var stack_buf: [4096]u8 = undefined;
    var stack_fba = std.heap.FixedBufferAllocator.init(&stack_buf);
    const stack_alloc = stack_fba.allocator();
    var stack = std.ArrayList(StackItem).init(stack_alloc);
    try stack.append(.root);

    var bw = std.io.bufferedWriter(wtr);
    const stdout = bw.writer();

    var jr = std.json.reader(j_alloc, rdr);

    while (true) {
        const token = try jr.nextAlloc(val_alloc, .alloc_if_needed);

        // write stack
        switch (token) {
            .true, .false, .null, .number, .allocated_number, .string, .allocated_string, .object_begin, .array_begin => {
                try writeStack(stack.items, &stdout);
            },
            else => {},
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
                        const val = try jr.nextAlloc(val_alloc, .alloc_if_needed);
                        switch (val) {
                            .end_of_document => break,
                            .number, .allocated_number => |v| {
                                try stdout.print("{s} = {s};\n", .{ s, v });
                            },
                            .string, .allocated_string => |v| {
                                try stdout.print("{s} = \"{s}\";\n", .{ s, v });
                            },
                            .true => try stdout.print("{s} = true;\n", .{s}),
                            .false => try stdout.print("{s} = false;\n", .{s}),
                            .null => try stdout.print("{s} = null;\n", .{s}),
                            .object_begin => {
                                try stdout.print("{s} = {{}};\n", .{s});
                                // TODO copy memory better
                                const k = try fmt.allocPrint(stack_alloc, "{s}", .{s});
                                try stack.append(.{ .object_begin = k });
                            },
                            .array_begin => {
                                try stdout.print("{s} = [];\n", .{s});
                                const v = try fmt.allocPrint(stack_alloc, "{s}", .{s});
                                try stack.append(.{ .array_begin = .{ .name = v } });
                            },
                            .object_end => {
                                // unwind stack to previous bracket + key
                                const last = stack.pop();
                                std.debug.assert(std.meta.activeTag(last) == StackItem.object_begin);
                                // TODO free field string
                            },
                            .array_end => {
                                // unwind stack to previous bracket + key
                                const last = stack.pop();
                                std.debug.assert(std.meta.activeTag(last) == StackItem.array_begin);
                                // TODO free field string
                            },
                            else => return error.PartialValue,
                        }
                    },
                    else => {
                        // just a string
                        try stdout.print(" = \"{s}\";\n", .{s});
                    },
                }
            },
            .object_begin => {
                try stdout.print(" = {{}};\n", .{});
                try stack.append(.{ .object_begin = null });
            },
            .array_begin => {
                try stdout.print(" = [];\n", .{});
                try stack.append(.{ .array_begin = .{} });
            },
            .object_end => {
                // unwind stack to previous bracket + one
                const last = stack.pop();
                std.debug.assert(std.meta.activeTag(last) == StackItem.object_begin);
                // TODO free field string
            },
            .array_end => {
                // unwind stack to previous bracket
                const last = stack.pop();
                std.debug.assert(std.meta.activeTag(last) == StackItem.array_begin);
                // TODO free field string
            },
            else => return error.PartialValue,
        }
        try bw.flush();
        val_fba.reset();

        // increase index if stack inside array
        //std.debug.print("{any}\n", .{stack.items});
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
}

fn writeStack(stack: []StackItem, wtr: anytype) !void {
    for (stack) |item| {
        switch (item) {
            .root => try wtr.print("json", .{}),
            .object_begin => |name| {
                if (name) |n| {
                    try wtr.print("{s}.", .{n});
                } else {
                    try wtr.print(".", .{});
                }
            },
            .array_begin => |a| {
                if (a.name) |n| {
                    try wtr.print("{s}[{d}]", .{ n, a.curr_idx.? });
                } else {
                    try wtr.print("[{d}]", .{a.curr_idx.?});
                }
            },
        }
    }
}

const StackItem = union(enum) {
    root,
    object_begin: ?[]const u8,
    array_begin: struct {
        name: ?[]const u8 = null,
        curr_idx: ?u64 = null,
    },
};