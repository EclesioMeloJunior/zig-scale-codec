const std = @import("std");
const binary = @import("./binary.zig");

fn Compact(comptime T: type) type {
    return struct {
        value: T,
        const Self = @This();

        pub fn encode(s: Self, enc: *std.ArrayList(u8)) !void {
            try compact_unsigned(T, s.value, enc);
        }
    };
}

pub const CompactUsize = Compact(usize);
pub const CompactUint8 = Compact(u8);
pub const CompactUint16 = Compact(u16);
pub const CompactUint32 = Compact(u32);
pub const CompactUint64 = Compact(u64);

fn compact_unsigned(comptime T: type, value: T, enc_bytes_ref: *std.ArrayList(u8)) !void {
    comptime {
        switch (T) {
            usize, u8, u16, u32, u64, u128 => {},
            else => @compileError("compact encoding only supports usize, u8, u16, u32, u64 and u128"),
        }
    }

    switch (value) {
        0...0b0011_1111 => {
            const uint8value: u8 = @intCast(value);
            try enc_bytes_ref.append(uint8value << 2);
        },
        (0b0011_1111 + 1)...0b0011_1111_1111_1111 => {
            var enc: [2]u8 = undefined;
            binary.LittleEndianEncode(u16, (@as(u16, @truncate(value)) << 2) | 0b01, &enc);
            try enc_bytes_ref.appendSlice(&enc);
        },
        (0b0011_1111_1111_1111 + 1)...0b0011_1111_1111_1111_1111_1111_1111_1111 => {
            var enc: [4]u8 = undefined;
            binary.LittleEndianEncode(u32, (@as(u32, @truncate(value)) << 2) | 0b10, &enc);
            try enc_bytes_ref.appendSlice(&enc);
        },
        else => {
            var cpy_value = value;
            var alpha = if (T == u64) 8 else if (T == u128) 16 else @panic("alpha should be only 8 for u64 or 16 for u128");
            var bytes_needed = alpha - @clz(cpy_value) / 8;

            try enc_bytes_ref.append(0b11 + @as(u8, (bytes_needed - 4) << 2));

            for (1..bytes_needed) |_| {
                const ls8b: u8 = @truncate(value);
                try enc_bytes_ref.append(ls8b);
                cpy_value >>= 8;
            }

            if (cpy_value != 0) {
                @panic("expected 0 values but still values missing");
            }
        },
    }
}
