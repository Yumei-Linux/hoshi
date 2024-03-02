const std = @import("std");

const Self = @This();

const stdout = std.io.getStdOut().writer();
const stderr = std.io.getStdErr().writer();

pub fn title(message: []const u8) !void {
    try stdout.print("{s}\n", .{message});

    for (0..message.len) |_| {
        try stdout.print("=", .{});
    }

    try stdout.print("\n", .{});
}

// basic confirmation function
pub fn ask(prompt: []const u8) !bool {
    const stdin = std.io.getStdIn().reader();

    try stdout.print("? {s} [Y/n] ", .{prompt});

    var buf: [10]u8 = undefined;

    if (try stdin.readUntilDelimiterOrEof(buf[0..], '\n')) |user_input| {
        const valid_responses = [_][]const u8{ "Y", "y", "" };
        for (valid_responses) |expected_response| {
            if (std.mem.eql(u8, expected_response, user_input)) {
                return true;
            }
        }

        return false;
    } else {
        try stderr.print("cannot get user input\n", .{});
        std.process.exit(1);
    }
}
