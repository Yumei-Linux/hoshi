const std = @import("std");
const fs = @import("../utils/fs.zig");
const cmd = @import("../utils/cmd.zig");

const io = std.io;

const stdout = io.getStdOut().writer();
const stderr = io.getStdErr().writer();

const Self = @This();

fn emptyMkdir(dirname: []const u8) !void {
    var opened_dir = try fs.xmkdir(dirname);
    opened_dir.close();
}

fn cloneFormulas(allocator: std.mem.Allocator) !void {
    var args = [_][]const u8{ "git", "clone", "https://github.com/yumei-linux/hoshi-formulas.git", "/var/lib/hoshi/hoshi-formulas" };
    try cmd.exec(allocator, &args);
}

fn cleanWorkdir() !void {
    comptime var workdir_path: []const u8 = "/var/lib/hoshi";

    var opened_workdir = try fs.xmkdir(workdir_path);
    defer opened_workdir.close();

    var subfolders = [_][]const u8{ "hoshi-formulas", "packages", "debug-rootfs" };

    for (subfolders) |subfolder| {
        try opened_workdir.deleteTree(subfolder);
    }
}

pub fn run(allocator: std.mem.Allocator, clean: bool) !void {
    if (clean)
        try cleanWorkdir();

    const required_folders = [_][]const u8{ "/var/lib/hoshi", "/var/lib/hoshi/debug-rootfs", "/var/lib/hoshi/packages" };

    try stdout.print("Creating required folders\n", .{});

    for (required_folders) |folder| {
        try stdout.print("++ {s}\n", .{folder});
        try Self.emptyMkdir(folder);
    }

    try stdout.print("The folders have been created successfully\n", .{});
    try cloneFormulas(allocator);
}
