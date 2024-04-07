const std = @import("std");

pub const c = @cImport({
    @cInclude("duktape.h");
    @cInclude("duk_config.h");
});

pub const Error = error{
    HeapAllocationError,
    EvaluationError,
    CompilationError,
    FunctionCallError,
    NotFoundError,
    InvalidArgument,
};

pub const Value = union(enum) {
    null: void,
    undefined: void,
    boolean: bool,
    number: f64,
    string: []const u8,
    pointer: *anyopaque,

    //TODO: add object, array, buffer, lightfunc
};

pub const Context = struct {
    ctx: *c.duk_context,

    const Self = @This();
    pub fn alloc() Error!Self {
        return Self{
            .ctx = c.duk_create_heap(null, null, null, null, null) orelse return Error.HeapAllocationError,
        };
    }

    pub fn dealloc(self: *Self) void {
        c.duk_destroy_heap(self.ctx);
    }

    pub fn eval(self: *Self, code: []const u8) Error!?Value {
        if (c.duk_eval_raw(self.ctx, code.ptr, @as(c_int, 0), (((@as(c_int, 0) | c.DUK_COMPILE_EVAL) | c.DUK_COMPILE_NOSOURCE) | c.DUK_COMPILE_STRLEN) | c.DUK_COMPILE_NOFILENAME) != 0) {
            const err = std.mem.span(c.duk_safe_to_lstring(self.ctx, -1, null));
            std.log.err("duktape-zig eval error: {s}\n", .{err});
            return Error.EvaluationError;
        }

        return get_stack_value(self);
    }

    pub fn compile(self: *Self, code: []const u8) Error!void {
        if (c.duk_pcompile_string(self.ctx, 0, code.ptr) != 0) {
            const err = std.mem.span(c.duk_safe_to_lstring(self.ctx, -1, null));
            std.log.err("duktape-zig compile error: {s}\n", .{err});
            return Error.CompilationError;
        }

        _ = c.duk_pcall(self.ctx, 0);
        c.duk_pop(self.ctx);
    }

    pub fn call(self: *Self, name: []const u8, comptime args: anytype) Error!?Value {
        const args_type = @typeInfo(@TypeOf(args));
        if (args_type != .Struct and args_type != .Null) {
            @compileError("args should be a struct or null");
        }

        if (c.duk_get_global_string(self.ctx, name.ptr) != 1) {
            return Error.NotFoundError;
        }

        var nargs: c.duk_idx_t = 0;
        if (args_type == .Struct) {
            inline for (args) |value| {
                switch (@typeInfo(@TypeOf(value))) {
                    .Null => c.duk_push_null(self.ctx),
                    .Bool => |b| c.duk_push_boolean(self.ctx, @intFromBool(b)),
                    .Int => c.duk_push_number(self.ctx, @floatFromInt(value)),
                    .ComptimeInt => c.duk_push_number(self.ctx, @floatFromInt(value)),
                    .Float => c.duk_push_number(self.ctx, @floatCast(value)),
                    .ComptimeFloat => c.duk_push_number(self.ctx, @floatCast(value)),
                    .Pointer => _ = c.duk_push_string(self.ctx, value.ptr),

                    else => {
                        std.log.err("Unknown type {any}", .{@typeName(@TypeOf(value))});
                        return Error.InvalidArgument;
                    },
                }
                nargs += 1;
            }
        }

        if (c.duk_pcall(self.ctx, nargs) != 0) {
            const err = std.mem.span(c.duk_safe_to_lstring(self.ctx, -1, null));
            std.log.err("duktape-zig error in {s}: {s}\n", .{ name, err });
            return Error.FunctionCallError;
        }

        return get_stack_value(self);
    }

    fn get_stack_value(self: *Self) ?Value {
        const value = switch (c.duk_get_type(self.ctx, -1)) {
            c.DUK_TYPE_NULL => .null,
            c.DUK_TYPE_UNDEFINED => .undefined,
            c.DUK_TYPE_BOOLEAN => Value{ .boolean = c.duk_get_boolean(self.ctx, -1) == 1 },
            c.DUK_TYPE_NUMBER => Value{ .number = @floatCast(c.duk_get_number(self.ctx, -1)) },
            c.DUK_TYPE_STRING => Value{ .string = std.mem.span(c.duk_get_string(self.ctx, -1)) },
            c.DUK_TYPE_POINTER => Value{ .pointer = c.duk_get_pointer(self.ctx, -1) orelse return .null },
            else => null,
        };

        c.duk_pop(self.ctx);
        return value;
    }
};

test "eval" {
    var context = try Context.alloc();
    defer context.dealloc();

    try std.testing.expect((try context.eval("5 + 5")).?.number == 10);
}

test "call" {
    var context = try Context.alloc();
    defer context.dealloc();

    try context.compile("function a(value) { return value + 10; }");
    try context.compile("function b(value) { return a(value) + 10; }");
    try context.compile("function c(value, str) { return b(value) + str; }");

    if (try context.call("a", .{10})) |result| {
        try std.testing.expect(result.number == 20);
    }

    if (try context.call("b", .{0})) |result| {
        try std.testing.expect(result.number == 20);
    }

    if (try context.call("c", .{ 20, "whoops... now its not a number!" })) |result| {
        try std.testing.expect(result != .number);
    }
}
