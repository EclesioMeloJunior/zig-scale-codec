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
    std.debug.print("{any}\n", .{encoded_bytes.items});
}
