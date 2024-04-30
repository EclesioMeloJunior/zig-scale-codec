const std = @import("std");
const meta = std.meta;
const compact = @import("./compact.zig");

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
        if (field.type == []const u8) {
            const str_value: []const u8 = @field(inst, field.name);
            try compact.Encode(u8, 0b0011_1111, enc_bytes_ref);
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
