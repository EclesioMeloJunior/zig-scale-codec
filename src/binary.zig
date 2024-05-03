const std = @import("std");
const testing = std.testing;
const benchmark = @import("bench");

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

test "benchmark" {
    try benchmark.benchmark(struct {
        // The functions will be benchmarked with the following inputs.
        // If not present, then it is assumed that the functions
        // take no input.
        pub const args = [_]type{ u128, i128, u64, i64, u32, i32, u16, i16, u8, i8 };

        // You can specify `arg_names` to give the inputs more meaningful
        // names. If the index of the input exceeds the available string
        // names, the index is used as a backup.
        pub const arg_names = [_][]const u8{
            "block=u128",
            "block=i128",
            "block=u64",
            "block=i64",
            "block=u32",
            "block=i32",
            "block=u16",
            "block=i16",
            "block=u8",
            "block=i8",
        };

        // How many iterations to run each benchmark.
        // If not present then a default will be used.
        pub const min_iterations = 1000;
        pub const max_iterations = 100000;

        pub fn mem_simple_write(comptime T: type) u32 {
            var buf: [@sizeOf(T)]u8 = undefined;
            LittleEndianEncode(T, std.math.maxInt(T), &buf);

            return 0;
        }
    });
}
