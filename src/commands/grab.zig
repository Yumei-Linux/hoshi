const std = @import("std");

const Self = @This();
const stdout = std.io.getStdOut().writer();

allocator: std.mem.Allocator,
packages: []const []const u8,

pub fn new(allocator: std.mem.Allocator, packages: *[]const []const u8) !*Self {
    var instance = try allocator.create(Self);
    instance.allocator = allocator;
    instance.packages = packages.*;
    return instance;
}

pub fn run(self: *Self) !void {
    for (self.packages) |package| {
        try stdout.print("Got package to build [grab.zig] {s}\n", .{package});
    }
}

pub fn deinit(self: *Self) void {
    self.allocator.destroy(self);
}
