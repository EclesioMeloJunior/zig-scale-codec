const std = @import("std");
const codec = @import("codec.zig");
const testing = std.testing;

test "encode a  basic struct" {
    const Animal = struct { name: []const u8 };

    const size_hint = codec.SizeHint(Animal);

    var cow: Animal = .{ .name = "cow_name" };

    var encoded_bytes = try std.ArrayList(u8).initCapacity(
        testing.allocator,
        size_hint,
    );

    defer encoded_bytes.deinit();

    try codec.Encode(Animal, cow, &encoded_bytes);
    std.debug.print("default value {any}\n", .{encoded_bytes.items});
}
