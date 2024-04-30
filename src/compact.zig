const std = @import("std");
const binary = @import("./binary.zig");

fn CompactInt(comptime T: type) type {
    return struct {
        value: T,

        const Self = @This();

        fn encode(_: *Self, enc: []u8) void {
            const v = [1]u8{0x32};
            std.mem.copy(u8, enc, &v);
        }
    };
}

const CompactUint8 = CompactInt(u8);
const CompactUint16 = CompactInt(u16);
const CompactUint32 = CompactInt(u32);
const CompactUint64 = CompactInt(u64);

const CompactInt8 = CompactInt(i8);
const CompactInt16 = CompactInt(i16);
const CompactInt32 = CompactInt(i32);
const CompactInt64 = CompactInt(i64);

fn compact_unsigned(comptime T: type, value: T, enc_bytes_ref: *std.ArrayList(u8)) !void {
    switch (T) {
        u8 => {
            switch (value) {
                0...0b0011_1111 => {
                    const uint8value: u8 = @intCast(value);
                    try enc_bytes_ref.append(uint8value << 2);
                },
                else => {
                    var enc: [2]u8 = undefined;
                    binary.LittleEndianEncode(u16, (@as(u16, value) << 2) | 0b01, &enc);
                    try enc_bytes_ref.appendSlice(&enc);
                },
            }
        },
        else => {},
    }
}

pub fn Encode(comptime T: type, value: T, enc_bytes_ref: *std.ArrayList(u8)) !void {
    comptime {
        if (@typeInfo(T) != .Int) {}
    }

    switch (@typeInfo(T)) {
        .Int => |int| {
            switch (int.signedness) {
                .unsigned => try compact_unsigned(T, value, enc_bytes_ref),
                .signed => {},
            }
        },
        else => {},
    }
}
