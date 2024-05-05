const std = @import("std");
const meta = std.meta;
const testing = std.testing;

const binary = @import("./binary.zig");
const compact = @import("./compact.zig");

pub fn SizeHint(comptime T: type) usize {
    var size_hint: usize = 0;

    inline for (meta.fields(T)) |field| {
        size_hint += @sizeOf(field.type);
    }

    return size_hint;
}

pub fn Encode(comptime T: type, to_encode: T, enc: *std.ArrayList(u8)) !void {
    switch (@typeInfo(T)) {
        .Int => try encode_integer(T, to_encode, enc),
        .Struct => try encode_struct(T, to_encode, enc),
        else => @compileError("encoding only supports structs"),
    }
}

pub fn encode_struct(comptime T: type, to_encode: T, enc: *std.ArrayList(u8)) !void {
    inline for (meta.fields(T)) |field| {
        switch (field.type) {
            []const u8 => {
                const str_value: []const u8 = @field(to_encode, field.name);
                try encode_const_byte_slice(str_value, enc);
            },
            usize, u8, u16, u32, u64, u128, isize, i8, i16, i32, i64, i128 => {
                const integer: field.type = @field(to_encode, field.name);
                try encode_integer(field.type, integer, enc);
            },
            else => @compileError("structs only supports []const u8"),
        }
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

test "encode a  basic struct" {
    const Animal = struct { name: []const u8, age: u64 };

    const size_hint = SizeHint(Animal);

    var cow: Animal = .{ .name = "cow_name", .age = 10 };

    var encoded_bytes = try std.ArrayList(u8).initCapacity(
        testing.allocator,
        size_hint,
    );
    defer encoded_bytes.deinit();

    try Encode(Animal, cow, &encoded_bytes);

    var exp = &[_]u8{ 32, 99, 111, 119, 95, 110, 97, 109, 101, 10, 0, 0, 0, 0, 0, 0, 0 };
    try testing.expect(std.mem.eql(u8, exp, encoded_bytes.items));
}
