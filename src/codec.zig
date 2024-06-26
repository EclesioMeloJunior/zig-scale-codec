const std = @import("std");
const meta = std.meta;
const testing = std.testing;

const binary = @import("binary.zig");
const compact = @import("compact.zig");
const iterator = @import("iterator.zig");

const Errors = error{
    CouldNotReadFromIterator,
    UnexpectedByte,
    TypeNotSupported,
    UnexpectedEnd,
    EncodingOptional,
    TooManyElementsInColletion,
} || iterator.Errors || compact.Errors || std.mem.Allocator.Error;

pub fn SizeHint(comptime T: type, value: T) usize {
    if (T == []const u8) {
        return value.len;
    }

    switch (@typeInfo(T)) {
        .Int => return @as(usize, @sizeOf(T)),
        .Bool => return @as(usize, 1),
        .Union => {
            // handle Result type or any other custom type that
            // has its own size_hint method
            if (std.meta.hasMethod(T, "size_hint")) {
                return value.size_hint();
            }

            const active_tag = @tagName(value);
            inline for (meta.fields(T)) |prop| {
                if (std.mem.eql(u8, active_tag, prop.name)) {
                    return 1 + SizeHint(prop.type, @field(value, prop.name));
                }
            }

            unreachable;
        },
        .Struct => {
            if (std.meta.hasMethod(T, "size_hint")) {
                return value.size_hint();
            }

            var size: usize = 0;
            inline for (meta.fields(T)) |prop| {
                size += SizeHint(prop.type, @field(value, prop.name));
            }
            return size;
        },
        .Optional => {
            if (value) |inner| {
                return 1 + SizeHint(@TypeOf(inner), inner);
            }
            return @as(usize, 1);
        },
        .Array => {
            return @sizeOf(u32) + @sizeOf(T);
        },
        .Pointer => |ptr| {
            switch (ptr.size) {
                .Many, .Slice => {
                    return @sizeOf(u32) + (@sizeOf(ptr.child) * value.len);
                },
                else => @panic("unsupported ptr"),
            }
        },
        .Enum => |enum_field| return @sizeOf(enum_field.tag_type),
        else => @panic("unsupported type"),
    }
}

pub fn Encode(comptime T: type, to_encode: T, enc: *std.ArrayList(u8)) !void {
    if (T == []const u8) {
        try encode_const_byte_slice(to_encode, enc);
        return;
    }

    switch (@typeInfo(T)) {
        .Int => try encode_integer(T, to_encode, enc),
        .Bool => try encode_boolean(to_encode, enc),
        .Union => {
            // handle Result type or any other custom type that
            // has its own size_hint method
            if (std.meta.hasMethod(T, "encode")) {
                return to_encode.encode(enc);
            }

            try enc.append(@intFromEnum(to_encode));
            const active_tag = @tagName(to_encode);
            inline for (meta.fields(T)) |prop| {
                if (std.mem.eql(u8, active_tag, prop.name)) {
                    return Encode(prop.type, @field(to_encode, prop.name), enc);
                }
            }

            unreachable;
        },
        .Struct => {
            if (std.meta.hasMethod(T, "encode")) {
                return to_encode.encode(enc);
            }
            try encode_struct(T, to_encode, enc);
        },
        .Optional => try encode_optional(T, to_encode, enc),
        .Array => |arr| {
            try encode_set_of_items(arr.child, @as([]arr.child, @constCast(&to_encode)), enc);
        },
        .Pointer => |ptr| {
            switch (ptr.size) {
                .Many, .Slice => try encode_set_of_items(ptr.child, @as([]ptr.child, to_encode), enc),
                else => @panic("unsuported size" ++ ptr.size),
            }
        },
        .Enum => |enum_field| switch (enum_field.tag_type) {
            u1 => try enc.append(@intFromEnum(to_encode)),
            else => @panic("unsuported enum tag type" ++ enum_field.tag_type),
        },
        else => @panic("unsuported type" ++ T),
    }
}

pub fn encode_struct(comptime T: type, to_encode: T, enc: *std.ArrayList(u8)) !void {
    inline for (meta.fields(T)) |prop| {
        try Encode(prop.type, @field(to_encode, prop.name), enc);
    }
}

pub fn encode_const_byte_slice(value: []const u8, enc: *std.ArrayList(u8)) !void {
    const compact_len: compact.CompactUsize = .{ .value = value.len };
    try compact_len.encode(enc);
    try enc.appendSlice(value);
}

pub fn encode_integer(comptime T: type, value: T, enc: *std.ArrayList(u8)) !void {
    var buf: [@sizeOf(T)]u8 = undefined;
    binary.LittleEndianEncode(T, value, &buf);
    try enc.appendSlice(&buf);
}

pub fn encode_boolean(value: bool, enc: *std.ArrayList(u8)) !void {
    if (value) try enc.append(0x01) else try enc.append(0x00);
}

pub fn encode_optional(comptime T: type, opt: T, enc: *std.ArrayList(u8)) Errors!void {
    if (opt) |inner_value| {
        try enc.append(0x01);
        Encode(@TypeOf(inner_value), inner_value, enc) catch return error.EncodingOptional;
    } else {
        try enc.append(0x00);
    }
}

pub fn compact_encode_len(len: usize, enc: *std.ArrayList(u8)) Errors!void {
    if (len > std.math.maxInt(u32)) {
        return error.TooManyElementsInColletion;
    }

    const prefixed_len = compact.CompactUsize{ .value = len };
    try prefixed_len.encode(enc);
}

pub fn encode_set_of_items(comptime T: type, arr: []T, enc: *std.ArrayList(u8)) Errors!void {
    try compact_encode_len(arr.len, enc);

    if (arr.len == 0) {
        return;
    }

    for (arr) |item| {
        try Encode(T, item, enc);
    }
}

pub fn Result(comptime ok_t: type, comptime err_t: type) type {
    return union(enum) {
        Ok: ok_t,
        Err: err_t,

        pub const Self = @This();

        pub fn size_hint(s: Self) usize {
            switch (s) {
                .Ok => |rest| return 1 + SizeHint(@TypeOf(rest), rest),
                .Err => |rest| return 1 + SizeHint(@TypeOf(rest), rest),
            }
        }

        pub fn encode(s: Self, enc: *std.ArrayList(u8)) !void {
            switch (s) {
                .Ok => |rest| {
                    try enc.append(0x00);
                    try Encode(@TypeOf(rest), rest, enc);
                },
                .Err => |rest| {
                    try enc.append(0x01);
                    try Encode(@TypeOf(rest), rest, enc);
                },
            }
        }

        pub fn decode(iter: *iterator.Iterator(u8)) Errors!Self {
            if (iter.next()) |byte| {
                switch (byte) {
                    0x00 => return Self{
                        .Ok = try Decode(ok_t, iter),
                    },
                    0x01 => return Self{
                        .Err = try Decode(err_t, iter),
                    },
                    else => return Errors.UnexpectedByte,
                }
            }
            return Errors.UnexpectedEnd;
        }
    };
}

pub fn Decode(comptime T: type, iter: *iterator.Iterator(u8)) Errors!T {
    if (T == []const u8) {
        return try decode_const_byte_slice(iter);
    }

    switch (@typeInfo(T)) {
        .Int => return try dencode_integer(T, iter),
        .Bool => {
            if (iter.next()) |byte| {
                return switch (byte) {
                    0x01 => true,
                    0x00 => false,
                    else => Errors.UnexpectedByte,
                };
            }
            return Errors.UnexpectedEnd;
        },
        .Union => {
            if (std.meta.hasFn(T, "decode")) {
                return T.decode(iter);
            }
            unreachable;
        },
        else => return Errors.TypeNotSupported,
    }
}

fn dencode_integer(comptime T: type, iter: *iterator.Iterator(u8)) Errors!T {
    var encoded_integer: [@sizeOf(T)]u8 = undefined;
    const n = iter.take(&encoded_integer) catch |err| return err;
    if (n == 0) {
        return Errors.CouldNotReadFromIterator;
    }

    return binary.LittleEndianDecode(
        T,
        @as(*const [@sizeOf(T)]u8, @ptrCast(&encoded_integer)),
    );
}

fn decode_const_byte_slice(iter: *iterator.Iterator(u8)) Errors![]const u8 {
    const slice_len = try compact.Decode(usize, iter);
    var encoded_slice = try std.ArrayList(u8).initCapacity(
        std.heap.page_allocator,
        slice_len.value,
    );
    defer encoded_slice.deinit();

    var idx: usize = 0;
    while (idx < slice_len.value) : (idx += 1) {
        try encoded_slice.append(iter.next().?);
    }

    return encoded_slice.toOwnedSlice();
}

test "decode bool" {
    const TestCase = struct { encoded: []const u8, expected: bool };

    const cases = [_]TestCase{
        .{
            .encoded = &[_]u8{1},
            .expected = true,
        },
        .{
            .encoded = &[_]u8{0},
            .expected = false,
        },
    };

    for (cases) |tt| {
        var iter = iterator.Iterator(u8).new(tt.encoded);
        const out = try Decode(bool, &iter);
        try testing.expect(out == tt.expected);
    }
}

fn DecodeTestRunner(comptime T: type) type {
    return struct {
        fn run(cases: []T) !void {
            for (cases) |tt| {
                const size_hint = SizeHint(T, tt);
                var encoded_bytes = try std.ArrayList(u8).initCapacity(
                    testing.allocator,
                    size_hint,
                );
                defer encoded_bytes.deinit();

                try Encode(T, tt, &encoded_bytes);

                var encoded_type = iterator.Iterator(u8).new(encoded_bytes.items);
                const decoded_result = try Decode(T, &encoded_type);

                try testing.expectEqual(tt, decoded_result);
            }
        }
    };
}

test "decode Result type" {
    {
        var cases = [_]Result(u64, u64){
            .{ .Ok = 10 },
            .{ .Err = 99 },
        };

        try DecodeTestRunner(Result(u64, u64)).run(&cases);
    }

    {
        var cases = [_]Result([]const u8, Result(u64, u64)){
            .{ .Ok = "okok" },
            .{ .Err = .{ .Err = 100 } },
        };

        try DecodeTestRunner(Result([]const u8, Result(u64, u64))).run(&cases);
    }
}

test "size hint" {
    try testing.expect(SizeHint(bool, true) == 1);
    try testing.expect(SizeHint(bool, false) == 1);
    try testing.expect(SizeHint(?bool, null) == 1);
    try testing.expect(SizeHint(?bool, true) == 2);

    const compactU128: compact.CompactUint128 = .{ .value = std.math.maxInt(u128) };
    try testing.expect(SizeHint(compact.CompactUint128, compactU128) == 17);

    const Struct = struct { name: []const u8, age: u64 };
    const str: Struct = .{ .name = "abc", .age = 10 };

    try testing.expect(SizeHint(Struct, str) == 11);
}

test "encode_bool" {
    var true_output = std.ArrayList(u8).init(testing.allocator);
    defer true_output.deinit();
    var exp = &[_]u8{0x01};
    try Encode(bool, true, &true_output);
    try testing.expect(std.mem.eql(u8, exp, true_output.items));

    var false_output = std.ArrayList(u8).init(testing.allocator);
    defer false_output.deinit();
    exp = &[_]u8{0x00};
    try Encode(bool, false, &false_output);
    try testing.expect(std.mem.eql(u8, exp, false_output.items));
}

test "encode_integer" {
    const TestValue = union(enum) {
        u128: u128,
        i128: i128,
        u64: u64,
        i64: i64,
        u32: u32,
        i32: i32,
        u16: u16,
        i16: i16,
        u8: u8,
        i8: i8,
    };

    const Test = struct {
        ty: type,
        value: TestValue,
        exp: []const u8,
    };

    const test_cases = [_]Test{
        .{ .ty = u128, .value = TestValue{ .u128 = std.math.maxInt(u128) }, .exp = &[_]u8{ 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff } },
        .{ .ty = u64, .value = TestValue{ .u64 = std.math.maxInt(u64) }, .exp = &[_]u8{ 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff } },
        .{ .ty = i64, .value = TestValue{ .i64 = std.math.maxInt(i64) }, .exp = &[_]u8{ 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 127 } },
        .{ .ty = u32, .value = TestValue{ .u32 = std.math.maxInt(u32) }, .exp = &[_]u8{ 0xff, 0xff, 0xff, 0xff } },
        .{ .ty = u16, .value = TestValue{ .u16 = std.math.maxInt(u16) }, .exp = &[_]u8{ 0xff, 0xff } },
        .{ .ty = u8, .value = TestValue{ .u8 = std.math.maxInt(u8) }, .exp = &[_]u8{0xff} },
        .{ .ty = i8, .value = TestValue{ .i8 = std.math.minInt(i8) }, .exp = &[_]u8{128} },
    };

    inline for (test_cases) |tt| {
        var arr = std.ArrayList(u8).init(testing.allocator);
        defer arr.deinit();

        try Encode(tt.ty, @field(tt.value, @typeName(tt.ty)), &arr);
        const imm: []const u8 = arr.items;
        try testing.expect(std.mem.eql(u8, tt.exp, imm));
    }
}

test "encode a basic struct" {
    const Animal = struct { name: []const u8, age: u64 };
    const cow: Animal = .{ .name = "some_name", .age = 10 };
    const size_hint = SizeHint(Animal, cow);

    var encoded_bytes = try std.ArrayList(u8).initCapacity(
        testing.allocator,
        size_hint,
    );
    defer encoded_bytes.deinit();

    try Encode(Animal, cow, &encoded_bytes);

    const exp = &[_]u8{ 36, 115, 111, 109, 101, 95, 110, 97, 109, 101, 10, 0, 0, 0, 0, 0, 0, 0 };
    try testing.expect(std.mem.eql(u8, exp, encoded_bytes.items));
}

test "encode a basic struct with optional type" {
    const Str = struct { str: []const u8, num: u64, opt: ?bool };
    var str: Str = .{ .str = "some_name", .num = 10, .opt = true };
    const str_size_hint = SizeHint(Str, str);

    var encoded_bytes = try std.ArrayList(u8).initCapacity(
        testing.allocator,
        str_size_hint,
    );
    defer encoded_bytes.deinit();

    try Encode(Str, str, &encoded_bytes);

    try testing.expect(std.mem.eql(
        u8,
        &[_]u8{ 36, 115, 111, 109, 101, 95, 110, 97, 109, 101, 10, 0, 0, 0, 0, 0, 0, 0, 1, 1 },
        encoded_bytes.items,
    ));

    encoded_bytes.clearRetainingCapacity();

    str = .{ .str = "some_name", .num = 10, .opt = false };
    try Encode(Str, str, &encoded_bytes);
    try testing.expect(std.mem.eql(
        u8,
        &[_]u8{ 36, 115, 111, 109, 101, 95, 110, 97, 109, 101, 10, 0, 0, 0, 0, 0, 0, 0, 1, 0 },
        encoded_bytes.items,
    ));

    encoded_bytes.clearRetainingCapacity();

    str = .{ .str = "some_name", .num = 10, .opt = null };
    try Encode(Str, str, &encoded_bytes);
    try testing.expect(std.mem.eql(
        u8,
        &[_]u8{ 36, 115, 111, 109, 101, 95, 110, 97, 109, 101, 10, 0, 0, 0, 0, 0, 0, 0, 0 },
        encoded_bytes.items,
    ));
}

test "encode compact" {
    const cmp_uint64: compact.CompactUint64 = .{ .value = 10 };
    const cmp_size_hint = SizeHint(compact.CompactUint64, cmp_uint64);
    var encoded_bytes = try std.ArrayList(u8).initCapacity(
        testing.allocator,
        cmp_size_hint,
    );
    defer encoded_bytes.deinit();

    try Encode(compact.CompactUint64, cmp_uint64, &encoded_bytes);

    try testing.expect(std.mem.eql(
        u8,
        &[_]u8{40},
        encoded_bytes.items,
    ));
}

test "encoding a result type" {
    const name_res: Result([]const u8, []const u8) = .{ .Ok = "eclesio" };
    const name_res_hint = SizeHint(@TypeOf(name_res), name_res);
    var encoded_bytes = try std.ArrayList(u8).initCapacity(
        testing.allocator,
        name_res_hint,
    );
    defer encoded_bytes.deinit();
    try name_res.encode(&encoded_bytes);

    try testing.expect(std.mem.eql(
        u8,
        &[_]u8{ 0, 28, 101, 99, 108, 101, 115, 105, 111 },
        encoded_bytes.items,
    ));

    const StrWithResult = struct {
        result: Result(u64, []const u8),
        cmp: compact.CompactUint64,
    };

    const test_cases = [_]struct {
        case: StrWithResult,
        expected: []const u8,
    }{
        .{
            .case = .{
                .result = .{ .Ok = 100 },
                .cmp = .{ .value = @as(u64, std.math.maxInt(u16)) },
            },
            .expected = &[_]u8{ 0, 100, 0, 0, 0, 0, 0, 0, 0, 254, 255, 3, 0 },
        },
        .{
            .case = .{
                .result = .{ .Err = "fail" },
                .cmp = .{ .value = @as(u64, std.math.maxInt(u8)) },
            },
            .expected = &[_]u8{ 1, 16, 102, 97, 105, 108, 253, 3 },
        },
    };

    for (test_cases) |tt| {
        const hint = SizeHint(StrWithResult, tt.case);
        var encoded_out = try std.ArrayList(u8).initCapacity(testing.allocator, hint);
        defer encoded_out.deinit();

        try Encode(StrWithResult, tt.case, &encoded_out);
        try testing.expect(std.mem.eql(
            u8,
            tt.expected,
            encoded_out.items,
        ));
    }
}

test "encoding fixed size arrays" {
    const vec = [_]?i32{ 1, 2, 10000 };
    const vec_hint = SizeHint(@TypeOf(vec), vec);

    var encoded_out = try std.ArrayList(u8).initCapacity(testing.allocator, vec_hint);
    defer encoded_out.deinit();

    try Encode([3]?i32, vec, &encoded_out);
    try testing.expect(std.mem.eql(
        u8,
        &[_]u8{ 12, 1, 1, 0, 0, 0, 1, 2, 0, 0, 0, 1, 16, 39, 0, 0 },
        encoded_out.items,
    ));
}

test "encoding a slice" {
    var arr = [_]Result([]const u8, u64){
        .{ .Ok = "ok!" },
        .{ .Err = 100 },
        .{ .Ok = "this is an ok" },
        .{ .Err = std.math.maxInt(u64) },
    };

    const slice: []Result([]const u8, u64) = arr[0..];

    const hint = SizeHint([]Result([]const u8, u64), slice);
    var encoded_out = try std.ArrayList(u8).initCapacity(testing.allocator, hint);
    defer encoded_out.deinit();

    try Encode([]Result([]const u8, u64), slice, &encoded_out);
    try testing.expect(std.mem.eql(
        u8,
        &[_]u8{ 16, 0, 12, 111, 107, 33, 1, 100, 0, 0, 0, 0, 0, 0, 0, 0, 52, 116, 104, 105, 115, 32, 105, 115, 32, 97, 110, 32, 111, 107, 1, 255, 255, 255, 255, 255, 255, 255, 255 },
        encoded_out.items,
    ));
}

test "encoding tuples" {
    const tuple = .{
        @as(u32, 9090),
        @as(u64, 9090),
        true,
        @as(Result([]const u8, []const u8), .{ .Ok = "ok!" }),
    };

    const hint = SizeHint(@TypeOf(tuple), tuple);

    var encoded_out = try std.ArrayList(u8).initCapacity(testing.allocator, hint);
    defer encoded_out.deinit();

    try Encode(@TypeOf(tuple), tuple, &encoded_out);

    try testing.expect(std.mem.eql(
        u8,
        &[_]u8{ 130, 35, 0, 0, 130, 35, 0, 0, 0, 0, 0, 0, 1, 0, 12, 111, 107, 33 },
        encoded_out.items,
    ));
}

test "encode enum" {
    // enums will always have size 1
    const SimpleEnum = enum { Var1, Var2 };

    try testing.expect(SizeHint(SimpleEnum, .Var1) == 1);

    var encoded_out = try std.ArrayList(u8).initCapacity(testing.allocator, 1);
    defer encoded_out.deinit();

    try Encode(SimpleEnum, .Var1, &encoded_out);
    try testing.expect(std.mem.eql(
        u8,
        &[_]u8{0},
        encoded_out.items,
    ));

    encoded_out.clearRetainingCapacity();
    try Encode(SimpleEnum, .Var2, &encoded_out);
    try testing.expect(std.mem.eql(
        u8,
        &[_]u8{1},
        encoded_out.items,
    ));
}

test "encoding union type" {
    const ComplexEnum = union(enum) {
        Var1: Result([]const u8, []const u8),
        Var2: ?Result([]const u8, []const u8),
        Var3: struct {
            a: bool,
            b: compact.CompactUint64,
            c: compact.CompactUint32,
        },
    };

    const var1 = ComplexEnum{
        .Var1 = @as(Result([]const u8, []const u8), .{ .Ok = "this is an ok" }),
    };
    const hint = SizeHint(ComplexEnum, var1);

    var encoded_out = try std.ArrayList(u8).initCapacity(testing.allocator, hint);
    defer encoded_out.deinit();

    try Encode(ComplexEnum, var1, &encoded_out);
    try testing.expect(std.mem.eql(
        u8,
        &[_]u8{ 0, 0, 52, 116, 104, 105, 115, 32, 105, 115, 32, 97, 110, 32, 111, 107 },
        encoded_out.items,
    ));

    encoded_out.clearRetainingCapacity();

    const var2Null = ComplexEnum{ .Var2 = null };
    try Encode(ComplexEnum, var2Null, &encoded_out);
    try testing.expect(std.mem.eql(
        u8,
        &[_]u8{ 1, 0 },
        encoded_out.items,
    ));

    encoded_out.clearRetainingCapacity();

    const var2Some = ComplexEnum{ .Var2 = .{ .Err = "an error" } };
    try Encode(ComplexEnum, var2Some, &encoded_out);
    try testing.expect(std.mem.eql(
        u8,
        &[_]u8{ 1, 1, 1, 32, 97, 110, 32, 101, 114, 114, 111, 114 },
        encoded_out.items,
    ));

    encoded_out.clearRetainingCapacity();

    const var3 = ComplexEnum{
        .Var3 = .{
            .a = true,
            .b = .{ .value = 0 },
            .c = .{ .value = 1 },
        },
    };

    try Encode(ComplexEnum, var3, &encoded_out);
    try testing.expect(std.mem.eql(
        u8,
        &[_]u8{ 2, 1, 0, 4 },
        encoded_out.items,
    ));
}
