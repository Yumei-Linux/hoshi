const std = @import("std");

const Package = @import("../utils/package.zig");
const ui = @import("../utils/ui.zig");

const Self = @This();

const stdout = std.io.getStdOut().writer();
const stderr = std.io.getStdErr().writer();

allocator: std.mem.Allocator,
packages: []const []const u8,
rootfs: []const u8,

pub fn new(allocator: std.mem.Allocator, packages: *[]const []const u8, rootfs: *?[]const u8) !*Self {
    var instance = try allocator.create(Self);
    instance.allocator = allocator;
    instance.packages = packages.*;

    // defaulting to / can be dangerous... this will be like this
    // only for the debug builds!
    // NOTE: One possible and efficient solution may be by using a
    // comptime config value which would target to the default
    // rootfs value, but just that... in comptime.
    instance.rootfs = rootfs.* orelse "/var/lib/hoshi/debug-rootfs";

    return instance;
}

// just a little error wrapper function for the grab() one
fn doBuild(self: *Self, package: *Package) !void {
    try package.startBuild();
    try package.mergeAt(self.rootfs);
}

fn grab(self: *Self, pkgid: []const u8) !void {
    var package = try Package.new(self.allocator, pkgid);
    var parsed_metadata = try package.parseMetadata();

    defer package.deinit();
    defer parsed_metadata.deinit();

    const metadata = parsed_metadata.value;

    // recursively installing dependencies first
    if (metadata.depends) |depends| {
        for (depends) |dep| {
            var dep_package = try Package.new(self.allocator, dep);
            defer dep_package.deinit();

            // skip this dependency if it's already installed
            if (try dep_package.isInstalled()) {
                continue;
            }

            self.grab(dep) catch |err| {
                try stderr.print("Cannot install dependency {s} for package {s}: {s}\n", .{ dep, pkgid, @errorName(err) });
                std.process.exit(1);
                return err;
            };
        }
    }

    self.doBuild(package) catch |err| {
        try stderr.print("Cannot run the build process for pkg {s}: {s}", .{ pkgid, @errorName(err) });
        std.process.exit(1);
        return err;
    };
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

    if (!try ui.ask("Would you like to grab these packages?")) {
        try stderr.print("Sure, giving up!\n", .{});
        std.process.exit(0);
    }

    try stdout.print("\n", .{});

    for (self.packages) |pkgid| {
        self.grab(pkgid) catch |x| {
            try stderr.print("Cannot grab package {s}: {s}\n", .{ pkgid, @errorName(x) });
            std.process.exit(1);
            return x;
        };
    }
}

pub fn deinit(self: *Self) void {
    self.allocator.destroy(self);
}
