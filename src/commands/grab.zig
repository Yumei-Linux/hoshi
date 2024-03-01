const std = @import("std");

const Package = @import("../utils/package.zig");

const Self = @This();

const stdout = std.io.getStdOut().writer();
const stderr = std.io.getStdErr().writer();

allocator: std.mem.Allocator,
packages: []const []const u8,

pub fn new(allocator: std.mem.Allocator, packages: *[]const []const u8) !*Self {
    var instance = try allocator.create(Self);
    instance.allocator = allocator;
    instance.packages = packages.*;
    return instance;
}

pub fn run(self: *Self) !void {
    try stdout.print("Showing resumes for the desired packages to grab...\n\n", .{});

    for (self.packages) |pkg| {
        var package = try Package.new(self.allocator, pkg);

        package.showResume() catch |err| {
            try stderr.print("Cannot show resume for package {s}: {s}\n", .{ package.name, @errorName(err) });
            std.process.exit(1);
            return err;
        };

        package.deinit();
    }
}

pub fn deinit(self: *Self) void {
    self.allocator.destroy(self);
}
