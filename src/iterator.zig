const std = @import("std");
const testing = std.testing;

pub const Errors = error{
    IteratorExhausted,
};

pub fn Iterator(comptime T: type) type {
    return struct {
        encode_bytes: []const T,
        cursor: usize,

        const Self = @This();

        pub fn new(encoded_bytes: []const u8) Self {
            return Self{ .encode_bytes = encoded_bytes, .cursor = 0 };
        }

        pub fn next(self: *Self) ?T {
            if (self.cursor >= self.encode_bytes.len) return null;
            defer self.cursor += 1;
            return self.encode_bytes[self.cursor];
        }

        // take consumes the amount of bytes in out from the iterator
        // and place them in the out slice returning the amount of items consumed
        pub fn take(self: *Self, out: []T) Errors!usize {
            if (self.cursor >= self.encode_bytes.len) return Errors.IteratorExhausted;
            if (out.len == 0) return 0;

            const available_iter_length = self.encode_bytes.len - self.cursor;
            const start_at = self.cursor;

            const slices = blk: {
                if (out.len <= available_iter_length) {
                    break :blk .{ out, self.encode_bytes[self.cursor..(self.cursor + out.len)] };
                } else {
                    break :blk .{ out[0..available_iter_length], self.encode_bytes[self.cursor..] };
                }
            };

            for (slices[0], slices[1]) |*rv, from| {
                rv.* = from;
                self.cursor += 1;
            }

            return self.cursor - start_at;
        }
    };
}

test "test interator take" {
    const TestCase = struct {
        bytes: []const u8,
        bytes_out: type,
        expected_n: usize,
        expected_error: ?Errors,
    };

    const cases = [_]TestCase{
        .{
            .bytes = &[_]u8{ 1, 2, 3, 4 },
            .bytes_out = [10]u8,
            .expected_n = 4,
            .expected_error = null,
        },
        .{
            .bytes = &[_]u8{},
            .bytes_out = [10]u8,
            .expected_n = 0,
            .expected_error = Errors.IteratorExhausted,
        },
    };

    inline for (cases) |case| {
        var iter = Iterator(u8).new(case.bytes);
        var out = std.mem.zeroes(case.bytes_out);
        if (case.expected_error) |expected_err| {
            try testing.expectError(expected_err, iter.take(&out));
        } else {
            const result = try iter.take(&out);
            try testing.expect(result == case.expected_n);
            try testing.expect(std.mem.eql(u8, out[0..result], case.bytes));
        }
    }
}

test "test empty iterator" {
    const encoded = [_]u8{};
    var iter = Iterator(u8).new(&encoded);
    try testing.expect(iter.next() == null);
    try testing.expect(iter.cursor == 0);
}
