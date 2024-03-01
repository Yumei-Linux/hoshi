const std = @import("std");

const Self = @This();

const stdout = std.io.getStdOut().writer();

pub fn title(message: []const u8) !void {
    try stdout.print("{s}\n", .{message});

    for (0..message.len) |_| {
        try stdout.print("=", .{});
    }

    try stdout.print("\n", .{});
}
