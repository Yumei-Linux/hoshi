const std = @import("std");
const clap = @import("clap");

const Setup = @import("./commands/setup.zig");
const Grab = @import("./commands/grab.zig");

const debug = std.debug;
const io = std.io;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const params = comptime clap.parseParamsComptime(
        \\-h, --help                        Displays this message and exit
        \\-s, --setup                       Perform a new scaffolding of the hoshi formulas repository
        \\-c, --clean                       Clean the last formulas repository archive before re cloning it
        \\-g, --grab <str>...               Build from source and install the desired packages
        \\
    );

    var diag = clap.Diagnostic{};

    var res = clap.parse(clap.Help, &params, clap.parsers.default, .{
        .diagnostic = &diag,
        .allocator = gpa.allocator(),
    }) catch |err| {
        diag.report(io.getStdErr().writer(), err) catch {};
        std.process.exit(1);
        return err;
    };

    defer res.deinit();

    var stdout = io.getStdOut().writer();
    var stderr = io.getStdErr().writer();

    if (res.args.help != 0) {
        try stdout.print("usage: ", .{});
        try clap.usage(stderr, clap.Help, &params);
        try stdout.print("\n\n", .{});
        return clap.help(io.getStdErr().writer(), clap.Help, &params, .{});
    }

    if (res.args.setup != 0) {
        Setup.run(gpa.allocator(), res.args.clean != 0) catch |err| {
            std.debug.print("Cannot setup hoshi formulas: {s}\n", .{@errorName(err)});
        };
    }

    if (res.args.grab.len > 0) {
        var grab = try Grab.new(gpa.allocator(), &res.args.grab);
        defer grab.deinit();
        try grab.run();
    }
}
