const std = @import("std");

const Self = @This();

const cmd = @import("../utils/cmd.zig");
const Package = @import("../utils/package.zig");

const stdout = std.io.getStdOut().writer();
const stderr = std.io.getStdErr().writer();

pub fn run(allocator: std.mem.Allocator) !void {
    var packages_dir = std.fs.openIterableDirAbsolute(Package.packages_dirname, .{}) catch |err| {
        try stderr.print("Cannot open " ++ Package.packages_dirname ++ ": {s}\n", .{@errorName(err)});
        std.process.exit(1);
        return err;
    };

    defer packages_dir.close();

    var walker = try packages_dir.walk(allocator);
    defer walker.deinit();

    try stdout.print("Showing installed packages:\n", .{});

    while (try walker.next()) |entry| {
        var ids = try Package.Ids.fromPkgFilename(allocator, entry.path);
        defer allocator.free(ids.pkgid);

        if (ids.pkgname) |pkgname| {
            try stdout.print("++ {s}\n", .{pkgname});
        }

        var package = try Package.new(allocator, ids.pkgid);
        var package_extractor = try Package.PackageExtractionInfo.fromPackage(package);

        try package_extractor.performExtraction();

        defer {
            package_extractor.cleanupExtraction() catch |err| {
                stderr.print("Cannot remove {s}: {s}\n", .{ package_extractor.dirname, @errorName(err) }) catch unreachable;
                std.process.exit(1);
            };

            package_extractor.deinit();
            package.deinit();
        }

        var metadata_path = try std.fmt.allocPrint(allocator, "{s}/metadata.json", .{package_extractor.dirname});
        defer allocator.free(metadata_path);

        var parsed = try package.parseMetadata(metadata_path);
        defer parsed.deinit();

        const metadata = parsed.value;

        if (metadata.depends) |depends| {
            for (depends) |dep| {
                var dep_ids = try Package.Ids.fromPkgId(allocator, dep);
                defer dep_ids.deinit();
                if (dep_ids.pkgname) |dep_pkgname| {
                    try stdout.print("  -- {s}\n", .{dep_pkgname});
                }
            }
        }
    }
}
