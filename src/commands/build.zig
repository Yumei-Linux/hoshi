const std = @import("std");

const ui = @import("../utils/ui.zig");
const fs = @import("../utils/fs.zig");
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

fn doBuild(self: *Self, name: []const u8) !void {
    var package = try Package.new(self.allocator, name);
    defer package.deinit();

    try package.showResume();

    if (!try ui.ask("Would you like to start a building step for it?")) {
        try stderr.print("Sure, giving up...\n", .{});
        std.process.exit(0);
    }

    try package.startBuild();

    var ids = try Package.Ids.fromPkgId(self.allocator, name);
    defer ids.deinit();

    if (ids.pkgfilename) |pkgfilename| {
        var built_filename = try std.fmt.allocPrint(self.allocator, Package.packages_dirname ++ "/{s}", .{pkgfilename});

        var path_buf: [100]u8 = undefined;
        var cwd = try std.fs.cwd().realpath(".", path_buf[0..]);
        var dist_dirname = try std.fmt.allocPrint(self.allocator, "{s}/dist", .{cwd});
        var dest_filename = try std.fmt.allocPrint(self.allocator, "{s}/dist/{s}", .{ cwd, pkgfilename });

        defer {
            self.allocator.free(built_filename);
            self.allocator.free(dist_dirname);
            self.allocator.free(dest_filename);
        }

        _ = try fs.xmkdir(dist_dirname);

        try std.fs.copyFileAbsolute(built_filename, dest_filename, .{});
        try std.fs.deleteFileAbsolute(built_filename);

        try stdout.print("{s} has been saved at ./dist/{s}\n", .{ pkgfilename, pkgfilename });
    }
}

pub fn run(self: *Self) !void {
    for (self.packages) |pkgid| {
        self.doBuild(pkgid) catch |err| {
            stderr.print("Cannot start build step for package {s}: {s}\n", .{ pkgid, @errorName(err) }) catch unreachable;
            std.process.exit(1);
            return err;
        };
    }
}

pub fn deinit(self: *Self) void {
    self.allocator.destroy(self);
}
