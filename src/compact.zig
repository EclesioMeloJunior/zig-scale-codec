const std = @import("std");
const testing = std.testing;
const binary = @import("binary.zig");
const iterator = @import("iterator.zig");

pub const Errors = error{
    UnexpectedExhaustedIterator,
} || iterator.Errors || std.mem.Allocator.Error;

fn Compact(comptime T: type) type {
    return struct {
        value: T,
        const Self = @This();

        pub fn size_hint(s: Self) usize {
            comptime {
                switch (T) {
                    usize, u8, u16, u32, u64, u128 => {},
                    else => @compileError("compact encoding only supports usize, u8, u16, u32, u64 and u128"),
                }
            }

            switch (s.value) {
                0...0b0011_1111 => return 1,
                (0b0011_1111 + 1)...0b0011_1111_1111_1111 => return 2,
                (0b0011_1111_1111_1111 + 1)...0b0011_1111_1111_1111_1111_1111_1111_1111 => return 4,
                else => {
                    const alpha = if (T == u64) 8 else if (T == u128) 16 else @panic("alpha should be only 8 for u64 or 16 for u128");
                    const bytes_needed = alpha - @clz(s.value) / 8;
                    return bytes_needed + 1;
                },
            }
        }

        pub fn encode(s: Self, enc_bytes_ref: *std.ArrayList(u8)) !void {
            comptime {
                switch (T) {
                    usize, u8, u16, u32, u64, u128 => {},
                    else => @compileError("compact encoding only supports usize, u8, u16, u32, u64 and u128"),
                }
            }

            switch (s.value) {
                0...0b0011_1111 => {
                    const uint8value: u8 = @intCast(s.value);
                    try enc_bytes_ref.append(uint8value << 2);
                },
                (0b0011_1111 + 1)...0b0011_1111_1111_1111 => {
                    var enc: [2]u8 = undefined;
                    binary.LittleEndianEncode(u16, (@as(u16, @truncate(s.value)) << 2) | 0b01, &enc);
                    try enc_bytes_ref.appendSlice(&enc);
                },
                (0b0011_1111_1111_1111 + 1)...0b0011_1111_1111_1111_1111_1111_1111_1111 => {
                    var enc: [4]u8 = undefined;
                    binary.LittleEndianEncode(u32, (@as(u32, @truncate(s.value)) << 2) | 0b10, &enc);
                    try enc_bytes_ref.appendSlice(&enc);
                },
                else => {
                    var cpy_value = s.value;
                    const alpha = if (T == u64) 8 else if (T == u128) 16 else @panic("alpha should be only 8 for u64 or 16 for u128");
                    const bytes_needed = alpha - @clz(cpy_value) / 8;

                    if (bytes_needed < 4) {
                        @panic("previous match arm matches anyting less than 2^30; qed");
                    }

                    try enc_bytes_ref.append(0b11 + @as(u8, (bytes_needed - 4) << 2));

                    for (0..bytes_needed) |_| {
                        try enc_bytes_ref.append(@as(u8, @truncate(cpy_value)));
                        cpy_value >>= 8;
                    }

                    if (cpy_value != 0) {
                        @panic("expected 0 values but still values missing");
                    }
                },
            }
        }
    };
}

pub const CompactUsize = Compact(usize);
pub const CompactUint8 = Compact(u8);
pub const CompactUint16 = Compact(u16);
pub const CompactUint32 = Compact(u32);
pub const CompactUint64 = Compact(u64);
pub const CompactUint128 = Compact(u128);

fn compactMode(byte: u8) enum { singleByteMode, twoByteMode, fourByteMode, bigIntegerMode } {
    switch (byte << 6) {
        0b00000000 => return .singleByteMode,
        0b01000000 => return .twoByteMode,
        0b10000000 => return .fourByteMode,
        0b11000000 => return .bigIntegerMode,
        else => @panic("encoded compact mode not supported"),
    }
}

pub fn Decode(comptime T: type, iter: *iterator.Iterator(u8)) Errors!Compact(T) {
    const fst = iter.next() orelse return Errors.UnexpectedExhaustedIterator;
    switch (compactMode(fst)) {
        .singleByteMode => return .{ .value = @as(T, fst >> 2) },
        .twoByteMode => {
            const snd = iter.next() orelse return Errors.UnexpectedExhaustedIterator;
            const buf = [_]u8{
                (fst >> 2) | (snd << 6),
                snd >> 2,
            };
            return .{ .value = @as(T, std.mem.readInt(u16, &buf, .little)) };
        },
        .fourByteMode => {
            var next_bytes: [3]u8 = undefined;
            const n = try iter.take(&next_bytes);
            if (n != 3) return Errors.UnexpectedExhaustedIterator;
            const buf = [_]u8{
                (fst >> 2) | (next_bytes[0] << 6),
                (next_bytes[0] >> 2) | (next_bytes[1] << 6),
                (next_bytes[1] >> 2) | (next_bytes[2] << 6),
                next_bytes[2] >> 2,
            };
            return .{ .value = @as(T, std.mem.readInt(u32, &buf, .little)) };
        },
        .bigIntegerMode => {
            const amount_next_bytes = (fst >> 2) + 4;
            if (amount_next_bytes == 4) {
                var next_bytes: [4]u8 = undefined;
                const n = try iter.take(&next_bytes);
                if (n != 4) return Errors.UnexpectedExhaustedIterator;
                return .{ .value = @as(T, std.mem.readInt(u32, @as(*const [4]u8, @alignCast(&next_bytes)), .little)) };
            }

            if (amount_next_bytes > 4 and amount_next_bytes < 8) {
                const bytes = try read_bytes(amount_next_bytes, iter);
                return .{ .value = @as(T, std.mem.readInt(u64, @as(*const [8]u8, @ptrCast(bytes.ptr)), .little)) };
            }

            if (amount_next_bytes == 8) {
                var next_bytes: [8]u8 = undefined;
                const n = try iter.take(&next_bytes);
                if (n != 8) return Errors.UnexpectedExhaustedIterator;
                return .{ .value = @as(T, std.mem.readInt(u64, @as(*const [8]u8, @alignCast(&next_bytes)), .little)) };
            }

            const bytes = try read_bytes(amount_next_bytes, iter);
            return .{ .value = @as(T, std.mem.readInt(u128, @as(*const [16]u8, @ptrCast(bytes.ptr)), .little)) };
        },
    }
}

fn read_bytes(amount: usize, iter: *iterator.Iterator(u8)) Errors![]u8 {
    var encoded_number = try std.ArrayList(u8).initCapacity(
        std.heap.page_allocator,
        amount,
    );
    defer encoded_number.deinit();

    var idx: usize = 0;
    while (idx < amount) : (idx += 1) {
        const byte = iter.next() orelse return Errors.UnexpectedExhaustedIterator;
        try encoded_number.append(byte);
    }

    return encoded_number.toOwnedSlice();
}

test "compact_encode" {
    var compact_u32: CompactUint32 = .{ .value = 1 };
    var arr = std.ArrayList(u8).init(testing.allocator);
    defer arr.deinit();

    try compact_u32.encode(&arr);
    try testing.expect(std.mem.eql(u8, &[_]u8{0x04}, arr.items));

    arr.clearRetainingCapacity();

    var compact_u64: CompactUint64 = .{ .value = 42 };
    try compact_u64.encode(&arr);
    try testing.expect(std.mem.eql(u8, &[_]u8{0xa8}, arr.items));

    arr.clearRetainingCapacity();

    var compact_u128: CompactUint128 = .{ .value = 69 };
    try compact_u128.encode(&arr);
    try testing.expect(std.mem.eql(u8, &[_]u8{ 0x15, 0x01 }, arr.items));

    arr.clearRetainingCapacity();

    compact_u64 = .{ .value = 65535 };
    try compact_u64.encode(&arr);
    try testing.expect(std.mem.eql(u8, &[_]u8{ 0xfe, 0xff, 0x03, 0x00 }, arr.items));

    arr.clearRetainingCapacity();

    compact_u64 = .{ .value = std.math.maxInt(u64) };
    try compact_u64.encode(&arr);

    try testing.expect(std.mem.eql(u8, &[_]u8{ 19, 255, 255, 255, 255, 255, 255, 255, 255 }, arr.items));

    arr.clearRetainingCapacity();

    compact_u128 = .{ .value = 100000000000000 };
    try compact_u128.encode(&arr);

    try testing.expect(std.mem.eql(u8, &[_]u8{ 11, 0, 64, 122, 16, 243, 90 }, arr.items));
}
