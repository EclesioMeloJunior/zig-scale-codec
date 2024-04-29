const std = @import("std");
const meta = std.meta;

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

fn compact_encode(comptime T: type, _: T) []const u8 {
    // const is_signed = @typeInfo(T).Type == std.meta.IntType;
    // const is_unsigned = is_signed and @typeInfo(T).Type.bit_width > 0;
    var uint8 = CompactUint8{ .value = 32 };
    return uint8.encode();
}

pub fn SizeHint(comptime T: type) usize {
    var size_hint: usize = 0;

    inline for (meta.fields(T)) |field| {
        size_hint += @sizeOf(field.type);
    }

    return size_hint;
}

pub fn Encode(comptime T: type, inst: T, enc_bytes_ref: *std.ArrayList(u8)) !void {

    // only works for struct unions
    inline for (meta.fields(T)) |field| {
        std.debug.print("got an array: {any}\n", .{field.type});

        if (field.type == []const u8) {
            const str_value: []const u8 = @field(inst, field.name);
            try enc_bytes_ref.appendSlice(compact_encode(usize, str_value.len));
            try enc_bytes_ref.appendSlice(str_value);
        }

        // switch (@typeInfo(field.type)) {
        //     .Pointer => {
        //         std.debug.print("got an array: {s}\n", .{field.name});
        //     },
        //     else => @compileError("type not supported!!\n"),
        // }
    }
}
