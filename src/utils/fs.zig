const std = @import("std");
const io = std.io;
const fs = std.fs;

pub fn xmkdir(dirname: []const u8) !fs.Dir {
    return std.fs.openDirAbsolute(dirname, .{}) catch retry: {
        std.fs.makeDirAbsolute(dirname) catch |err| {
            const stderr = io.getStdErr().writer();
            try stderr.print("Cannot mkdir {s}: {s}\n", .{ dirname, @errorName(err) });
            std.process.exit(1);
            return err;
        };

        // now it shouldn't fail
        break :retry std.fs.openDirAbsolute(dirname, .{}) catch unreachable;
    };
}

pub fn isEmptyDir(dirname: []const u8) !bool {
    const dir = try std.fs.openIterableDirAbsolute(dirname, .{});
    defer dir.close();

    var walker = try dir.walk();
    var result = true;

    while (walker.next()) |_| {
        result = false;
        break;
    }

    return result;
}
