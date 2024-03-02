const std = @import("std");

const Self = @This();

const ui = @import("./ui.zig");
const cmd = @import("./cmd.zig");
const fs = @import("./fs.zig");

const stdout = std.io.getStdOut().writer();
const stderr = std.io.getStdErr().writer();

// paths that will serve as utility.
const workdir = "/var/lib/hoshi";
const dist_dirname = workdir ++ "/hoshi-formulas/dist";
const packages_dirname = workdir ++ "/packages";

allocator: std.mem.Allocator,
name: []const u8,

pub fn new(allocator: std.mem.Allocator, name: []const u8) !*Self {
    var instance = try allocator.create(Self);
    instance.allocator = allocator;
    instance.name = name;
    return instance;
}

fn obtainMetadataPath(self: *Self) ![]const u8 {
    return std.fmt.allocPrint(self.allocator, "/var/lib/hoshi/hoshi-formulas/{s}/metadata.json", .{self.name}) catch |x| {
        return x;
    };
}

const ParsedMetadata = struct {
    name: []const u8,
    description: []const u8,
    depends: ?[]const []const u8,
    downloads: ?[]const []const u8,

    pub fn fromContents(allocator: std.mem.Allocator, contents: []const u8) !std.json.Parsed(ParsedMetadata) {
        return std.json.parseFromSlice(ParsedMetadata, allocator, contents, .{ .allocate = .alloc_always });
    }
};

fn showMetadataInfo(self: *Self) !void {
    var parsed = try self.parseMetadata();
    defer parsed.deinit();

    const metadata = parsed.value;

    try stdout.print("Name: {s}\n", .{metadata.name});
    try stdout.print("Description: {s}\n", .{metadata.description});

    if (metadata.depends) |depends| {
        if (depends.len > 0) {
            try stdout.print("Depends on ({d})\n", .{depends.len});
            for (depends) |dep| {
                try stdout.print("  -> {s}\n", .{dep});
            }
        }
    }

    if (metadata.downloads) |downloads| {
        if (downloads.len > 0) {
            try stdout.print("Downloads ({d})\n", .{downloads.len});
            for (downloads) |download| {
                try stdout.print("  -> {s}\n", .{download});
            }
        }
    }
}

fn performDownloads(self: *Self) !void {
    var parsed = try self.parseMetadata();
    defer parsed.deinit();

    const metadata = parsed.value;

    _ = try fs.xmkdir("/var/lib/hoshi/hoshi-formulas/downloads");

    if (metadata.downloads) |downloads| {
        for (downloads) |download| {
            var argv = [_][]const u8{ "wget", download, "-P", "/var/lib/hoshi/hoshi-formulas/downloads" };
            try cmd.exec(self.allocator, &argv);
        }
    }
}

const IdParsingErrors = error{InvalidGivenPkgId};

pub const Ids = struct {
    // an allocator is always needed ;)
    allocator: std.mem.Allocator,

    // consists in the next format <category>/<packagename>
    pkgid: []const u8,

    // just the <packagename> (no category) (can be optional)
    pkgname: ?[]const u8,

    // <packagename> + .hoshi -> <packagename>.hoshi (can be optional)
    pkgfilename: ?[]const u8,

    // obtain a Ids instance by a `pkgid`.
    pub fn fromPkgId(allocator: std.mem.Allocator, pkgid: []const u8) !Ids {
        var slashpos = std.mem.indexOfScalar(u8, pkgid, '/') orelse return error.InvalidGivenPkgId;
        var pkgname = pkgid[slashpos + 1 ..];
        var pkgfilename = try allocator.alloc(u8, pkgname.len + 6);

        std.mem.copy(u8, pkgfilename, pkgname);
        std.mem.copy(u8, pkgfilename[pkgname.len..], ".hoshi");

        return Ids{
            .allocator = allocator,
            .pkgid = pkgid,
            .pkgname = pkgname,
            .pkgfilename = pkgfilename,
        };
    }

    // free the allocated data
    pub fn deinit(self: Ids) void {
        if (self.pkgfilename) |filename| {
            self.allocator.free(filename);
        }
    }
};

pub fn startBuild(self: *Self) !void {
    try stdout.print("\nBuilding package {s}\n\n", .{self.name});

    self.performDownloads() catch |err| {
        try stderr.print("Cannot perform downloads for package {s}: {s}\n", .{ self.name, @errorName(err) });
        std.process.exit(1);
        return err;
    };

    var argv = [_][]const u8{ "/var/lib/hoshi/hoshi-formulas/builder.sh", self.name };
    try cmd.exec(self.allocator, &argv);

    // move the package from the dist directory to the packages one
    // in order to register it as an installed one
    var ids = try Ids.fromPkgId(self.allocator, self.name);
    defer ids.deinit();

    if (ids.pkgfilename == null) {
        try stderr.print("Invalid package id {s}\n", .{self.name});
        std.process.exit(1);
    }

    const pkgfilename = ids.pkgfilename.?;

    var dist_filename = try std.fmt.allocPrint(self.allocator, dist_dirname ++ "/{s}", .{pkgfilename});
    var dest_filename = try std.fmt.allocPrint(self.allocator, packages_dirname ++ "/{s}", .{pkgfilename});

    defer self.allocator.free(dist_filename);
    defer self.allocator.free(dest_filename);

    try std.fs.copyFileAbsolute(dist_filename, dest_filename, .{});
    try std.fs.deleteFileAbsolute(dist_filename);

    try stdout.print("\n[mv]: " ++ dist_dirname ++ "/{s} -> " ++ packages_dirname ++ "/{s}\n", .{ pkgfilename, pkgfilename });
}

pub fn mergeAt(self: *Self, rootfs: []const u8) !void {
    try stdout.print("\nMerging package {s} into {s}\n\n", .{ self.name, rootfs });

    var ids = try Ids.fromPkgId(self.allocator, self.name);
    defer ids.deinit();

    if (ids.pkgfilename == null or ids.pkgname == null) {
        try stderr.print("Invalid package id {s}\n", .{self.name});
        std.process.exit(1);
    }

    // at this point it should be okay to do this i guess
    const pkgfilename = ids.pkgfilename.?;
    const pkgname = ids.pkgname.?;

    var pkg_filepath = try std.fmt.allocPrint(self.allocator, packages_dirname ++ "/{s}", .{pkgfilename});
    var pkg_extracted_dirname = try std.fmt.allocPrint(self.allocator, packages_dirname ++ "/{s}", .{pkgname});

    defer {
        self.allocator.free(pkg_filepath);
        self.allocator.free(pkg_extracted_dirname);
    }

    // extracting the .hoshi file
    _ = try fs.xmkdir(pkg_extracted_dirname);

    var extract_argv = [_][]const u8{ "tar", "xpf", pkg_filepath, "--strip-components=1", "-C", pkg_extracted_dirname };
    try cmd.exec(self.allocator, &extract_argv);

    // remove the extracted tar file
    defer std.fs.deleteTreeAbsolute(pkg_extracted_dirname) catch |err| {
        stderr.print("cannot cleanup the extracted .hoshi file! (package -> {s}): {s}", .{ self.name, @errorName(err) }) catch unreachable;
        std.process.exit(1);
    };

    // merging into rootfs by using the files.txt file as reference
    // NOTE: files.txt is a file which lists which files are present
    // in a .hoshi file, it's generated by the formulas builder
    var files_registry_path = try std.fmt.allocPrint(self.allocator, "{s}/files.txt", .{pkg_extracted_dirname});
    var files_registry = try std.fs.openFileAbsolute(files_registry_path, .{});

    defer self.allocator.free(files_registry_path);
    defer files_registry.close();

    var files_reader = files_registry.reader();
    var line: [1024]u8 = undefined;

    while (try files_reader.readUntilDelimiterOrEof(&line, '\n')) |file| {
        if (file.len == 0) continue;

        var real_path = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ pkg_extracted_dirname, file });
        var dest_path = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ rootfs, file });
        var install_command = try std.fmt.allocPrint(self.allocator, "install -D {s} {s} >/dev/null 2>&1", .{ real_path, dest_path });

        // free the allocated strings calculations
        defer {
            const to_free_strings = [_][]const u8{ real_path, dest_path, install_command };
            for (to_free_strings) |string| {
                self.allocator.free(string);
            }
        }

        var merge_argv = [_][]const u8{ "bash", "-c", install_command };

        try stdout.print("++ {s} -> {s}\n", .{ file, dest_path });
        try cmd.exec(self.allocator, &merge_argv);
    }
}

fn parseMetadata(self: *Self) !std.json.Parsed(ParsedMetadata) {
    var metadata_path = try self.obtainMetadataPath();
    defer self.allocator.free(metadata_path);

    var metadata_buf: [1024]u8 = undefined;
    var metadata_file = try std.fs.openFileAbsolute(metadata_path, .{});
    var metadata_bytes = try metadata_file.readAll(metadata_buf[0..]);

    defer metadata_file.close();

    return ParsedMetadata.fromContents(self.allocator, metadata_buf[0..metadata_bytes]);
}

pub fn showResume(self: *Self) !void {
    var title_message = try std.fmt.allocPrint(self.allocator, "Package: {s}", .{self.name});
    defer self.allocator.free(title_message);

    try ui.title(title_message);
    try stdout.print("\n", .{});

    try self.showMetadataInfo();
    try stdout.print("\n", .{});
}

pub fn deinit(self: *Self) void {
    self.allocator.destroy(self);
}
