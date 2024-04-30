const std = @import("std");
pub fn LittleEndianEncode(comptime T: type, value: T, enc: []u8) void {
    comptime {
        switch (T) {
            u8, u16, u32, u64 => {},
            else => @compileError("little endian encode only supports u8, u16, u32, u64"),
        }
    }

    inline for (0..@sizeOf(T)) |idx| {
        enc[idx] = @as(u8, @truncate(value >> (idx * 8)));
    }
}
