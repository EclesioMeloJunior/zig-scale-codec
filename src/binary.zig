const std = @import("std");
const testing = std.testing;

pub fn LittleEndianEncode(comptime T: type, value: T, enc: []u8) void {
    comptime {
        switch (@typeInfo(T)) {
            .Int => {},
            else => @compileError("little endian encode only supports usize, u8, u16, u32, u64 and u128"),
        }
    }

    // inspired by std.mem.writeInt
    @as(*align(1) T, @ptrCast(enc)).* = value;
}

pub fn LittleEndianDecode(comptime T: type, enc: *const [@sizeOf(T)]u8) T {
    comptime {
        switch (@typeInfo(T)) {
            .Int => {},
            else => @compileError("little endian encode only supports usize, u8, u16, u32, u64 and u128"),
        }
    }

    return std.mem.readInt(T, enc, .little);
}
