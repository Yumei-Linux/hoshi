const std = @import("std");

const Self = @This();

const cmd = @import("../utils/cmd.zig");
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
    instance.rootfs = rootfs.* orelse "/var/lib/hoshi/debug-rootfs";
    return instance;
}

fn removePackage(self: *Self, pkgid: []const u8) !void {
    var package = try Package.new(self.allocator, pkgid);
    defer package.deinit();

    if (!try package.isValidPkgId()) {
        try stderr.print("Invalid package name {s}... Have you forgotten to include the category?\n", .{pkgid});
        std.process.exit(1);
    }

    if (!try package.isInstalled()) {
        try stderr.print("{s} is a valid package but hasn't been installed yet... have you tried calling grab {s}?\n", .{ package.name, package.name });
        std.process.exit(1);
    }

    var package_extractor_manager = try Package.PackageExtractionInfo.fromPackage(package);

    try package_extractor_manager.performExtraction();

    defer {
        package_extractor_manager.cleanupExtraction() catch unreachable;
        package_extractor_manager.deinit();
    }

    // at this point we should be able to access to the package content
    // by using `package_extractor_manager.dirname`/*
    var files_registry_path = try std.fmt.allocPrint(self.allocator, "{s}/files.txt", .{package_extractor_manager.dirname});
    var files_registry = try std.fs.openFileAbsolute(files_registry_path, .{});

    defer {
        self.allocator.free(files_registry_path);
        files_registry.close();
    }

    // reading files.txt in order to see which files should one remove
    var reader = files_registry.reader();
    var lines_buf: [1024]u8 = undefined;

    // collecting files
    var files = std.ArrayList([]const u8).init(self.allocator);
    var dirs = std.ArrayList([]const u8).init(self.allocator);

    defer files.deinit();
    defer dirs.deinit();

    defer {
        files.deinit();
        dirs.deinit();
    }

    try stdout.print("Files to remove:\n", .{});

    while (try reader.readUntilDelimiterOrEof(lines_buf[0..], '\n')) |abstract_filename| {
        if (std.mem.eql(u8, abstract_filename, "")) continue;
        var filename = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ self.rootfs, abstract_filename });
        defer self.allocator.free(filename);
        std.debug.print("-- {s}\n", .{filename});
        const stat = try std.fs.cwd().statFile(filename);
        var copy = try std.fmt.allocPrint(self.allocator, "{s}", .{filename});
        switch (stat.kind) {
            .directory => try dirs.append(copy),
            .file => try files.append(copy),
            else => continue,
        }
    }

    std.debug.print("\n", .{});

    for (files.items) |file|
        std.debug.print("FILE {s}\n", .{file});

    for (dirs.items) |dir|
        std.debug.print("DIR {s}\n", .{dir});
}

pub fn run(self: *Self) !void {
    for (self.packages) |package| {
        self.removePackage(package) catch |err| {
            try stderr.print("Cannot remove package {s}: {s}", .{ package, @errorName(err) });
            std.process.exit(1);
            return err;
        };
    }
}

pub fn deinit(self: *Self) void {
    self.allocator.destroy(self);
}
