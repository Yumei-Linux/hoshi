const std = @import("std");

const Self = @This();

pub fn exec(allocator: std.mem.Allocator, argv: [][]const u8) !void {
    var cmd = std.ChildProcess.init(argv, allocator);
    _ = try cmd.spawnAndWait();
}
