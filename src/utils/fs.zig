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
