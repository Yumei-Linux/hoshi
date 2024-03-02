const std = @import("std");

const Self = @This();

const Package = @import("../utils/package.zig");

const stdout = std.io.getStdOut().writer();
const stderr = std.io.getStdErr().writer();

allocator: std.mem.Allocator,
packages: []const []const u8,
rootfs: []const u8,

pub fn new(allocator: std.mem.Allocator, packages: *[]const []const u8, rootfs: *?[]const u8) !*Self {
    var instance = try allocator.create(Self);

    instance.allocator = allocator;
    instance.packages = packages.*;

    // read the note at src.commands.Grab:new().rootfs
    // definition.
    instance.rootfs = rootfs.* orelse "/var/lib/hoshi/debug-rootfs";

    return instance;
}

fn importPackage(self: *Self, package_filename: []const u8) !void {
    var basename = std.fs.path.basename(package_filename);

    var abs_buf: [100]u8 = undefined;
    var abspath = try std.fs.cwd().realpath(package_filename, abs_buf[0..]);

    var dest_path = try std.fmt.allocPrint(self.allocator, Package.packages_dirname ++ "/{s}", .{basename});
    defer self.allocator.free(dest_path);

    try std.fs.copyFileAbsolute(abspath, dest_path, .{});
    try stdout.print("{s} -> {s}\n", .{ abspath, dest_path });

    var ids = try Package.Ids.fromPkgFilename(self.allocator, basename);

    // ids.deinit() just frees pkgfilename and ids.fromPkgFilename()
    // allocates date at ids.pkgid, so we gotta free that.
    defer self.allocator.free(ids.pkgid);

    var package = try Package.new(self.allocator, ids.pkgid);
    defer package.deinit();

    package.mergeAt(self.rootfs) catch |err| {
        try stderr.print("Cannot merge the package {s} at {s}: {s}", .{ package_filename, self.rootfs, @errorName(err) });
        std.process.exit(1);
        return err;
    };
}

pub fn run(self: *Self) !void {
    for (self.packages) |package| {
        self.importPackage(package) catch |err| {
            try stderr.print("Cannot import package {s}: {s}\n", .{ package, @errorName(err) });
            std.process.exit(1);
            return err;
        };
    }
}

pub fn deinit(self: *Self) void {
    self.allocator.destroy(self);
}
