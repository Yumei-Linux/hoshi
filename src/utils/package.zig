const std = @import("std");

const Self = @This();
const ui = @import("./ui.zig");

const stdout = std.io.getStdOut().writer();

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

fn showMetadataInfo(self: *Self, contents: []const u8) !void {
    var parsed = try ParsedMetadata.fromContents(self.allocator, contents);
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

pub fn showResume(self: *Self) !void {
    var title_message = try std.fmt.allocPrint(self.allocator, "Package: {s}", .{self.name});
    defer self.allocator.free(title_message);
    try ui.title(title_message);
    try stdout.print("\n", .{});

    var metadata_path = try self.obtainMetadataPath();
    defer self.allocator.free(metadata_path);

    var metadata_buf: [1024]u8 = undefined;
    var metadata_file = try std.fs.openFileAbsolute(metadata_path, .{});
    var metadata_bytes = try metadata_file.readAll(metadata_buf[0..]);

    const metadata_content = metadata_buf[0..metadata_bytes];

    defer metadata_file.close();

    try self.showMetadataInfo(metadata_content);

    try stdout.print("\n", .{});
}

pub fn deinit(self: *Self) void {
    self.allocator.destroy(self);
}
