const std = @import("std");
const meta = std.meta;
const testing = std.testing;

const binary = @import("./binary.zig");
const compact = @import("./compact.zig");

const Error = error{EncodingOptional} || std.mem.Allocator.Error;

pub fn SizeHint(comptime T: type, value: T) usize {
    switch (@typeInfo(T)) {
        .Int => return @as(usize, @sizeOf(T)),
        .Bool => return @as(usize, 1),
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
        else => switch (T) {
            []const u8 => return value.len,
            else => @panic("unsuported type" ++ T),
        },
    }
}

pub fn Encode(comptime T: type, to_encode: T, enc: *std.ArrayList(u8)) !void {
    switch (@typeInfo(T)) {
        .Int => try encode_integer(T, to_encode, enc),
        .Bool => try encode_boolean(to_encode, enc),
        .Struct => {
            if (std.meta.hasMethod(T, "encode")) {
                return to_encode.encode(enc);
            }
            try encode_struct(T, to_encode, enc);
        },
        .Optional => try encode_optional(T, to_encode, enc),
        else => switch (T) {
            []const u8 => try encode_const_byte_slice(to_encode, enc),
            else => @panic("unsuported type" ++ T),
        },
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

pub fn encode_optional(comptime T: type, opt: T, enc: *std.ArrayList(u8)) Error!void {
    if (opt) |inner_value| {
        try enc.append(0x01);
        Encode(@TypeOf(inner_value), inner_value, enc) catch return error.EncodingOptional;
    } else {
        try enc.append(0x00);
    }
}

test "size hint" {
    try testing.expect(SizeHint(bool, true) == 1);
    try testing.expect(SizeHint(bool, false) == 1);
    try testing.expect(SizeHint(?bool, null) == 1);
    try testing.expect(SizeHint(?bool, true) == 2);

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
